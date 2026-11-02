"""Inspect built iOS apps; device packages are unsigned developer previews."""
import argparse
import json
from pathlib import Path
import plistlib
from app_version import version_info
from macos_bundle import macho_files, architectures


def audit(app):
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    version, build = version_info()
    assert info['CFBundleIdentifier'] == 'com.converto.app'
    assert info['CFBundleShortVersionString'] == version
    assert info['CFBundleVersion'] == str(build)
    assert float(info['MinimumOSVersion']) >= 15
    assert info['UIApplicationSceneManifest']
    assert not info.get('UIFileSharingEnabled', False)
    assert not info.get('NSAppTransportSecurity', {}).get('NSAllowsArbitraryLoads', False)
    engines = [path for path in macho_files(app) if 'pdf_oxide' in path.as_posix()]
    assert engines, 'Missing bundled PDF engine'
    native = {str(path.relative_to(app)): architectures(path) for path in macho_files(app)}
    assert native and all(value for value in native.values())
    manifests = list(app.rglob('NativeAssetsManifest.json'))
    return {'app': str(app), 'version': version, 'build': build,
            'minimumIOS': info['MinimumOSVersion'], 'platforms': info.get('CFBundleSupportedPlatforms'),
            'bundleIdentifier': info['CFBundleIdentifier'], 'nativeLibraries': native,
            'nativeAssetManifests': [str(path.relative_to(app)) for path in manifests],
            'deviceDistribution': 'Requires developer signing before device installation or TestFlight'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    parser.add_argument('--output', type=Path, default=Path('build/audit/ios/simulator.json'))
    args = parser.parse_args()
    report = audit(args.app)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(f'Verified iOS {report["version"]} build {report["build"]}: {args.output}')


if __name__ == '__main__':
    main()
