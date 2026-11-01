import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:converto/core/terminal/input_parser.dart';
import 'package:converto/services/storage_service.dart';
import 'package:converto/core/utils/file_utils.dart';
import 'package:converto/services/pdf/pdf_text.dart';

void main() {
  group('Local text encoding and font safety', () {
    for (final little in [true, false]) {
      test(
        'UTF-16 ${little ? 'LE' : 'BE'} preserves surrogate pairs',
        () async {
          final dir = await Directory.systemTemp.createTemp('converto-utf16-');
          try {
            final bytes = <int>[
              if (little) ...[255, 254] else ...[254, 255],
            ];
            for (final unit in 'A🧪'.codeUnits) {
              bytes.addAll(
                little ? [unit & 255, unit >> 8] : [unit >> 8, unit & 255],
              );
            }
            final file = File('${dir.path}/sample.txt');
            await file.writeAsBytes(bytes);
            expect(await FileUtils.readLocalText(file), 'A🧪');
          } finally {
            await dir.delete(recursive: true);
          }
        },
      );
    }
    for (final bytes in [
      [255, 254, 65],
      [255, 254, 0, 216],
    ]) {
      test('rejects malformed UTF-16 $bytes', () async {
        final dir = await Directory.systemTemp.createTemp(
          'converto-utf16-invalid-',
        );
        try {
          final file = File('${dir.path}/invalid.txt');
          await file.writeAsBytes(bytes);
          await expectLater(
            FileUtils.readLocalText(file),
            throwsFormatException,
          );
        } finally {
          await dir.delete(recursive: true);
        }
      });
    }
    test('UTF-8 BOM is decoded', () async {
      final dir = await Directory.systemTemp.createTemp('converto-utf8-');
      try {
        final file = File('${dir.path}/bom.txt');
        await file.writeAsBytes([239, 187, 191, 65]);
        expect(await FileUtils.readLocalText(file), 'A');
      } finally {
        await dir.delete(recursive: true);
      }
    });
    test('retains WinAnsi punctuation and detects non-Western text', () {
      expect(PdfText.needsUnicodeFont('Café – “quotes” €'), isFalse);
      expect(() => PdfText.requireBasicFont('你好'), throwsUnsupportedError);
    });
  });
  group('Terminal input regressions', () {
    final cases = <String, List<String>>{
      r"/tmp/apostrophe\'s.png pdf": ["/tmp/apostrophe's.png", 'pdf'],
      r'/tmp/quote\"name.png pdf': ['/tmp/quote"name.png', 'pdf'],
      r'/tmp/a\(1\)\&\[2\]\#\$.png': [r'/tmp/a(1)&[2]#$.png'],
      r"'/tmp/a'\''b.png'": ["/tmp/a'b.png"],
      r'"/tmp/a\"b.png"': ['/tmp/a"b.png'],
      '/tmp/a.png\t/tmp/b.png': ['/tmp/a.png', '/tmp/b.png'],
      'file:///tmp/a.png\r\nfile:///tmp/b.png': ['/tmp/a.png', '/tmp/b.png'],
      'file:///C:/Users/Jo/My%20File.pdf': [r'C:\Users\Jo\My File.pdf'],
      r'\\server\share\file.pdf': [r'\\server\share\file.pdf'],
      r"& 'C:\Users\Jo\O''Brien.pdf'": [r"C:\Users\Jo\O'Brien.pdf"],
      '"/tmp/ é 你好 .png"': ['/tmp/ é 你好 .png'],
      '/tmp/00~real01~.png': ['/tmp/00~real01~.png'],
      "'/tmp/ space .png '": ['/tmp/ space .png '],
    };
    for (final entry in cases.entries) {
      test(
        entry.key,
        () => expect(TerminalInputParser.tokenize(entry.key), entry.value),
      );
    }
    test('remote file URI is rejected', () {
      expect(
        () => TerminalInputParser.tokenize('file://remote/private.pdf'),
        throwsFormatException,
      );
    });
    test('malformed URI escape is rejected', () {
      expect(
        () => TerminalInputParser.tokenize('file:///tmp/%ZZ.pdf'),
        throwsFormatException,
      );
    });
    test('unclosed filename quote is rejected', () {
      expect(
        () => TerminalInputParser.tokenize("'/tmp/file.pdf"),
        throwsFormatException,
      );
    });
  });

  test(
    'a failed atomic write preserves an existing destination and cleans staging',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'converto-atomic-test-',
      );
      try {
        final destination = File('${dir.path}/existing.pdf');
        await destination.writeAsString('keep this original');
        await expectLater(
          StorageService.writeAtomically(destination, (temp) async {
            await temp.writeAsString('partial output');
            throw const FileSystemException('Simulated disk write failure');
          }),
          throwsA(isA<FileSystemException>()),
        );
        expect(await destination.readAsString(), 'keep this original');
        expect(dir.listSync().length, 1);
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
}
