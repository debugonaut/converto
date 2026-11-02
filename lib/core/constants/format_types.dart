enum FileCategory {
  image,
  pdf,
  document,
  spreadsheet,
  presentation,
  archive,
  unknown,
}

class FormatInfo {
  final String extension;
  final String name;
  final FileCategory category;
  final String mimeType;
  final int colorValue;

  const FormatInfo({
    required this.extension,
    required this.name,
    required this.category,
    required this.mimeType,
    required this.colorValue,
  });
}

class FormatRegistry {
  static const Map<String, FormatInfo> formats = {
    // Images
    'jpg': FormatInfo(
      extension: 'jpg',
      name: 'JPEG Image',
      category: FileCategory.image,
      mimeType: 'image/jpeg',
      colorValue: 0xFFF97316,
    ),
    'jpeg': FormatInfo(
      extension: 'jpeg',
      name: 'JPEG Image',
      category: FileCategory.image,
      mimeType: 'image/jpeg',
      colorValue: 0xFFF97316,
    ),
    'png': FormatInfo(
      extension: 'png',
      name: 'PNG Image',
      category: FileCategory.image,
      mimeType: 'image/png',
      colorValue: 0xFF3B82F6,
    ),
    'webp': FormatInfo(
      extension: 'webp',
      name: 'WebP Image',
      category: FileCategory.image,
      mimeType: 'image/webp',
      colorValue: 0xFF14B8A6,
    ),
    'bmp': FormatInfo(
      extension: 'bmp',
      name: 'Bitmap Image',
      category: FileCategory.image,
      mimeType: 'image/bmp',
      colorValue: 0xFFA855F7,
    ),
    'gif': FormatInfo(
      extension: 'gif',
      name: 'GIF Animation',
      category: FileCategory.image,
      mimeType: 'image/gif',
      colorValue: 0xFFF59E0B,
    ),
    'tiff': FormatInfo(
      extension: 'tiff',
      name: 'TIFF Image',
      category: FileCategory.image,
      mimeType: 'image/tiff',
      colorValue: 0xFF6366F1,
    ),
    'tif': FormatInfo(
      extension: 'tif',
      name: 'TIFF Image',
      category: FileCategory.image,
      mimeType: 'image/tiff',
      colorValue: 0xFF6366F1,
    ),
    'ico': FormatInfo(
      extension: 'ico',
      name: 'Icon File',
      category: FileCategory.image,
      mimeType: 'image/x-icon',
      colorValue: 0xFF06B6D4,
    ),

    // PDF
    'pdf': FormatInfo(
      extension: 'pdf',
      name: 'Portable Document Format',
      category: FileCategory.pdf,
      mimeType: 'application/pdf',
      colorValue: 0xFFEF4444,
    ),

    // Documents
    'docx': FormatInfo(
      extension: 'docx',
      name: 'Word Document',
      category: FileCategory.document,
      mimeType:
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      colorValue: 0xFF2563EB,
    ),
    'doc': FormatInfo(
      extension: 'doc',
      name: 'Word 97-2003',
      category: FileCategory.document,
      mimeType: 'application/msword',
      colorValue: 0xFF1D4ED8,
    ),
    'odt': FormatInfo(
      extension: 'odt',
      name: 'OpenDocument Text',
      category: FileCategory.document,
      mimeType: 'application/vnd.oasis.opendocument.text',
      colorValue: 0xFF0EA5E9,
    ),
    'rtf': FormatInfo(
      extension: 'rtf',
      name: 'Rich Text Format',
      category: FileCategory.document,
      mimeType: 'application/rtf',
      colorValue: 0xFF06B6D4,
    ),
    'txt': FormatInfo(
      extension: 'txt',
      name: 'Plain Text',
      category: FileCategory.document,
      mimeType: 'text/plain',
      colorValue: 0xFF64748B,
    ),

    // Spreadsheets
    'xlsx': FormatInfo(
      extension: 'xlsx',
      name: 'Excel Spreadsheet',
      category: FileCategory.spreadsheet,
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      colorValue: 0xFF10B981,
    ),
    'xls': FormatInfo(
      extension: 'xls',
      name: 'Excel 97-2003',
      category: FileCategory.spreadsheet,
      mimeType: 'application/vnd.ms-excel',
      colorValue: 0xFF059669,
    ),
    'csv': FormatInfo(
      extension: 'csv',
      name: 'Comma Separated Values',
      category: FileCategory.spreadsheet,
      mimeType: 'text/csv',
      colorValue: 0xFF0D9488,
    ),

    // Presentations
    'pptx': FormatInfo(
      extension: 'pptx',
      name: 'PowerPoint Presentation',
      category: FileCategory.presentation,
      mimeType:
          'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      colorValue: 0xFFF97316,
    ),
    'ppt': FormatInfo(
      extension: 'ppt',
      name: 'PowerPoint 97-2003',
      category: FileCategory.presentation,
      mimeType: 'application/vnd.ms-powerpoint',
      colorValue: 0xFFEA580C,
    ),
    'odp': FormatInfo(
      extension: 'odp',
      name: 'OpenDocument Presentation',
      category: FileCategory.presentation,
      mimeType: 'application/vnd.oasis.opendocument.presentation',
      colorValue: 0xFFF97316,
    ),
  };

  static FormatInfo getFormatInfo(String extension) {
    final cleanExt = extension.replaceAll('.', '').toLowerCase();
    return formats[cleanExt] ??
        FormatInfo(
          extension: cleanExt,
          name: cleanExt.toUpperCase(),
          category: FileCategory.unknown,
          mimeType: 'application/octet-stream',
          colorValue: 0xFF94A3B8,
        );
  }

  /// Returns valid target output formats for a given source extension
  static List<String> getAvailableTargetFormats(String sourceExtension) {
    final info = getFormatInfo(sourceExtension);

    switch (info.category) {
      case FileCategory.image:
        return [
          'pdf',
          'png',
          'jpg',
          'jpeg',
          'webp',
          'bmp',
          'tiff',
          'gif',
          'ico',
        ];
      case FileCategory.pdf:
        return [
          'png',
          'jpg',
          'webp',
          'txt',
          'md',
          'html',
          'docx',
          'xlsx',
          'pptx',
        ];
      case FileCategory.document:
        return ['pdf', 'txt'];
      case FileCategory.spreadsheet:
        return ['pdf', 'csv'];
      case FileCategory.presentation:
        return ['pdf', 'png', 'jpg'];
      default:
        return ['pdf'];
    }
  }

  /// All valid file picker extensions
  static List<String> get allSupportedExtensions => formats.keys.toList();
}
