"""Portable Windows bundle validation; no runtime downloads or installers."""
import hashlib
from pathlib import Path
import struct
import zipfile

X64 = 0x8664
REQUIRED = (
    'Converto.exe', 'flutter_windows.dll', 'desktop_drop_plugin.dll',
    'pdf_oxide.dll', 'data/app.so', 'data/icudtl.dat',
    'data/flutter_assets/AssetManifest.bin',
    'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll',
)


def pe_machine(path):
    with Path(path).open('rb') as stream:
        header = stream.read(64)
        if len(header) < 64 or header[:2] != b'MZ':
            raise ValueError(f'Invalid PE image: {path}')
        offset = struct.unpack_from('<I', header, 60)[0]
        stream.seek(offset)
        signature = stream.read(6)
        if len(signature) != 6 or signature[:4] != b'PE\0\0':
            raise ValueError(f'Truncated or invalid PE image: {path}')
        return struct.unpack_from('<H', signature, 4)[0]


def aot_machine(path):
    # Flutter uses app-aot-elf snapshots on Windows too; the engine's own
    # loader reads this file. It is not a Windows DLL despite containing code.
    with Path(path).open('rb') as stream:
        header = stream.read(64)
    if header[:2] == b'MZ':
        return pe_machine(path)
    if len(header) < 64 or header[:6] != b'\x7fELF\x02\x01':
        raise ValueError(f'Invalid 64-bit little-endian AOT snapshot: {path}')
    machine = struct.unpack_from('<H', header, 18)[0]
    return X64 if machine == 62 else machine


def files(root):
    return sorted(p for p in Path(root).rglob('*') if p.is_file())


def digest(path):
    value = hashlib.sha256()
    with Path(path).open('rb') as stream:
        while chunk := stream.read(1024 * 1024):
            value.update(chunk)
    return value.hexdigest()


def validate(root):
    root = Path(root)
    for name in REQUIRED:
        if not (root / name).is_file() or not (root / name).stat().st_size:
            raise ValueError(f'Missing Windows runtime file: {name}')
    binaries = []
    for path in files(root):
        if path.suffix.lower() in ('.exe', '.dll') or path.name == 'app.so':
            machine = aot_machine(path) if path.name == 'app.so' else pe_machine(path)
            if machine != X64:
                raise ValueError(f'Incorrect Windows architecture: {path.name}')
            binaries.append(path.relative_to(root).as_posix())
    return binaries


def verify_archive(archive, source, extracted):
    """Reject traversal/aliases, CRC errors, omissions and changed resources."""
    source, extracted = Path(source), Path(extracted)
    with zipfile.ZipFile(archive) as package:
        seen = set()
        for member in package.infolist():
            name = member.orig_filename
            canonical = name.lower()
            if (name != member.filename or '\0' in name or name.startswith(('/', '\\')) or '\\' in name or ':' in name or
                    '..' in name.split('/') or canonical in seen):
                raise ValueError(f'Unsafe or duplicate archive member: {name}')
            seen.add(canonical)
            if not (extracted / name).resolve().is_relative_to(extracted.resolve()):
                raise ValueError(f'Archive member leaves destination: {name}')
            if member.external_attr >> 16 & 0o170000 == 0o120000:
                raise ValueError(f'Archive symlink is not supported: {name}')
        if package.testzip() is not None:
            raise ValueError('Windows ZIP CRC verification failed')
        package.extractall(extracted)
    original = {p.relative_to(source).as_posix(): digest(p) for p in files(source)}
    actual = {p.relative_to(extracted).as_posix(): digest(p) for p in files(extracted)}
    if actual != original:
        raise ValueError('ZIP content differs from the complete Windows runtime')
    return validate(extracted)
