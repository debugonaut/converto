#!/usr/bin/env python3
"""Package the full local app with notices and a verifiable ad-hoc signature."""
from pathlib import Path
import json
import subprocess
from package_cli import third_party_notices

root = Path(__file__).resolve().parents[1]
app = root / 'build/macos/Build/Products/Release/Converto.app'
assert app.is_dir(), 'Build the macOS app first'
resources = app / 'Contents/Resources'
resources.joinpath('LICENSE').write_text(root.joinpath('LICENSE').read_text())
resources.joinpath('THIRD_PARTY_NOTICES.txt').write_text(third_party_notices(root))
subprocess.run(['codesign', '--force', '--deep', '--sign', '-', str(app)], check=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
archive = root / 'Converto-macOS-preview.zip'
subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(app), str(archive)], check=True)
metadata = {
    'bundleBytes': sum(file.stat().st_size for file in app.rglob('*') if file.is_file() and not file.is_symlink()),
    'archiveBytes': archive.stat().st_size,
    'signing': 'ad-hoc developer preview; not notarized',
}
root.joinpath('build/audit/gui/package.json').write_text(json.dumps(metadata, indent=2))
print(json.dumps(metadata))
