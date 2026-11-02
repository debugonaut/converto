import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../core/utils/file_utils.dart';
import '../models/scan_options.dart';
import 'file_operations.dart';
import 'pdf/pdf_engine.dart';
import 'scan_image_filter.dart';

class ScannedPdfService {
  static Future<File> create({
    required File source,
    required String outputPath,
    required ScanOptions options,
    Future<void> Function()? checkpoint,
    void Function(double)? onProgress,
  }) async {
    options.validate();
    final work = await Directory(p.dirname(outputPath)).createTemp('.scan-');
    try {
      await checkpoint?.call();
      final pdf = FileUtils.getExtension(source.path) == 'pdf'
          ? source
          : await FileOperations.convert(
              sourceFile: source,
              targetFormat: 'pdf',
              outputPath: p.join(work.path, 'source.pdf'),
              recordHistory: false,
              onProgress: (value) => onProgress?.call(value * .15),
            );
      await checkpoint?.call();
      final pages = <File>[];
      await for (final raster in PdfEngine.rasterizePages(
        sourceFile: pdf,
        dpi: options.dpi,
      )) {
        await checkpoint?.call();
        final decoded = img.decodePng(raster.png);
        if (decoded == null)
          throw StateError('Could not decode the scanned page.');
        final filtered = ScanImageFilter.apply(decoded, options);
        final document = pw.Document();
        final image = pw.MemoryImage(img.encodePng(filtered));
        document.addPage(
          pw.Page(
            pageFormat: PdfPageFormat(raster.width, raster.height),
            margin: pw.EdgeInsets.zero,
            build: (_) => pw.Image(image, fit: pw.BoxFit.fill),
          ),
        );
        final page = File(p.join(work.path, 'page-${pages.length}.pdf'));
        await page.writeAsBytes(await document.save());
        pages.add(page);
        onProgress?.call(.15 + pages.length / raster.pageCount * .75);
        await checkpoint?.call();
      }
      if (pages.isEmpty)
        throw ArgumentError('The source has no pages to scan.');
      final result = await PdfEngine.merge(
        files: pages,
        outputPath: outputPath,
        onProgress: (value) => onProgress?.call(.9 + value * .1),
      );
      await checkpoint?.call();
      return result;
    } finally {
      await work.delete(recursive: true);
    }
  }
}
