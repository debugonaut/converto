import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:converto/models/gui/tool_definition.dart';
import 'package:converto/services/gui/gui_executor.dart';
import 'package:converto/services/gui/gui_job_controller.dart';
import 'package:converto/services/gui/workspace_validation.dart';
import 'package:converto/services/pdf/pdf_engine.dart';

void main() {
  late Directory scratch;
  late File source;
  setUp(() async {
    scratch = Directory.systemTemp.createTempSync('scanned-pdf-');
    final pdf = pw.Document();
    for (final (width, height, shade) in [
      (120.0, 180.0, .25),
      (240.0, 100.0, .75),
    ]) {
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(width, height),
          margin: pw.EdgeInsets.zero,
          build: (_) => pw.Container(
            width: width,
            height: height,
            color: PdfColor(shade, shade, shade),
            child: pw.Text(
              'Searchable source',
              style: const pw.TextStyle(fontSize: 8),
            ),
          ),
        ),
      );
    }
    source = File('${scratch.path}/source.pdf')
      ..writeAsBytesSync(await pdf.save());
  });
  tearDown(() async {
    await PdfEngine.dispose();
    scratch.deleteSync(recursive: true);
  });
  GuiRequest request(
    List<String> paths, {
    Map<String, Object> options = const {},
    String? name,
  }) => GuiRequest(
    tool: ToolId.scanPdf,
    paths: paths,
    outputDirectory: '${scratch.path}/out',
    outputName: name,
    options: {'dpi': '72', ...options},
  );

  test(
    'contrast and brightness affect every page while retaining PDF dimensions',
    () async {
      final original = source.readAsBytesSync();
      final out = Directory('${scratch.path}/out')..createSync();
      final existing = File('${out.path}/Scanned.pdf')
        ..writeAsStringSync('keep');
      final result = await GuiExecutor.run(
        request(
          [source.path],
          name: 'Scanned',
          options: {'contrast': 2, 'brightness': .1},
        ),
      );
      final output = File(result.outputs.single);
      expect(output.path, isNot(existing.path));
      expect(existing.readAsStringSync(), 'keep');
      final pages = await PdfEngine.rasterizePages(
        sourceFile: output,
        dpi: 72,
      ).toList();
      expect(pages.length, 2);
      expect(pages.map((page) => (page.width, page.height)), [
        (120.0, 180.0),
        (240.0, 100.0),
      ]);
      final dark = img.decodePng(pages[0].png)!.getPixel(60, 90);
      final light = img.decodePng(pages[1].png)!.getPixel(120, 50);
      expect(dark.r, closeTo(26, 4));
      expect(light.r, 255);
      expect(
        (await PdfEngine.extractText(source)),
        contains('Searchable source'),
      );
      expect((await PdfEngine.extractText(output)).trim(), isEmpty);
      expect(source.readAsBytesSync(), original);
      expect(result.metrics.outputBytes, output.lengthSync());
      expect(result.metrics.inputBytes, original.length);
      expect(out.listSync().whereType<Directory>(), isEmpty);
    },
  );

  test(
    'PDFs, photos, text and spreadsheets form one ordered scanned PDF',
    () async {
      final photo = File('${scratch.path}/photo.jpg')
        ..writeAsBytesSync(
          img.encodeJpg(
            img.fill(
              img.Image(width: 20, height: 30),
              color: img.ColorRgb8(255, 0, 0),
            ),
          ),
        );
      final text = File('${scratch.path}/notes.txt')
        ..writeAsStringSync('Notes');
      final csv = File('${scratch.path}/budget.csv')
        ..writeAsStringSync('Name,Amount\nPaper,10\n');
      final result = await GuiExecutor.run(
        request(
          [photo.path, source.path, text.path, csv.path],
          options: {'scanMode': 'color', 'contrast': 1},
        ),
      );
      expect(p.basename(result.outputs.single), 'scanned.pdf');
      expect(Directory('${scratch.path}/out').listSync().length, 1);
      final pages = await PdfEngine.rasterizePages(
        sourceFile: File(result.outputs.single),
        dpi: 72,
      ).toList();
      expect(pages.length, 5);
      final photoPage = img.decodePng(pages.first.png)!;
      final red = photoPage.getPixel(
        photoPage.width ~/ 2,
        photoPage.height ~/ 2,
      );
      expect(red.r, greaterThan(240));
      expect(red.g, lessThan(10));
      expect(pages[1].width, 120);
      expect(pages[2].width, 240);
      final metrics = result.metrics;
      expect(
        metrics.inputBytes,
        [
          photo,
          source,
          text,
          csv,
        ].fold<int>(0, (n, file) => n + file.lengthSync()),
      );
    },
  );

  test('rotated pages retain their displayed orientation and size', () async {
    final rotated = await PdfEngine.rotate(
      sourceFile: source,
      degrees: 90,
      outputPath: '${scratch.path}/rotated.pdf',
    );
    final result = await GuiExecutor.run(request([rotated.path]));
    final pages = await PdfEngine.rasterizePages(
      sourceFile: File(result.outputs.single),
      dpi: 72,
    ).toList();
    expect(pages.map((page) => (page.width, page.height)), [
      (180.0, 120.0),
      (100.0, 240.0),
    ]);
  });

  test('black and white export produces dark ink and white paper', () async {
    final result = await GuiExecutor.run(
      request([source.path], options: {'scanMode': 'blackAndWhite'}),
    );
    final pages = await PdfEngine.rasterizePages(
      sourceFile: File(result.outputs.single),
      dpi: 72,
    ).toList();
    final first = img.decodePng(pages[0].png)!;
    final second = img.decodePng(pages[1].png)!;
    expect(first.getPixel(60, 90).r, 0);
    expect(second.getPixel(120, 50).r, 255);
  });

  test(
    'cancelling between scan pages cleans staging and leaves the source usable',
    () async {
      var cancelled = false;
      await expectLater(
        GuiExecutor.run(
          request([source.path]),
          onProgress: (value, _) {
            if (value > .2) cancelled = true;
          },
          isCancelled: () => cancelled,
        ),
        throwsA(isA<GuiCancelled>()),
      );
      expect(cancelled, isTrue);
      expect(Directory('${scratch.path}/out').listSync(), isEmpty);
      expect(await PdfEngine.pageCount(source), 2);
    },
  );

  test(
    'a corrupt later input rolls back every scanned page and reports its source',
    () async {
      final broken = File('${scratch.path}/broken.png')
        ..writeAsStringSync('invalid image');
      await expectLater(
        GuiExecutor.run(request([source.path, broken.path])),
        throwsA(
          isA<GuiInputFailure>().having(
            (error) => error.sourcePath,
            'source',
            broken.path,
          ),
        ),
      );
      expect(Directory('${scratch.path}/out').listSync(), isEmpty);
    },
  );

  test(
    'worker publishes one named scanned result and one history record',
    () async {
      var records = 0;
      final job = GuiJobController(
        recordHistory: (items) async => records += items.length,
      );
      try {
        await job.run(request([source.path, source.path], name: 'Scan set'));
        expect(job.error, isNull);
        expect(p.basename(job.result!.outputs.single), 'Scan set.pdf');
        expect(await PdfEngine.pageCount(File(job.result!.outputs.single)), 4);
        expect(records, 1);
        expect(job.progress, 1);
      } finally {
        job.dispose();
      }
    },
  );

  test(
    'UI and worker reject invalid scan settings without publishing files',
    () async {
      expect(
        WorkspaceValidation.check(ToolId.scanPdf, {'contrast': 0}),
        contains('scan'),
      );
      await expectLater(
        GuiExecutor.run(request([source.path], options: {'contrast': 0})),
        throwsA(isA<GuiInputFailure>()),
      );
      expect(Directory('${scratch.path}/out').listSync(), isEmpty);
    },
  );
}
