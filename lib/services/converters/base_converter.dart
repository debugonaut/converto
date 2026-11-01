import 'dart:io';
import '../../models/edit_options.dart';

abstract class BaseConverter {
  String get name;
  List<String> get supportedSourceFormats;
  List<String> get supportedTargetFormats;

  bool canConvert(String fromExt, String toExt) {
    final cleanFrom = fromExt.replaceAll('.', '').toLowerCase();
    final cleanTo = toExt.replaceAll('.', '').toLowerCase();
    return supportedSourceFormats.contains(cleanFrom) &&
        supportedTargetFormats.contains(cleanTo);
  }

  Future<File> convert({
    required File sourceFile,
    required String targetFormat,
    ImageEditOptions? imageOptions,
    PdfEditOptions? pdfOptions,
    String? outputPath,
    void Function(double progress)? onProgress,
  });
}
