import 'dart:io';
import 'package:pdf_manipulator/io.dart';
import 'package:pdf_manipulator/pdf_manipulator.dart';
import '../pdf/pdf_engine.dart';
import '../storage_service.dart';

/// Extends the shared organizer with per-output-page rotations. All edits stay
/// inside the GUI transaction; no document is rasterized for page operations.
class PdfPageActions {
  static Future<File> organize({
    required File source,
    required String order,
    required String outputPath,
    required List<int> rotations,
    void Function(double)? onProgress,
  }) async {
    final total = await PdfEngine.pageCount(source);
    final pages = PdfEngine.parsePageList(order, total);
    if (rotations.isNotEmpty && rotations.length != pages.length) {
      throw ArgumentError('Page rotations do not match the selected pages.');
    }
    if (rotations.any((angle) => ![0, 90, 180, 270].contains(angle))) {
      throw ArgumentError('Page rotation must be 0, 90, 180 or 270 degrees.');
    }
    if (pages.toSet().length != pages.length) {
      // Repeated references in a PDF page tree are unsafe to mutate in place.
      // Import each occurrence as its own document so duplicate pages have
      // independent objects and can carry different rotations.
      final staging = await File(
        outputPath,
      ).parent.createTemp('.converto-pages-');
      try {
        final parts = <File>[];
        for (var index = 0; index < pages.length; index++) {
          var part = await PdfEngine.extractPages(
            sourceFile: source,
            expression: '${pages[index] + 1}',
            outputPath: '${staging.path}/$index.pdf',
          );
          final angle = rotations.isEmpty ? 0 : rotations[index];
          if (angle != 0)
            part = await PdfEngine.rotate(
              sourceFile: part,
              degrees: angle,
              outputPath: '${staging.path}/rotated-$index.pdf',
            );
          parts.add(part);
          onProgress?.call((index + 1) / pages.length * .8);
        }
        return await PdfEngine.merge(
          files: parts,
          outputPath: outputPath,
          onProgress: (value) => onProgress?.call(.8 + value * .2),
        );
      } finally {
        await staging.delete(recursive: true);
      }
    }
    final file = await PdfEngine.organize(
      sourceFile: source,
      order: order,
      outputPath: outputPath,
    );
    if (rotations.every((angle) => angle == 0)) {
      onProgress?.call(1);
      return file;
    }
    final pdf = Pdf();
    final editor = await pdf.edit(FileSource(file));
    try {
      final count = await editor.pageCount;
      if (rotations.length != count)
        throw ArgumentError('Page rotations do not match the selected pages.');
      for (var page = 0; page < count; page++) {
        if (![0, 90, 180, 270].contains(rotations[page]))
          throw ArgumentError(
            'Page rotation must be 0, 90, 180 or 270 degrees.',
          );
        if (rotations[page] != 0)
          await editor.rotatePage(page, degrees: rotations[page]);
      }
      await StorageService.writeAtomically(file, (temporary) async {
        final sink = await FileSink.create(temporary);
        try {
          await editor.save(sink);
        } finally {
          await sink.close();
        }
      });
      onProgress?.call(1);
      return file;
    } finally {
      await editor.dispose();
      await pdf.dispose();
    }
  }
}
