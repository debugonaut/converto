#!/usr/bin/env python3
"""Small reproducible local before/after benchmark, separate from acceptance tests."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import random
import re
import statistics
import subprocess
import tempfile
import time
from PIL import Image
import pymupdf


def main():
    p=argparse.ArgumentParser()
    p.add_argument('--before',type=Path,required=True)
    p.add_argument('--after',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    a=p.parse_args()
    a.output.mkdir(parents=True,exist_ok=True)
    results=[]
    with tempfile.TemporaryDirectory(prefix='converto-benchmark-') as work:
        root=Path(work)
        im=Image.frombytes('RGB',(2400,1600),random.Random(42).randbytes(2400*1600*3))
        jpeg=root/'photo.jpg';im.save(jpeg,quality=88)
        png=root/'photo.png';im.save(png)
        text=root/'notes.txt';text.write_text('\n'.join(f'Audit line {i}: local conversion text.' for i in range(1500)))
        pdf=root/'pages.pdf'
        with pymupdf.open() as d:
            for i in range(200):d.new_page().insert_text((30,50),f'Audit page {i+1}')
            d.save(pdf)
        cases=[('jpeg-to-pdf',jpeg,['convert',str(jpeg),'-t','pdf'],'pdf'),
               ('png-to-jpg',png,['convert',str(png),'-t','jpg'],'jpg'),
               ('txt-to-pdf',text,['convert',str(text),'-t','pdf'],'pdf'),
               ('merge-400-pages',pdf,['merge',str(pdf),str(pdf)],'pdf')]
        for name,src,args,ext in cases:
            for label,binary in [('before',a.before),('after',a.after)]:
                samples=[]
                for sample in range(3):
                    dest=root/f'{name}-{label}.{ext}'
                    command=[str(binary.resolve()),*args,'-o',str(dest)]
                    if platform.system()=='Darwin':command=['/usr/bin/time','-l',*command]
                    elif platform.system()=='Linux':command=['/usr/bin/time','-f','MAXRSS_KB=%M',*command]
                    start=time.perf_counter()
                    r=subprocess.run(command,capture_output=True,text=True,timeout=90,
                        env=dict(os.environ,CONVERTO_OUTPUT_DIR=str(root/'output'),CONVERTO_DATA_DIR=str(root/'state'),CONVERTO_HISTORY='off'))
                    elapsed=(time.perf_counter()-start)*1000
                    if r.returncode:raise RuntimeError(r.stdout+r.stderr)
                    if ext=='pdf':
                        with pymupdf.open(dest) as d:assert len(d)>0
                    else:
                        with Image.open(dest) as d:d.load()
                    rss=re.search(r'(\d+)\s+maximum resident set size',r.stderr)
                    if rss:rss_bytes=int(rss.group(1))
                    else:
                        rss=re.search(r'MAXRSS_KB=(\d+)',r.stderr)
                        rss_bytes=int(rss.group(1))*1024 if rss else None
                    samples.append(dict(wall_ms=round(elapsed,3),peak_rss_bytes=rss_bytes,output_bytes=dest.stat().st_size))
                    dest.unlink()
                results.append(dict(case=name,version=label,input_bytes=src.stat().st_size,
                    input_sha256=hashlib.sha256(src.read_bytes()).hexdigest(),samples=samples,
                    median_wall_ms=round(statistics.median(s['wall_ms'] for s in samples),3),
                    median_peak_rss_bytes=statistics.median(s['peak_rss_bytes'] for s in samples) if all(s['peak_rss_bytes'] is not None for s in samples) else None))
                print(name,label,results[-1]['median_wall_ms'],'ms',flush=True)
    (a.output/'benchmarks.json').write_text(json.dumps(dict(environment=platform.platform(),samples_per_case=3,before_sha256=hashlib.sha256(a.before.read_bytes()).hexdigest(),after_sha256=hashlib.sha256(a.after.read_bytes()).hexdigest(),results=results),indent=2))


if __name__=='__main__':main()
