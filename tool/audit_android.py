#!/usr/bin/env python3
"""Inspect actual release APKs; a successful build alone is not package QA."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import xml.etree.ElementTree as ET
import zipfile

ANDROID = '{http://schemas.android.com/apk/res/android}'
MACHINES = {'armeabi-v7a': 40, 'arm64-v8a': 183, 'x86_64': 62}


def run(*args):
    return subprocess.check_output([str(arg) for arg in args], text=True)


def native_info(data):
    assert data[:4] == b'\x7fELF', 'Native library is not ELF'
    assert data[5] == 1, 'Unexpected ELF byte order'
    bits = data[4]
    machine = struct.unpack_from('<H', data, 18)[0]
    if bits == 2:
        offset = struct.unpack_from('<Q', data, 32)[0]
        size, count = struct.unpack_from('<HH', data, 54)
        aligns = [struct.unpack_from('<Q', data, offset + i * size + 48)[0]
                  for i in range(count) if struct.unpack_from('<I', data, offset + i * size)[0] == 1]
    else:
        offset = struct.unpack_from('<I', data, 28)[0]
        size, count = struct.unpack_from('<HH', data, 42)
        aligns = [struct.unpack_from('<I', data, offset + i * size + 28)[0]
                  for i in range(count) if struct.unpack_from('<I', data, offset + i * size)[0] == 1]
    return {'machine': machine, 'bytes': len(data), 'load_alignment': aligns,
            'supports_16k_pages': bool(aligns) and min(aligns) >= 16384}


def audit(apk, sdk):
    tools = sorted((sdk / 'build-tools').iterdir(), key=lambda p: tuple(int(x) for x in p.name.split('.') if x.isdigit()))[-1]
    analyzer = sdk / 'cmdline-tools/latest/bin/apkanalyzer'
    manifest_text = run(analyzer, 'manifest', 'print', apk)
    manifest = ET.fromstring(manifest_text)
    assert manifest.get('package') == 'com.converto.app'
    permissions = [item.get(ANDROID + 'name') for item in manifest.findall('uses-permission')]
    forbidden = {'android.permission.INTERNET', 'android.permission.MANAGE_EXTERNAL_STORAGE',
                 'android.permission.READ_EXTERNAL_STORAGE', 'android.permission.WRITE_EXTERNAL_STORAGE'}
    assert not forbidden.intersection(permissions), f'Unexpected permissions: {permissions}'
    app = manifest.find('application')
    assert app is not None and app.get(ANDROID + 'allowBackup') == 'false'
    assert app.get(ANDROID + 'debuggable', 'false') == 'false'
    activity = app.find('activity')
    assert activity is not None and activity.get(ANDROID + 'name') == 'com.converto.app.MainActivity'
    assert activity.findall("intent-filter/action[@" + ANDROID + "name='android.intent.action.MAIN']")
    provider = next(item for item in app.findall('provider') if item.get(ANDROID + 'authorities') == 'com.converto.app.results')
    assert provider.get(ANDROID + 'exported') == 'false'
    assert provider.get(ANDROID + 'grantUriPermissions') == 'true'
    assert not activity.findall("intent-filter/action[@" + ANDROID + "name='android.intent.action.SEND']")
    native = {}
    with zipfile.ZipFile(apk) as archive:
        assert 'assets/flutter_assets/NativeAssetsManifest.json' in archive.namelist()
        for name in archive.namelist():
            if name.startswith('lib/') and name.endswith('.so'):
                abi = name.split('/')[1]
                info = native_info(archive.read(name))
                assert info['machine'] == MACHINES[abi], f'Wrong architecture: {name}'
                native[name] = info
        for abi in {name.split('/')[1] for name in native}:
            for library in ['libflutter.so', 'libapp.so', 'libpdf_oxide.so']:
                assert f'lib/{abi}/{library}' in native, f'Missing {library} for {abi}'
    assert native, 'APK contains no native engine'
    signature = run(tools / 'apksigner', 'verify', '--print-certs', apk)
    run(tools / 'zipalign', '-c', '-P', '16', '4', apk)
    uses_sdk = manifest.find('uses-sdk')
    return {'apk': str(apk), 'bytes': apk.stat().st_size,
            'sha256': hashlib.sha256(apk.read_bytes()).hexdigest(),
            'min_sdk': uses_sdk.get(ANDROID + 'minSdkVersion'),
            'target_sdk': uses_sdk.get(ANDROID + 'targetSdkVersion'),
            'permissions': permissions, 'native_libraries': native,
            'signature': signature.strip(), 'zip_alignment_16k': True}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sdk', type=Path, default=os.environ.get('ANDROID_HOME'))
    parser.add_argument('--output', type=Path, default=Path('build/audit/android/package.json'))
    parser.add_argument('apks', nargs='*', type=Path)
    args = parser.parse_args()
    if not args.sdk:
        parser.error('--sdk or ANDROID_HOME is required')
    apks = args.apks or sorted(Path('build/app/outputs/flutter-apk').glob('*-release.apk'))
    assert apks, 'No release APKs found'
    report = [audit(apk, args.sdk) for apk in apks]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(f'Verified {len(report)} APK(s). Report: {args.output}')


if __name__ == '__main__':
    main()
