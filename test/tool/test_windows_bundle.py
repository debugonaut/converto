"""Windows ZIP completeness and architecture checks, runnable on every OS."""
from pathlib import Path
import struct
import tempfile
import unittest
import zipfile
from tool.windows_bundle import REQUIRED, X64, pe_machine, validate, verify_archive


def pe(machine=X64):
    data = bytearray(134)
    data[:2] = b'MZ'
    struct.pack_into('<I', data, 60, 128)
    data[128:132] = b'PE\0\0'
    struct.pack_into('<H', data, 132, machine)
    return data


class WindowsBundleTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory()
        self.root = Path(self.scratch.name)
        self.bundle = self.root / 'app'
        for name in REQUIRED:
            path = self.bundle / name
            path.parent.mkdir(parents=True, exist_ok=True)
            executable = path.suffix in ('.exe', '.dll') or path.name == 'app.so'
            path.write_bytes(pe() if executable else b'offline asset content')
        (self.bundle / 'data/font-data.bin').write_bytes(b'local font resources')

    def tearDown(self):
        self.scratch.cleanup()

    def archive(self, extra=None, replace=None):
        output = self.root / 'app.zip'
        with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as package:
            for path in sorted(self.bundle.rglob('*')):
                if path.is_file():
                    name = path.relative_to(self.bundle).as_posix()
                    package.writestr(name, replace[name] if replace and name in replace else path.read_bytes())
            if extra:
                for name, payload in extra.items():
                    member = zipfile.ZipInfo(name)
                    # ZipInfo normalizes backslashes on Windows at construction.
                    # Preserve the raw hostile name to exercise the ZIP reader.
                    member.filename = name
                    package.writestr(member, payload)
        return output

    def test_complete_x64_runtime_and_aot_are_verified(self):
        actual = validate(self.bundle)
        self.assertIn('Converto.exe', actual)
        self.assertIn('data/app.so', actual)
        self.assertIn('pdf_oxide.dll', actual)

    def test_missing_native_engine_is_rejected(self):
        (self.bundle / 'pdf_oxide.dll').unlink()
        with self.assertRaisesRegex(ValueError, 'Missing Windows runtime file'):
            validate(self.bundle)

    def test_missing_private_crt_is_rejected(self):
        (self.bundle / 'vcruntime140_1.dll').unlink()
        with self.assertRaisesRegex(ValueError, 'Missing Windows runtime file'):
            validate(self.bundle)

    def test_mixed_architectures_are_rejected(self):
        (self.bundle / 'pdf_oxide.dll').write_bytes(pe(0x14c))
        with self.assertRaisesRegex(ValueError, 'Incorrect Windows architecture'):
            validate(self.bundle)

    def test_truncated_pe_is_rejected(self):
        file = self.bundle / 'Converto.exe'
        file.write_bytes(b'MZ\0\0')
        with self.assertRaisesRegex(ValueError, 'Invalid PE'):
            pe_machine(file)

    def test_complete_zip_preserves_code_and_offline_data(self):
        verify_archive(self.archive(), self.bundle, self.root / 'extracted')
        self.assertEqual((self.root / 'extracted/data/font-data.bin').read_bytes(), b'local font resources')

    def test_modified_asset_is_rejected_even_with_valid_zip_crc(self):
        archive = self.archive(replace={'data/font-data.bin': b'missing local fonts'})
        with self.assertRaisesRegex(ValueError, 'ZIP content differs'):
            verify_archive(archive, self.bundle, self.root / 'extracted')

    def test_traversal_and_windows_case_aliases_are_rejected(self):
        for name in ('../escaped.dll', 'C:/escape.dll', r'folder\escape.dll', 'converto.exe'):
            with self.subTest(name=name):
                archive = self.archive(extra={name: b'bad'})
                with self.assertRaisesRegex(ValueError, 'Unsafe or duplicate'):
                    verify_archive(archive, self.bundle, self.root / 'extracted')


if __name__ == '__main__':
    unittest.main()
