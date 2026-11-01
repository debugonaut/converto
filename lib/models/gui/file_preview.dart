import 'dart:typed_data';

class FilePreview {
  final String path;
  final String kind;
  final int sizeBytes;
  final int page;
  final int pageCount;
  final double width;
  final double height;
  final int rasterWidth;
  final int rasterHeight;
  final Uint8List? image;
  final String? text;
  final String? message;
  final bool encrypted;
  const FilePreview({
    required this.path,
    this.kind = 'metadata',
    this.sizeBytes = 0,
    this.page = 0,
    this.pageCount = 1,
    this.width = 0,
    this.height = 0,
    this.rasterWidth = 0,
    this.rasterHeight = 0,
    this.image,
    this.text,
    this.message,
    this.encrypted = false,
  });

  int get memoryBytes =>
      (image?.length ?? 0) +
      rasterWidth * rasterHeight * 4 +
      (text?.length ?? 0) * 2;
  factory FilePreview.fromMap(Map data) => FilePreview(
    path: data['path'] as String,
    kind: data['kind'] as String? ?? 'metadata',
    sizeBytes: data['sizeBytes'] as int? ?? 0,
    page: data['page'] as int? ?? 0,
    pageCount: data['pageCount'] as int? ?? 1,
    width: (data['width'] as num?)?.toDouble() ?? 0,
    height: (data['height'] as num?)?.toDouble() ?? 0,
    rasterWidth: data['rasterWidth'] as int? ?? 0,
    rasterHeight: data['rasterHeight'] as int? ?? 0,
    image: data['image'] as Uint8List?,
    text: data['text'] as String?,
    message: data['message'] as String?,
    encrypted: data['encrypted'] == true,
  );
}
