import 'dart:io';
import 'package:path/path.dart' as p;
import '../../core/constants/format_types.dart';
import '../../core/utils/file_utils.dart';

class IntakeResult {
  final List<String> paths;
  final List<String> issues;
  const IntakeResult(this.paths, this.issues);
}

/// OS drop/picker paths are already tokenized. Never shell-parse them.
/// Folder intake is shallow and ignores links, including directory symlinks.
class FileIntake {
  static Future<IntakeResult> collect(
    Iterable<String> inputs, {
    Iterable<String> existing = const [],
  }) async {
    final selected = <String>[...existing];
    String key(String path) => Platform.isWindows ? path.toLowerCase() : path;
    final seen = selected.map((s) => key(p.normalize(p.absolute(s)))).toSet();
    final issues = <String>[];
    Future<void> add(String path) async {
      final normalized = p.normalize(p.absolute(path));
      if (await FileSystemEntity.type(normalized, followLinks: false) !=
          FileSystemEntityType.file) {
        issues.add('Skipped ${p.basename(path)}: not a regular file.');
        return;
      }
      if (!FormatRegistry.formats.containsKey(
        FileUtils.getExtension(normalized),
      )) {
        issues.add('Skipped ${p.basename(path)}: unsupported format.');
        return;
      }
      if (seen.add(key(normalized))) selected.add(normalized);
    }

    for (final path in inputs) {
      try {
        final type = await FileSystemEntity.type(path, followLinks: false);
        if (type == FileSystemEntityType.directory) {
          final files = await Directory(path).list(followLinks: false).toList();
          files.sort((a, b) => a.path.compareTo(b.path));
          for (final entry in files) {
            if (p.basename(entry.path).startsWith('.')) continue;
            if (await FileSystemEntity.type(entry.path, followLinks: false) ==
                FileSystemEntityType.file) {
              await add(entry.path);
            }
          }
        } else {
          await add(path);
        }
      } on FileSystemException {
        issues.add('Cannot read ${p.basename(path)}. Check file permissions.');
      }
    }
    return IntakeResult(List.unmodifiable(selected), List.unmodifiable(issues));
  }
}
