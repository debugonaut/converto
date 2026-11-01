from pathlib import Path
import io
import struct
import tarfile
import tempfile
import unittest
from tool.linux_bundle import REQUIRED, validate, verify_archive


def elf(machine=62):
    header = bytearray(64)
    header[:6] = b'\x7fELF\x02\x01'
    struct.pack_into('<H', header, 18, machine)
    return header


class LinuxBundleTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory()
        self.root = Path(self.scratch.name)
        self.app = self.root / 'source'
        for name in (*REQUIRED, 'lib/libpdf_oxide.so'):
            path = self.app / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(elf() if name == 'converto' or '.so' in name else b'local asset')
        (self.app / 'converto').chmod(0o755)

    def tearDown(self):
        self.scratch.cleanup()

    def archive(self, extra=None):
        path = self.root / 'app.tar.gz'
        with tarfile.open(path, 'w:gz') as archive:
            archive.add(self.app, arcname='Converto')
            if extra:
                entry = tarfile.TarInfo(extra)
                entry.size = 1
                archive.addfile(entry, io.BytesIO(b'x'))
        return path

    def test_complete_runtime_preserves_modes_and_assets(self):
        binaries = verify_archive(self.archive(), self.app, self.root / 'unpacked')
        self.assertIn('lib/libapp.so', binaries)
        self.assertIn('lib/libpdf_oxide.so', binaries)

    def test_missing_pdf_engine_is_rejected(self):
        (self.app / 'lib/libpdf_oxide.so').unlink()
        with self.assertRaisesRegex(ValueError, 'PDF engine'):
            validate(self.app)

    def test_arm_binary_is_rejected(self):
        (self.app / 'lib/libpdf_oxide.so').write_bytes(elf(183))
        with self.assertRaisesRegex(ValueError, 'architecture'):
            validate(self.app)

    def test_truncated_elf_is_rejected(self):
        (self.app / 'lib/libpdf_oxide.so').write_bytes(b'\x7fELF')
        with self.assertRaisesRegex(ValueError, 'Invalid 64-bit'):
            validate(self.app)

    @unittest.skipIf(__import__('os').name == 'nt', 'Windows does not preserve Unix execute bits')
    def test_executable_permission_required(self):
        (self.app / 'converto').chmod(0o644)
        with self.assertRaisesRegex(ValueError, 'permission'):
            validate(self.app)

    def test_traversal_absolute_duplicates_and_aliases_rejected(self):
        for name in ('Converto/../../escape', '/tmp/escape', 'wrong-root',
                     'Converto/converto', 'Converto\\escape'):
            with self.subTest(name=name), self.assertRaises(ValueError):
                verify_archive(self.archive(name), self.app, self.root / 'unpacked')

    def test_links_rejected(self):
        archive = self.archive()
        # Rewrite an archive with a link, as gzip archives cannot append.
        with tarfile.open(archive, 'w:gz') as package:
            package.add(self.app, arcname='Converto')
            link = tarfile.TarInfo('Converto/link')
            link.type = tarfile.SYMTYPE
            link.linkname = '/etc/passwd'
            package.addfile(link)
        with self.assertRaisesRegex(ValueError, 'Unsafe'):
            verify_archive(archive, self.app, self.root / 'unpacked')

    def test_changed_asset_rejected(self):
        archive = self.archive()
        (self.app / 'data/icudtl.dat').write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'content or permissions'):
            verify_archive(archive, self.app, self.root / 'unpacked')
