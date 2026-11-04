import 'dart:io';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_manipulator/pdf_manipulator.dart' as native;
import 'package:pdf_manipulator/io.dart';
import 'package:converto/models/pdf_layout_options.dart';
import 'package:converto/services/pdf/pdf_engine.dart';
import 'package:converto/services/pdf/pdf_extended_tools.dart';

void main() {
  test(
    'page numbers remain visible in the selected corner of rotated cropped pages',
    () async {
      final scratch = Directory.systemTemp.createTempSync(
        'converto-cropped-numbers-',
      );
      addTearDown(() async {
        await PdfEngine.dispose();
        scratch.deleteSync(recursive: true);
      });
      final document = pw.Document()
        ..addPage(
          pw.Page(
            pageFormat: const PdfPageFormat(300, 400),
            build: (_) => pw.SizedBox(),
          ),
        );
      final blank = File('${scratch.path}/blank.pdf')
        ..writeAsBytesSync(await document.save());
      final cropped = await PdfEngine.crop(
        sourceFile: blank,
        left: 60,
        right: 60,
        top: 90,
        bottom: 70,
        outputPath: '${scratch.path}/cropped.pdf',
      );
      for (final rotation in [0, 90, 180, 270]) {
        final source = await PdfEngine.rotate(
          sourceFile: cropped,
          degrees: rotation,
          outputPath: '${scratch.path}/rot-$rotation.pdf',
        );
        final numbered = await PdfEngine.pageNumbers(
          sourceFile: source,
          outputPath: '${scratch.path}/num-$rotation.pdf',
          layout: const PdfLayoutOptions(position: 'topLeft'),
        );
        final page = await PdfEngine.rasterizePages(
          sourceFile: numbered,
          dpi: 72,
        ).first;
        final bitmap = img.decodePng(page.png)!;
        final ink = bitmap
            .where((pixel) => pixel.r < 170)
            .map((pixel) => (pixel.x, pixel.y))
            .toList();
        expect(ink.length, greaterThan(20), reason: 'rotation $rotation');
        expect(
          ink.every(
            (point) =>
                point.$1 < bitmap.width / 2 && point.$2 < bitmap.height / 2,
          ),
          isTrue,
          reason: 'rotation $rotation',
        );
      }
    },
  );
  late Directory temp;
  late File source;
  late File logo;
  setUp(() async {
    temp = Directory.systemTemp.createTempSync('extended-pdf-');
    logo = File('${temp.path}/logo.jpg')
      ..writeAsBytesSync(
        img.encodeJpg(
          img.fill(
            img.Image(width: 40, height: 20),
            color: img.ColorRgb8(255, 0, 0),
          ),
        ),
      );
    final pdf = pw.Document(title: 'Private title', author: 'Private author');
    pdf.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(240, 320),
        build: (_) => pw.Column(
          children: [
            pw.Text('First page'),
            pw.Image(pw.MemoryImage(logo.readAsBytesSync())),
          ],
        ),
      ),
    );
    pdf.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(240, 320),
        build: (_) => pw.Text('Second page'),
      ),
    );
    source = File('${temp.path}/source.pdf')
      ..writeAsBytesSync(await pdf.save());
  });
  tearDown(() async {
    await PdfEngine.dispose();
    temp.deleteSync(recursive: true);
  });
  test(
    'clean removes selected metadata while retaining pages and originals',
    () async {
      final original = source.readAsBytesSync();
      final out = await PdfExtendedTools.clean(
        sourceFile: source,
        outputPath: '${temp.path}/clean.pdf',
        metadata: true,
        javascript: false,
        attachments: false,
      );
      final info = await PdfEngine.info(out);
      expect(info.title, anyOf(isNull, isEmpty));
      expect(info.author, anyOf(isNull, isEmpty));
      expect(await PdfEngine.extractText(out), contains('Second page'));
      expect(source.readAsBytesSync(), original);
    },
  );
  test(
    'flatten preserves filled text appearance and removes interactive fields',
    () async {
      final pdf = pw.Document();
      pdf.addPage(
        pw.Page(
          build: (_) => pw.TextField(
            name: 'Name',
            value: 'Alice',
            width: 180,
            height: 40,
          ),
        ),
      );
      final input = File('${temp.path}/form.pdf')
        ..writeAsBytesSync(await pdf.save());
      final out = await PdfExtendedTools.flatten(
        sourceFile: input,
        outputPath: '${temp.path}/flat.pdf',
        forms: true,
        annotations: true,
      );
      final engine = native.Pdf();
      final doc = await engine.open(FileSource(out));
      try {
        expect(await doc.formFields, isEmpty);
      } finally {
        await doc.dispose();
        await engine.dispose();
      }
      expect(await PdfEngine.extractText(out), contains('Alice'));
      final rendered = await PdfEngine.rasterizePages(
        sourceFile: out,
        dpi: 72,
      ).first;
      final bitmap = img.decodePng(rendered.png)!;
      expect(
        bitmap.toUint8List().where((v) => v < 100).length,
        greaterThan(50),
      );
    },
  );
  test(
    'embedded image extraction returns images rather than rendered PDF pages',
    () async {
      final outputs = await PdfExtendedTools.extractImages(
        sourceFile: source,
        outputDirectory: '${temp.path}/images',
      );
      expect(outputs.length, 1);
      expect(img.decodeImage(outputs.single.readAsBytesSync())!.width, 40);
      expect(outputs.single.path, endsWith('.jpg'));
      final textPdf = pw.Document()
        ..addPage(pw.Page(build: (_) => pw.Text('Text only')));
      final text = File('${temp.path}/text.pdf')
        ..writeAsBytesSync(await textPdf.save());
      await expectLater(
        PdfExtendedTools.extractImages(
          sourceFile: text,
          outputDirectory: '${temp.path}/empty',
        ),
        throwsArgumentError,
      );
    },
  );
  test(
    'numbering scopes pages and applies the requested starting number',
    () async {
      final out = await PdfEngine.pageNumbers(
        sourceFile: source,
        outputPath: '${temp.path}/numbered.pdf',
        layout: const PdfLayoutOptions(
          pages: '2',
          startNumber: 7,
          position: 'topLeft',
        ),
      );
      final syntax = latin1.decode(out.readAsBytesSync());
      final content = RegExp(r'stream\r?\n(.*?)\r?\nendstream', dotAll: true)
          .allMatches(syntax)
          .map((m) {
            final bytes = latin1.encode(m[1]!);
            try {
              return latin1.decode(ZLibDecoder().decodeBytes(bytes));
            } catch (_) {
              return m[1]!;
            }
          })
          .join('\n');
      expect(content, contains('(Page 7 of 7) Tj'));
      expect(content, isNot(contains('Page 1 of')));
      final before = await PdfEngine.rasterizePages(
        sourceFile: source,
        dpi: 72,
      ).toList();
      final after = await PdfEngine.rasterizePages(
        sourceFile: out,
        dpi: 72,
      ).toList();
      expect(
        img.decodePng(after[0].png)!.toUint8List(),
        img.decodePng(before[0].png)!.toUint8List(),
      );
      expect(
        img.decodePng(after[1].png)!.toUint8List(),
        isNot(img.decodePng(before[1].png)!.toUint8List()),
      );
      expect(await PdfEngine.pageCount(out), 2);
    },
  );
  test(
    'image watermark fits the displayed top-left corner on every rotation',
    () async {
      for (final angle in [0, 90, 180, 270]) {
        final base = await PdfEngine.rotate(
          sourceFile: source,
          degrees: angle,
          outputPath: '${temp.path}/r$angle.pdf',
        );
        final out = await PdfExtendedTools.imageWatermark(
          sourceFile: base,
          imageFile: logo,
          outputPath: '${temp.path}/stamp$angle.pdf',
          opacity: 1,
          layout: const PdfLayoutOptions(
            pages: '2',
            position: 'topLeft',
            margin: 20,
            imageWidthPercent: 25,
          ),
        );
        final pages = await PdfEngine.rasterizePages(
          sourceFile: out,
          dpi: 72,
        ).toList();
        final bitmap = img.decodePng(pages[1].png)!;
        final red = bitmap.getPixel(25, 25);
        expect(red.r, greaterThan(230), reason: 'rotation $angle');
        expect(red.g, lessThan(30), reason: 'rotation $angle');
        final below = bitmap.getPixel(25, 100);
        expect(below.g, greaterThan(200));
      }
    },
  );
  test(
    'layout and destructive options reject invalid or empty actions',
    () async {
      expect(
        () => PdfLayoutOptions.fromMap({'startNumber': '-1'}),
        throwsArgumentError,
      );
      expect(
        () => PdfLayoutOptions.fromMap({'position': 'outside'}),
        throwsArgumentError,
      );
      await expectLater(
        PdfExtendedTools.flatten(
          sourceFile: source,
          outputPath: '${temp.path}/none.pdf',
          forms: false,
          annotations: false,
        ),
        throwsArgumentError,
      );
      await expectLater(
        PdfExtendedTools.clean(
          sourceFile: source,
          outputPath: '${temp.path}/none.pdf',
          metadata: false,
          javascript: false,
          attachments: false,
        ),
        throwsArgumentError,
      );
      expect(File('${temp.path}/none.pdf').existsSync(), false);
    },
  );
}
