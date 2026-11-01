import 'dart:io';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';
import '../core/platform/platform_detector.dart';
import '../core/utils/file_utils.dart';
import 'local_process.dart';
import 'storage_service.dart';

/// Isolated local Office conversion. A private profile prevents daemon collisions;
/// staging prevents stale output detection and accidental source replacement.
class OfficeBridge {
  static Future<void> validate(File source) async {
    final ext = FileUtils.getExtension(source.path);
    final bytes = await source.open();
    late List<int> header;
    try {
      header = await bytes.read(8);
    } finally {
      await bytes.close();
    }
    if (['doc', 'xls', 'ppt'].contains(ext)) {
      const magic = [0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1];
      if (header.length < 8 ||
          List.generate(8, (i) => header[i] == magic[i]).contains(false)) {
        throw FormatException(
          'Invalid .$ext file: expected an OLE Office document.',
        );
      }
    } else if (['docx', 'xlsx', 'pptx', 'odt', 'odp'].contains(ext)) {
      final archive = ZipDecoder().decodeBytes(
        await source.readAsBytes(),
        verify: true,
      );
      final required = {
        'docx': 'word/document.xml',
        'xlsx': 'xl/workbook.xml',
        'pptx': 'ppt/presentation.xml',
        'odt': 'content.xml',
        'odp': 'content.xml',
      }[ext]!;
      if (archive.findFile(required) == null)
        throw FormatException('Invalid .$ext: missing $required.');
      XmlDocument.parse(
        utf8.decode(archive.findFile(required)!.content as List<int>),
      );
    } else if (ext == 'rtf') {
      if (!String.fromCharCodes(header).startsWith(r'{\rtf'))
        throw const FormatException('Invalid RTF document.');
    }
  }

  static Future<File> convert({
    required File source,
    required String target,
    String? outputPath,
  }) async {
    await validate(source);
    final caps = await PlatformDetector.detect();
    if (!caps.hasLibreOfficeCLI) {
      throw UnsupportedError(
        '.${FileUtils.getExtension(source.path)} conversion requires a locally installed LibreOffice. No helper is downloaded.',
      );
    }
    final temp = await Directory.systemTemp.createTemp('converto-office-');
    try {
      final csv = FileUtils.getExtension(source.path) == 'csv';
      final inputPath = p.join(temp.path, 'input${p.extension(source.path)}');
      // Older Calc releases guess a legacy encoding for UTF-8 CSV. Normalize
      // only the private staged input (including BOM-marked UTF-16 sources).
      final input = csv
          ? await File(
              inputPath,
            ).writeAsString(await FileUtils.readLocalText(source))
          : await source.copy(inputPath);
      final outputDir = await Directory(p.join(temp.path, 'out')).create();
      final profile = Directory(p.join(temp.path, 'profile')).uri;
      await LocalProcess.run(caps.libreOfficePath!, [
        '-env:UserInstallation=$profile',
        '--headless',
        '--nologo',
        '--nodefault',
        '--nofirststartwizard',
        if (csv) '--infilter=Text - txt - csv (StarCalc):44,34,76,1',
        '--convert-to',
        target,
        '--outdir',
        outputDir.path,
        input.path,
      ]);
      final ext = target.split(':').first;
      final generated = File(p.join(outputDir.path, 'input.$ext'));
      if (!generated.existsSync() || generated.lengthSync() == 0) {
        throw StateError('LibreOffice did not generate a valid .$ext result.');
      }
      return await StorageService().saveFromFile(
        source: generated,
        originalName: FileUtils.getBaseNameWithoutExtension(source.path),
        targetExtension: ext,
        explicitDestinationPath: outputPath,
      );
    } finally {
      await temp.delete(recursive: true);
    }
  }
}
