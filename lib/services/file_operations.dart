import 'dart:io';

import '../core/constants/format_types.dart';
import '../core/utils/file_utils.dart';
import '../models/edit_options.dart';
import 'converters/base_converter.dart';
import 'converters/document_converter.dart';
import 'converters/image_converter.dart';
import 'converters/pdf_converter.dart';
import 'converters/presentation_converter.dart';
import 'converters/spreadsheet_converter.dart';
import 'pdf/pdf_engine.dart';
import 'history_service.dart';

/// Shared execution for argv, interactive commands and file drops.
class FileOperations {
  static final List<BaseConverter> converters = [
    ImageConverter(),
    DocumentConverter(),
    SpreadsheetConverter(),
    PresentationConverter(),
    PdfConverter(),
  ];

  static Future<File> convert({
    required File sourceFile,
    required String targetFormat,
    String? outputPath,
    int quality = 85,
    void Function(double)? onProgress,
  }) async {
    if (!sourceFile.existsSync())
      throw ArgumentError('File not found: ${sourceFile.path}');
    if (quality < 1 || quality > 100)
      throw ArgumentError('Quality must be 1-100.');
    final ext = FileUtils.getExtension(sourceFile.path);
    final target = targetFormat.replaceFirst(RegExp(r'^\.'), '').toLowerCase();
    final converter = converters
        .where((c) => c.canConvert(ext, target))
        .firstOrNull;
    if (converter == null)
      throw ArgumentError('Cannot convert .$ext to .$target.');
    final result = await converter.convert(
      sourceFile: sourceFile,
      targetFormat: target,
      outputPath: outputPath,
      imageOptions: ImageEditOptions(compressionQuality: quality),
      onProgress: onProgress,
    );
    await HistoryService().addRecord(
      HistoryItem(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        sourceName: FileUtils.getFileName(sourceFile.path),
        sourcePath: sourceFile.path,
        sourceFormat: ext,
        targetPath: result.path,
        targetFormat: target,
        fileSizeBytes: await result.length(),
        timestamp: DateTime.now(),
      ),
    );
    return result;
  }

  static bool canMerge(File file) {
    final category = FormatRegistry.getFormatInfo(
      FileUtils.getExtension(file.path),
    ).category;
    return category == FileCategory.image || category == FileCategory.pdf;
  }

  static Future<File> merge({
    required List<File> files,
    String? outputPath,
    void Function(double)? onProgress,
  }) async {
    if (files.isEmpty) throw ArgumentError('Merge requires at least one file.');
    for (final f in files) {
      if (!f.existsSync() || !canMerge(f)) {
        throw ArgumentError(
          'Merge requires readable PDFs or images: ${f.path}',
        );
      }
    }
    if (files.every((f) => FileUtils.getExtension(f.path) == 'pdf')) {
      // Native merge validates inputs into private staging; no double parsing.
      return PdfEngine.merge(
        files: files,
        outputPath: outputPath,
        onProgress: onProgress,
      );
    }
    // Keep only one decoded image in memory and remove intermediates on failure.
    final temp = await Directory.systemTemp.createTemp('converto-merge-');
    try {
      final pdfs = <File>[];
      for (var i = 0; i < files.length; i++) {
        final source = files[i];
        if (FileUtils.getExtension(source.path) == 'pdf') {
          pdfs.add(source);
        } else {
          pdfs.add(
            await ImageConverter().convert(
              sourceFile: source,
              targetFormat: 'pdf',
              outputPath: '${temp.path}/$i.pdf',
            ),
          );
        }
        onProgress?.call((i + 1) / files.length * 0.4);
      }
      return await PdfEngine.merge(
        files: pdfs,
        outputPath: outputPath,
        onProgress: (p) => onProgress?.call(0.4 + p * 0.6),
      );
    } finally {
      await temp.delete(recursive: true);
    }
  }
}
