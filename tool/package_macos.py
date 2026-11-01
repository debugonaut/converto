#!/usr/bin/env python3
"""Package offline Mac apps for each CPU; never installs runtime components."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

from macos_bundle import architectures, macho_files, verify_variant
from package_cli import third_party_notices

ROOT = Path(__file__).resolve().parents[1]
ASSET_KEYS = {'arm64': 'macos_arm64', 'x86_64': 'macos_x64'}


def bundle_bytes(app):
    return sum(file.stat().st_size for file in app.rglob('*')
               if file.is_file() and not file.is_symlink())


def package(app, output, architecture):
    archive = output / f'Converto-macOS-{architecture}.zip'
    with tempfile.TemporaryDirectory(prefix='.converto-package-', dir=output) as temporary:
        candidate = Path(temporary) / 'Converto.app'
        subprocess.run(['ditto', str(app), str(candidate)], check=True)
        for file in macho_files(candidate):
            present = architectures(file)
            if architecture not in present:
                raise ValueError(f'{architecture} missing from {file.relative_to(candidate)}')
            if len(present) > 1:
                thinned = file.with_name(file.name + '.thin')
                subprocess.run(['lipo', str(file), '-thin', architecture, '-output', str(thinned)], check=True)
                thinned.replace(file)
        # Keep the selected engine/Objective-C mappings; every engine is bundled.
        for manifest in candidate.rglob('NativeAssetsManifest.json'):
            value = json.loads(manifest.read_text())
            value['native-assets'] = {ASSET_KEYS[architecture]: value['native-assets'][ASSET_KEYS[architecture]]}
            manifest.write_text(json.dumps(value, separators=(',', ':')))
        resources = candidate / 'Contents/Resources'
        resources.joinpath('LICENSE').write_text(ROOT.joinpath('LICENSE').read_text())
        resources.joinpath('THIRD_PARTY_NOTICES.txt').write_text(third_party_notices(ROOT))
        subprocess.run(['codesign', '--force', '--deep', '--sign', '-', str(candidate)], check=True)
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(candidate)], check=True)
        executables = verify_variant(app, candidate, architecture)
        size = bundle_bytes(candidate)
        # Native ZIP preserves framework symlinks and opens with Archive Utility.
        subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent',
                        '--zlibCompressionLevel', '9', str(candidate), str(archive)], check=True)
        # Validate what users extract, including signatures and every code section.
        unpacked = Path(temporary) / 'unpacked'
        subprocess.run(['ditto', '-x', '-k', str(archive), str(unpacked)], check=True)
        extracted = unpacked / 'Converto.app'
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(extracted)], check=True)
        verify_variant(app, extracted, architecture)
    with archive.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    return {
        'architecture': architecture,
        'archive': archive.name,
        'bundleBytes': size,
        'archiveBytes': archive.stat().st_size,
        'sha256': digest,
        'verifiedExecutableFiles': executables,
        'executableSectionsUnchanged': True,
        'signing': 'ad-hoc developer preview; not notarized',
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, default=ROOT / 'build/macos/Build/Products/Release/Converto.app')
    parser.add_argument('--output-dir', type=Path, default=ROOT)
    parser.add_argument('--architectures', nargs='+', choices=ASSET_KEYS, default=list(ASSET_KEYS))
    parser.add_argument('--report', type=Path, default=ROOT / 'build/audit/gui/package.json')
    args = parser.parse_args()
    app, output = args.app.resolve(), args.output_dir.resolve()
    if not app.is_dir():
        parser.error('Build the macOS app first')
    output.mkdir(parents=True, exist_ok=True)
    metadata = {
        'universalBundleBytes': bundle_bytes(app),
        'packages': [package(app, output, arch) for arch in dict.fromkeys(args.architectures)],
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(metadata, indent=2) + '\n')
    print(json.dumps(metadata, indent=2))


if __name__ == '__main__':
    main()
