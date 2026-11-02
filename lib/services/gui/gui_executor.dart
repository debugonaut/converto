import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../../core/utils/file_utils.dart';
import '../../models/edit_options.dart';
import '../../models/scan_options.dart';
import '../../models/gui/tool_definition.dart';
import '../file_operations.dart';
import '../pdf/pdf_engine.dart';
import '../scanned_pdf_service.dart';
import 'output_names.dart';
import 'pdf_page_actions.dart';

class GuiRequest {
  final ToolId tool;
  final List<String> paths;
  final String outputDirectory;
  final Map<String, Object> options;
  final String? outputName;
  final Map<String, String> outputNames;
  const GuiRequest({
    required this.tool,
    required this.paths,
    required this.outputDirectory,
    this.options = const {},
    this.outputName,
    this.outputNames = const {},
  });

  bool get combinesImagesToPdf {
    final definition = ToolDefinition.byId(tool);
    final extensions = paths.map(FileUtils.getExtension);
    final target =
        options['format'] as String? ??
        definition.targets(extensions).firstOrNull ??
        '';
    return options['pdfOutput'] != 'separate' &&
        definition.canCombineImagesToPdf(extensions, target);
  }

  bool get hasCombinedOutput =>
      tool == ToolId.merge ||
      (tool == ToolId.scanPdf && paths.length > 1) ||
      combinesImagesToPdf;
}

class GuiResult {
  final List<String> outputs;
  final List<String> details;
  final Map<String, String> sourcePaths;
  final GuiMetrics metrics;
  const GuiResult(
    this.outputs,
    this.details, [
    this.sourcePaths = const {},
    this.metrics = const GuiMetrics(),
  ]);
}

class GuiMetrics {
  final int inputBytes;
  final int outputBytes;
  final int elapsedMs;
  const GuiMetrics({
    this.inputBytes = 0,
    this.outputBytes = 0,
    this.elapsedMs = 0,
  });
  Map<String, int> toMap() => {
    'inputBytes': inputBytes,
    'outputBytes': outputBytes,
    'elapsedMs': elapsedMs,
  };
  factory GuiMetrics.fromMap(Map data) => GuiMetrics(
    inputBytes: data['inputBytes'] as int? ?? 0,
    outputBytes: data['outputBytes'] as int? ?? 0,
    elapsedMs: data['elapsedMs'] as int? ?? 0,
  );
}

class GuiInputFailure implements Exception {
  final String sourcePath;
  final String message;
  const GuiInputFailure(this.sourcePath, this.message);
  @override
  String toString() => '${p.basename(sourcePath)}: $message';
}

class GuiCancelled implements Exception {
  const GuiCancelled();
}

