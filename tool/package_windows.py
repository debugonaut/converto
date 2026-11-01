#!/usr/bin/env python3
"""Package the complete release app and app-local Microsoft CRT for offline use."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import zipfile

from package_cli import third_party_notices
from windows_bundle import digest, files, validate, verify_archive


def locate_crt():
    vswhere = Path(os.environ.get('ProgramFiles(x86)', r'C:\Program Files (x86)')) / 'Microsoft Visual Studio/Installer/vswhere.exe'
    if not vswhere.is_file():
        raise RuntimeError('Visual Studio redistributable discovery is unavailable')
    installation = subprocess.check_output([
        str(vswhere), '-latest', '-products', '*', '-requires',
        'Microsoft.VisualStudio.Component.VC.Tools.x86.x64', '-property', 'installationPath',
    ], text=True).strip()
    candidates = list((Path(installation) / 'VC/Redist/MSVC').glob('*/x64/Microsoft.VC*.CRT'))
    candidates.sort(key=lambda p: tuple(int(n) for n in p.parents[1].name.split('.') if n.isdigit()))
    if not candidates:
        raise RuntimeError('No x64 app-local Microsoft C++ release runtime found')
    return candidates[-1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--app', type=Path, default=Path('build/windows/x64/runner/Release'))
    parser.add_argument('--output', type=Path, default=Path('Converto-Windows-x64.zip'))
    parser.add_argument('--report', type=Path, default=Path('build/audit/windows-app/package.json'))
    parser.add_argument('--vc-redist-dir', type=Path)
    args = parser.parse_args()
    if os.name != 'nt':
        raise RuntimeError('Build and package Windows releases on Windows')
    root = Path(__file__).resolve().parents[1]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='converto-windows-') as temporary:
        staging = Path(temporary) / 'app'
        shutil.copytree(args.app, staging, ignore=shutil.ignore_patterns('*.pdb', '*.lib', '*.exp'))
        crt = args.vc_redist_dir or locate_crt()
        for library in crt.glob('*.dll'):
            shutil.copy2(library, staging / library.name)
        shutil.copy2(root / 'LICENSE', staging / 'LICENSE')
        (staging / 'THIRD_PARTY_NOTICES.txt').write_text(third_party_notices(root), encoding='utf-8')
        (staging / 'START_HERE.txt').write_text(
            'Converto for Windows 10/11 x64 — developer preview\n\n'
            '1. Extract the entire ZIP to a writable folder.\n'
            '2. Open Converto.exe from that folder. Keep data/ and the DLLs beside it.\n\n'
            'The bundled app and PDF/image engines work locally without accounts,\n'
            'runtime downloads, or a separate C++ runtime installer. No administrator\n'
            'installation is required. Processing uses available RAM and disk.\n'
            'Some Office formats and WebP encoding need optional locally installed\n'
            'helpers; they are never downloaded automatically.\n\n'
            'Choose output names and a folder before Run. Originals are preserved.\n'
            'Local preferences/history are stored in your user profile, not the app\n'
            'folder. Ctrl+O chooses files; Ctrl+F focuses tool search.\n\n'
            'This preview is not code-signed. Native Explorer drag/drop and file\n'
            'dialog checks still require a real Windows desktop manual pass.\n', encoding='utf-8')
        validate(staging)
        with zipfile.ZipFile(args.output, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
            for path in files(staging):
                archive.write(path, path.relative_to(staging))
        extracted = Path(temporary) / 'extracted'
        binaries = verify_archive(args.output, staging, extracted)
        # Load the packaged runtime using application-local DLL search paths.
        # This validates dependencies without PATH entries from the build tree.
        loader = (
            'import ctypes,os,sys; from pathlib import Path; '
            'root=Path(sys.argv[1]); search=os.add_dll_directory(str(root)); '
            'libraries=[ctypes.WinDLL(str(root/name)) for name in sys.argv[2:]]'
        )
        subprocess.run([sys.executable, '-c', loader, str(extracted),
                        'vcruntime140.dll', 'vcruntime140_1.dll', 'msvcp140.dll',
                        'flutter_windows.dll', 'desktop_drop_plugin.dll', 'pdf_oxide.dll'],
                       cwd=temporary, timeout=30, check=True,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        # First Flutter frame, no visible app window or interactive UI automation.
        # The source/build directories are not the current working directory.
        env = dict(os.environ)
        env['CONVERTO_DATA_DIR'] = str(Path(temporary) / 'profile')
        env['CONVERTO_OUTPUT_DIR'] = str(Path(temporary) / 'outputs')
        env['CONVERTO_HISTORY'] = 'off'
        subprocess.run([str(extracted / 'Converto.exe'), '--converto-startup-probe'],
                       cwd=temporary, env=env, timeout=45, check=True,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        report = {
            'architecture': 'x64', 'minimumWindows': 'Windows 10',
            'archive': args.output.name, 'archiveBytes': args.output.stat().st_size,
            'bundleBytes': sum(p.stat().st_size for p in files(extracted)),
            'sha256': digest(args.output), 'verifiedBinaryFiles': binaries,
            'allFilesUnchangedAfterZip': True, 'privateRuntimeDllLoads': 'pass',
            'firstFlutterFrame': 'pass', 'vcRuntimeAppLocal': True,
            'signing': 'unsigned developer preview',
        }
        args.report.write_text(json.dumps(report, indent=2), encoding='utf-8')
        print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
