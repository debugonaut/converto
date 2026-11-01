"""Independent executable/data integrity tests for CPU-specific packaging."""
import hashlib
from pathlib import Path
import struct
import tempfile
import unittest

from tool.macos_bundle import CPU_TYPES, macho_files, section_hashes


def thin(cpu, code=b'executable instructions', data=b'embedded offline resources'):
    command_size = 72 + 80
    start = 32 + 2 * command_size
    commands, payload = [], b''
    for segment, name, content in [(b'__TEXT', b'__text', code), (b'__DATA', b'__const', data)]:
        offset = start + len(payload)
        commands.append(struct.pack('<II16sQQQQiiII', 0x19, command_size, segment, 0, len(content), offset, len(content), 7, 5, 1, 0))
        commands.append(struct.pack('<16s16sQQIIIIIIII', name, segment, 0, len(content), offset, 0, 0, 0, 0, 0, 0, 0))
        payload += content
    return struct.pack('<IiiIIIII', 0xfeedfacf, cpu, 0, 6, 2, 2 * command_size, 0, 0) + b''.join(commands) + payload


def universal(arm, intel):
    start = 8 + 2 * 20
    return (struct.pack('>II', 0xcafebabe, 2)
            + struct.pack('>iiIII', CPU_TYPES['arm64'], 0, start, len(arm), 0)
            + struct.pack('>iiIII', CPU_TYPES['x86_64'], 0, start + len(arm), len(intel), 0)
            + arm + intel)


class IntegrityTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory()
        self.root = Path(self.scratch.name)
        self.arm = thin(CPU_TYPES['arm64'])
        self.intel = thin(CPU_TYPES['x86_64'], code=b'Intel instructions')

    def tearDown(self):
        self.scratch.cleanup()

    def write(self, name, payload):
        file = self.root / name
        file.write_bytes(payload)
        return file

    def test_hashes_cover_both_code_and_embedded_data(self):
        actual = section_hashes(self.write('arm', self.arm), 'arm64')
        self.assertEqual(actual, {
            '__TEXT.__text': hashlib.sha256(b'executable instructions').hexdigest(),
            '__DATA.__const': hashlib.sha256(b'embedded offline resources').hexdigest(),
        })

    def test_selected_cpu_matches_its_universal_slice(self):
        source = self.write('fat', universal(self.arm, self.intel))
        for architecture, payload in [('arm64', self.arm), ('x86_64', self.intel)]:
            self.assertEqual(section_hashes(source, architecture),
                             section_hashes(self.write(architecture, payload), architecture))

    def test_detects_changed_code(self):
        original = self.write('original', self.arm)
        modified = self.write('modified', thin(CPU_TYPES['arm64'], code=b'corrupted instructions'))
        self.assertNotEqual(section_hashes(original, 'arm64'), section_hashes(modified, 'arm64'))

    def test_detects_changed_engine_data(self):
        original = self.write('original', self.arm)
        modified = self.write('modified', thin(CPU_TYPES['arm64'], data=b'missing offline fonts'))
        self.assertNotEqual(section_hashes(original, 'arm64'), section_hashes(modified, 'arm64'))

    def test_rejects_wrong_cpu(self):
        with self.assertRaisesRegex(ValueError, 'Incorrect architecture'):
            section_hashes(self.write('intel', self.intel), 'arm64')

    def test_rejects_truncated_section(self):
        with self.assertRaisesRegex(ValueError, 'exceeds'):
            section_hashes(self.write('broken', self.arm[:-4]), 'arm64')

    def test_bundle_scan_ignores_assets_and_aliases(self):
        file = self.write('binary', self.arm)
        self.write('font.ttf', b'ordinary asset')
        try:
            (self.root / 'alias').symlink_to(file)
        except OSError:
            pass
        self.assertEqual(list(macho_files(self.root)), [file])


if __name__ == '__main__':
    unittest.main()
