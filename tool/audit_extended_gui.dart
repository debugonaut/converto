// The synthetic action fixture uses low-level PDF objects only in this audit.
// ignore_for_file: implementation_imports
import 'dart:convert';
import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/src/pdf/format/dict.dart';
import 'package:pdf/src/pdf/format/string.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_manipulator/io.dart';
import 'package:pdf_manipulator/pdf_manipulator.dart' as native;
import 'package:converto/models/gui/tool_definition.dart';
import 'package:converto/services/gui/gui_executor.dart';
import 'package:converto/services/pdf/pdf_engine.dart';

const extendedTools = {
  ToolId.compare,
  ToolId.repair,
  ToolId.clean,
  ToolId.sign,
  ToolId.ocr,
  ToolId.flatten,
};

Future<List<Map<String, Object?>>> auditExtendedGui(Directory root) async {
  final scratch = Directory('${root.path}/extended')..createSync();
  final rows = <Map<String, Object?>>[];
  void check(bool condition, String message) {
    if (!condition) throw StateError(message);
  }

  Future<void> exercise(
    String name,
    Future<List<String>> Function() run,
  ) async {
    final clock = Stopwatch()..start();
    try {
      final outputs = await run();
      rows.add({
        'case': name,
        'status': 'pass',
        'ms': clock.elapsedMilliseconds,
        'outputs': outputs,
      });
      stdout.writeln('PASS $name');
    } catch (error) {
      rows.add({'case': name, 'status': 'fail', 'error': '$error'});
      stdout.writeln('FAIL $name: $error');
    }
  }

  void unavailable(String name, String reason) {
    rows.add({'case': name, 'status': 'unavailable', 'reason': reason});
    stdout.writeln('UNAVAILABLE $name: $reason');
  }

  Future<File> save(pw.Document doc, String name) async =>
      File('${scratch.path}/$name.pdf')..writeAsBytesSync(await doc.save());
  Future<GuiResult> run(
    ToolId tool,
    List<File> inputs, {
    Map<String, Object> options = const {},
    String? name,
  }) => GuiExecutor.run(
    GuiRequest(
      tool: tool,
      paths: inputs.map((file) => file.path).toList(),
      outputDirectory: '${scratch.path}/out',
      options: options,
      outputName: name ?? tool.name,
    ),
  );
  Future<List<String>> reject(
    ToolId tool,
    File input,
    String name,
    String message, {
    Map<String, Object> options = const {},
  }) async {
    final bytes = input.readAsBytesSync();
    try {
      await run(tool, [input], name: name, options: options);
    } on GuiInputFailure catch (error) {
      check(error.message.contains(message), 'Unexpected rejection: $error');
      check(
        !Directory('${scratch.path}/out').listSync().any(
          (entry) => entry.uri.pathSegments.last.startsWith(name),
        ),
        'Rejected operation left an output',
      );
      check(
        base64Encode(input.readAsBytesSync()) == base64Encode(bytes),
        'Rejected operation changed the input',
      );
      return [];
    }
    throw StateError('Unsafe PDF operation was accepted');
  }

  final base = await save(
    pw.Document(title: 'Synthetic audit title')..addPage(
      pw.Page(
        build: (_) => pw.Text(
          'OFFLINE TEST 12345',
          style: const pw.TextStyle(fontSize: 34),
        ),
      ),
    ),
    'original',
  );
  final original = base.readAsBytesSync();

  await exercise('compare detects changed content and added pages', () async {
    final revised = await save(
      pw.Document()
        ..addPage(pw.Page(build: (_) => pw.Text('Changed report text')))
        ..addPage(pw.Page(build: (_) => pw.Container(color: PdfColors.red))),
      'revised',
    );
    final result = await run(ToolId.compare, [base, revised]);
    final report = File(result.outputs.single).readAsStringSync();
    check(
      result.outputs.single.endsWith('.html') &&
          report.contains('data:image/png;base64,'),
      'Standalone HTML report missing',
    );
    check(
      report.contains('Changed') &&
          report.contains('Page 2') &&
          report.contains('Page not present'),
      'Missing text or added page evidence',
    );
    check(
      !RegExp(r'(src|href)=["\x27]https?://').hasMatch(report),
      'Report loads remote assets',
    );
    return result.outputs;
  });
  await exercise('repair reopens PDF with malformed trailer', () async {
    final broken = File('${scratch.path}/malformed.pdf');
    final text = latin1.decode(original);
    final damaged = text.replaceFirst(RegExp(r'/Size\s+\d+'), '');
    check(damaged != text, 'Fixture trailer has no Size entry');
    broken.writeAsBytesSync(latin1.encode(damaged));
    final result = await run(ToolId.repair, [broken]);
    check(
      (await PdfEngine.extractText(
        File(result.outputs.single),
      )).contains('OFFLINE TEST'),
      'Repair lost readable content',
    );
    return result.outputs;
  });
  await exercise(
    'clean removes active content and preserves unselected metadata',
    () async {
      final source = pw.Document(title: 'Metadata retained');
      source.document.catalog.params['/OpenAction'] = PdfDict.values({
        '/S': const PdfName('/JavaScript'),
        '/JS': PdfString.fromString('/* synthetic audit action */'),
      });
      source.addPage(pw.Page(build: (_) => pw.Text('Readable page')));
      final files = PdfaAttachedFiles(source.document, [
        PdfaAttachedFile(name: 'sample.txt', data: 'local fixture'),
      ]);
      source.document.pdfNames.params.merge(files.catalogNames());
      source.document.catalog.attached = null;
      final attached = await save(source, 'attached');
      final engine = native.Pdf();
      try {
        final before = await engine.open(FileSource(attached));
        try {
          check(
            (await before.attachments).length == 1,
            'Missing attachment fixture',
          );
          check(
            before.title == 'Metadata retained',
            'Missing metadata fixture',
          );
        } finally {
          await before.dispose();
        }
        check(
          latin1.decode(attached.readAsBytesSync()).contains('/JavaScript'),
          'Missing script fixture',
        );
        final result = await run(
          ToolId.clean,
          [attached],
          options: {'cleanMetadata': false},
        );
        final cleaned = File(result.outputs.single);
        final after = await engine.open(FileSource(cleaned));
        try {
          check((await after.attachments).isEmpty, 'Attachment remained');
          check(
            after.title == 'Metadata retained',
            'Unselected metadata was removed',
          );
        } finally {
          await after.dispose();
        }
        check(
          !latin1.decode(cleaned.readAsBytesSync()).contains('/JavaScript'),
          'JavaScript action remained',
        );
        check(
          (await PdfEngine.extractText(cleaned)).contains('Readable page'),
          'Cleaning lost page content',
        );
        return result.outputs;
      } finally {
        await engine.dispose();
      }
    },
  );
  await exercise('clean refuses to leave an associated file behind', () async {
    final doc = pw.Document()
      ..addPage(pw.Page(build: (_) => pw.Text('Associated file fixture')));
    PdfaAttachedFiles(doc.document, [
      PdfaAttachedFile(name: 'associated.txt', data: 'local fixture'),
    ]);
    return reject(
      ToolId.clean,
      await save(doc, 'associated'),
      'associated-rejected',
      'attachments that cannot be safely removed',
    );
  });
  await exercise('clean refuses to leave page JavaScript behind', () async {
    final doc = pw.Document()
      ..addPage(pw.Page(build: (_) => pw.Text('Page action fixture')));
    doc.document.pdfPageList.pages.single.params['/AA'] = PdfDict.values({
      '/O': PdfDict.values({
        '/S': const PdfName('/JavaScript'),
        '/JS': PdfString.fromString('/* synthetic page action */'),
      }),
    });
    return reject(
      ToolId.clean,
      await save(doc, 'page-script'),
      'script-rejected',
      'JavaScript that cannot be safely removed',
    );
  });
  await exercise(
    'flatten keeps visible form value and removes field interactivity',
    () async {
      final form = await save(
        pw.Document()..addPage(
          pw.Page(
            build: (_) => pw.TextField(
              name: 'Sample field',
              value: 'Visible form value',
              width: 220,
              height: 40,
            ),
          ),
        ),
        'form',
      );
      final result = await run(ToolId.flatten, [form]);
      final output = File(result.outputs.single), engine = native.Pdf();
      try {
        final doc = await engine.open(FileSource(output));
        try {
          check((await doc.formFields).isEmpty, 'Interactive fields remain');
        } finally {
          await doc.dispose();
        }
      } finally {
        await engine.dispose();
      }
      check(
        (await PdfEngine.extractText(output)).contains('Visible form value'),
        'Flatten lost visible value',
      );
      return result.outputs;
    },
  );
  await exercise('annotations-only flatten protects editable widgets', () {
    return reject(
      ToolId.flatten,
      File('${scratch.path}/form.pdf'),
      'widget-rejected',
      'Choose form flattening too',
      options: {'flattenForms': false},
    );
  });
  await exercise('flatten refuses an annotation with no appearance', () async {
    final doc = pw.Document()
      ..addPage(
        pw.Page(
          build: (_) => pw.Annotation(
            builder: pw.AnnotationSquare(color: PdfColors.blue),
            child: pw.SizedBox(width: 100, height: 100),
          ),
        ),
      );
    return reject(
      ToolId.flatten,
      await save(doc, 'square'),
      'square-rejected',
      'annotation without a supported appearance',
    );
  });
  await exercise(
    'flatten paints a supported annotation into page content',
    () async {
      final watermarked = await PdfEngine.watermark(
        sourceFile: base,
        outputPath: '${scratch.path}/stamp.pdf',
        text: 'Flattened stamp',
        angle: 0,
        opacity: 1,
      );
      final result = await run(
        ToolId.flatten,
        [watermarked],
        options: {'flattenForms': false},
        name: 'annotation-painted',
      );
      final output = File(result.outputs.single);
      check(
        (await PdfEngine.extractText(output)).contains('Flattened stamp'),
        'Flatten lost the annotation appearance',
      );
      return result.outputs;
    },
  );
  try {
    await Process.run('openssl', ['version']);
    await exercise(
      'sign with synthetic PKCS12 and report unverified trust',
      () async {
        final pem = '${scratch.path}/synthetic-cert.pem';
        final key = '${scratch.path}/synthetic-key.pem';
        final p12 = '${scratch.path}/synthetic.p12';
        const password = 'synthetic-audit-only';
        try {
          final req = await Process.run('openssl', [
            'req',
            '-x509',
            '-newkey',
            'rsa:2048',
            '-nodes',
            '-keyout',
            key,
            '-out',
            pem,
            '-days',
            '2',
            '-subj',
            '/CN=Converto Synthetic Test',
          ]);
          check(req.exitCode == 0, 'Synthetic certificate generation failed');
          final pack = await Process.run('openssl', [
            'pkcs12',
            '-export',
            '-inkey',
            key,
            '-in',
            pem,
            '-out',
            p12,
            '-passout',
            'pass:$password',
          ]);
          check(pack.exitCode == 0, 'Synthetic certificate packaging failed');
          final result = await run(
            ToolId.sign,
            [base],
            options: {'certificatePath': p12, 'certificatePassword': password},
          );
          final info = await PdfEngine.info(File(result.outputs.single));
          check(
            info.signatureSummaries.isNotEmpty &&
                info.signatureSummaries.every((s) => s.contains('unverified')),
            'Missing signature or incorrect trust label',
          );
          return result.outputs;
        } finally {
          for (final path in [key, pem, p12]) {
            final file = File(path);
            if (file.existsSync()) file.deleteSync();
          }
        }
      },
    );
  } on ProcessException {
    unavailable(
      'sign',
      'OpenSSL is needed to generate a synthetic test certificate.',
    );
  }
  if (await PdfEngine.tesseractVersion() == null) {
    unavailable('ocr', 'Local Tesseract is unavailable.');
  } else {
    await exercise(
      'OCR converts an image-only scan into searchable PDF',
      () async {
        final scanned = await run(
          ToolId.scanPdf,
          [base],
          options: {'dpi': '150', 'scanMode': 'grayscale'},
        );
        final scan = File(scanned.outputs.single);
        check(
          (await PdfEngine.extractText(scan)).trim().isEmpty,
          'Fixture already contains searchable text',
        );
        final result = await run(
          ToolId.ocr,
          [scan],
          options: {'format': 'pdf', 'language': 'eng', 'dpi': '200'},
        );
        check(
          (await PdfEngine.extractText(
            File(result.outputs.single),
          )).contains('OFFLINE TEST 12345'),
          'Recognized text layer is missing or incorrect',
        );
        return result.outputs;
      },
    );
  }
  await exercise(
    'embedded image extraction and image layout HTML preserve output formats',
    () async {
      final jpeg = img.encodeJpg(img.Image(width: 32, height: 20));
      final input = await save(
        pw.Document()
          ..addPage(pw.Page(build: (_) => pw.Image(pw.MemoryImage(jpeg)))),
        'embedded',
      );
      final extracted = await run(
        ToolId.pdfImages,
        [input],
        options: {'imageMode': 'extract'},
      );
      check(
        extracted.outputs.single.endsWith('.jpg') &&
            img
                    .decodeJpg(File(extracted.outputs.single).readAsBytesSync())
                    ?.width ==
                32,
        'Embedded JPEG was not preserved',
      );
      final html = await run(
        ToolId.convert,
        [base],
        options: {'format': 'html', 'htmlLayout': true},
      );
      check(
        html.outputs.single.endsWith('.html') &&
            File(
              html.outputs.single,
            ).readAsStringSync().contains('data:image/png;base64,'),
        'Standalone image layout HTML is invalid',
      );
      return [...extracted.outputs, ...html.outputs];
    },
  );
  check(
    base.readAsBytesSync().length == original.length &&
        base64Encode(base.readAsBytesSync()) == base64Encode(original),
    'Extended workflows changed the original',
  );
  return rows;
}
