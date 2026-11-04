import '../../core/constants/format_types.dart';

enum ToolId {
  convert,
  merge,
  split,
  compress,
  organize,
  editImage,
  watermark,
  protect,
  redact,
  pdfImages,
  pdfText,
  pdfOffice,
  extract,
  rotate,
  pageNumbers,
  crop,
  pdfa,
  unlock,
  info,
  scanPdf,
  compare,
  repair,
  clean,
  sign,
  ocr,
  flatten,
}

enum ToolCategory { all, convert, organize, edit, optimize, security }

class ToolDefinition {
  final ToolId id;
  final String title;
  final String description;
  final ToolCategory category;
  const ToolDefinition(this.id, this.title, this.description, this.category);

  bool accepts(String extension) {
    final category = FormatRegistry.getFormatInfo(extension).category;
    if (category == FileCategory.unknown) return false;
    return switch (id) {
      ToolId.convert || ToolId.scanPdf => true,
      ToolId.merge =>
        category == FileCategory.pdf || category == FileCategory.image,
      ToolId.editImage => category == FileCategory.image,
      _ => category == FileCategory.pdf,
    };
  }

  List<String> targets(Iterable<String> extensions) {
    if (id == ToolId.pdfImages) return ['png', 'jpg'];
    if (id == ToolId.pdfOffice) return ['docx', 'xlsx', 'pptx'];
    if (id == ToolId.pdfText) return ['txt'];
    if (id == ToolId.compare) return ['html'];
    if (id == ToolId.ocr) return ['txt', 'pdf'];
    if (id != ToolId.convert && id != ToolId.editImage) return ['pdf'];
    Set<String>? shared;
    for (final ext in extensions.toSet()) {
      final values = FormatRegistry.getAvailableTargetFormats(ext).toSet();
      shared = shared == null ? values : shared.intersection(values);
    }
    return (shared ?? {'pdf', 'png', 'jpg', 'txt'}).toList();
  }

  bool canCombineImagesToPdf(Iterable<String> extensions, String target) {
    final sources = extensions.toList();
    return id == ToolId.convert &&
        target == 'pdf' &&
        sources.length > 1 &&
        sources.every(
          (ext) =>
              FormatRegistry.getFormatInfo(ext).category == FileCategory.image,
        );
  }

  static const tools = <ToolDefinition>[
    ToolDefinition(
      ToolId.convert,
      'Convert files',
      'Images, documents, spreadsheets & slides.',
      ToolCategory.convert,
    ),
    ToolDefinition(
      ToolId.merge,
      'Merge PDF',
      'Combine PDFs and images in your order.',
      ToolCategory.organize,
    ),
    ToolDefinition(
      ToolId.scanPdf,
      'Create scanned PDF',
      'Adjust contrast and turn files into scanned pages.',
      ToolCategory.convert,
    ),
    ToolDefinition(
      ToolId.split,
      'Split PDF',
      'Separate pages into smaller documents.',
      ToolCategory.organize,
    ),
    ToolDefinition(
      ToolId.compress,
      'Compress PDF',
      'Reduce file size with a quality preset.',
      ToolCategory.optimize,
    ),
    ToolDefinition(
      ToolId.organize,
      'Organize pages',
      'Reorder, repeat or remove PDF pages.',
      ToolCategory.organize,
    ),
    ToolDefinition(
      ToolId.editImage,
      'Image editor',
      'Rotate, flip, crop and resize images.',
      ToolCategory.edit,
    ),
    ToolDefinition(
      ToolId.watermark,
      'Watermark',
      'Add text or an image watermark to selected pages.',
      ToolCategory.edit,
    ),
    ToolDefinition(
      ToolId.protect,
      'Protect PDF',
      'Encrypt a PDF with a password.',
      ToolCategory.security,
    ),
    ToolDefinition(
      ToolId.redact,
      'Redact PDF',
      'Permanently remove matching text.',
      ToolCategory.security,
    ),
    ToolDefinition(
      ToolId.pdfImages,
      'PDF to images',
      'Export every page as PNG or JPG.',
      ToolCategory.convert,
    ),
    ToolDefinition(
      ToolId.pdfText,
      'PDF to text',
      'Extract selectable text into a text file.',
      ToolCategory.convert,
    ),
    ToolDefinition(
      ToolId.pdfOffice,
      'PDF to Office',
      'Create a Word, Excel or PowerPoint file.',
      ToolCategory.convert,
    ),
    ToolDefinition(
      ToolId.extract,
      'Extract pages',
      'Save selected pages in a new PDF.',
      ToolCategory.organize,
    ),
    ToolDefinition(
      ToolId.rotate,
      'Rotate PDF',
      'Turn all pages by 90, 180 or 270 degrees.',
      ToolCategory.edit,
    ),
    ToolDefinition(
      ToolId.pageNumbers,
      'Page numbers',
      'Number selected pages with a starting number and position.',
      ToolCategory.edit,
    ),
    ToolDefinition(
      ToolId.crop,
      'Crop PDF',
      'Trim page margins by a precise amount.',
      ToolCategory.edit,
    ),
    ToolDefinition(
      ToolId.pdfa,
      'PDF/A export',
      'Create an archival PDF/A file.',
      ToolCategory.convert,
    ),
    ToolDefinition(
      ToolId.unlock,
      'Unlock PDF',
      'Remove encryption with its password.',
      ToolCategory.security,
    ),
    ToolDefinition(
      ToolId.info,
      'PDF info',
      'Inspect pages, metadata and encryption.',
      ToolCategory.organize,
    ),
    ToolDefinition(
      ToolId.compare,
      'Compare PDFs',
      'Compare two PDFs and export a local visual report.',
      ToolCategory.organize,
    ),
    ToolDefinition(
      ToolId.repair,
      'Repair PDF',
      'Rebuild a recoverable PDF into a new file.',
      ToolCategory.optimize,
    ),
    ToolDefinition(
      ToolId.clean,
      'Clean PDF',
      'Remove metadata, scripts or embedded files.',
      ToolCategory.security,
    ),
    ToolDefinition(
      ToolId.sign,
      'Certificate signing',
      'Sign a PDF with your local P12 or PFX certificate.',
      ToolCategory.security,
    ),
    ToolDefinition(
      ToolId.ocr,
      'OCR PDF',
      'Recognize scans with an installed desktop OCR engine.',
      ToolCategory.convert,
    ),
    ToolDefinition(
      ToolId.flatten,
      'Flatten PDF',
      'Bake forms and annotations into page content.',
      ToolCategory.edit,
    ),
  ];

  static ToolDefinition byId(ToolId id) =>
      tools.firstWhere((tool) => tool.id == id);
}
