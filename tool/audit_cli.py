#!/usr/bin/env python3
"""Independent, local CLI acceptance audit. Requires Pillow and PyMuPDF.

python3 tool/audit_cli.py --binary build/cli/<platform>/bundle/bin/converto \
    --output build/audit/after

Never downloads fixtures or dependencies. Results include command output and timing;
fixture paths and passwords are synthetic. Does not open files in desktop apps.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import time
import zipfile
import shlex
import xml.etree.ElementTree as ET

from PIL import Image, ImageChops, ImageStat, ImageFilter
import pymupdf as fitz


def quote_terminal_arg(value):
    """Quote text sent to the interactive CLI, not process argv."""
    value = str(value)
    if os.name == 'nt':
        return "'" + value.replace("'", "''") + "'"
    return shlex.quote(value)


def make_fixtures(directory):
    directory.mkdir(parents=True, exist_ok=True)
    image = Image.new('RGBA', (64, 48))
    image.putdata([((x * 13) % 256, (x * 7) % 256, (x * 3) % 256,
                    128 if x % 7 == 0 else 255) for x in range(64 * 48)])
    for ext, fmt in [('png', 'PNG'), ('jpg', 'JPEG'), ('jpeg', 'JPEG'),
                     ('webp', 'WEBP'), ('bmp', 'BMP'), ('gif', 'GIF'),
                     ('tiff', 'TIFF'), ('ico', 'ICO')]:
        src = image.convert('RGB') if ext in ('jpg', 'jpeg', 'bmp') else image
        src.save(directory / f'image.{ext}', format=fmt)
    shutil.copyfile(directory/'image.tiff',directory/'image.tif')
    image.save(directory / 'animation.gif', save_all=True,
               append_images=[Image.new('RGBA', image.size, 'blue')], duration=100, loop=0)
    image.save(directory / 'multipage.tiff', save_all=True,
               append_images=[Image.new('RGBA', image.size, 'red')])
    (directory / 'document.txt').write_text('Audit Alpha\nSECRET token\nLocal only\n')
    (directory / 'document.rtf').write_text(r'{\rtf1\ansi Audit Alpha\par SECRET token\par Local only}')
    (directory / 'table.csv').write_text('Name,Value,Note\nAlice,12,"hello, world"\nBob,3,local\n')
    pdf = fitz.open()
    for index in range(3):
        page = pdf.new_page(width=300, height=400)
        page.insert_text((30, 50), f'Audit page {index + 1}: SECRET token', fontsize=12)
        page.insert_text((30, 90), 'Retained Alpha content', fontsize=12)
    pdf.save(directory / 'document.pdf')
    pdf.close()

    def archive(name, files):
        with zipfile.ZipFile(directory / name, 'w', zipfile.ZIP_DEFLATED) as z:
            for member, content in files.items():
                z.writestr(member, content)

    ns = 'http://schemas.openxmlformats.org'
    relns = f'{ns}/package/2006/relationships'
    offns = f'{ns}/officeDocument/2006/relationships'
    types = f'{ns}/package/2006/content-types'
    archive('document.docx', {
        '[Content_Types].xml': f'<Types xmlns="{types}"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>',
        '_rels/.rels': f'<Relationships xmlns="{relns}"><Relationship Id="rId1" Type="{offns}/officeDocument" Target="word/document.xml"/></Relationships>',
        'word/document.xml': f'<w:document xmlns:w="{ns}/wordprocessingml/2006/main"><w:body><w:p><w:r><w:t>Audit Alpha SECRET token</w:t></w:r></w:p></w:body></w:document>',
    })
    archive('document.odt', {
        'mimetype': 'application/vnd.oasis.opendocument.text',
        'META-INF/manifest.xml': '<manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0"><manifest:file-entry manifest:full-path="/" manifest:media-type="application/vnd.oasis.opendocument.text"/><manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/></manifest:manifest>',
        'content.xml': '<office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"><office:body><office:text><text:p>Audit Alpha SECRET token</text:p></office:text></office:body></office:document-content>',
    })
    archive('table.xlsx', {
        '[Content_Types].xml': f'<Types xmlns="{types}"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>',
        '_rels/.rels': f'<Relationships xmlns="{relns}"><Relationship Id="rId1" Type="{offns}/officeDocument" Target="xl/workbook.xml"/></Relationships>',
        'xl/workbook.xml': f'<workbook xmlns="{ns}/spreadsheetml/2006/main" xmlns:r="{offns}"><sheets><sheet name="Audit" sheetId="1" r:id="rId1"/></sheets></workbook>',
        'xl/_rels/workbook.xml.rels': f'<Relationships xmlns="{relns}"><Relationship Id="rId1" Type="{offns}/worksheet" Target="worksheets/sheet1.xml"/></Relationships>',
        'xl/worksheets/sheet1.xml': f'<worksheet xmlns="{ns}/spreadsheetml/2006/main"><sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>Name</t></is></c><c r="B1" t="inlineStr"><is><t>Value</t></is></c></row><row r="2"><c r="A2" t="inlineStr"><is><t>Alice</t></is></c><c r="B2"><v>12</v></c></row></sheetData></worksheet>',
    })
    pns = f'{ns}/presentationml/2006/main'
    ans = f'{ns}/drawingml/2006/main'
    files = {
        '[Content_Types].xml': f'<Types xmlns="{types}"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>' + ''.join(f'<Override PartName="/ppt/slides/slide{i}.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>' for i in range(1, 13)) + '</Types>',
        '_rels/.rels': f'<Relationships xmlns="{relns}"><Relationship Id="rId1" Type="{offns}/officeDocument" Target="ppt/presentation.xml"/></Relationships>',
        'ppt/presentation.xml': f'<p:presentation xmlns:p="{pns}" xmlns:r="{offns}"><p:sldIdLst>' + ''.join(f'<p:sldId id="{255+i}" r:id="rId{i}"/>' for i in range(1, 13)) + '</p:sldIdLst><p:sldSz cx="9144000" cy="6858000"/><p:notesSz cx="6858000" cy="9144000"/></p:presentation>',
        'ppt/_rels/presentation.xml.rels': f'<Relationships xmlns="{relns}">' + ''.join(f'<Relationship Id="rId{i}" Type="{offns}/slide" Target="slides/slide{i}.xml"/>' for i in range(1, 13)) + '</Relationships>',
    }
    for i in range(1, 13):
        files[f'ppt/slides/slide{i}.xml'] = f'<p:sld xmlns:p="{pns}" xmlns:a="{ans}"><p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/><p:sp><p:nvSpPr><p:cNvPr id="2" name="Title"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x="457200" y="457200"/><a:ext cx="8229600" cy="914400"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:noFill/><a:ln><a:noFill/></a:ln></p:spPr><p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:rPr lang="en-US" sz="2800"><a:solidFill><a:srgbClr val="111111"/></a:solidFill></a:rPr><a:t>Slide {i} Audit Alpha</a:t></a:r></a:p></p:txBody></p:sp></p:spTree></p:cSld></p:sld>'
    archive('slides.pptx', files)
    # The optional fixture builder is local LibreOffice; absence is an explicit skip.
    legacy = Path(__file__).resolve().parents[1]/'test'/'fixtures'/'legacy'
    for name in ['document.doc','table.xls','slides.ppt','slides.odp']:
        if (legacy/name).exists(): shutil.copyfile(legacy/name, directory/name)
    helper = shutil.which('soffice')
    if helper:
        for src, target in [('document.docx', 'doc'), ('table.xlsx', 'xls'), ('slides.pptx', 'ppt'), ('slides.pptx', 'odp')]:
            try:
                subprocess.run([helper, '--headless', '--convert-to', target,
                                str(directory / src), '--outdir', str(directory)],
                               capture_output=True, timeout=30, check=False)
            except subprocess.TimeoutExpired:
                pass
    return directory


def validate(path, kind, pages=None, contains=None):
    assert path.is_file(), f'Missing output: {path.name}'
    assert path.stat().st_size, 'Empty output'
    if kind == 'pdf':
        with fitz.open(path) as doc:
            assert not doc.needs_pass, 'Unexpected encrypted output'
            if pages is not None:
                assert len(doc) == pages, f'Expected {pages} pages, got {len(doc)}'
            text = ''.join(p.get_text() for p in doc)
            if contains:
                assert contains in text, f'Missing text {contains!r}'
    elif kind in ['docx', 'xlsx', 'pptx']:
        with zipfile.ZipFile(path) as z:
            prefix = {'docx': 'word/document.xml', 'xlsx': 'xl/workbook.xml', 'pptx': 'ppt/presentation.xml'}[kind]
            assert prefix in z.namelist(), f'Missing {prefix}'
            for member in z.namelist():
                if member.endswith('.xml'):
                    ET.fromstring(z.read(member))
            if contains:
                assert contains in ''.join(z.read(x).decode(errors='replace') for x in z.namelist() if x.endswith('.xml')), f'Missing Office text {contains!r}'
    elif kind in ['txt', 'csv']:
        text = path.read_text(encoding='utf-8-sig')
        if contains:
            assert contains in text, f'Missing text {contains!r}'
        assert not text.startswith('{\\rtf'), 'RTF syntax copied as text'
        assert not text.startswith('PK\x03'), 'ZIP bytes copied as text'
    else:
        with Image.open(path) as image:
            actual = image.format.lower()
            expected = {'jpg': 'jpeg', 'tif': 'tiff'}.get(kind, kind)
            assert actual == expected, f'Expected {expected}, got {actual}'
            image.load()


def validate_conversion(source, dest, target):
    image_sources={'.png','.jpg','.jpeg','.webp','.bmp','.gif','.tiff','.tif','.ico'}
    expected=None
    if source.suffix in ['.docx','.doc','.odt','.rtf','.txt'] and target in ['pdf','txt']:expected='Audit Alpha'
    elif source.suffix in ['.xlsx','.xls','.csv'] and target in ['pdf','csv']:expected='Alice'
    elif source.suffix in ['.pptx','.ppt','.odp'] and target=='pdf':expected='Slide 12 Audit Alpha'
    elif source.suffix=='.pdf' and target in ['txt','docx','xlsx','pptx','pdf']:expected='Audit'
    validate(dest,target,pages=(1 if source.suffix in image_sources else 12 if source.suffix in ['.pptx','.ppt','.odp'] else None) if target=='pdf' else None,contains=expected)
    if source.suffix in ['.pptx','.ppt','.odp','.pdf'] and target in ['png','jpg','jpeg']:
        with Image.open(dest) as rendered:
            assert rendered.convert('L').getextrema()[0]<245, 'Rendered page/slide is blank'

    if source.suffix in image_sources and target!='pdf':
        with Image.open(source) as original,Image.open(dest) as result:
            assert original.size==result.size, f'Image dimensions changed: {original.size} to {result.size}'
            if target in ['png','tiff']:
                def composite(im):
                    rgba=im.convert('RGBA')
                    return Image.alpha_composite(Image.new('RGBA',im.size,'white'),rgba).convert('RGB')
                error=ImageStat.Stat(ImageChops.difference(composite(original),composite(result))).mean
                compared_error=error
                if original.format=='JPEG':
                    # libjpeg uses interpolated chroma; image 4.3 uses nearest-neighbour
                    # upsampling. Both decode JPEG correctly. Compare low-frequency
                    # colours and retain the unfiltered difference in the evidence.
                    reference=composite(original).filter(ImageFilter.GaussianBlur(1.5))
                    decoded=composite(result).filter(ImageFilter.GaussianBlur(1.5))
                    compared_error=ImageStat.Stat(ImageChops.difference(reference,decoded)).mean
                assert max(compared_error)<=5, f'Lossless target changed visible colors: mean absolute error {compared_error}'
                return dict(raw_rgb_mean_absolute_error=error,compared_rgb_mean_absolute_error=compared_error,
                            jpeg_chroma_normalized=original.format=='JPEG',threshold=5)


class Audit:
    def __init__(self, binary, output, fixtures, profile):
        self.binary, self.output, self.fixtures = binary, output, fixtures
        self.results = []
        self.profile = profile
        self.env = dict(os.environ, CONVERTO_OUTPUT_DIR=str(output / 'default'),
                        CONVERTO_DATA_DIR=str(output / 'state'))
        if profile == 'standalone': self.env['CONVERTO_DISABLE_HELPERS']='1'

    def case(self, name, args, check=None, expected=0, stdin='', group='operation', timeout=15, env=None, status='pass'):
        start = time.perf_counter()
        record = dict(name=name, group=group, args=[str(a) for a in args])
        try:
            r = subprocess.run([str(self.binary), *record['args']], input=stdin,
                               text=True, encoding='utf-8', capture_output=True, timeout=timeout,
                               cwd=self.output, env=self.env | (env or {}))
            record.update(exit_code=r.returncode, stdout=r.stdout, stderr=r.stderr)
            assert (r.returncode == 0) if expected == 0 else (r.returncode != 0), f'Unexpected exit {r.returncode}'
            if check:
                details=check(r)
                if isinstance(details,dict):record['verification']=details
            record['status'] = status
        except Exception as error:
            record.update(status='fail', error=str(error))
        if '-o' in record['args']:
            destination=Path(record['args'][record['args'].index('-o')+1])
            files=[destination] if destination.is_file() else list(destination.rglob('*')) if destination.is_dir() else []
            record['output_bytes']=sum(f.stat().st_size for f in files if f.is_file())
        record['input_bytes']=sum(Path(a).stat().st_size for i,a in enumerate(record['args'])
                                  if (i==0 or record['args'][i-1]!='-o') and Path(a).is_file())
        record['wall_ms'] = round((time.perf_counter() - start) * 1000, 3)
        self.results.append(record)
        return record

    def matrix(self):
        groups = [(['image.' + x for x in ['jpg','jpeg','png','webp','bmp','gif','tiff','tif','ico']], ['pdf','png','jpg','jpeg','webp','bmp','tiff','gif','ico']),
                  (['document.' + x for x in ['docx','doc','odt','rtf','txt']], ['pdf','txt']),
                  (['table.' + x for x in ['xlsx','xls','csv']], ['pdf','csv']),
                  (['slides.' + x for x in ['pptx','ppt','odp']], ['pdf','png','jpg']),
                  (['document.pdf'], ['png','jpg','jpeg','txt','docx','xlsx','pptx','pdf'])]
        for sources, targets in groups:
            for src in sources:
                for target in targets:
                    name = f'{src}-to-{target}'
                    source = self.fixtures / src
                    if not source.exists():
                        self.results.append(dict(name=name, group='format', status='skip', error='Local legacy fixture builder unavailable'))
                        continue
                    dest = self.output / f'{name}.{target}'
                    needs_helper = (target=='webp' or source.suffix in ['.doc','.rtf','.xls','.ppt','.odp'] or (source.suffix=='.odt' and target=='pdf'))
                    if self.profile=='standalone' and needs_helper:
                        self.case(name,['convert',source,'-t',target,'-o',dest],
                                  lambda r,d=dest: require('requires' in (r.stdout+r.stderr).lower() and not d.exists(),'Missing truthful helper diagnostic'),expected=1,group='format',status='unsupported')
                        continue
                    self.case(name, ['convert', source, '-t', target, '-o', dest],
                              lambda r, d=dest, t=target, s=source: validate_conversion(s,d,t), group='format')

    def operations(self):
        p = self.fixtures / 'document.pdf'
        image = self.fixtures / 'image.png'
        def pdfcase(name, args, pages=3, contains=None):
            dest = self.output / f'{name}.pdf'
            self.case(name, [*args, '-o', dest], lambda r: validate(dest, 'pdf', pages, contains))
        pdfcase('merge-pdfs', ['merge', p, p], 6)
        pdfcase('merge-images', ['merge', image, image], 2)
        pdfcase('merge-image-pdf', ['merge', image, p], 4, 'Audit page 3')
        pdfcase('merge-pdf-image', ['merge', p, image], 4, 'Audit page 3')
        for mode, value, counts in [('--every','2',[2,1]),('--pages','1-2,3',[2,1]),('--size','10KB',None)]:
            dest = self.output / ('parts-' + mode[2:])
            def check(r, dest=dest, counts=counts):
                files = sorted(dest.glob('*.pdf'))
                assert files, 'No split parts'
                actual = []
                for f in files:
                    with fitz.open(f) as doc: actual.append(len(doc))
                assert sum(actual) == 3, actual
                if counts: assert actual == counts, actual
            self.case('split-' + mode[2:], ['split',p,mode,value,'-o',dest], check)
        pdfcase('extract', ['extract',p,'--pages','3,1'], 2, 'Audit page 3')
        pdfcase('organize-order', ['organize',p,'--order','3,2,1'])
        pdfcase('organize-delete', ['organize',p,'--delete','2'], 2)
        pdfcase('rotate', ['rotate',p,'--degrees','90'])
        pdfcase('crop', ['crop',p,'--left','12','--top','12'])
        for level in ['screen','ebook','print','lossless']:
            pdfcase('compress-' + level, ['compress',p,'--level',level], contains='Audit page 1')
        pdfcase('watermark', ['watermark',p,'--text','LOCAL'], contains='Audit page 1')
        pdfcase('page-numbers', ['page-numbers',p])
        protected = self.output / 'protected.pdf'
        def encryption_check(r):
            with fitz.open(protected) as d:
                assert d.needs_pass, 'No PDF encryption'
                assert d.authenticate('audit-password'), 'Wrong password set'
                assert len(d) == 3
        self.case('protect', ['protect',p,'--password','audit-password','-o',protected], encryption_check)
        pdfcase('unlock', ['unlock',protected,'--password','audit-password'], contains='Audit page 1')
        self.case('unlock-wrong-password', ['unlock',protected,'--password','wrong','-o',self.output/'wrong.pdf'], expected=1, group='edge')
        for fmt in ['png','jpg','jpeg']:
            dest = self.output / f'pages-{fmt}'
            def pagescheck(r, dest=dest, fmt=fmt):
                files = list(dest.iterdir())
                assert len(files) == 3, f'Expected 3 pages, got {len(files)}'
                for f in files: validate(f, fmt)
            self.case('pdf2img-' + fmt, ['pdf2img',p,'--to',fmt,'--dpi','72','-o',dest], pagescheck)
        dest = self.output / 'text.txt'
        self.case('pdf2text', ['pdf2text',p,'-o',dest], lambda r: validate(dest,'txt',contains='Audit page 3'))
        for fmt in ['docx','xlsx','pptx']:
            dest = self.output / f'office.{fmt}'
            self.case('pdf2office-' + fmt, ['pdf2office',p,'--to',fmt,'-o',dest], lambda r,d=dest,t=fmt: validate(d,t))
        for level in ['1','2','3']:
            pdfcase('pdfa-' + level, ['pdfa',p,'--level',level])
        redacted = self.output / 'redacted.pdf'
        def redactcheck(r):
            validate(redacted,'pdf',3)
            with fitz.open(redacted) as doc:
                assert 'SECRET' not in ''.join(page.get_text() for page in doc), 'Secret text survives redaction'
                assert all('Retained Alpha content' in page.get_text() for page in doc), 'Unrelated text lost'
        self.case('redact', ['redact',p,'--text','SECRET','-o',redacted], redactcheck)
        self.case('info', ['info',p], lambda r: require('Pages:     3' in r.stdout, 'Wrong page info'))
        dest = self.output / 'edited.png'
        self.case('edit', ['edit-image',image,'--rotate','90','--flip-h','-o',dest], lambda r: validate(dest,'png'))
        for command in ['formats','privacy','recent','help','clear','exit']:
            self.case('slash-' + command, ['interactive'], stdin=f'/{command}\n/exit\n')

    def edges(self):
        p, image = self.fixtures/'document.pdf', self.fixtures/'image.png'
        invalid = [('split-zero',['split',p,'--every','0']),
                   ('split-too-small',['split',p,'--size','1B']),
                   ('extract-zero',['extract',p,'--pages','0']),
                   ('extract-overflow',['extract',p,'--pages','4']),
                   ('extract-reversed',['extract',p,'--pages','3-1']),
                   ('delete-all',['organize',p,'--delete','1-3']),
                   ('rotate-invalid',['rotate',p,'--degrees','45']),
                   ('crop-negative',['crop',p,'--left','-1']),
                   ('crop-too-large',['crop',p,'--left','9999']),
                   ('crop-nan',['crop',p,'--left','NaN']),
                   ('dpi-zero',['pdf2img',p,'--dpi','0']),
                   ('dpi-negative',['pdf2img',p,'--dpi','-1']),
                   ('quality-zero',['convert',image,'-t','jpg','--quality','0']),
                   ('quality-overflow',['convert',image,'-t','jpg','--quality','101']),
                   ('quality-invalid',['convert',image,'-t','jpg','--quality','abc']),
                   ('edit-unsupported',['edit-image',image,'--to','xyz']),
                   ('unsupported-target',['convert',image,'-t','xyz']),
                   ('missing-input',['convert',self.fixtures/'missing.png','-t','pdf']),
                   ('redact-no-match',['redact',p,'--text','NOT_FOUND']),
                   ('pdfa-invalid',['pdfa',p,'--level','4'])]
        for name,args in invalid:
            self.case(name,[*args,'-o',self.output/(name+'.out')],expected=1,group='edge')
        for source in sorted(self.fixtures.iterdir()):
            if source.suffix not in ['.png','.jpg','.jpeg','.webp','.bmp','.gif','.tiff','.tif','.ico','.pdf','.docx','.doc','.odt','.rtf','.txt','.xlsx','.xls','.csv','.pptx','.ppt','.odp']: continue
            dest = self.output / f'drop-{source.name}.pdf'
            line = f"/convert '{source}' pdf -o '{dest}'\n/exit\n"
            if self.profile=='standalone' and source.suffix in ['.doc','.rtf','.odt','.xls','.ppt','.odp']:
                self.case('drop-'+source.name,['interactive'],lambda r,d=dest: require('requires' in (r.stdout+r.stderr).lower() and not d.exists(),'Missing helper diagnostic'),expected=1,stdin=line,group='drop',status='unsupported')
            else:
                self.case('drop-' + source.name,['interactive'], lambda r,d=dest: validate(d,'pdf'), stdin=line,group='drop')
        for name in ['space name.png', "apostrophe's.png", 'quote"name.png', 'a(1)&[2]#$.png', 'unicode-é-你好.png', '00~real01~.png']:
            if os.name == 'nt' and '"' in name:
                self.results.append(dict(name='escaped-'+name, group='drop', status='skip',
                                         error='Windows does not permit double quotes in filenames; parser-only coverage remains in the Dart tests.'))
                continue
            source = self.fixtures / name
            shutil.copyfile(image, source)
            dest = self.output / ('escaped-' + hashlib.sha256(name.encode()).hexdigest()[:8] + '.pdf')
            escaped = quote_terminal_arg(source) if os.name == 'nt' else ''.join('\\' + c if c in " \\'\"()&[]#$;" else c for c in str(source))
            self.case('escaped-' + name,['interactive'],lambda r,d=dest: validate(d,'pdf'),stdin=f'/convert {escaped} pdf -o "{dest}"\n/exit\n',group='drop')
        for ext in ['png','jpg','jpeg','webp','bmp','gif','tiff','ico','pdf','docx','doc','odt','xlsx','xls','pptx','ppt']:
            corrupt = self.fixtures / f'corrupt.{ext}'
            corrupt.write_bytes(b'not a valid document\x00\xff')
            self.case('corrupt-' + ext,['convert',corrupt,'-t','pdf','-o',self.output/f'bad-{ext}.pdf'],expected=1,group='edge')
        for ext in ['pdf','csv','txt']:
            src = self.fixtures / ('table.csv' if ext=='csv' else 'document.'+ext)
            dest = self.output / f'copy.{ext}'
            self.case('same-format-copy-' + ext,['convert',src,'-t',ext,'-o',dest],lambda r,d=dest,s=src: require(d.is_file() and d.read_bytes()==s.read_bytes(),'Copy destination not honored'),group='edge')
        dest = self.output / 'output-directory'
        dest.mkdir(exist_ok=True)
        self.case('existing-output-directory',['convert',image,'-t','jpg','-o',dest],lambda r: validate(dest/'image.jpg','jpg'),group='edge')
        self.case('shorthand-missing-companion',[image,self.fixtures/'missing.png','pdf'],expected=1,group='edge')
        self.case('batch-all-fail',[image,image,'xyz'],expected=1,group='edge')
        self.case('empty-shell-eof',['interactive'],group='drop')
        self.case('pending-command-eof',['interactive'],stdin='/convert\n',group='drop')

    def extended(self):
        p, image = self.fixtures/'document.pdf', self.fixtures/'image.png'
        for encoding in ['utf-16-le','utf-16-be']:
            bom=b'\xff\xfe' if encoding.endswith('le') else b'\xfe\xff'
            for ext,content,word in [('txt','Audit Alpha\nLocal text','Audit Alpha'),('csv','Name,Value\nAlice,12\n','Alice')]:
                source=self.fixtures/f'{encoding}.{ext}';source.write_bytes(bom+content.encode(encoding))
                dest=self.output/f'{encoding}-{ext}.pdf'
                self.case('windows-encoding-'+encoding+'-'+ext,['convert',source,'-t','pdf','-o',dest],
                          lambda r,d=dest,w=word:validate(d,'pdf',contains=w),group='edge')
        source=self.fixtures/'utf-16-le.txt';dest=self.output/'utf16-copy.txt'
        self.case('utf16-copy-preserves-encoding',['convert',source,'-t','txt','-o',dest],
                  lambda r:require(source.read_bytes()==dest.read_bytes(),'Text copy changed encoding'),group='edge')
        source=self.fixtures/'truncated.txt';source.write_bytes(b'\xff\xfeA')
        self.case('truncated-utf16-rejected',['convert',source,'-t','pdf','-o',self.output/'truncated.pdf'],expected=1,group='edge')
        for ext in ['txt','csv','docx','pptx']:
            source=self.fixtures/f'unicode-content.{ext}'
            if ext in ['txt','csv']:
                source.write_text('Audit Alpha 你好\n' if ext=='txt' else 'Name,Value\n你好,12\n', encoding='utf-8')
            else:
                original=self.fixtures/('document.docx' if ext=='docx' else 'slides.pptx')
                with zipfile.ZipFile(original) as old,zipfile.ZipFile(source,'w',zipfile.ZIP_DEFLATED) as z:
                    for member in old.namelist():z.writestr(member,old.read(member).replace(b'Audit Alpha','Audit Alpha 你好'.encode()))
            dest=self.output/f'unicode-content-{ext}.pdf'
            if self.profile=='standalone':
                self.case('unicode-font-safety-'+ext,['convert',source,'-t','pdf','-o',dest],
                          lambda r,d=dest:require('requires' in (r.stdout+r.stderr).lower() and not d.exists(),'Unicode text was silently dropped'),
                          expected=1,group='edge',status='unsupported')
            else:
                self.case('unicode-font-safety-'+ext,['convert',source,'-t','pdf','-o',dest],
                          lambda r,d=dest:validate(d,'pdf',contains='你好'),group='edge')
        sources=sorted({Path(r['args'][1]) for r in self.results if r['group']=='format' and '-to-' in r['name']})
        for source in sources:
            target='png' if source.suffix=='.pdf' else 'pdf'
            directory=self.output/'bare-drops'/source.name
            line=quote_terminal_arg(source)+'\n1\n'+target+'\n/exit\n'
            needs_helper=source.suffix in ['.doc','.rtf','.odt','.xls','.ppt','.odp']
            if self.profile=='standalone' and needs_helper:
                self.case('bare-drop-'+source.name,['interactive'],expected=1,stdin=line,group='drop',
                          env={'CONVERTO_OUTPUT_DIR':str(directory)},status='unsupported',
                          check=lambda r,d=directory:require('requires' in (r.stdout+r.stderr).lower() and not list(d.glob('*')),'Missing helper diagnostic on bare drop'))
            else:
                def barecheck(r,d=directory,t=target):
                    files=list(d.glob('*.'+t));require(len(files)==1,'Bare drop did not complete its action menu')
                    validate(files[0],t)
                self.case('bare-drop-'+source.name,['interactive'],barecheck,stdin=line,group='drop',
                          env={'CONVERTO_OUTPUT_DIR':str(directory)})
        selected={'merge-pdfs','split-every','extract','organize-order','rotate','crop',
                  'compress-ebook','watermark','page-numbers','protect','unlock',
                  'pdf2img-png','pdf2text','pdf2office-docx','pdfa-2','redact','info','edit'}
        for original in list(self.results):
            if original['name'] not in selected: continue
            tokens=list(original['args'])
            tokens[0] = 'edit' if tokens[0]=='edit-image' else tokens[0]
            dest=None
            if '-o' in tokens:
                i=tokens.index('-o')+1
                old=Path(tokens[i])
                dest=self.output/('slash-'+old.name)
                tokens[i]=str(dest)
            def check(r,dest=dest,command=tokens[0]):
                if command=='info': require('Pages:     3' in r.stdout,'Wrong slash info');return
                if command in ['split','pdf2img']:
                    files=sorted(dest.iterdir())
                    require(len(files)==(2 if command=='split' else 3),'Wrong slash output count')
                    for f in files: validate(f,'pdf' if command=='split' else 'png')
                elif command=='protect':
                    with fitz.open(dest) as doc: require(doc.needs_pass,'Slash protect is unencrypted')
                else: validate(dest,dest.suffix[1:])
            line='/'+tokens[0]+' '+' '.join(quote_terminal_arg(x) for x in tokens[1:])+'\n/exit\n'
            self.case('slash-'+tokens[0],['interactive'],check,stdin=line,group='slash')
        dest=self.output/'slash-convert.pdf'
        self.case('slash-convert',['interactive'],lambda r:validate(dest,'pdf',1),
                  stdin=f'/convert "{image}" pdf -o "{dest}"\n/exit\n',group='slash')

        # Independent semantics beyond signatures and exit codes.
        def pdf_semantics(r):
            with fitz.open(self.output/'rotated-check.pdf') as d:
                require(d[0].rotation==90 and round(d[0].rect.width)==400,'Wrong rotation geometry')
        self.case('rotate-geometry',['rotate',p,'--degrees','90','-o',self.output/'rotated-check.pdf'],pdf_semantics,group='edge')
        dest=self.output/'crop-check.pdf'
        def cropcheck(r):
            with fitz.open(dest) as d:require(round(d[0].rect.width)==288 and round(d[0].rect.height)==388,'Wrong crop geometry')
        self.case('crop-geometry',['crop',p,'--left','12','--top','12','-o',dest],cropcheck,group='edge')
        dest=self.output/'order-check.pdf'
        def ordercheck(r):
            with fitz.open(dest) as d:
                for index,page in enumerate(d):require(f'page {3-index}:' in page.get_text(),'Wrong page order')
        self.case('organize-content-order',['organize',p,'--order','3,2,1','-o',dest],ordercheck,group='edge')
        dest=self.output/'extract-check.pdf'
        def extractcheck(r):
            with fitz.open(dest) as d:require('page 3:' in d[0].get_text() and 'page 1:' in d[1].get_text(),'Wrong extraction order')
        self.case('extract-content-order',['extract',p,'--pages','3,1','-o',dest],extractcheck,group='edge')
        for level in ['screen','ebook','print','lossless']:
            dest=self.output/f'size-check-{level}.pdf'
            self.case('compress-never-grows-'+level,['compress',p,'--level',level,'-o',dest],
                      lambda r,d=dest:require(d.stat().st_size<=p.stat().st_size,'Compression increased storage'),group='edge')
        for ext in ['gif','tiff']:
            src=self.fixtures/('animation.gif' if ext=='gif' else 'multipage.tiff')
            dest=self.output/f'frames-{ext}.pdf'
            self.case('preserve-multiframe-'+ext,['convert',src,'-t','pdf','-o',dest],lambda r,d=dest:validate(d,'pdf',2),group='edge')
        for ext in ['gif','ico']:
            dest=self.output/('real-output.'+ext)
            self.case('encode-real-'+ext,['edit-image',image,'--to',ext,'-o',dest],lambda r,d=dest,t=ext:validate(d,t),group='format')
        exif=self.fixtures/'oriented.jpg'
        im=Image.new('RGB',(40,20),'green');metadata=im.getexif();metadata[274]=6;im.save(exif,exif=metadata)
        dest=self.output/'oriented.png'
        def orientation(r):
            with Image.open(dest) as im:require(im.size==(20,40),'EXIF orientation ignored')
        self.case('jpeg-exif-orientation',['convert',exif,'-t','png','-o',dest],orientation,group='edge')
        for args in [['rotate',p,'--degrees','abc'],['crop',p,'--left','abc'],
                     ['split',p,'--every','abc'],['pdfa',p,'--level','abc'],
                     ['watermark',p,'--text','X','--opacity','NaN'],
                     ['watermark',p,'--text','X','--opacity','2']]:
            self.case('invalid-value-'+args[0]+'-'+args[-1],[*args,'-o',self.output/'invalid-value.pdf'],expected=1,group='edge')
        for command in ['rotate','compress','pdf2office','pdfa','pdf2img']:
            self.case('slash-unknown-option-'+command,['interactive'],expected=1,
                      stdin=f'/{command} "{p}" --typo 1\n/exit\n',group='edge')
        sentinel=self.output/'existing.pdf';sentinel.write_bytes(b'ORIGINAL OUTPUT MUST SURVIVE')
        self.case('failed-write-preserves-existing',['convert',self.fixtures/'corrupt.png','-t','pdf','-o',sentinel],
                  lambda r:require(sentinel.read_bytes()==b'ORIGINAL OUTPUT MUST SURVIVE','Existing output lost'),expected=1,group='edge')
        src=self.output/'source.png';shutil.copyfile(image,src);before=src.read_bytes()
        self.case('mismatched-extension-preserves-source',['convert',src,'-t','jpg','-o',src],
                  lambda r:require(src.read_bytes()==before,'Source overwritten'),expected=1,group='edge')
        folder=self.fixtures/'drop-folder';folder.mkdir()
        shutil.copyfile(image,folder/'a.png');shutil.copyfile(image,folder/'b.png')
        (folder/'.hidden.png').write_bytes(b'corrupt hidden');(folder/'unsupported.zzz').write_text('skip')
        has_cycle = False
        try:
            os.symlink(folder,folder/'cycle',target_is_directory=True)
            has_cycle = True
        except OSError:
            if os.name != 'nt':
                raise
            self.results.append(dict(name='folder-symlink-cycle', group='drop', status='skip',
                                     error='Windows runner does not grant symlink creation privileges.'))
        dest=self.output/'folder.pdf'
        self.case('folder-snapshot-no-symlink-loop' if has_cycle else 'folder-snapshot',[folder,'pdf','-o',dest],lambda r:validate(dest,'pdf',2),group='drop')
        dest=self.output/'convert-folder.pdf'
        self.case('convert-command-folder',['convert',folder,'-t','pdf','-o',dest],lambda r:validate(dest,'pdf',2),group='drop')
        dest=self.output/'duplicate.pdf'
        self.case('duplicate-drop-preserves-order',[p,p,'pdf','-o',dest],lambda r:validate(dest,'pdf',6),group='drop')
        dest=self.output/'mixed-direct.pdf'
        self.case('mixed-direct-drop',[image,p,'pdf','-o',dest],lambda r:validate(dest,'pdf',4),group='drop')
        dest=self.output/'mixed-slash.pdf'
        self.case('multiple-files-at-convert',['interactive'],lambda r:validate(dest,'pdf',4),
                  stdin=f'/convert "{image}" "{p}" pdf -o "{dest}"\n/exit\n',group='drop')
        for name,content in [('lf','Name,Value\nAlice,001\nBob,002\n'),('crlf','Name,Value\r\nAlice,001\r\nBob,002\r\n'),('quoted','Name,Value\n"Alice, Test",001\nBob,"line1\nline2"\n')]:
            src=self.fixtures/f'{name}.csv';src.write_bytes(content.encode())
            dest=self.output/f'csv-{name}.pdf'
            self.case('csv-lines-'+name,['convert',src,'-t','pdf','-o',dest],lambda r,d=dest:validate(d,'pdf',contains='Bob'),group='edge')
        # A second sheet must not disappear in PDF output.
        multi=self.fixtures/'multi.xlsx'
        with zipfile.ZipFile(self.fixtures/'table.xlsx') as original,zipfile.ZipFile(multi,'w',zipfile.ZIP_DEFLATED) as z:
            for member in original.namelist():
                data=original.read(member)
                if member=='xl/workbook.xml':data=data.replace(b'</sheets>',b'<sheet name="Second" sheetId="2" r:id="rId2"/></sheets>')
                if member=='xl/_rels/workbook.xml.rels':data=data.replace(b'</Relationships>',b'<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/></Relationships>')
                if member=='[Content_Types].xml':data=data.replace(b'</Types>',b'<Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>')
                z.writestr(member,data)
            z.writestr('xl/worksheets/sheet2.xml','<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>SECOND_SHEET_CONTENT</t></is></c></row></sheetData></worksheet>')
        dest=self.output/'multi-sheet.pdf'
        self.case('xlsx-all-sheets',['convert',multi,'-t','pdf','-o',dest],lambda r:validate(dest,'pdf',pages=2,contains='SECOND_SHEET_CONTENT'),group='edge')
        dest=self.output/'folder-named.png';dest.mkdir()
        self.case('pdf2img-directory-with-image-suffix',['pdf2img',p,'--dpi','72','-o',dest],
                  lambda r:require(len(list(dest.glob('*.png')))==3,'Images were written outside the output directory'),group='edge')
        folder=self.output/'explicit-page-clash';folder.mkdir()
        first=folder/'document_page_2.png'
        def clash(r):
            files=list(folder.glob('*.png'))
            require(len(files)==3,'Explicit page filename overwrote another page')
            require(len({hashlib.sha256(f.read_bytes()).hexdigest() for f in files})==3,'Distinct pages were overwritten')
        self.case('pdf2img-first-name-collides-with-page-two',['pdf2img',p,'--dpi','72','-o',first],clash,group='edge')
        reordered=self.fixtures/'reordered.pptx'
        with zipfile.ZipFile(self.fixtures/'slides.pptx') as original,zipfile.ZipFile(reordered,'w',zipfile.ZIP_DEFLATED) as z:
            for member in original.namelist():
                data=original.read(member)
                if member=='ppt/presentation.xml':
                    ids=re.findall(rb'<p:sldId [^>]*/>',data)
                    data=re.sub(rb'<p:sldIdLst>.*?</p:sldIdLst>',b'<p:sldIdLst>'+ids[2]+ids[0]+ids[1]+b''.join(ids[3:])+b'</p:sldIdLst>',data)
                z.writestr(member,data)
        dest=self.output/'slide-order.pdf'
        def slideorder(r):
            with fitz.open(dest) as d:require('Slide 3 Audit Alpha' in d[0].get_text() and 'Slide 1 Audit Alpha' in d[1].get_text(),'PPTX relationship order lost')
        self.case('pptx-fallback-relationship-order',['convert',reordered,'-t','pdf','-o',dest],slideorder,
                  env={'CONVERTO_DISABLE_HELPERS':'1'},group='edge')
        for command,flag in [('rotate','--degrees'),('pdfa','--level')]:
            self.case('slash-invalid-numeric-'+command,['interactive'],expected=1,
                      stdin=f'/{command} "{p}" {flag} abc -o "{self.output}/invalid.pdf"\n/exit\n',group='edge')
        dest=self.output/'slash-convert-to-flag.pdf'
        self.case('slash-convert-matching-cli-flags',['interactive'],lambda r:validate(dest,'pdf',1),
                  stdin=f'/convert "{image}" --to pdf --output "{dest}"\n/exit\n',group='slash')
        self.case('slash-missing-pdf',['interactive'],expected=1,
                  stdin=f'/info "{self.fixtures}/not-present.pdf"\n/exit\n',group='edge')
        dest=self.output/'page-number-position.pdf'
        def numberposition(r):
            with fitz.open(dest) as doc:
                for i,page in enumerate(doc):
                    rects=page.search_for(f'Page {i+1} of {len(doc)}')
                    require(len(rects)==1,'Page number missing or duplicated')
                    require(rects[0].x0>page.rect.width/2 and rects[0].y0>page.rect.height/2,
                            'Page number is not at the bottom right')
        self.case('page-number-position',['page-numbers',p,'-o',dest],numberposition,group='edge')
        leftovers=[str(f) for f in self.output.rglob('*') if f.name.startswith('.converto-') or '.part-' in f.name]
        self.results.append(dict(name='temporary-output-cleanup',group='edge',status='fail' if leftovers else 'pass',error=str(leftovers)))

    def save(self):
        summary = {s:sum(r['status']==s for r in self.results) for s in ['pass','fail','skip','unsupported']}
        data = dict(environment=dict(os=platform.platform(),machine=platform.machine(),python=platform.python_version(),binary=str(self.binary),binary_sha256=hashlib.sha256(self.binary.read_bytes()).hexdigest(),profile=self.profile,audit_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest()),summary=summary,results=self.results)
        (self.output/'results.json').write_text(json.dumps(data,indent=2))
        print(json.dumps(summary))
        for r in self.results:
            if r['status'] in ['fail','skip']: print(r['status'],r['name'],r.get('error',''))


def require(condition, message):
    assert condition, message


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--binary',required=True,type=Path)
    parser.add_argument('--profile',choices=['full','standalone'],default='full')
    parser.add_argument('--output',required=True,type=Path)
    args=parser.parse_args()
    output=args.output.resolve()
    output.mkdir(parents=True,exist_ok=True)
    if (output/'results.json').exists(): raise SystemExit('Choose a fresh --output directory to preserve previous evidence.')
    fixtures=make_fixtures(output/'fixtures')
    audit=Audit(args.binary.resolve(),output,fixtures,args.profile)
    audit.matrix()
    audit.operations()
    audit.edges()
    audit.extended()
    audit.save()
    if any(r["status"]=="fail" for r in audit.results): raise SystemExit(1)


if __name__=='__main__': main()
