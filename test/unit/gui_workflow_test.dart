import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pdf/widgets.dart' as pw;
import 'package:converto/models/gui/tool_definition.dart';
import 'package:converto/services/gui/gui_executor.dart';
import 'package:converto/services/gui/gui_job_controller.dart';
import 'package:converto/services/pdf/pdf_engine.dart';

void main() {
  late Directory scratch;
  late File image, pdf;
  setUp(() async {
    scratch = Directory.systemTemp.createTempSync('gui-workflow-');
    image = File('${scratch.path}/source.png')
      ..writeAsBytesSync(img.encodePng(img.Image(width: 64, height: 48)));
    final document = pw.Document();
    for (var page = 1; page <= 3; page++) {
      document.addPage(pw.Page(build: (_) => pw.Text('Page $page SAMPLE')));
    }
    pdf = File('${scratch.path}/source.pdf')
      ..writeAsBytesSync(await document.save());
  });
  tearDown(() async {
    await PdfEngine.dispose();
    scratch.deleteSync(recursive: true);
  });
  Future<GuiResult> run(
    ToolId tool,
    List<String> paths, {
    String? name,
    Map<String, String> names = const {},
    Map<String, Object> options = const {},
    String? output,
  }) => GuiExecutor.run(
    GuiRequest(
      tool: tool,
      paths: paths,
      outputDirectory: output ?? '${scratch.path}/out',
      outputName: name,
      outputNames: names,
      options: options,
    ),
  );

  test(
    'single output uses an inline Unicode name and its actual encoder extension',
    () async {
      final result = await run(
        ToolId.convert,
        [image.path],
        name: 'Invoice résumé.PDF',
        options: {'format': 'pdf'},
      );
      expect(p.basename(result.outputs.single), 'Invoice résumé.pdf');
      expect(result.sourcePaths[result.outputs.single], image.path);
      expect(result.metrics.inputBytes, image.lengthSync());
      expect(
        result.metrics.outputBytes,
        File(result.outputs.single).lengthSync(),
      );
    },
  );
  test('merge names the combined result', () async {
    final result = await run(ToolId.merge, [
      pdf.path,
      image.path,
    ], name: 'Combined');
    expect(p.basename(result.outputs.single), 'Combined.pdf');
    expect(await PdfEngine.pageCount(File(result.outputs.single)), 4);
  });
  test(
    'page exports and splits use the chosen base and stable numbers',
    () async {
      final rendered = await run(
        ToolId.pdfImages,
        [pdf.path],
        name: 'Scan.png',
        options: {'format': 'png', 'dpi': '30'},
      );
      expect(rendered.outputs.map(p.basename), [
        'Scan_001.png',
        'Scan_002.png',
        'Scan_003.png',
      ]);
      final split = await run(ToolId.split, [pdf.path], name: 'Section');
      expect(split.outputs.map(p.basename), [
        'Section_001.pdf',
        'Section_002.pdf',
        'Section_003.pdf',
      ]);
    },
  );
  test(
    'batch outputs retain independently edited names and original source mappings',
    () async {
      final second = image.copySync('${scratch.path}/second.png');
      final result = await run(
        ToolId.convert,
        [image.path, second.path],
        names: {image.path: 'First', second.path: 'Second'},
        options: {'format': 'jpg'},
      );
      expect(result.outputs.map(p.basename), ['First.jpg', 'Second.jpg']);
      expect(result.sourcePaths.values, [image.path, second.path]);
    },
  );
  test(
    'colliding custom names preserve existing results and source bytes',
    () async {
      final original = image.readAsBytesSync();
      final result = await run(
        ToolId.convert,
        [image.path],
        name: 'source',
        options: {'format': 'png'},
        output: scratch.path,
      );
      expect(result.outputs.single, isNot(image.path));
      expect(image.readAsBytesSync(), original);
      final again = await run(
        ToolId.convert,
        [image.path],
        name: 'source',
        options: {'format': 'png'},
        output: scratch.path,
      );
      expect(again.outputs.single, isNot(result.outputs.single));
      expect(File(result.outputs.single).existsSync(), isTrue);
    },
  );
  test(
    'invalid names fail before any output directory or file is created',
    () async {
      final output = '${scratch.path}/not-created';
      for (final name in ['../outside', 'report..pdf']) {
        await expectLater(
          run(
            ToolId.convert,
            [image.path],
            name: name,
            options: {'format': 'pdf'},
            output: output,
          ),
          throwsArgumentError,
        );
        expect(Directory(output).existsSync(), isFalse);
      }
    },
  );
  test(
    'visual page rotation is applied after reorder and duplication',
    () async {
      final result = await run(
        ToolId.organize,
        [pdf.path],
        name: 'Arranged',
        options: {
          'pages': '3,1,2,2',
          'pageRotations': [90, 0, 180, 270],
        },
      );
      final info = await PdfEngine.info(File(result.outputs.single));
      expect(info.pageCount, 4);
      expect(info.rotation, 90);
      expect(
        await PdfEngine.extractText(File(result.outputs.single)),
        contains('Page 3'),
      );
    },
  );
  test('invalid visual page plans roll back the whole batch', () async {
    await expectLater(
      run(
        ToolId.organize,
        [pdf.path],
        options: {
          'pages': '1,2',
          'pageRotations': [90],
        },
      ),
      throwsA(isA<GuiInputFailure>()),
    );
    expect(Directory('${scratch.path}/out').listSync(), isEmpty);
  });
  test(
    'worker failures identify the input and a subsequent retry works',
    () async {
      final corrupt = File('${scratch.path}/corrupt.pdf')
        ..writeAsStringSync('not a PDF');
      final job = GuiJobController();
      try {
        await job.run(
          GuiRequest(
            tool: ToolId.pdfText,
            paths: [pdf.path, corrupt.path],
            outputDirectory: '${scratch.path}/out',
          ),
          remember: false,
        );
        expect(job.error, contains('corrupt.pdf'));
        expect(job.failedSource, corrupt.path);
        expect(Directory('${scratch.path}/out').listSync(), isEmpty);
        await job.run(
          GuiRequest(
            tool: ToolId.pdfText,
            paths: [pdf.path],
            outputDirectory: '${scratch.path}/out',
            outputName: 'Recovered',
          ),
          remember: false,
        );
        expect(job.error, isNull);
        expect(job.failedSource, isNull);
        expect(p.basename(job.result!.outputs.single), 'Recovered.txt');
      } finally {
        job.dispose();
      }
    },
  );
  test(
    'history write failure keeps successful named outputs and reports a warning',
    () async {
      final job = GuiJobController(
        recordHistory: (_) async =>
            throw const FileSystemException('Read-only history'),
      );
      try {
        await job.run(
          GuiRequest(
            tool: ToolId.convert,
            paths: [image.path],
            outputDirectory: '${scratch.path}/out',
            outputName: 'Saved successfully',
            options: {'format': 'jpg'},
          ),
        );
        expect(job.error, isNull);
        expect(job.historyWarning, contains('Files were saved'));
        expect(
          p.basename(job.result!.outputs.single),
          'Saved successfully.jpg',
        );
        expect(File(job.result!.outputs.single).existsSync(), isTrue);
      } finally {
        job.dispose();
      }
    },
  );
}
