import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/widgets.dart' as pw;
import 'package:converto/models/gui/tool_definition.dart';
import 'package:converto/models/gui/file_preview.dart';
import 'package:converto/services/gui/gui_executor.dart';
import 'package:converto/services/gui/tool_capabilities.dart';
import 'package:converto/services/gui/workspace_validation.dart';
import 'package:converto/services/pdf/pdf_engine.dart';

void main() {
  test('inactive page ranges do not block size or count splitting', () {
    const preview = FilePreview(path: '/sample.pdf', kind: 'pdf', pageCount: 2);
    for (final mode in ['count', 'size']) {
      expect(
        WorkspaceValidation.check(ToolId.split, {
          'splitMode': mode,
          'pages': '99',
          'every': '1',
          'maxSizeMb': '10',
        }, preview: preview),
        isEmpty,
      );
    }
  });
  test(
    'invalid active page ranges become inline errors instead of exceptions',
    () {
      const preview = FilePreview(
        path: '/sample.pdf',
        kind: 'pdf',
        pageCount: 2,
      );
      for (final tool in [
        ToolId.extract,
        ToolId.organize,
        ToolId.split,
        ToolId.watermark,
        ToolId.pageNumbers,
      ]) {
        final errors = WorkspaceValidation.check(tool, {
          'pages': '99',
          'splitMode': 'ranges',
          'text': 'DRAFT',
          'opacity': '.2',
          'angle': '0',
          'fontSize': '20',
        }, preview: preview);
        expect(errors.keys, contains('pages'), reason: tool.name);
      }
    },
  );
  late Directory temp;
  late File first, second;
  setUp(() async {
    temp = Directory.systemTemp.createTempSync('parity-executor-');
    Future<File> pdf(String name, String text) async {
      final doc = pw.Document(title: 'Private metadata');
      for (var i = 0; i < 2; i++) {
        doc.addPage(pw.Page(build: (_) => pw.Text('$text page $i')));
      }
      return File('${temp.path}/$name.pdf')..writeAsBytesSync(await doc.save());
    }

    first = await pdf('first', 'Original');
    second = await pdf('second', 'Changed');
  });
  tearDown(() async {
    await PdfEngine.dispose();
    temp.deleteSync(recursive: true);
  });
  GuiRequest request(
    ToolId id, {
    List<String>? paths,
    Map<String, Object> options = const {},
    String? name,
  }) => GuiRequest(
    tool: id,
    paths: paths ?? [first.path],
    outputDirectory: '${temp.path}/out',
    options: options,
    outputName: name,
  );
  test(
    'comparison produces one self-contained HTML report in the chosen order',
    () async {
      final out = await GuiExecutor.run(
        request(
          ToolId.compare,
          paths: [first.path, second.path],
          name: 'Changes',
        ),
      );
      expect(out.outputs.single, endsWith('Changes.html'));
      final html = File(out.outputs.single).readAsStringSync();
      expect(html, contains('data:image/png;base64,'));
      expect(html, contains('Original'));
      expect(html, contains('Changed'));
      expect(RegExp(r'(src|href)=["\x27]https?://').hasMatch(html), false);
      expect(Directory('${temp.path}/out').listSync().length, 1);
    },
  );
  test(
    'comparison rejects anything other than two input PDFs before publication',
    () async {
      await expectLater(
        GuiExecutor.run(request(ToolId.compare)),
        throwsArgumentError,
      );
      await expectLater(
        GuiExecutor.run(
          request(ToolId.compare, paths: [first.path, second.path, first.path]),
        ),
        throwsArgumentError,
      );
      expect(Directory('${temp.path}/out').existsSync(), false);
    },
  );
  test(
    'repair clean and flatten are app workflows that preserve sources',
    () async {
      final original = first.readAsBytesSync();
      for (final id in [ToolId.repair, ToolId.clean, ToolId.flatten]) {
        final result = await GuiExecutor.run(request(id, name: id.name));
        expect(await PdfEngine.pageCount(File(result.outputs.single)), 2);
        if (id == ToolId.clean)
          expect(
            (await PdfEngine.info(File(result.outputs.single))).title,
            anyOf(isNull, isEmpty),
          );
      }
      expect(first.readAsBytesSync(), original);
    },
  );
  test(
    'image extraction mode retains genuine image extensions and caller names',
    () async {
      final photo = img.encodeJpg(img.Image(width: 32, height: 24));
      final doc = pw.Document()
        ..addPage(pw.Page(build: (_) => pw.Image(pw.MemoryImage(photo))));
      final input = File('${temp.path}/photo.pdf')
        ..writeAsBytesSync(await doc.save());
      final result = await GuiExecutor.run(
        request(
          ToolId.pdfImages,
          paths: [input.path],
          options: {'imageMode': 'extract'},
          name: 'Original image',
        ),
      );
      expect(result.outputs.single, endsWith('Original image.jpg'));
      expect(
        img.decodeJpg(File(result.outputs.single).readAsBytesSync())!.width,
        32,
      );
    },
  );
  test(
    'visual HTML uses the existing standalone image-layout exporter',
    () async {
      final result = await GuiExecutor.run(
        request(
          ToolId.convert,
          options: {'format': 'html', 'htmlLayout': true},
          name: 'Exact',
        ),
      );
      expect(result.outputs.single, endsWith('Exact.html'));
      expect(
        File(result.outputs.single).readAsStringSync(),
        contains('data:image/png;base64,'),
      );
    },
  );
  test(
    'size splitting retains oversized individual pages and explains the target',
    () async {
      final result = await GuiExecutor.run(
        request(
          ToolId.split,
          options: {'splitMode': 'size', 'maxSizeMb': '.001'},
          name: 'Part',
        ),
      );
      expect(result.outputs.length, 2);
      expect(result.details.join(' '), contains('exceed'));
      expect(await PdfEngine.pageCount(File(result.outputs[0])), 1);
      expect(await PdfEngine.pageCount(File(result.outputs[1])), 1);
    },
  );
  test(
    'invalid signing credentials and empty cleaning actions leave no output',
    () async {
      final key = File('${temp.path}/wrong.p12')
        ..writeAsStringSync('not a certificate');
      await expectLater(
        GuiExecutor.run(
          request(
            ToolId.sign,
            options: {
              'certificatePath': key.path,
              'certificatePassword': 'wrong',
            },
          ),
        ),
        throwsA(isA<GuiInputFailure>()),
      );
      expect(Directory('${temp.path}/out').listSync(), isEmpty);
      await expectLater(
        GuiExecutor.run(
          request(
            ToolId.clean,
            options: {
              'cleanMetadata': false,
              'cleanJavascript': false,
              'cleanAttachments': false,
            },
          ),
        ),
        throwsA(isA<GuiInputFailure>()),
      );
      expect(Directory('${temp.path}/out').listSync(), isEmpty);
    },
  );
  test(
    'capabilities distinguish free bundled operations from desktop-only helpers',
    () {
      const mobile = ToolCapabilities(
        mobile: true,
        libreOffice: false,
        webp: false,
        tesseract: false,
      );
      expect(mobile.check(ToolId.ocr, ['pdf'], {}), contains('mobile'));
      expect(
        mobile.check(ToolId.convert, ['doc'], {'format': 'pdf'}),
        contains('LibreOffice'),
      );
      expect(mobile.check(ToolId.convert, ['docx'], {'format': 'pdf'}), isNull);
      expect(
        mobile.check(ToolId.convert, ['png'], {'format': 'webp'}),
        contains('WebP'),
      );
      expect(
        mobile.check(ToolId.pdfImages, ['pdf'], {'imageMode': 'extract'}),
        isNull,
      );
      expect(mobile.check(ToolId.sign, ['pdf'], {}), isNull);
      const desktop = ToolCapabilities(
        mobile: false,
        libreOffice: true,
        webp: true,
        tesseract: true,
      );
      expect(desktop.check(ToolId.ocr, ['pdf'], {}), isNull);
    },
  );
  test('validation checks the selected mode and required secondary files', () {
    expect(
      WorkspaceValidation.check(ToolId.split, {
        'splitMode': 'size',
        'maxSizeMb': '-2',
      }).keys,
      contains('maxSizeMb'),
    );
    expect(
      WorkspaceValidation.check(ToolId.sign, {}).keys,
      contains('certificatePath'),
    );
    expect(
      WorkspaceValidation.check(ToolId.flatten, {
        'flattenForms': false,
        'flattenAnnotations': false,
      }).keys,
      contains('flatten'),
    );
    expect(
      WorkspaceValidation.check(ToolId.pdfImages, {'imageMode': 'extract'}),
      isEmpty,
    );
  });
}
