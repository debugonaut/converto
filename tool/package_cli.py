#!/usr/bin/env python3
"""Package an already verified native bundle; never downloads or publishes."""
import argparse
import json
from pathlib import Path
import urllib.parse
from urllib.request import url2pathname
import zipfile


def main():
    p=argparse.ArgumentParser()
    p.add_argument('--binary',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    a=p.parse_args()
    root=Path(__file__).resolve().parents[1]
    binary=a.binary.resolve()
    bundle=binary.parent.parent
    assert binary.is_file() and (bundle/'lib').is_dir(), 'Build a complete native bundle first'
    a.output.parent.mkdir(parents=True,exist_ok=True)
    notices=[]
    config=root/'.dart_tool/package_config.json'
    for package in json.loads(config.read_text())['packages']:
        uri=urllib.parse.urljoin(config.as_uri(),package['rootUri'])
        location=Path(url2pathname(urllib.parse.urlparse(uri).path))
        if location==root:continue
        for license_file in sorted(location.glob('LICENSE*')):
            if license_file.is_file():
                notices.append(f"{package['name']} / {license_file.name}\n{'='*60}\n"+license_file.read_text(errors='replace'))
        if package['name']=='pdf_manipulator':
            for license_file in sorted((location/'vendor').glob('*/LICENSE*')):
                if license_file.is_file():
                    notices.append(str(license_file.relative_to(location))+'\n'+license_file.read_text(errors='replace'))
    with zipfile.ZipFile(a.output,'w',zipfile.ZIP_DEFLATED) as z:
        for file in sorted(bundle.rglob('*')):
            if file.is_file():z.write(file,file.relative_to(bundle))
        z.write(root/'LICENSE','LICENSE')
        z.write(root/'README.md','README.md')
        z.writestr('THIRD_PARTY_NOTICES.txt','\n\n'.join(notices))
    print(f'{a.output}: {a.output.stat().st_size} bytes')


if __name__=='__main__':main()
