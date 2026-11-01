import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:converto/services/pdf/pdf_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/widgets.dart' as pw;
import 'package:converto/models/gui/file_preview.dart';
import 'package:converto/services/gui/local_preview_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory scratch;
  late File source;
  setUp(() {
    scratch = Directory.systemTemp.createTempSync('converto-preview-');
    source = File('${scratch.path}/image.png')
      ..writeAsBytesSync(img.encodePng(img.Image(width: 64, height: 48)));
  });
  tearDown(() {
    scratch.deleteSync(recursive: true);
  });
  FilePreview data(String path) => FilePreview(
    path: path,
    kind: 'image',
    sizeBytes: source.lengthSync(),
    width: 64,
    height: 48,
    rasterWidth: 64,
    rasterHeight: 48,
    image: Uint8List.fromList([1, 2, 3]),
  );

  test('same visible preview is deduplicated and cached', () async {
    var calls = 0;
    final service = LocalPreviewService(
      renderer: (path, page, dimension, password) async {
        calls++;
        return data(path);
      },
    );
    try {
      final values = await Future.wait(
        List.generate(8, (_) => service.load(source.path)),
      );
      expect(calls, 1);
      expect(values.every((value) => identical(value, values.first)), isTrue);
      await service.load(source.path);
      expect(calls, 1);
      expect(service.cacheEntries, 1);
    } finally {
      service.dispose();
    }
  });
  test('LRU evicts previews and accounts for decoded pixels', () async {
    final service = LocalPreviewService(
      maxEntries: 2,
      maxMemoryBytes: 25000,
      renderer: (path, page, dimension, password) async => data(path),
    );
    try {
      for (var i = 0; i < 4; i++) await service.load(source.path, page: i);
      expect(service.cacheEntries, 2);
      expect(service.cachedBytes, lessThanOrEqualTo(25000));
    } finally {
      service.dispose();
    }
  });
  test('a changed source invalidates the cached request', () async {
    var calls = 0;
    final service = LocalPreviewService(
      renderer: (path, page, dimension, password) async {
        calls++;
        return data(path);
      },
    );
    try {
      await service.load(source.path);
      source.writeAsBytesSync([0], mode: FileMode.append);
      await service.load(source.path);
      expect(calls, 2);
    } finally {
      service.dispose();
    }
  });
  test('password-protected previews and passwords are not cached', () async {
    var calls = 0;
    final service = LocalPreviewService(
      renderer: (path, page, dimension, password) async {
        calls++;
        expect(password, 'test-only');
        return data(path);
      },
    );
    try {
      await service.load(source.path, password: 'test-only');
      await service.load(source.path, password: 'test-only');
      expect(calls, 2);
      expect(service.cacheEntries, 0);
    } finally {
      service.dispose();
    }
  });
  test(
    'clearing during a request cannot reinsert stale data or lose a new request',
    () async {
      final firstStarted = Completer<void>(), secondStarted = Completer<void>();
      final first = Completer<FilePreview>(), second = Completer<FilePreview>();
      var calls = 0;
      final service = LocalPreviewService(
        renderer: (path, page, dimension, password) {
          if (++calls == 1) {
            firstStarted.complete();
            return first.future;
          }
          secondStarted.complete();
          return second.future;
        },
      );
      try {
        final oldRequest = service.load(source.path);
        await firstStarted.future;
        service.clear();
        final newRequest = service.load(source.path);
        first.complete(data(source.path));
        await oldRequest;
        await secondStarted.future;
        expect(service.cacheEntries, 0);
        second.complete(data(source.path));
        await newRequest;
        expect(service.cacheEntries, 1);
        expect(calls, 2);
      } finally {
        service.dispose();
      }
    },
  );
  test(
    'processing pauses queued previews and dispose releases paused callers',
    () async {
      var calls = 0;
      final service = LocalPreviewService(
        renderer: (path, page, dimension, password) async {
          calls++;
          return data(path);
        },
      );
      service.paused = true;
      final waiting = service.load(source.path);
      service.dispose();
      await waiting;
      expect(calls, 0);
    },
  );
  test(
    'real image and text previews create no files and do not mutate sources',
    () async {
      final text = File('${scratch.path}/text.txt')
        ..writeAsStringSync('Local text preview');
      final original = source.readAsBytesSync();
      final before = scratch.listSync().map((file) => file.path).toSet();
      final service = LocalPreviewService();
      try {
        final preview = await service.load(source.path, dimension: 160);
        expect(preview.kind, 'image');
        expect(preview.width, 64);
        expect(preview.height, 48);
        expect(preview.image, isNotEmpty);
        final excerpt = await service.load(text.path);
        expect(excerpt.text, contains('Local text preview'));
        expect(source.readAsBytesSync(), original);
        expect(scratch.listSync().map((file) => file.path).toSet(), before);
      } finally {
        service.dispose();
      }
    },
  );
  test(
    'real PDF pages are rendered lazily and corrupt files fail cleanly',
    () async {
      final document = pw.Document();
      document.addPage(pw.Page(build: (_) => pw.Text('Page one')));
      document.addPage(pw.Page(build: (_) => pw.Text('Page two')));
      final pdf = File('${scratch.path}/source.pdf')
        ..writeAsBytesSync(await document.save());
      final corrupt = File('${scratch.path}/corrupt.pdf')
        ..writeAsStringSync('not a PDF');
      final service = LocalPreviewService();
      try {
        final page = await service.load(pdf.path, page: 1, dimension: 160);
        expect(page.kind, 'pdf');
        expect(page.pageCount, 2);
        expect(page.page, 1);
        expect(page.image, isNotEmpty);
        final failure = await service.load(corrupt.path);
        expect(failure.kind, 'error');
        expect(failure.message, isNotEmpty);
        final validAgain = await service.load(
          pdf.path,
          page: 0,
          dimension: 160,
        );
        expect(validAgain.kind, 'pdf');
      } finally {
        service.dispose();
      }
    },
  );
  test(
    'all nine supported image extensions produce bounded local previews',
    () async {
      final image = img.Image(width: 64, height: 48);
      final encodings = <String, List<int>>{
        'png': img.encodePng(image),
        'jpg': img.encodeJpg(image),
        'jpeg': img.encodeJpg(image),
        'bmp': img.encodeBmp(image),
        'gif': img.encodeGif(image),
        'tiff': img.encodeTiff(image),
        'tif': img.encodeTiff(image),
        'ico': img.encodeIco(image),
        'webp': File('test/fixtures/previews/sample.webp').readAsBytesSync(),
      };
      final service = LocalPreviewService();
      try {
        for (final entry in encodings.entries) {
          final file = File('${scratch.path}/sample.${entry.key}')
            ..writeAsBytesSync(entry.value);
          final preview = await service.load(file.path, dimension: 160);
          expect(preview.kind, 'image', reason: entry.key);
          expect(preview.image, isNotEmpty, reason: entry.key);
          expect(
            preview.rasterWidth,
            lessThanOrEqualTo(160),
            reason: entry.key,
          );
          expect(
            preview.rasterHeight,
            lessThanOrEqualTo(160),
            reason: entry.key,
          );
        }
      } finally {
        service.dispose();
      }
    },
  );

  test(
    'animated GIF frames and largest ICO entry are available locally',
    () async {
      final animated = img.Image(width: 32, height: 24);
      img.fill(animated, color: img.ColorRgb8(255, 0, 0));
      animated.addFrame(
        img.Image(width: 32, height: 24)..setPixelRgb(0, 0, 0, 0, 255),
      );
      final gif = File('${scratch.path}/animation.gif')
        ..writeAsBytesSync(img.encodeGif(animated));
      final ico = File('${scratch.path}/sizes.ico')
        ..writeAsBytesSync(
          img.encodeIco(
            img.Image(width: 16, height: 16)
              ..addFrame(img.Image(width: 64, height: 64)),
          ),
        );
      final service = LocalPreviewService();
      try {
        final frame1 = await service.load(gif.path);
        final frame2 = await service.load(gif.path, page: 1);
        expect(frame1.pageCount, 2);
        expect(frame2.page, 1);
        expect(frame1.image, isNot(equals(frame2.image)));
        final icon = await service.load(ico.path);
        expect(icon.width, 64);
        expect(icon.pageCount, 1);
      } finally {
        service.dispose();
      }
    },
  );

  test(
    'JPEG EXIF orientation is reflected in the preview dimensions',
    () async {
      final image = img.Image(width: 64, height: 48);
      image.exif.imageIfd.orientation = 6;
      final file = File('${scratch.path}/oriented.jpg')
        ..writeAsBytesSync(img.encodeJpg(image));
      final service = LocalPreviewService();
      try {
        final preview = await service.load(file.path);
        expect([preview.width, preview.height], [48, 64]);
      } finally {
        service.dispose();
      }
    },
  );

  test(
    'local Office excerpts and UTF16 text do not need helper processes',
    () async {
      final documents = {
        'docx': {
          'word/document.xml': '<document><p><t>Local Alpha</t></p></document>',
        },
        'odt': {'content.xml': '<document><p>Local Alpha</p></document>'},
        'pptx': {
          'ppt/slides/slide1.xml': '<slide><t>Local Alpha</t></slide>',
          'ppt/slides/slide2.xml': '<slide><t>Second slide</t></slide>',
        },
        'xlsx': {
          'xl/sharedStrings.xml': '<sst><si><t>Local Alpha</t></si></sst>',
          'xl/worksheets/sheet1.xml':
              '<worksheet><row><c t="s"><v>0</v></c><c><v>12</v></c></row></worksheet>',
        },
      };
      final service = LocalPreviewService();
      try {
        for (final entry in documents.entries) {
          final archive = Archive();
          for (final member in entry.value.entries) {
            final bytes = utf8.encode(member.value);
            archive.addFile(ArchiveFile(member.key, bytes.length, bytes));
          }
          final file = File('${scratch.path}/local.${entry.key}')
            ..writeAsBytesSync(ZipEncoder().encode(archive)!);
          final preview = await service.load(file.path);
          expect(preview.text, contains('Local Alpha'), reason: entry.key);
          if (entry.key == 'pptx') {
            final slide2 = await service.load(file.path, page: 1);
            expect(slide2.pageCount, 2);
            expect(slide2.text, contains('Second slide'));
          }
        }
        final utf16 = File('${scratch.path}/utf16.txt')
          ..writeAsBytesSync([255, 254, 65, 0, 66, 0]);
        expect((await service.load(utf16.path)).text, 'AB');
        final csv = File('${scratch.path}/table.csv')
          ..writeAsStringSync('Name,Value\nAlpha,12');
        expect((await service.load(csv.path)).text, contains('Alpha,12'));
        for (final ext in ['doc', 'xls', 'ppt', 'odp', 'rtf']) {
          final file = File('${scratch.path}/legacy.$ext')
            ..writeAsStringSync('legacy placeholder');
          final preview = await service.load(file.path);
          expect(preview.image, isNull);
          expect(preview.message, contains('Open original'), reason: ext);
        }
      } finally {
        service.dispose();
      }
    },
  );

  test(
    'protected PDFs require a password and never cache decrypted thumbnails',
    () async {
      final doc = pw.Document()
        ..addPage(pw.Page(build: (_) => pw.Text('Private preview')));
      final plain = File('${scratch.path}/plain.pdf')
        ..writeAsBytesSync(await doc.save());
      final protected = await PdfEngine.protect(
        sourceFile: plain,
        password: 'local-password',
        outputPath: '${scratch.path}/protected.pdf',
      );
      final service = LocalPreviewService();
      try {
        expect((await service.load(protected.path)).encrypted, isTrue);
        final wrong = await service.load(protected.path, password: 'wrong');
        expect(wrong.kind, 'error');
        final before = service.cacheEntries;
        final unlocked = await service.load(
          protected.path,
          password: 'local-password',
        );
        expect(unlocked.kind, 'pdf');
        expect(unlocked.image, isNotEmpty);
        expect(service.cacheEntries, before);
      } finally {
        service.dispose();
        await PdfEngine.dispose();
      }
    },
  );
}
