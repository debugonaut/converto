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
      ToolId.convert => true,
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
    if (id != ToolId.convert && id != ToolId.editImage) return ['pdf'];
    Set<String>? shared;
    for (final ext in extensions) {
      final values = FormatRegistry.getAvailableTargetFormats(ext).toSet();
      shared = shared == null ? values : shared.intersection(values);
    }
    return (shared ?? {'pdf', 'png', 'jpg', 'txt'}).toList();
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
      'Add a text watermark to every page.',
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
      'Add Page X of N to each PDF page.',
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
  ];

  static ToolDefinition byId(ToolId id) =>
      tools.firstWhere((tool) => tool.id == id);
}
