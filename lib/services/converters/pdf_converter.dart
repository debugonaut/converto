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
    'webp',
    'txt',
    'md',
    'html',
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
    if (['png', 'jpg', 'jpeg', 'webp'].contains(cleanTarget)) {
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

    if (['txt', 'md', 'html'].contains(cleanTarget)) {
      return await pdfToText(
        pdfFile: sourceFile,
        targetFormat: cleanTarget,
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
    if (!['png', 'jpg', 'jpeg', 'webp'].contains(clean)) {
      throw ArgumentError(
        'PDF page export supports PNG, JPG, or WebP, not .$targetFormat.',
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
    String targetFormat = 'txt',
    String? password,
    String? outputPath,
    void Function(double progress)? onProgress,
  }) async {
    final format = targetFormat.replaceAll('.', '').toLowerCase();
    if (!['txt', 'md', 'markdown', 'html', 'htm'].contains(format)) {
      throw ArgumentError('PDF text export supports txt, md, or html.');
    }
    final extension = switch (format) {
      'md' || 'markdown' => 'md',
      'html' || 'htm' => 'html',
      _ => 'txt',
    };

    onProgress?.call(0.2);
    final extracted = await PdfEngine.extractAs(
      pdfFile,
      extension,
      password: password,
    );
    final text = extension == 'html'
        ? '<!DOCTYPE html>\n<html lang="en">\n<head>\n'
              '<meta charset="utf-8">\n'
              '<meta name="viewport" content="width=device-width, initial-scale=1">\n'
              '<title>${_escapeHtml(FileUtils.getBaseNameWithoutExtension(pdfFile.path))}</title>\n'
              '<style>body{font-family:system-ui,-apple-system,"Segoe UI",sans-serif;'
              'line-height:1.6;max-width:52rem;margin:2rem auto;padding:0 1rem;'
              'color:#18181b}img{max-width:100%;height:auto}'
              'table{border-collapse:collapse;width:100%}'
              'td,th{border:1px solid #d4d4d8;padding:.35rem .5rem}</style>\n'
              '</head>\n<body>\n$extracted\n</body>\n</html>\n'
        : extracted;
    final originalName = FileUtils.getBaseNameWithoutExtension(pdfFile.path);
    onProgress?.call(0.8);
    final file = await StorageService().saveConvertedFile(
      originalName: originalName,
      targetExtension: extension,
      bytes: utf8.encode(text),
      explicitDestinationPath: outputPath,
    );
    onProgress?.call(1.0);
    return file;
  }

  /// Writes every page as an embedded PNG inside one standalone HTML file.
  ///
  /// This is the exact-layout option for complex tables and multi-column
  /// pages; the page has no selectable text layer, but it preserves what the
  /// PDF actually looks like and works entirely offline.
  Future<File> pdfToHtmlVisual({
    required File pdfFile,
    String? password,
    int dpi = 150,
    String? outputPath,
    void Function(double progress)? onProgress,
  }) async {
    final temporary = await Directory.systemTemp.createTemp('converto-html-');
    try {
      final pages = await PdfEngine.renderPages(
        sourceFile: pdfFile,
        targetFormat: 'png',
        dpi: dpi,
        password: password,
        outputDirectory: temporary.path,
        onProgress: (progress) => onProgress?.call(progress * 0.6),
      );

      final base = FileUtils.getBaseNameWithoutExtension(pdfFile.path);
      final title = _escapeHtml(base);
      final output = await StorageService().resolveOutputFile(
        originalName: base,
        targetExtension: 'html',
        explicitDestinationPath: outputPath,
      );

      await StorageService.writeAtomically(output, (temp) async {
        final sink = temp.openWrite();
        try {
          sink.write('<!DOCTYPE html>\n<html lang="en">\n<head>\n');
          sink.write('<meta charset="utf-8">\n');
          sink.write(
            '<meta name="viewport" content="width=device-width, initial-scale=1">\n',
          );
          sink.write('<title>$title</title>\n');
          sink.write(
            '<style>body{font-family:system-ui,-apple-system,"Segoe UI",sans-serif;'
            'background:#f4f4f5;color:#18181b;margin:0;padding:2rem 1rem}'
            'main{max-width:960px;margin:0 auto}.page{background:#fff;'
            'border:1px solid #d4d4d8;border-radius:8px;padding:.75rem;'
            'margin:0 0 1.25rem}.label{font-size:.75rem;color:#71717a;'
            'margin:0 0 .5rem}img{display:block;width:100%;height:auto}'
            '@media(max-width:720px){body{padding:1rem .5rem}}</style>\n',
          );
          sink.write('</head>\n<body><main>\n<h1>$title</h1>\n');

          for (var index = 0; index < pages.length; index++) {
            final image = base64Encode(await pages[index].readAsBytes());
            sink.write('<section class="page">\n');
            sink.write(
              '<div class="label">Page ${index + 1} of ${pages.length}</div>\n',
            );
            sink.write(
              '<img alt="Page ${index + 1}" src="data:image/png;base64,$image">\n',
            );
            sink.write('</section>\n');
            onProgress?.call(0.6 + 0.4 * ((index + 1) / pages.length));
          }

          sink.write('</main></body></html>\n');
          await sink.flush();
        } finally {
          await sink.close();
        }
      });
      onProgress?.call(1.0);
      return output;
    } finally {
      if (temporary.existsSync()) {
        await temporary.delete(recursive: true);
      }
    }
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

  static String _escapeHtml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

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
