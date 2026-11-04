import 'dart:convert';
import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pdf/widgets.dart' as pw;
import 'package:converto/models/gui/tool_definition.dart';
import 'package:converto/services/gui/gui_executor.dart';
import 'package:converto/services/pdf/pdf_engine.dart';
import 'audit_extended_gui.dart';

/// Real engine acceptance suite for the exact executor used by GUI isolates.
/// No Flutter UI/native display is required. Keeps machine-readable analytics.
Future<void> main() async {
  final root = Directory('build/audit/gui').absolute;
  if (root.existsSync()) root.deleteSync(recursive: true);
  root.createSync(recursive: true);
  final fixtures = Directory(p.join(root.path, 'inputs'))..createSync();
  final pdf = pw.Document();
  for (var i = 1; i <= 3; i++) {
    pdf.addPage(pw.Page(build: (_) => pw.Text('Page $i SECRET sample')));
  }
  final source = File(p.join(fixtures.path, 'sample 日本語 spaces.pdf'))
    ..writeAsBytesSync(await pdf.save());
  final image = File(p.join(fixtures.path, 'image.png'))
    ..writeAsBytesSync(img.encodePng(img.Image(width: 60, height: 40)));
  final original = source.readAsBytesSync();
  final rows = <Map<String, Object?>>[];
  void check(bool condition, String message) {
    if (!condition) throw StateError(message);
  }

  Future<GuiResult?> exercise(
    String name,
    Future<GuiResult> Function() action, {
    Future<void> Function(GuiResult)? verify,
    bool expectedFailure = false,
  }) async {
    final clock = Stopwatch()..start();
    try {
      final result = await action();
      if (expectedFailure) throw StateError('Expected failure did not occur');
      for (final output in result.outputs) {
        check(File(output).lengthSync() > 0, 'Empty output');
      }
      await verify?.call(result);
      rows.add({
        'case': name,
        'status': 'pass',
        'ms': clock.elapsedMicroseconds / 1000,
        'outputs': result.outputs,
        'bytes': result.outputs.fold<int>(
          0,
          (sum, file) => sum + File(file).lengthSync(),
        ),
      });
      stdout.writeln('PASS $name');
      return result;
    } catch (error) {
      final pass = expectedFailure && error is! StateError;
      rows.add({
        'case': name,
        'status': pass ? 'pass' : 'fail',
        'ms': clock.elapsedMicroseconds / 1000,
        'error': '$error',
      });
      stdout.writeln(
        '${pass ? 'PASS' : 'FAIL'} $name${pass ? '' : ': $error'}',
      );
      return null;
    }
  }

  Future<GuiResult> run(
    ToolId id, {
    List<String>? paths,
    Map<String, Object> options = const {},
    String? output,
    bool Function()? cancelled,
    void Function(double, String)? progress,
  }) => GuiExecutor.run(
    GuiRequest(
      tool: id,
      paths: paths ?? [source.path],
      options: options,
      outputName: id == ToolId.info ? null : 'Reviewed ${id.name}',
      outputDirectory: output ?? p.join(root.path, id.name),
    ),
    isCancelled: cancelled,
    onProgress: progress,
  );
  String? protected;
  try {
    for (final id in ToolId.values.where((id) => !extendedTools.contains(id))) {
      final options = <String, Object>{};
      List<String>? paths;
      switch (id) {
        case ToolId.scanPdf:
          paths = [source.path, image.path];
          options.addAll({
            'scanMode': 'blackAndWhite',
            'contrast': 1.5,
            'dpi': '72',
          });
        case ToolId.convert:
          paths = [image.path];
          options['format'] = 'pdf';
        case ToolId.merge:
          paths = [source.path, image.path];
        case ToolId.split:
          options['every'] = '1';
        case ToolId.organize:
          options['pages'] = '3,1,2,2';
        case ToolId.editImage:
          paths = [image.path];
          options.addAll({
            'format': 'png',
            'degrees': '90',
            'width': '20',
            'flipHorizontal': true,
          });
        case ToolId.watermark:
          options['text'] = 'DRAFT';
        case ToolId.protect:
          options['password'] = 'test-password';
        case ToolId.redact:
          options['text'] = 'SECRET';
        case ToolId.pdfImages:
          options.addAll({'format': 'jpg', 'dpi': '40'});
        case ToolId.pdfOffice:
          options['format'] = 'docx';
        case ToolId.extract:
          options['pages'] = '1,3';
        case ToolId.crop:
          options['left'] = '10';
        case ToolId.unlock:
          paths = [protected ?? 'missing.pdf'];
          options['password'] = 'test-password';
        default:
          break;
      }
      final result = await exercise(
        id.name,
        () => run(id, paths: paths, options: options),
        verify: (result) async {
          check(
            result.outputs.every(
              (output) => p.basename(output).startsWith('Reviewed ${id.name}'),
            ),
            'Chosen output name was not applied',
          );
          switch (id) {
            case ToolId.scanPdf:
              check(result.outputs.length == 1, 'Scan must publish one PDF');
              check(
                await PdfEngine.pageCount(File(result.outputs.single)) == 4,
                'Scan page count',
              );
              check(
                (await PdfEngine.extractText(
                  File(result.outputs.single),
                )).trim().isEmpty,
                'Scan must contain image-only pages',
              );
            case ToolId.watermark:
              Future<String> pixels(File file, String directory) async {
                final pages = await PdfEngine.renderPages(
                  sourceFile: file,
                  dpi: 24,
                  maxPages: 1,
                  outputDirectory: p.join(root.path, directory),
                );
                final image = img.decodePng(await pages.single.readAsBytes());
                check(image != null, 'Watermark render failed');
                return base64Encode(image!.getBytes());
              }
              check(
                await pixels(source, 'watermark-before') !=
                    await pixels(
                      File(result.outputs.single),
                      'watermark-after',
                    ),
                'Watermark must change rendered page pixels',
              );
              check(
                (await PdfEngine.extractText(
                  File(result.outputs.single),
                )).contains('Page 1'),
                'Watermark must preserve original text',
              );
            case ToolId.merge:
              check(
                await PdfEngine.pageCount(File(result.outputs.single)) == 4,
                'Merge page order/count',
              );
            case ToolId.split:
              check(result.outputs.length == 3, 'Split output count');
            case ToolId.organize:
              check(
                await PdfEngine.pageCount(File(result.outputs.single)) == 4,
                'Organize page count',
              );
              check(
                (await PdfEngine.extractText(
                  File(result.outputs.single),
                )).contains('Page 3'),
                'Organize output must remain fully readable',
              );
            case ToolId.extract:
              check(
                await PdfEngine.pageCount(File(result.outputs.single)) == 2,
                'Extract page count',
              );
            case ToolId.pdfImages:
              check(result.outputs.length == 3, 'Must export every page');
            case ToolId.pdfText:
              check(
                File(
                  result.outputs.single,
                ).readAsStringSync().contains('SECRET'),
                'Text extraction',
              );
            case ToolId.editImage:
              check(
                img
                        .decodeImage(
                          File(result.outputs.single).readAsBytesSync(),
                        )!
                        .width ==
                    20,
                'Image resize',
              );
            case ToolId.redact:
              check(
                !(await PdfEngine.extractText(
                  File(result.outputs.single),
                )).contains('SECRET'),
                'Redaction retained text',
              );
            case ToolId.unlock:
              check(
                !(await PdfEngine.info(
                  File(result.outputs.single),
                )).isEncrypted,
                'Unlock retained encryption',
              );
            case ToolId.compress:
              check(
                File(result.outputs.single).lengthSync() <= source.lengthSync(),
                'Compression grew output',
              );
            case ToolId.info:
              check(
                result.outputs.isEmpty &&
                    result.details.single.contains('3 pages'),
                'Info output',
              );
            default:
              break;
          }
        },
      );
      if (id == ToolId.protect) protected = result?.outputs.single;
    }
    await exercise(
      'PDF conversion exports ALL pages',
      () => run(ToolId.convert, options: {'format': 'png'}),
      verify: (result) async =>
          check(result.outputs.length == 3, 'Dropped pages'),
    );
    await exercise(
      'split explicit ranges',
      () => run(ToolId.split, options: {'pages': '1-2,3'}),
      verify: (result) async =>
          check(result.outputs.length == 2, 'Wrong range split'),
    );
    await exercise(
      'PDF to XLSX',
      () => run(ToolId.pdfOffice, options: {'format': 'xlsx'}),
    );
    await exercise(
      'PDF to PPTX',
      () => run(ToolId.pdfOffice, options: {'format': 'pptx'}),
    );
    await exercise(
      'collision retains existing output',
      () => run(ToolId.merge, paths: [source.path, image.path]),
      verify: (result) async {
        check(
          p.basename(result.outputs.single) != 'merged.pdf',
          'Overwrote existing merged.pdf',
        );
      },
    );
    final cancelledOutput = p.join(root.path, 'cancelled');
    await exercise(
      'cancel before start',
      () => run(
        ToolId.convert,
        output: cancelledOutput,
        options: {'format': 'pdf'},
        cancelled: () => true,
      ),
      expectedFailure: true,
    );
    var cancel = false;
    await exercise(
      'cancel after engine progress',
      () => run(
        ToolId.pdfImages,
        output: cancelledOutput,
        options: {'dpi': '40'},
        cancelled: () => cancel,
        progress: (_, __) => cancel = true,
      ),
      expectedFailure: true,
    );
    rows.addAll(await auditExtendedGui(root));
    check(
      Directory(cancelledOutput).listSync().isEmpty,
      'Cancellation leaked output',
    );
    final corrupt = File(p.join(fixtures.path, 'corrupt.pdf'))
      ..writeAsStringSync('broken');
    final failedOutput = p.join(root.path, 'failed');
    await exercise(
      'batch rollback after first success',
      () => run(
        ToolId.pdfText,
        paths: [source.path, corrupt.path],
        output: failedOutput,
      ),
      expectedFailure: true,
    );
    check(
      Directory(failedOutput).listSync().isEmpty,
      'Failed batch leaked output',
    );
    await exercise(
      'bad page range',
      () => run(ToolId.extract, options: {'pages': '999'}),
      expectedFailure: true,
    );
    await exercise(
      'wrong password',
      () => run(
        ToolId.unlock,
        paths: [protected!],
        options: {'password': 'wrong'},
      ),
      expectedFailure: true,
    );
    await exercise(
      'empty password',
      () => run(ToolId.protect),
      expectedFailure: true,
    );
    await exercise(
      'invalid image crop',
      () => run(ToolId.editImage, paths: [image.path], options: {'cropX': '0'}),
      expectedFailure: true,
    );
    await exercise(
      'invalid dimensions',
      () =>
          run(ToolId.editImage, paths: [image.path], options: {'width': '-5'}),
      expectedFailure: true,
    );
    check(
      base64Encode(source.readAsBytesSync()) == base64Encode(original),
      'Original source changed',
    );
    check(
      !root
          .listSync(recursive: true)
          .any((entry) => p.basename(entry.path).startsWith('.converto-')),
      'Staging leak',
    );
  } finally {
    await PdfEngine.dispose();
    File(
      p.join(root.path, 'results.json'),
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(rows));
  }
  final failures = rows.where((row) => row['status'] == 'fail').length;
  final unavailable = rows
      .where((row) => row['status'] == 'unavailable')
      .length;
  stdout.writeln(
    '${rows.length - failures - unavailable}/${rows.length - unavailable} GUI executor checks passed. $unavailable unavailable.',
  );
  if (failures > 0) exitCode = 1;
}
