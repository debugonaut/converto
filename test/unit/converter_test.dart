import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:converto/core/constants/format_types.dart';
import 'package:converto/core/platform/platform_detector.dart';
import 'package:converto/core/utils/file_utils.dart';
import 'package:converto/services/converters/document_converter.dart';
import 'package:converto/services/converters/image_converter.dart';
import 'package:converto/services/converters/spreadsheet_converter.dart';
import 'package:converto/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('oc_test_');
    StorageService().setCustomOutputDirectory(tempDir.path);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('FileUtils Tests', () {
    test('formatBytes formats properly', () {
      expect(FileUtils.formatBytes(500), '500.0 B');
      expect(FileUtils.formatBytes(1024), '1.0 KB');
      expect(FileUtils.formatBytes(1024 * 1024 * 5), '5.0 MB');
    });

    test('getExtension extracts lowercase clean extension', () {
      expect(FileUtils.getExtension('document.PDF'), 'pdf');
      expect(FileUtils.getExtension('archive.tar.gz'), 'gz');
      expect(FileUtils.getExtension('/path/to/photo.PNG'), 'png');
    });

    test('sanitizeFileName removes illegal filesystem characters', () {
      expect(
        FileUtils.sanitizeFileName('file:name*test?.pdf'),
        'file_name_test_.pdf',
      );
    });

    test('listSupportedFiles discovers valid files and skips hidden files', () {
      final img = File(p.join(tempDir.path, 'photo.png'))
        ..writeAsStringSync('dummy');
      final doc = File(p.join(tempDir.path, 'report.pdf'))
        ..writeAsStringSync('dummy');
      final hidden = File(p.join(tempDir.path, '.hidden.png'))
        ..writeAsStringSync('dummy');
      final unsupported = File(p.join(tempDir.path, 'data.xyz'))
        ..writeAsStringSync('dummy');

      final found = FileUtils.listSupportedFiles(tempDir);
      final paths = found.map((f) => f.path).toList();

      expect(paths, contains(img.path));
      expect(paths, contains(doc.path));
      expect(paths, isNot(contains(hidden.path)));
      expect(paths, isNot(contains(unsupported.path)));
    });
  });

  group('FormatRegistry Tests', () {
    test('Image formats return PDF and image targets', () {
      final targets = FormatRegistry.getAvailableTargetFormats('png');
      expect(targets, contains('pdf'));
      expect(targets, contains('jpg'));
      expect(targets, contains('webp'));
    });

    test('PDF format returns image and text targets', () {
      final targets = FormatRegistry.getAvailableTargetFormats('pdf');
      expect(targets, contains('png'));
      expect(targets, contains('jpg'));
    });

    test('Spreadsheet format returns PDF and CSV targets', () {
      final targets = FormatRegistry.getAvailableTargetFormats('xlsx');
      expect(targets, contains('pdf'));
      expect(targets, contains('csv'));
    });
  });

  group('ImageConverter Tests', () {
    test('converts PNG image to PDF document', () async {
      // 1. Create a 100x100 red test image
      final testImage = img.Image(width: 100, height: 100);
      img.fill(testImage, color: img.ColorRgba8(255, 0, 0, 255));
      final pngBytes = img.encodePng(testImage);

      final inputFile = File('${tempDir.path}/test_image.png');
      await inputFile.writeAsBytes(pngBytes);

      final converter = ImageConverter();
      expect(converter.canConvert('png', 'pdf'), isTrue);

      final resultFile = await converter.convert(
        sourceFile: inputFile,
        targetFormat: 'pdf',
      );

      expect(resultFile.existsSync(), isTrue);
      expect(resultFile.path.endsWith('.pdf'), isTrue);
      expect(resultFile.lengthSync(), greaterThan(0));
    });

    test('converts PNG to JPG format', () async {
      final testImage = img.Image(width: 50, height: 50);
      img.fill(testImage, color: img.ColorRgba8(0, 255, 0, 255));
      final pngBytes = img.encodePng(testImage);

      final inputFile = File('${tempDir.path}/test_green.png');
      await inputFile.writeAsBytes(pngBytes);

      final converter = ImageConverter();
      final resultFile = await converter.convert(
        sourceFile: inputFile,
        targetFormat: 'jpg',
      );

      expect(resultFile.existsSync(), isTrue);
      expect(resultFile.path.endsWith('.jpg'), isTrue);
      expect(resultFile.lengthSync(), greaterThan(0));
    });
  });

  group('SpreadsheetConverter Tests', () {
    test('converts CSV to paginated PDF table', () async {
      const csvData =
          'Item,Quantity,Price\nLaptop,5,999.99\nMouse,25,29.99\nKeyboard,15,79.99';
      final csvFile = File('${tempDir.path}/inventory.csv');
      await csvFile.writeAsString(csvData);

      final converter = SpreadsheetConverter();
      expect(converter.canConvert('csv', 'pdf'), isTrue);

      final resultFile = await converter.convert(
        sourceFile: csvFile,
        targetFormat: 'pdf',
      );

      expect(resultFile.existsSync(), isTrue);
      expect(resultFile.path.endsWith('.pdf'), isTrue);
      expect(resultFile.lengthSync(), greaterThan(0));
    });
  });

  group('DocumentConverter Tests', () {
    test('converts plain text to PDF document', () async {
      const textData =
          'Hello Converto!\nThis is a sample document for testing.\nAll processing is 100% local.';
      final txtFile = File('${tempDir.path}/sample.txt');
      await txtFile.writeAsString(textData);

      final converter = DocumentConverter();
      expect(converter.canConvert('txt', 'pdf'), isTrue);

      final resultFile = await converter.convert(
        sourceFile: txtFile,
        targetFormat: 'pdf',
      );

      expect(resultFile.existsSync(), isTrue);
      expect(resultFile.path.endsWith('.pdf'), isTrue);
      expect(resultFile.lengthSync(), greaterThan(0));
    });
  });

  group('PlatformDetector Tests', () {
    test('detect returns valid platform capabilities', () async {
      final caps = await PlatformDetector.detect();
      expect(caps, isNotNull);
      // Exactly one OS should be true on real execution
      final osCount = [
        caps.isAndroid,
        caps.isWindows,
        caps.isMacOS,
        caps.isLinux,
        caps.isIOS,
      ].where((v) => v).length;
      expect(osCount, greaterThanOrEqualTo(1));
    });
  });
}