/// The GUI and its worker use the CLI engines, with one private transaction
/// per explicit run. All outputs stay private until the entire batch succeeds.
class GuiExecutor {
  static Future<GuiResult> run(
    GuiRequest request, {
    void Function(double, String)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final clock = Stopwatch()..start();
    final tool = ToolDefinition.byId(request.tool);
    final combineImages = request.combinesImagesToPdf;
    final combinedOutput = request.hasCombinedOutput;
    final combinePages =
        combineImages ||
        (request.tool == ToolId.scanPdf && request.paths.length > 1);
    final extension = switch (request.tool) {
      ToolId.pdfText => 'txt',
      ToolId.convert ||
      ToolId.editImage ||
      ToolId.pdfImages ||
      ToolId.pdfOffice =>
        request.options['format'] as String? ??
            tool.targets(request.paths.map(FileUtils.getExtension)).firstOrNull,
      _ => 'pdf',
    };
    if (request.outputName != null)
      OutputNames.base(request.outputName!, extension: extension);
    for (final name in request.outputNames.values) {
      OutputNames.base(name, extension: extension);
    }
    var inputBytes = 0;
    if (request.paths.isEmpty) throw ArgumentError('Choose at least one file.');
    if (request.tool == ToolId.merge && request.paths.length < 2) {
      throw ArgumentError('Choose at least two PDFs or images to merge.');
    }
    for (final path in request.paths) {
      if (await FileSystemEntity.type(path, followLinks: false) !=
              FileSystemEntityType.file ||
          !tool.accepts(FileUtils.getExtension(path))) {
        throw ArgumentError('${tool.title} cannot use ${p.basename(path)}.');
      }
      inputBytes += await File(path).length();
    }
    Future<void> checkpoint() async {
      // Let queued cancellation messages run even after synchronous codecs.
      await Future<void>.delayed(Duration.zero);
      if (isCancelled?.call() ?? false) throw const GuiCancelled();
    }

    final output = Directory(request.outputDirectory);
    await output.create(recursive: true);
    final staging = await output.createTemp('.converto-gui-');
    final generated = <File>[];
    final generatedSources = <String, String>{};
    final published = <File>[];
    final publishedSources = <String, String>{};
    final details = <String>[];
    final o = request.options;
    String text(String name, [String fallback = '']) =>
        (o[name] as String?) ?? fallback;
    int integer(String name, int fallback, {int? min, int? max}) {
      final raw = o[name];
      final value = raw == null || raw == '' ? fallback : int.tryParse('$raw');
      if (value == null ||
          (min != null && value < min) ||
          (max != null && value > max)) {
        throw ArgumentError(
          'Enter a valid $name${min == null ? '' : ' (at least $min)'}.',
        );
      }
      return value;
    }

    double decimal(String name, double fallback) {
      final raw = o[name];
      final value = raw == null || raw == ''
          ? fallback
          : double.tryParse('$raw');
      if (value == null || !value.isFinite)
        throw ArgumentError('Enter a valid $name.');
      return value;
    }

    try {
      await checkpoint();
      if (request.tool == ToolId.merge) {
        generated.add(
          await FileOperations.merge(
            files: request.paths.map(File.new).toList(),
            outputPath: p.join(staging.path, 'merged.pdf'),
            onProgress: (v) => onProgress?.call(v * .95, 'Merging files'),
          ),
        );
      } else {
        for (var index = 0; index < request.paths.length; index++) {
          await checkpoint();
          final source = File(request.paths[index]);
          final folder = await Directory(
            p.join(staging.path, '$index'),
          ).create();
          final base = FileUtils.getBaseNameWithoutExtension(source.path);
          String target = text(
            'format',
            tool.targets([FileUtils.getExtension(source.path)]).first,
          );
          String destination([String? ext]) => p.join(
            folder.path,
            '${base}_${request.tool.name}.${ext ?? 'pdf'}',
          );
          void progress(double v) => onProgress?.call(
            combinePages
                ? (index + v.clamp(0, 1)) / request.paths.length * .9
                : (index + v.clamp(0, 1) * .95) / request.paths.length,
            '${index + 1} of ${request.paths.length} · ${p.basename(source.path)}',
          );
          progress(0);
          final firstNewOutput = generated.length;
          try {
            switch (request.tool) {
              case ToolId.scanPdf:
                generated.add(
                  await ScannedPdfService.create(
                    source: source,
                    outputPath: destination(),
                    options: ScanOptions.fromMap(o),
                    checkpoint: checkpoint,
                    onProgress: progress,
                  ),
                );
              case ToolId.convert:
              case ToolId.editImage:
              case ToolId.pdfText:
              case ToolId.pdfOffice:
                if (request.tool == ToolId.pdfText) target = 'txt';
                ImageEditOptions? edit;
                if (request.tool == ToolId.editImage) {
                  final cropFields = [
                    'cropX',
                    'cropY',
                    'cropWidth',
                    'cropHeight',
                  ];
                  final cropSet = cropFields
                      .where((key) => text(key).isNotEmpty)
                      .length;
                  if (cropSet != 0 && cropSet != 4)
                    throw ArgumentError(
                      'Fill all four image crop values, or leave them blank.',
                    );
                  edit = ImageEditOptions(
                    rotationDegrees: integer('degrees', 0),
                    flipHorizontal: o['flipHorizontal'] == true,
                    flipVertical: o['flipVertical'] == true,
                    compressionQuality: integer(
                      'quality',
                      85,
                      min: 1,
                      max: 100,
                    ),
                    targetWidth: text('width').isEmpty
                        ? null
                        : integer('width', 1, min: 1),
                    targetHeight: text('height').isEmpty
                        ? null
                        : integer('height', 1, min: 1),
                    cropX: cropSet == 0 ? null : integer('cropX', 0, min: 0),
                    cropY: cropSet == 0 ? null : integer('cropY', 0, min: 0),
                    cropWidth: cropSet == 0
                        ? null
                        : integer('cropWidth', 1, min: 1),
                    cropHeight: cropSet == 0
                        ? null
                        : integer('cropHeight', 1, min: 1),
                  );
                }
                // In the GUI, PDF image conversion always exports every page.
                if (FileUtils.getExtension(source.path) == 'pdf' &&
                    ['png', 'jpg', 'jpeg'].contains(target)) {
                  generated.addAll(
                    await PdfEngine.renderPages(
                      sourceFile: source,
                      targetFormat: target,
                      outputDirectory: folder.path,
                      onProgress: progress,
                    ),
                  );
                } else {
                  generated.add(
                    await FileOperations.convert(
                      sourceFile: source,
                      targetFormat: target,
                      outputPath: destination(target),
                      imageOptions: edit,
                      quality: integer('quality', 85, min: 1, max: 100),
                      recordHistory: false,
                      onProgress: progress,
                    ),
                  );
                }
              case ToolId.pdfImages:
                generated.addAll(
                  await PdfEngine.renderPages(
                    sourceFile: source,
                    targetFormat: target,
                    dpi: integer('dpi', 150, min: 1),
                    outputDirectory: folder.path,
                    onProgress: progress,
                  ),
                );
              case ToolId.split:
                if (text('pages').trim().isNotEmpty) {
                  generated.addAll(
                    await PdfEngine.splitExpression(
                      sourceFile: source,
                      expression: text('pages'),
                      outputDirectory: folder.path,
                      onProgress: progress,
                    ),
                  );
                } else {
                  generated.addAll(
                    await PdfEngine.splitEvery(
                      sourceFile: source,
                      every: integer('every', 1, min: 1),
                      outputDirectory: folder.path,
                      onProgress: progress,
                    ),
                  );
                }
              case ToolId.extract:
                generated.add(
                  await PdfEngine.extractPages(
                    sourceFile: source,
                    expression: text('pages'),
                    outputPath: destination(),
                  ),
                );
              case ToolId.organize:
                generated.add(
                  await PdfPageActions.organize(
                    source: source,
                    order: text('pages'),
                    outputPath: destination(),
                    rotations: List<int>.from(
                      o['pageRotations'] as List? ?? const [],
                    ),
                    onProgress: progress,
                  ),
                );
              case ToolId.rotate:
                generated.add(
                  await PdfEngine.rotate(
                    sourceFile: source,
                    degrees: integer('degrees', 90),
                    outputPath: destination(),
                    onProgress: progress,
                  ),
                );
              case ToolId.watermark:
                if (text('text').trim().isEmpty)
                  throw ArgumentError('Enter watermark text.');
                generated.add(
                  await PdfEngine.watermark(
                    sourceFile: source,
                    text: text('text'),
                    opacity: decimal('opacity', .25),
                    angle: decimal('angle', 45),
                    fontSize: decimal('fontSize', 54),
                    outputPath: destination(),
                    onProgress: progress,
                  ),
                );
              case ToolId.pageNumbers:
                generated.add(
                  await PdfEngine.pageNumbers(
                    sourceFile: source,
                    outputPath: destination(),
                    onProgress: progress,
                  ),
                );
              case ToolId.crop:
                generated.add(
                  await PdfEngine.crop(
                    sourceFile: source,
                    left: decimal('left', 0),
                    top: decimal('top', 0),
                    right: decimal('right', 0),
                    bottom: decimal('bottom', 0),
                    outputPath: destination(),
                    onProgress: progress,
                  ),
                );
              case ToolId.compress:
                generated.add(
                  await PdfEngine.compress(
                    sourceFile: source,
                    level: text('level', 'ebook'),
                    outputPath: destination(),
                    onProgress: progress,
                  ),
                );
              case ToolId.protect:
                if (text('password').isEmpty)
                  throw ArgumentError('Enter a password.');
                generated.add(
                  await PdfEngine.protect(
                    sourceFile: source,
                    password: text('password'),
                    outputPath: destination(),
                  ),
                );
              case ToolId.unlock:
                if (text('password').isEmpty)
                  throw ArgumentError('Enter the PDF password.');
                generated.add(
                  await PdfEngine.unlock(
                    sourceFile: source,
                    password: text('password'),
                    outputPath: destination(),
                  ),
                );
              case ToolId.pdfa:
                generated.add(
                  await PdfEngine.convertToPdfA(
                    sourceFile: source,
                    level: integer('pdfaLevel', 2, min: 1, max: 3),
                    outputPath: destination(),
                    onProgress: progress,
                  ),
                );
                details.add(
                  'PDF/A-${integer('pdfaLevel', 2)} export created. Independent conformance validation is not bundled.',
                );
              case ToolId.redact:
                final result = await PdfEngine.redactText(
                  sourceFile: source,
                  query: text('text'),
                  outputPath: destination(),
                  onProgress: progress,
                );
                generated.add(result.file);
                details.add(
                  '${p.basename(source.path)}: ${result.matches} matches redacted. Review the output before sharing.',
                );
              case ToolId.info:
                final info = await PdfEngine.info(
                  source,
                  password: text('password').isEmpty ? null : text('password'),
                );
                details.add(
                  '${p.basename(source.path)}\n${info.pageCount} pages · PDF ${info.version}\n'
                  'Title: ${info.title ?? '—'}\nAuthor: ${info.author ?? '—'}\n'
                  'Encrypted: ${info.isEncrypted ? 'Yes' : 'No'} · Tagged: ${info.isTagged ? 'Yes' : 'No'}\n'
                  'First page: ${info.firstPageWidth.toStringAsFixed(1)} × ${info.firstPageHeight.toStringAsFixed(1)} pt',
                );
              case ToolId.merge:
                throw StateError('Merge is executed as one ordered batch.');
            }
          } on GuiCancelled {
            rethrow;
          } catch (error) {
            throw GuiInputFailure(source.path, PdfEngine.errorMessage(error));
          }
          for (final file in generated.skip(firstNewOutput)) {
            generatedSources[file.path] = source.path;
          }
          await checkpoint();
        }
        if (combinePages) {
          final message = combineImages
              ? 'Combining images'
              : 'Combining scanned pages';
          onProgress?.call(.9, message);
          await checkpoint();
          final combined = await PdfEngine.merge(
            files: generated,
            outputPath: p.join(
              staging.path,
              request.tool == ToolId.scanPdf ? 'scanned.pdf' : 'combined.pdf',
            ),
            onProgress: (v) => onProgress?.call(.9 + v * .05, message),
          );
          generated
            ..clear()
            ..add(combined);
          generatedSources.clear();
        }
      }
      await checkpoint();
      // No await between the final cancellation check and publication: the
      // entire rename transaction is one event-loop turn, not a partial batch.
      final counts = <String, int>{};
      for (final file in generated) {
        final source = generatedSources[file.path] ?? request.paths.first;
        counts[source] = (counts[source] ?? 0) + 1;
      }
      final counters = <String, int>{};
      var globalIndex = 0;
      var outputBytes = 0;
      for (final file in generated) {
        final source = generatedSources[file.path] ?? request.paths.first;
        final override = request.outputNames[source];
        final name = combinedOutput
            ? request.outputName
            : override ?? request.outputName;
        var filename = p.basename(file.path);
        if (name != null) {
          final globalBatch =
              override == null &&
              request.outputNames.isEmpty &&
              request.paths.length > 1 &&
              !combinedOutput;
          final count = globalBatch ? generated.length : counts[source]!;
          final number = globalBatch
              ? ++globalIndex
              : counters.update(source, (n) => n + 1, ifAbsent: () => 1);
          filename = OutputNames.filename(
            name,
            FileUtils.getExtension(file.path),
            index: count > 1 ? number : null,
            total: count,
          );
        }
        final destination = FileUtils.getUniqueFilePath(output.path, filename);
        outputBytes += file.lengthSync();
        publishedSources[destination] = source;
        published.add(file.renameSync(destination));
      }
      onProgress?.call(1, 'Complete');
      return GuiResult(
        published.map((file) => file.path).toList(),
        details,
        publishedSources,
        GuiMetrics(
          inputBytes: inputBytes,
          outputBytes: outputBytes,
          elapsedMs: clock.elapsedMilliseconds,
        ),
      );
    } catch (_) {
      for (final file in published) {
        if (file.existsSync()) file.deleteSync();
      }
      rethrow;
    } finally {
      if (staging.existsSync()) await staging.delete(recursive: true);
    }
  }
}
