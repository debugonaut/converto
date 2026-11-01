import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';
import 'package:converto/core/constants/format_types.dart';
import 'package:path/path.dart' as p;

class FileUtils {
  /// UTF-8 and BOM-marked UTF-16 from Windows/PowerShell. Invalid encodings
  /// fail visibly rather than being converted into replacement characters.
  static Future<String> readLocalText(File file) async {
    final bytes = await file.readAsBytes();
    if (bytes.length >= 2 &&
        ((bytes[0] == 0xff && bytes[1] == 0xfe) ||
            (bytes[0] == 0xfe && bytes[1] == 0xff))) {
      if (bytes.length.isOdd)
        throw const FormatException('Truncated UTF-16 text.');
      final data = ByteData.sublistView(bytes);
      final endian = bytes[0] == 0xff ? Endian.little : Endian.big;
      final units = Uint16List((bytes.length - 2) ~/ 2);
      for (var i = 0; i < units.length; i++) {
        units[i] = data.getUint16(2 + i * 2, endian);
      }
      for (var i = 0; i < units.length; i++) {
        final u = units[i];
        if (u >= 0xd800 && u <= 0xdbff) {
          if (++i >= units.length || units[i] < 0xdc00 || units[i] > 0xdfff) {
            throw const FormatException('Invalid UTF-16 surrogate pair.');
          }
        } else if (u >= 0xdc00 && u <= 0xdfff) {
          throw const FormatException('Unexpected UTF-16 low surrogate.');
        }
      }
      return String.fromCharCodes(units);
    }
    return utf8.decode(bytes);
  }

  /// Format bytes to human readable format (e.g. "12.4 MB")
  static String formatBytes(int bytes, [int decimals = 1]) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    final i = (log(bytes) / log(1024)).floor();
    final clampedIndex = i.clamp(0, suffixes.length - 1);
    final size = bytes / pow(1024, clampedIndex);
    return '${size.toStringAsFixed(decimals)} ${suffixes[clampedIndex]}';
  }

  /// Get extension without leading dot, lowercased
  static String getExtension(String path) {
    final ext = p.extension(path);
    return ext.startsWith('.')
        ? ext.substring(1).toLowerCase()
        : ext.toLowerCase();
  }

  /// Get filename without extension
  static String getBaseNameWithoutExtension(String path) {
    return p.basenameWithoutExtension(path);
  }

  /// Get full filename with extension
  static String getFileName(String path) {
    return p.basename(path);
  }

  /// Sanitize filename for safe file system writes
  static String sanitizeFileName(String name) {
    return name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
  }

  /// Generate unique filename if file already exists in target directory
  static String getUniqueFilePath(String targetDir, String fileName) {
    var file = File(p.join(targetDir, fileName));
    if (FileSystemEntity.typeSync(file.path, followLinks: false) ==
        FileSystemEntityType.notFound)
      return file.path;

    final baseName = p.basenameWithoutExtension(fileName);
    final ext = p.extension(fileName);
    int counter = 1;

    while (FileSystemEntity.typeSync(file.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      final newName = '${baseName}_$counter$ext';
      file = File(p.join(targetDir, newName));
      counter++;
    }
    return file.path;
  }

  /// Scans a directory for supported convertible files, ignoring hidden files
  static List<File> listSupportedFiles(Directory dir) {
    if (!dir.existsSync()) return [];
    final results = <File>[];
    try {
      final entities = dir.listSync(recursive: false, followLinks: false);
      for (final entity in entities) {
        if (entity is File) {
          final fileName = getFileName(entity.path);
          if (fileName.startsWith('.'))
            continue; // skip hidden files (.DS_Store etc)
          final ext = getExtension(entity.path);
          if (FormatRegistry.formats.containsKey(ext)) {
            results.add(entity);
          }
        }
      }
      results.sort(
        (a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()),
      );
    } catch (_) {}
    return results;
  }

  /// Open file in system default application (offline native OS call)
  static Future<bool> openFile(String path) async {
    try {
      if (Platform.isMacOS) {
        final result = await Process.run('open', [File(path).absolute.path]);
        return result.exitCode == 0;
      } else if (Platform.isWindows) {
        final result = await Process.run('rundll32.exe', [
          'url.dll,FileProtocolHandler',
          File(path).absolute.uri.toString(),
        ]);
        return result.exitCode == 0;
      } else if (Platform.isLinux) {
        final result = await Process.run('xdg-open', [
          File(path).absolute.path,
        ]);
        return result.exitCode == 0;
      }
    } catch (_) {}
    return false;
  }

  /// Reveal file in system file manager (Finder on macOS, Explorer on Windows)
  static Future<bool> revealInFileManager(String path) async {
    try {
      final isDir = FileSystemEntity.isDirectorySync(path);
      if (Platform.isMacOS) {
        if (isDir) {
          await Process.run('open', [path]);
        } else {
          await Process.run('open', ['-R', path]);
        }
        return true;
      } else if (Platform.isWindows) {
        if (isDir) {
          await Process.run('explorer.exe', [path]);
        } else {
          await Process.run('explorer.exe', ['/select,', path]);
        }
        return true;
      } else if (Platform.isLinux) {
        final target = isDir ? path : File(path).parent.path;
        await Process.run('xdg-open', [target]);
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Searches for similarly named files in current directory & subdirectories to assist user typos
  static File? findSimilarFile(String rawPath) {
    final queryName = p.basename(rawPath).toLowerCase().trim();
    if (queryName.isEmpty) return null;

    final queryWithoutExt = p.basenameWithoutExtension(rawPath).toLowerCase();
    final queryExt = getExtension(rawPath);

    try {
      // Typo assistance must not enumerate an entire disk after a failed drop.
      final parent = Directory(p.dirname(rawPath));
      final search = parent.existsSync() ? parent : Directory.current;
      final entities = search
          .listSync(recursive: false, followLinks: false)
          .take(256);
      for (final entity in entities) {
        if (entity is File) {
          final entityBase = p.basename(entity.path).toLowerCase();
          final entityNoExt = p
              .basenameWithoutExtension(entity.path)
              .toLowerCase();
          final entityExt = getExtension(entity.path);

          // Exact name match in another directory
          if (entityBase == queryName) return entity;

          // Same extension and fuzzy base match (substring or edit distance <= 2)
          if (queryExt.isNotEmpty && entityExt == queryExt) {
            if (entityNoExt.contains(queryWithoutExt) ||
                queryWithoutExt.contains(entityNoExt)) {
              return entity;
            }
            if (_levenshtein(queryWithoutExt, entityNoExt) <= 2) {
              return entity;
            }
          }

          // Substring match
          if (queryWithoutExt.length >= 3 &&
              entityBase.contains(queryWithoutExt)) {
            return entity;
          }
        }
      }
    } catch (_) {}

    return null;
  }

  static int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    List<int> v0 = List<int>.generate(b.length + 1, (i) => i);
    List<int> v1 = List<int>.filled(b.length + 1, 0);

    for (int i = 0; i < a.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < b.length; j++) {
        final cost = (a[i] == b[j]) ? 0 : 1;
        v1[j + 1] = min(v1[j] + 1, min(v0[j + 1] + 1, v0[j] + cost));
      }
      for (int j = 0; j <= b.length; j++) {
        v0[j] = v1[j];
      }
    }
    return v1[b.length];
  }
}
