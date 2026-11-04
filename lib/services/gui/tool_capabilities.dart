import 'dart:io';
import '../../core/platform/platform_detector.dart';
import '../../models/gui/tool_definition.dart';
import '../pdf/pdf_engine.dart';

/// Availability policy shared by the form and its independent worker.
class ToolCapabilities {
  final bool mobile, libreOffice, webp, tesseract;
  const ToolCapabilities({
    required this.mobile,
    required this.libreOffice,
    required this.webp,
    required this.tesseract,
  });
  static Future<ToolCapabilities> detect({bool? mobile}) async {
    final isMobile = mobile ?? (Platform.isAndroid || Platform.isIOS);
    if (isMobile)
      return const ToolCapabilities(
        mobile: true,
        libreOffice: false,
        webp: false,
        tesseract: false,
      );
    final platform = await PlatformDetector.detect();
    return ToolCapabilities(
      mobile: false,
      libreOffice: platform.hasLibreOfficeCLI,
      webp: await PdfEngine.hasWebpEncoder(),
      tesseract: await PdfEngine.tesseractVersion() != null,
    );
  }

  String? check(
    ToolId tool,
    Iterable<String> extensions,
    Map<String, Object> options,
  ) {
    if (tool == ToolId.ocr && !tesseract)
      return mobile
          ? 'OCR is not bundled on mobile yet. Other PDF tools work offline.'
          : 'OCR needs a locally installed Tesseract engine and language data. No engine is downloaded by Converto.';
    if (![
      ToolId.convert,
      ToolId.scanPdf,
      ToolId.editImage,
      ToolId.pdfImages,
    ].contains(tool))
      return null;
    if (tool == ToolId.pdfImages && options['imageMode'] == 'extract')
      return null;
    final target = tool == ToolId.scanPdf
        ? 'pdf'
        : '${options['format'] ?? (tool == ToolId.pdfImages ? 'png' : 'pdf')}';
    if (target == 'webp' && !webp)
      return 'WebP output needs a local encoder, which is ${mobile ? 'not bundled on mobile' : 'not installed'}. Choose PNG or JPG.';
    if (!libreOffice) {
      for (final ext in extensions) {
        final needsOffice =
            ['doc', 'xls', 'ppt', 'odp'].contains(ext) ||
            ext == 'rtf' ||
            (ext == 'odt' && target != 'txt');
        if (needsOffice)
          return '.$ext → $target needs a local LibreOffice engine, which is ${mobile ? 'unavailable on mobile' : 'not installed'}. Choose a supported format instead.';
      }
    }
    return null;
  }
}
