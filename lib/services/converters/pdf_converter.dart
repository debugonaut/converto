import 'dart:convert';
import 'dart:io';

import '../../core/utils/file_utils.dart';
import '../../models/edit_options.dart';
import '../pdf/pdf_engine.dart';
import '../storage_service.dart';
import 'base_converter.dart';

/// PDF conversions and edits backed by the bundled, fully local engine.
///
/// No Ghostscript, poppler, LibreOffice, ImageMagick, or network calls are
/// required for any operation here.
class PdfConverter extends BaseConverter {
  @override
  String get name => 'Bundled Local PDF Engine';

  @override
  List<String> get supportedSourceFormats => ['pdf'];

  @override
  List<String> get supportedTargetFormats => [
    'png',
    'jpg',
    'jpeg',
    'txt',
    'docx',
    'xlsx',
    'pptx',
    'pdf',
  ];

  @override
  Future<File> convert({
    required File sourceFile,
    required String targetFormat,
    ImageEditOptions? imageOptions,
    PdfEditOptions? pdfOptions,
    String? outputPath,
    void Function(double progress)? onProgress,
  }) async {
    final cleanTarget = targetFormat.replaceAll('.', '').toLowerCase();

    // PDF to image: the converter interface is single-output, so this
    // renders the first page. The pdf2img command renders every page.
    if (['png', 'jpg', 'jpeg'].contains(cleanTarget)) {
      stderr.writeln(
        'Exporting the first PDF page. Use pdf2img to export every page.',
      );
      return await convertPdfToImage(
        pdfFile: sourceFile,
        targetFormat: cleanTarget,
        dpi: pdfOptions?.rasterDpi ?? 200,
        outputPath: outputPath,
        onProgress: onProgress,
      );
    }

    if (cleanTarget == 'txt') {
      return await pdfToText(
        pdfFile: sourceFile,
        outputPath: outputPath,
        onProgress: onProgress,
      );
    }

    if (['docx', 'xlsx', 'pptx'].contains(cleanTarget)) {
      return await PdfEngine.convertToOffice(
        sourceFile: sourceFile,
        format: cleanTarget,
        outputPath: outputPath,
        onProgress: onProgress,
      );
    }

    if (cleanTarget == 'pdf' && pdfOptions?.watermarkText != null) {
      return await applyWatermark(
        pdfFile: sourceFile,
        watermarkText: pdfOptions!.watermarkText!,
        opacity: pdfOptions.watermarkOpacity,
        angle: pdfOptions.watermarkAngle,
        outputPath: outputPath,
        onProgress: onProgress,
      );
    }

    if (cleanTarget != 'pdf')
      throw ArgumentError('Unsupported PDF output .$cleanTarget.');
    await PdfEngine.pageCount(sourceFile);
    final copy = await StorageService().saveFromFile(
      source: sourceFile,
      originalName: FileUtils.getBaseNameWithoutExtension(sourceFile.path),
      targetExtension: 'pdf',
      explicitDestinationPath: outputPath,
    );
    onProgress?.call(1.0);
    return copy;
  }

  /// Renders the first page to PNG or JPG. The interactive `pdf2img`
  /// command uses [PdfEngine.renderPages] directly for every page.
  Future<File> convertPdfToImage({
    required File pdfFile,
    required String targetFormat,
    int dpi = 200,
    String? outputPath,
    void Function(double progress)? onProgress,
  }) async {
    final clean = targetFormat.replaceAll('.', '').toLowerCase();
    if (!['png', 'jpg', 'jpeg'].contains(clean)) {
      throw ArgumentError(
        'PDF page export supports PNG or JPG, not .$targetFormat.',
      );
    }

    final destination = outputPath == null
        ? null
        : await StorageService().resolveOutputFile(
            originalName: FileUtils.getBaseNameWithoutExtension(pdfFile.path),
            targetExtension: clean,
            explicitDestinationPath: outputPath,
          );
    final pages = await PdfEngine.renderPages(
      sourceFile: pdfFile,
      targetFormat: clean,
      dpi: dpi,
      maxPages: 1,
      outputDirectory: destination?.parent.path,
      onProgress: onProgress,
    );
    if (pages.isEmpty) {
      throw Exception('The PDF has no pages to render.');
    }

    final first = pages.first;
    if (destination != null &&
        destination.absolute.path != first.absolute.path) {
      try {
        return await StorageService().saveFromFile(
          source: first,
          originalName: FileUtils.getBaseNameWithoutExtension(pdfFile.path),
          targetExtension: clean,
          explicitDestinationPath: destination.path,
        );
      } finally {
        if (first.existsSync()) await first.delete();
      }
    }
    return first;
  }

  Future<File> pdfToText({
    required File pdfFile,
    String? outputPath,
    void Function(double progress)? onProgress,
  }) async {
    onProgress?.call(0.2);
    final text = await PdfEngine.extractText(pdfFile);
    final originalName = FileUtils.getBaseNameWithoutExtension(pdfFile.path);
    onProgress?.call(0.8);
    final file = await StorageService().saveConvertedFile(
      originalName: originalName,
      targetExtension: 'txt',
      bytes: utf8.encode(text),
      explicitDestinationPath: outputPath,
    );
    onProgress?.call(1.0);
    return file;
  }

  /// Merges multiple PDFs into one combined PDF with the bundled engine.
  Future<File> mergePdfs({
    required List<File> pdfFiles,
    required String outputName,
    String? outputPath,
    void Function(double progress)? onProgress,
  }) {
    if (pdfFiles.isEmpty) {
      throw ArgumentError('No PDF files provided for merge.');
    }
    return PdfEngine.merge(
      files: pdfFiles,
      outputName: outputName,
      outputPath: outputPath,
      onProgress: onProgress,
    );
  }

  /// Applies a text watermark over every page of a PDF.
  Future<File> applyWatermark({
    required File pdfFile,
    required String watermarkText,
    double opacity = 0.25,
    double angle = -45.0,
    String? outputPath,
    void Function(double progress)? onProgress,
  }) {
    return PdfEngine.watermark(
      sourceFile: pdfFile,
      text: watermarkText,
      opacity: opacity,
      angle: angle,
      outputPath: outputPath,
      onProgress: onProgress,
    );
  }
}
