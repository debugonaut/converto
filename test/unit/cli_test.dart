import 'dart:io';
import 'dart:ffi';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final arm64 = [
    Abi.macosArm64,
    Abi.linuxArm64,
    Abi.windowsArm64,
  ].contains(Abi.current());
  final binaryPath =
      Platform.environment['CONVERTO_TEST_BINARY'] ??
      'build/cli/${Platform.operatingSystem}_${arm64 ? 'arm64' : 'x64'}/bundle/bin/converto${Platform.isWindows ? '.exe' : ''}';

  setUpAll(() {
    if (!File(binaryPath).existsSync()) {
      fail(
        'Build the current CLI first: dart build cli --target bin/converto.dart',
      );
    }
  });

  ProcessResult runCli(List<String> args) {
    return Process.runSync(binaryPath, args);
  }

  group('Converto CLI Integration Tests', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('oc_cli_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('CLI --help prints usage', () {
      final res = runCli(['--help']);
      expect(res.exitCode, 0);
      expect(
        res.stdout.toString(),
        contains('100% Offline Local File Converter CLI'),
      );
      expect(res.stdout.toString(), contains('Available commands:'));
      expect(res.stdout.toString(), contains('convert'));
      expect(res.stdout.toString(), contains('merge'));
      expect(res.stdout.toString(), contains('watermark'));
      expect(res.stdout.toString(), contains('split'));
      expect(res.stdout.toString(), contains('compress'));
      expect(res.stdout.toString(), contains('protect'));
    });

    test('CLI formats lists supported categories', () {
      final res = runCli(['formats']);
      expect(res.exitCode, 0);
      expect(res.stdout.toString(), contains('IMAGE:'));
      expect(res.stdout.toString(), contains('PDF:'));
      expect(res.stdout.toString(), contains('DOCUMENT:'));
      expect(res.stdout.toString(), contains('SPREADSHEET:'));
    });

    test('CLI convert CSV to PDF', () {
      final csvFile = File('${tempDir.path}/data.csv');
      csvFile.writeAsStringSync(
        'Name,Age,Role\nAlice,30,Engineer\nBob,25,Designer',
      );

      final pdfPath = '${tempDir.path}/data.pdf';
      final res = runCli(['convert', csvFile.path, '-t', 'pdf', '-o', pdfPath]);

      expect(res.exitCode, 0);
      final pdf = File(pdfPath);
      expect(pdf.existsSync(), isTrue);
      expect(pdf.lengthSync(), greaterThan(0));
    });

    test('CLI watermark on PDF', () {
      final txtFile = File('${tempDir.path}/memo.txt');
      txtFile.writeAsStringSync('Internal Project Memo\nConfidential Data.');

      final pdfPath = '${tempDir.path}/memo.pdf';
      runCli(['convert', txtFile.path, '-t', 'pdf', '-o', pdfPath]);

      final watermarkedPath = '${tempDir.path}/memo_watermarked.pdf';
      final res = runCli([
        'watermark',
        pdfPath,
        '-w',
        'RESTRICTED',
        '-o',
        watermarkedPath,
      ]);

      expect(res.exitCode, 0);
      final wPdf = File(watermarkedPath);
      expect(wPdf.existsSync(), isTrue);
      expect(wPdf.lengthSync(), greaterThan(0));
    });

    test('CLI info reads page count and metadata', () {
      final res = runCli(['info', 'test_assets/merged_images.pdf']);
      expect(res.exitCode, 0);
      final out = res.stdout.toString();
      expect(out, contains('Pages:     2'));
      expect(out, contains('Encrypted: no'));
    });

    test('CLI split writes one PDF per part', () {
      final outDir = Directory('${tempDir.path}/parts');
      final res = runCli([
        'split',
        'test_assets/merged_images.pdf',
        '--every',
        '1',
        '-o',
        outDir.path,
      ]);

      expect(res.exitCode, 0, reason: res.stderr.toString());
      final parts = outDir.listSync().whereType<File>().toList();
      expect(parts.length, 2);
      expect(parts.every((f) => f.lengthSync() > 0), isTrue);
    });

    test('CLI organize, rotate, page numbers, compress, PDF/A', () {
      final outputs = <String, List<String>>{
        'reordered.pdf': [
          'organize',
          'test_assets/merged_images.pdf',
          '--order',
          '2,1',
        ],
        'rotated.pdf': [
          'rotate',
          'test_assets/merged_images.pdf',
          '--degrees',
          '90',
        ],
        'numbered.pdf': ['page-numbers', 'test_assets/merged_images.pdf'],
        'cropped.pdf': [
          'crop',
          'test_assets/merged_images.pdf',
          '--left',
          '18',
          '--top',
          '18',
          '--right',
          '18',
          '--bottom',
          '18',
        ],
        'compressed.pdf': [
          'compress',
          'test_assets/merged_images.pdf',
          '--level',
          'ebook',
        ],
        'archive.pdf': ['pdfa', 'test_assets/merged_images.pdf'],
      };

      for (final entry in outputs.entries) {
        final target = '${tempDir.path}/${entry.key}';
        final res = runCli([...entry.value, '-o', target]);
        expect(
          res.exitCode,
          0,
          reason: '${entry.value.first} failed: ${res.stderr}',
        );
        expect(File(target).existsSync(), isTrue);
        expect(File(target).lengthSync(), greaterThan(0));
      }
    });

    test('CLI protect and unlock round-trip', () {
      final protected = '${tempDir.path}/protected.pdf';
      final unlocked = '${tempDir.path}/unlocked.pdf';

      var res = runCli([
        'protect',
        'test_assets/merged_images.pdf',
        '--password',
        'secret',
        '-o',
        protected,
      ]);
      expect(res.exitCode, 0);

      res = runCli(['info', protected, '--password', 'secret']);
      expect(res.stdout.toString(), contains('Encrypted: yes'));

      res = runCli([
        'unlock',
        protected,
        '--password',
        'secret',
        '-o',
        unlocked,
      ]);
      expect(res.exitCode, 0);

      res = runCli(['info', unlocked]);
      expect(res.stdout.toString(), contains('Encrypted: no'));
    });

    test('CLI pdf2text and pdf2office produce readable outputs', () {
      final txtPath = '${tempDir.path}/notes.txt';
      var res = runCli(['pdf2text', 'test_assets/notes.pdf', '-o', txtPath]);
      expect(res.exitCode, 0);
      expect(File(txtPath).readAsStringSync(), contains('OfflineConvert'));

      final docxPath = '${tempDir.path}/pages.docx';
      res = runCli([
        'pdf2office',
        'test_assets/merged_images.pdf',
        '--to',
        'docx',
        '-o',
        docxPath,
      ]);
      expect(res.exitCode, 0);
      expect(File(docxPath).lengthSync(), greaterThan(0));
    });

    test('CLI pdf2img exports every page', () {
      final outDir = '${tempDir.path}/pages';
      final res = runCli([
        'pdf2img',
        'test_assets/merged_images.pdf',
        '--to',
        'png',
        '--dpi',
        '72',
        '-o',
        outDir,
      ]);

      expect(res.exitCode, 0);
      final pages = Directory(outDir).listSync().whereType<File>().toList();
      expect(pages.length, 2);
      expect(pages.every((f) => f.lengthSync() > 0), isTrue);
    });

    test('CLI redact removes matched text permanently', () {
      final redacted = '${tempDir.path}/redacted.pdf';
      final txt = '${tempDir.path}/redacted.txt';

      var res = runCli([
        'redact',
        'test_assets/notes.pdf',
        '--text',
        'OfflineConvert',
        '-o',
        redacted,
      ]);
      expect(res.exitCode, 0);

      res = runCli(['pdf2text', redacted, '-o', txt]);
      expect(res.exitCode, 0);
      expect(File(txt).readAsStringSync(), isNot(contains('OfflineConvert')));
    });
  });
}
