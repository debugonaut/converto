"""Complete ELF bundle and safe tar validation, runnable on any host."""
import hashlib
import os
from pathlib import Path, PurePosixPath
import struct
import tarfile

REQUIRED = ('converto', 'lib/libflutter_linux_gtk.so', 'lib/libapp.so',
            'lib/libdesktop_drop_plugin.so', 'data/icudtl.dat',
            'data/flutter_assets/AssetManifest.bin')


def files(root):
    return sorted(p for p in Path(root).rglob('*') if p.is_file())


def digest(path):
    value = hashlib.sha256()
    with Path(path).open('rb') as stream:
        while chunk := stream.read(1024 * 1024):
            value.update(chunk)
    return value.hexdigest()


def elf_machine(path):
    with Path(path).open('rb') as stream:
        header = stream.read(64)
    if len(header) < 64 or header[:6] != b'\x7fELF\x02\x01':
        raise ValueError(f'Invalid 64-bit little-endian ELF: {path}')
    return struct.unpack_from('<H', header, 18)[0]


def validate(root):
    root = Path(root)
    for name in REQUIRED:
        if not (root / name).is_file() or not (root / name).stat().st_size:
            raise ValueError(f'Missing Linux runtime file: {name}')
    if not list((root / 'lib').rglob('libpdf_oxide.so')):
        raise ValueError('Missing Linux PDF engine')
    if os.name != 'nt' and not (root / 'converto').stat().st_mode & 0o111:
        raise ValueError('Linux executable permission was lost')
    binaries = []
    for path in files(root):
        if path.name == 'converto' or '.so' in path.name:
            if elf_machine(path) != 62:
                raise ValueError(f'Incorrect Linux architecture: {path.name}')
            binaries.append(path.relative_to(root).as_posix())
    return binaries


def manifest(root):
    return {p.relative_to(root).as_posix(): (digest(p), p.stat().st_mode & 0o777)
            for p in files(root)}


def verify_archive(archive, source, extracted):
    extracted = Path(extracted)
    with tarfile.open(archive, 'r:gz') as package:
        seen = set()
        for entry in package.getmembers():
            name = entry.name
            parts = PurePosixPath(name).parts
            if (not parts or parts[0] != 'Converto' or name.startswith('/') or
                    '..' in parts or '\\' in name or name in seen or
                    not (entry.isdir() or entry.isfile())):
                raise ValueError(f'Unsafe or duplicate tar member: {name}')
            if not (extracted / name).resolve().is_relative_to(extracted.resolve()):
                raise ValueError(f'Tar member leaves destination: {name}')
            seen.add(name)
        # Every entry has been checked, including links/devices; compatible with
        # Python 3.10 as well as newer tarfile data filters.
        package.extractall(extracted)
    app = extracted / 'Converto'
    if manifest(source) != manifest(app):
        raise ValueError('Tar content or permissions differ from the complete runtime')
    return validate(app)
