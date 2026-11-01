import 'dart:io';
import 'dart:typed_data';
import '../core/constants/format_types.dart';
import '../core/utils/file_utils.dart';

class FileItem {
  final String path;
  final String name;
  final String extension;
  final int size;
  final Uint8List? bytes;
  final Uint8List? thumbnail;
  final int? pageCount;

  FileItem({
    required this.path,
    required this.name,
    required this.extension,
    required this.size,
    this.bytes,
    this.thumbnail,
    this.pageCount,
  });

  factory FileItem.fromFile(File file) {
    final size = file.lengthSync();
    final ext = FileUtils.getExtension(file.path);
    final name = FileUtils.getBaseNameWithoutExtension(file.path);

    return FileItem(
      path: file.path,
      name: name,
      extension: ext,
      size: size,
    );
  }

  FormatInfo get formatInfo => FormatRegistry.getFormatInfo(extension);

  String get formattedSize => FileUtils.formatBytes(size);

  FileItem copyWith({
    String? path,
    String? name,
    String? extension,
    int? size,
    Uint8List? bytes,
    Uint8List? thumbnail,
    int? pageCount,
  }) {
    return FileItem(
      path: path ?? this.path,
      name: name ?? this.name,
      extension: extension ?? this.extension,
      size: size ?? this.size,
      bytes: bytes ?? this.bytes,
      thumbnail: thumbnail ?? this.thumbnail,
      pageCount: pageCount ?? this.pageCount,
    );
  }
}

