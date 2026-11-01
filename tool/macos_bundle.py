"""Inspect and thin Mac bundles without changing executable sections."""
from pathlib import Path
import hashlib
import struct
import subprocess

CPU_TYPES = {'arm64': 0x0100000C, 'x86_64': 0x01000007}
MACH_MAGICS = {bytes.fromhex(value) for value in (
    'feedface', 'cefaedfe', 'feedfacf', 'cffaedfe',
    'cafebabe', 'bebafeca', 'cafebabf', 'bfbafeca',
)}


def macho_files(app):
    for path in sorted(Path(app).rglob('*')):
        if path.is_file() and not path.is_symlink():
            with path.open('rb') as stream:
                if stream.read(4) in MACH_MAGICS:
                    yield path


def architectures(path):
    return subprocess.check_output(['lipo', '-archs', str(path)], text=True).split()


def section_hashes(path, architecture):
    """Hash code/data sections, excluding signing metadata and zero-fill RAM.

    Works on both universal and thin 64-bit Mach-O files. A matching result
    proves architecture splitting/signing preserved instructions and data.
    """
    with Path(path).open('rb') as stream:
        magic = stream.read(4)
        base, slice_size = 0, Path(path).stat().st_size
        fat = {
            b'\xca\xfe\xba\xbe': ('>', False), b'\xbe\xba\xfe\xca': ('<', False),
            b'\xca\xfe\xba\xbf': ('>', True), b'\xbf\xba\xfe\xca': ('<', True),
        }
        if magic in fat:
            endian, fat64 = fat[magic]
            count = struct.unpack(endian + 'I', stream.read(4))[0]
            if count > 32:
                raise ValueError('Invalid Mach-O architecture table')
            fmt = endian + ('iiQQII' if fat64 else 'iiIII')
            records = [struct.unpack(fmt, stream.read(struct.calcsize(fmt))) for _ in range(count)]
            record = next((row for row in records if row[0] == CPU_TYPES[architecture]), None)
            if record is None:
                raise ValueError(f'Missing architecture {architecture}: {path}')
            base, slice_size = record[2], record[3]
        stream.seek(base)
        header = stream.read(32)
        if header[:4] == b'\xcf\xfa\xed\xfe':
            endian = '<'
        elif header[:4] == b'\xfe\xed\xfa\xcf':
            endian = '>'
        else:
            raise ValueError(f'Expected 64-bit Mach-O: {path}')
        values = struct.unpack(endian + 'IiiIIIII', header)
        if values[1] != CPU_TYPES[architecture]:
            raise ValueError(f'Incorrect architecture: {path}')
        commands = stream.read(values[5])
        cursor, sections = 0, []
        for _ in range(values[4]):
            kind, size = struct.unpack_from(endian + 'II', commands, cursor)
            if size < 8 or cursor + size > len(commands):
                raise ValueError('Invalid Mach-O load command')
            if kind == 0x19:  # LC_SEGMENT_64
                count = struct.unpack_from(endian + 'I', commands, cursor + 64)[0]
                for index in range(count):
                    section = struct.unpack_from(endian + '16s16sQQIIIIIIII', commands, cursor + 72 + 80 * index)
                    name, segment = (value.split(b'\0')[0].decode() for value in section[:2])
                    length, offset, flags = section[3], section[4], section[8]
                    if length == 0 or (flags & 0xff) in (1, 0x0c, 0x12):
                        continue
                    if segment == '__LINKEDIT':
                        continue
                    if offset + length > slice_size:
                        raise ValueError('Mach-O section exceeds its architecture slice')
                    sections.append((segment + '.' + name, offset, length))
            cursor += size
        result = {}
        for name, offset, length in sections:
            stream.seek(base + offset)
            digest = hashlib.sha256()
            remaining = length
            while remaining:
                data = stream.read(min(remaining, 1024 * 1024))
                if not data:
                    raise ValueError('Truncated Mach-O section')
                digest.update(data)
                remaining -= len(data)
            result[name] = digest.hexdigest()
        if not result:
            raise ValueError(f'No executable/data sections found: {path}')
        return result


def verify_variant(source, candidate, architecture):
    source, candidate = Path(source), Path(candidate)
    expected = {file.relative_to(source) for file in macho_files(source)}
    actual = {file.relative_to(candidate) for file in macho_files(candidate)}
    if expected != actual:
        raise ValueError('Executable files were removed or added during packaging')
    for relative in sorted(expected):
        if architectures(candidate / relative) != [architecture]:
            raise ValueError(f'Unexpected architectures in {relative}')
        if section_hashes(source / relative, architecture) != section_hashes(candidate / relative, architecture):
            raise ValueError(f'Executable or data sections changed: {relative}')
    return len(expected)
