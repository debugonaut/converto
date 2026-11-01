import 'dart:io';
import 'package:path/path.dart' as p;
import '../core/utils/file_utils.dart';

class StorageService {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  Directory? _customOutputDir;

  /// Default output directory: ~/Documents/Converto/ or custom
  Future<Directory> getOutputDirectory() async {
    if (_customOutputDir != null && _customOutputDir!.existsSync()) {
      return _customOutputDir!;
    }

    final configured = Platform.environment['CONVERTO_OUTPUT_DIR'];
    if (configured != null && configured.isNotEmpty) {
      return Directory(configured).create(recursive: true);
    }

    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    final docs = Directory(p.join(home, 'Documents'));
    final baseDir = docs.existsSync() ? docs : Directory.current;

    final outDir = Directory(p.join(baseDir.path, 'Converto'));
    if (!outDir.existsSync()) {
      outDir.createSync(recursive: true);
    }
    return outDir;
  }

  void setCustomOutputDirectory(String path) {
    final dir = Directory(path);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    _customOutputDir = dir;
  }

  /// Reserves an output path without writing it. Useful for engines that
  /// stream their result straight to disk instead of returning bytes.
  Future<File> resolveOutputFile({
    required String originalName,
    required String targetExtension,
    String? explicitDestinationPath,
  }) async {
    if (explicitDestinationPath != null) {
      if (Directory(explicitDestinationPath).existsSync() ||
          explicitDestinationPath.endsWith('/') ||
          (Platform.isWindows && explicitDestinationPath.endsWith('\\'))) {
        final dir = await Directory(
          explicitDestinationPath,
        ).create(recursive: true);
        return File(
          FileUtils.getUniqueFilePath(
            dir.path,
            '${FileUtils.sanitizeFileName(originalName)}.${targetExtension.replaceFirst('.', '')}',
          ),
        );
      }
      final explicitFile = File(explicitDestinationPath);
      String canonical(String ext) => ext == 'jpeg' ? 'jpg' : ext;
      final actualExt = FileUtils.getExtension(explicitDestinationPath);
      if (actualExt.isNotEmpty &&
          canonical(actualExt) !=
              canonical(targetExtension.replaceFirst('.', '').toLowerCase())) {
        throw ArgumentError(
          'Output extension .$actualExt does not match .$targetExtension.',
        );
      }
      if (!explicitFile.parent.existsSync()) {
        explicitFile.parent.createSync(recursive: true);
      }
      return explicitFile;
    }

    final outputDir = await getOutputDirectory();
    final cleanExt = targetExtension.startsWith('.')
        ? targetExtension
        : '.$targetExtension';
    final desiredFileName =
        '${FileUtils.sanitizeFileName(originalName)}$cleanExt';
    final finalPath = FileUtils.getUniqueFilePath(
      outputDir.path,
      desiredFileName,
    );
    return File(finalPath);
  }

  /// Saves a converted file with automatic collision avoidance (or explicit target)
  Future<File> saveConvertedFile({
    required String originalName,
    required String targetExtension,
    required List<int> bytes,
    String? explicitDestinationPath,
  }) async {
    final file = await resolveOutputFile(
      originalName: originalName,
      targetExtension: targetExtension,
      explicitDestinationPath: explicitDestinationPath,
    );
    await writeAtomically(
      file,
      (temp) => temp.writeAsBytes(bytes, flush: true),
    );
    return file;
  }

  Future<File> saveFromFile({
    required File source,
    required String originalName,
    required String targetExtension,
    String? explicitDestinationPath,
  }) async {
    final output = await resolveOutputFile(
      originalName: originalName,
      targetExtension: targetExtension,
      explicitDestinationPath: explicitDestinationPath,
    );
    if (p.equals(source.absolute.path, output.absolute.path)) return source;
    await writeAtomically(output, (temp) => source.copy(temp.path));
    return output;
  }

  /// A same-filesystem rename preserves existing output if conversion fails.
  static Future<void> writeAtomically(
    File output,
    Future<void> Function(File) action,
  ) async {
    await output.parent.create(recursive: true);
    final staging = await output.parent.createTemp('.converto-');
    final temp = File(p.join(staging.path, 'result'));
    try {
      await action(temp);
      await temp.rename(output.path);
    } finally {
      if (staging.existsSync()) await staging.delete(recursive: true);
    }
  }

  Future<void> openFile(String filePath) async {
    await FileUtils.openFile(filePath);
  }

  Future<void> showInFileManager(String filePath) async {
    await FileUtils.revealInFileManager(filePath);
  }
}
