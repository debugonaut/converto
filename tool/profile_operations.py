#!/usr/bin/env python3
"""Profile one successful representative of each catalog operation locally."""
import argparse
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import time


def main():
    p=argparse.ArgumentParser()
    p.add_argument('--results',type=Path,required=True)
    p.add_argument('--binary',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    a=p.parse_args()
    a.output.mkdir(parents=True,exist_ok=True)
    original=json.loads(a.results.read_text())['results']
    representatives={
        'convert':'image.png-to-pdf','pdf2img':'pdf2img-png','pdf2text':'pdf2text',
        'pdf2office':'pdf2office-docx','merge':'merge-pdfs','split':'split-every',
        'extract':'extract','organize':'organize-order','rotate':'rotate',
        'watermark':'watermark','page-numbers':'page-numbers','crop':'crop',
        'compress':'compress-ebook','redact':'redact','pdfa':'pdfa-2','edit':'edit',
        'protect':'protect','unlock':'unlock','info':'info',
        **{name:'slash-'+name for name in ['formats','privacy','recent','help','clear','exit']},
    }
    measurements=[]
    for operation,name in representatives.items():
        record=next(r for r in original if r['name']==name)
        args=list(record['args'])
        destination=None
        if '-o' in args:
            i=args.index('-o')+1
            destination=a.output.resolve()/('profile-'+Path(args[i]).name)
            args[i]=str(destination)
        command=[str(a.binary.resolve()),*args]
        if platform.system()=='Darwin':command=['/usr/bin/time','-l',*command]
        elif platform.system()=='Linux':command=['/usr/bin/time','-f','MAXRSS_KB=%M',*command]
        else:raise SystemExit('This resource probe currently supports macOS/Linux resource counters.')
        env=dict(os.environ,CONVERTO_OUTPUT_DIR=str(a.output.resolve()/'output'),
                 CONVERTO_DATA_DIR=str(a.output.resolve()/'state'),CONVERTO_HISTORY='off')
        start=time.perf_counter()
        r=subprocess.run(command,input=f'/{operation}\n/exit\n' if args==['interactive'] else '',
                         env=env,capture_output=True,text=True,timeout=30)
        elapsed=(time.perf_counter()-start)*1000
        if r.returncode:raise RuntimeError(f'{operation}: {r.stdout}\n{r.stderr}')
        match=re.search(r'(\d+)\s+maximum resident set size',r.stderr)
        rss=int(match.group(1)) if match else int(re.search(r'MAXRSS_KB=(\d+)',r.stderr).group(1))*1024
        files=[destination] if destination and destination.is_file() else list(destination.rglob('*')) if destination else []
        measurements.append(dict(operation=operation,representative=name,wall_ms=round(elapsed,3),
                                 peak_rss_bytes=rss,input_bytes=record.get('input_bytes',0),
                                 output_bytes=sum(f.stat().st_size for f in files if f.is_file()),exit_code=r.returncode))
    (a.output/'operation-profiles.json').write_text(json.dumps(dict(environment=platform.platform(),
        measurements=measurements,note='One cold command per operation; peak RSS is the OS-reported process/child maximum, not summed concurrent tree memory.'),indent=2))
    print(f'Profiled {len(measurements)} operations')


if __name__=='__main__':main()
