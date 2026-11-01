#!/usr/bin/env python3
"""Real controlling-PTY regressions (macOS/Linux). No desktop apps are opened."""
import argparse
import json
import os
from pathlib import Path
import select
import re
import signal
import sys
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--binary', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    binary = args.binary.resolve()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    if os.name == 'nt':
        (output/'terminal-results.json').write_text(json.dumps({'status':'skip','reason':'A real Windows console/ConPTY test is required; POSIX PTY does not emulate Windows.'},indent=2))
        print('SKIP: native Windows console validation still required')
        return
    import pty
    import termios
    import fcntl
    import struct
    from PIL import Image
    import pymupdf
    source = output/'drop image.png'
    Image.new('RGB',(24,16),'red').save(source)
    other = output/'second image.png'
    Image.new('RGB',(16,24),'blue').save(other)
    results = []

    class Session:
        def __init__(self):
            self.pid,self.fd = pty.fork()
            if self.pid == 0:
                env = dict(os.environ,CONVERTO_OUTPUT_DIR=str(output/'converted'),
                           CONVERTO_DATA_DIR=str(output/'state'),TERM='xterm-256color')
                os.chdir(output)
                os.execve(str(binary),[str(binary)],env)
            fcntl.ioctl(self.fd,termios.TIOCSWINSZ,struct.pack('HHHH',24,80,0,0))
            self.log=b''
            self.status=None
            self.wait_for('converto › ')
        def pump(self,seconds=.05):
            if select.select([self.fd],[],[],seconds)[0]:
                try:self.log+=os.read(self.fd,65536)
                except OSError:pass
            if self.status is None:
                pid,status=os.waitpid(self.pid,os.WNOHANG)
                if pid:self.status=os.waitstatus_to_exitcode(status)
        def wait_for(self,text,timeout=4):
            deadline=time.monotonic()+timeout
            start=len(self.log)
            needle=text.encode()
            def clean():return re.sub(rb'\x1b\[[0-?]*[ -/]*[@-~]',b'',self.log[start:])
            while needle not in clean() and self.status is None and time.monotonic()<deadline:
                self.pump()
            assert needle in clean(), f'Timed out waiting for {text!r}'
        def send(self,data):
            data=data if isinstance(data,bytes) else data.encode()
            while data:data=data[os.write(self.fd,data):]
        def exit(self,timeout=4):
            deadline=time.monotonic()+timeout
            while self.status is None and time.monotonic()<deadline:self.pump()
            assert self.status is not None,'Terminal did not exit (hang)'
            flags=termios.tcgetattr(self.fd)[3]
            assert flags & termios.ECHO, 'Terminal echo not restored'
            assert flags & termios.ICANON, 'Terminal canonical input not restored'
        def close(self):
            if self.status is None:
                os.kill(self.pid,signal.SIGKILL)
                os.waitpid(self.pid,0)
            os.close(self.fd)

    def case(name,action):
        session=None
        start=time.perf_counter()
        result={'name':name}
        try:
            session=Session()
            action(session)
            result['status']='pass'
        except Exception as error:
            result.update(status='fail',error=str(error))
        finally:
            result['wall_ms']=round((time.perf_counter()-start)*1000,3)
            if session:
                result['exit_code']=session.status
                result['output_bytes']=len(session.log)
                (output/f'{name}.log').write_bytes(session.log)
                session.close()
            results.append(result)

    def cancel(s,byte):s.send(byte);s.exit()
    case('ctrl-d',lambda s:cancel(s,b'\x04'))
    case('ctrl-c',lambda s:cancel(s,b'\x03'))
    case('exit-command',lambda s:cancel(s,b'/exit\r'))

    def paste(s,multiline=False,crlf=False,followup=False):
        if multiline:
            raw=f'{source.as_uri()}\n{other.as_uri()}'
            s.send(b'\x1b[200~'+raw.encode()+b'\x1b[201~')
            # Paste must not execute on an embedded newline.
            for _ in range(3):s.pump()
            assert b'File Detected' not in s.log and b'What would you like' not in s.log,'Paste executed before its closing marker and Enter'
            s.send(b'\r')
            s.wait_for('What would you like')
            s.send(b'\r')
            s.wait_for('Continue')
            # A newly dropped command must survive the one-key action prompt.
            s.send(b'/exit\r' if followup else b'\r/exit\r')
            s.exit()
            merged=list(output.glob('merged_*.pdf'))
            assert merged,'Missing merge result'
            with pymupdf.open(merged[-1]) as doc:assert len(doc)==2
            for f in merged:f.unlink()
        else:
            target=output/'pasted.pdf'
            command=f'/convert "{source}" pdf -o "{target}"'
            s.send(b'\x1b[200~'+command.encode()+b'\x1b[201~'+(b'\r\n' if crlf else b'\r'))
            s.wait_for('Continue')
            s.send(b'/exit\r' if followup else b'\r/exit\r')
            s.exit()
            with pymupdf.open(target) as doc:assert len(doc)==1
    case('bracketed-command',lambda s:paste(s))
    case('bracketed-crlf',lambda s:paste(s,crlf=True))
    case('multiline-uri-drop',lambda s:paste(s,multiline=True))
    case('next-command-at-post-action',lambda s:paste(s,followup=True))
    case('next-command-after-multidrop',lambda s:paste(s,multiline=True,followup=True))

    def pending(s):
        s.send(b'/convert \r')
        s.wait_for('Source file path')
        s.send(b'\x03')
        s.exit()
    case('ctrl-c-at-source-prompt',pending)
    def controls(s):
        s.send(b'\x1b[2~\x1b[999~\x1b[200~\x1b[201~/exit\r')
        s.exit()
    case('unknown-escape-and-empty-paste',controls)
    def largepaste(s):
        target=output/'large-paste.pdf'
        command=' '*70000+f'/convert "{source}" pdf -o "{target}"'
        s.send(b'\x1b[200~'+command.encode()+b'\x1b[201~\r')
        s.wait_for('Continue')
        s.send(b'\r/exit\r');s.exit()
        with pymupdf.open(target) as doc:assert len(doc)==1
    case('paste-over-64kb',largepaste)
    def soak(s):
        # Exercise the actual bare-file action menu once, then repeated drops.
        s.send(b'\x1b[200~'+('"'+str(source)+'"').encode()+b'\x1b[201~\r')
        s.wait_for('Choose [')
        s.send(b'1\r');s.wait_for('Target format');s.send(b'pdf\r');s.wait_for('Continue')
        s.send(b'\r');s.wait_for('converto › ')
        for i in range(25):
            target=output/f'soak-{i}.pdf'
            command=f'/convert "{source}" pdf -o "{target}"'
            s.send(b'\x1b[200~'+command.encode()+b'\x1b[201~\r')
            s.wait_for('Continue');s.send(b'\r');s.wait_for('converto › ')
            with pymupdf.open(target) as doc:assert len(doc)==1
        s.send(b'/exit\r');s.exit()
    case('bare-drop-and-repeated-drop-soak',soak)
    data={'summary':{status:sum(r['status']==status for r in results) for status in ['pass','fail']},'results':results}
    (output/'terminal-results.json').write_text(json.dumps(data,indent=2))
    print(json.dumps(data['summary']))
    for result in results:
        if result['status']=='fail':print(result['name'],result['error'])
    if data['summary']['fail']:sys.exit(1)


if __name__=='__main__':main()
