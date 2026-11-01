import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:xml/xml.dart';
import '../../core/platform/platform_detector.dart';
import '../../core/utils/file_utils.dart';
import '../../models/edit_options.dart';
import '../storage_service.dart';
import '../office_bridge.dart';
import '../pdf/pdf_text.dart';
import 'base_converter.dart';

class DocumentConverter extends BaseConverter {
  @override
  String get name => 'Document Conversion Engine (Android & Windows)';

  @override
  List<String> get supportedSourceFormats => [
    'docx',
    'doc',
    'odt',
    'rtf',
    'txt',
  ];

  @override
  List<String> get supportedTargetFormats => ['pdf', 'txt'];

  @override
  Future<File> convert({
    required File sourceFile,
    required String targetFormat,
    ImageEditOptions? imageOptions,
    PdfEditOptions? pdfOptions,
    String? outputPath,
    void Function(double progress)? onProgress,
  }) async {
    final cleanExt = FileUtils.getExtension(sourceFile.path);
    final cleanTarget = targetFormat.replaceAll('.', '').toLowerCase();
    final originalName = FileUtils.getBaseNameWithoutExtension(sourceFile.path);

    if (!supportedTargetFormats.contains(cleanTarget))
      throw ArgumentError('Unsupported document output .$cleanTarget.');
    await OfficeBridge.validate(sourceFile);
    onProgress?.call(0.1);
    final capabilities = await PlatformDetector.detect();

    // Text extraction and plain text layout need no external engine.
    if (cleanTarget == 'txt') {
      return _convertToPlainText(
        sourceFile,
        originalName,
        outputPath: outputPath,
      );
    }
    if (cleanExt == 'txt') {
      return _convertPlainTextToPdf(
        sourceFile,
        originalName,
        outputPath: outputPath,
      );
    }
    if (capabilities.hasLibreOfficeCLI) {
      return OfficeBridge.convert(
        source: sourceFile,
        target: 'pdf:writer_pdf_Export',
        outputPath: outputPath,
      );
    }

    // Strategy 2: Pure Dart Engine (Standard on Android & Fallback on Windows)
    onProgress?.call(0.4);

    if (cleanExt == 'docx') {
      stderr.writeln(
        'Using text/table-only DOCX fallback; images and original pagination are not preserved.',
      );
      return await _convertDocxToPdf(
        sourceFile,
        originalName,
        outputPath: outputPath,
        onProgress: onProgress,
      );
    }

    throw Exception(
      'Format .$cleanExt to .$cleanTarget requires LibreOffice on Desktop or is not supported by the offline parser.',
    );
  }

  /// Converts DOCX to PDF by parsing the OpenXML structure directly in Dart
  Future<File> _convertDocxToPdf(
    File sourceFile,
    String originalName, {
    String? outputPath,
    void Function(double progress)? onProgress,
  }) async {
    onProgress?.call(0.5);
    final bytes = await sourceFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    // Find document.xml inside word/
    final documentFile = archive.firstWhere(
      (file) => file.name == 'word/document.xml',
      orElse: () => throw Exception('Invalid DOCX: missing word/document.xml'),
    );

    final xmlString = utf8.decode(documentFile.content as List<int>);
    final document = XmlDocument.parse(xmlString);
    PdfText.requireBasicFont(
      document.findAllElements('w:t').map((e) => e.innerText).join(),
    );

    onProgress?.call(0.7);
    final pdf = pw.Document();
    final List<pw.Widget> contentWidgets = [];

    // Parse paragraphs and tables from document body
    final body = document.findAllElements('w:body').firstOrNull;
    if (body != null) {
      for (final child in body.children) {
        if (child is! XmlElement) continue;

        if (child.name.local == 'p') {
          // Paragraph element
          final paragraphWidget = _parseParagraph(child);
          if (paragraphWidget != null) {
            contentWidgets.add(paragraphWidget);
            contentWidgets.add(pw.SizedBox(height: 6));
          }
        } else if (child.name.local == 'tbl') {
          // Table element
          final tableWidget = _parseTable(child);
          if (tableWidget != null) {
            contentWidgets.add(tableWidget);
            contentWidgets.add(pw.SizedBox(height: 10));
          }
        }
      }
    }

    if (contentWidgets.isEmpty) {
      contentWidgets.add(
        pw.Text(
          'Empty Document',
          style: const pw.TextStyle(color: PdfColors.grey),
        ),
      );
    }

    onProgress?.call(0.85);
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (pw.Context context) => contentWidgets,
      ),
    );

    final pdfBytes = await pdf.save();
    onProgress?.call(0.95);

    return await StorageService().saveConvertedFile(
      originalName: originalName,
      targetExtension: 'pdf',
      bytes: pdfBytes,
      explicitDestinationPath: outputPath,
    );
  }

  pw.Widget? _parseParagraph(XmlElement pElement) {
    final runs = pElement.findAllElements('w:r');
    final List<pw.InlineSpan> spans = [];

    for (final r in runs) {
      final t = r.findElements('w:t').firstOrNull?.innerText;
      if (t == null || t.isEmpty) continue;

      final isBold = r.findAllElements('w:b').isNotEmpty;
      final isItalic = r.findAllElements('w:i').isNotEmpty;

      spans.add(
        pw.TextSpan(
          text: t,
          style: pw.TextStyle(
            fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
            fontStyle: isItalic ? pw.FontStyle.italic : pw.FontStyle.normal,
            fontSize: 11,
          ),
        ),
      );
    }

    if (spans.isEmpty) return null;
    return pw.RichText(text: pw.TextSpan(children: spans));
  }

  pw.Widget? _parseTable(XmlElement tblElement) {
    final rows = tblElement.findAllElements('w:tr');
    final List<List<String>> tableData = [];

    for (final row in rows) {
      final cells = row.findAllElements('w:tc');
      final List<String> rowData = [];
      for (final cell in cells) {
        final textElements = cell.findAllElements('w:t');
        final cellText = textElements.map((e) => e.innerText).join(' ');
        rowData.add(cellText.trim());
      }
      if (rowData.isNotEmpty) {
        tableData.add(rowData);
      }
    }

    if (tableData.isEmpty) return null;

    return pw.TableHelper.fromTextArray(
      data: tableData,
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      cellStyle: const pw.TextStyle(fontSize: 10),
      headerStyle: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
    );
  }

  /// Converts plain text to PDF
  Future<File> _convertPlainTextToPdf(
    File sourceFile,
    String originalName, {
    String? outputPath,
  }) async {
    final content = await FileUtils.readLocalText(sourceFile);
    if (PdfText.needsUnicodeFont(content)) {
      return OfficeBridge.convert(
        source: sourceFile,
        target: 'pdf:writer_pdf_Export',
        outputPath: outputPath,
      );
    }
    final lines = content.split('\n');

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (pw.Context context) => [
          for (final line in lines)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 4),
              child: pw.Text(
                line,
                style: const pw.TextStyle(fontSize: 10, lineSpacing: 1.4),
              ),
            ),
        ],
      ),
    );

    final pdfBytes = await pdf.save();
    return await StorageService().saveConvertedFile(
      originalName: originalName,
      targetExtension: 'pdf',
      bytes: pdfBytes,
      explicitDestinationPath: outputPath,
    );
  }

  /// Extracts text from document
  Future<File> _convertToPlainText(
    File sourceFile,
    String originalName, {
    String? outputPath,
  }) async {
    final ext = FileUtils.getExtension(sourceFile.path);
    String extracted = '';

    if (ext == 'docx') {
      final bytes = await sourceFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final docFile = archive.firstWhere(
        (f) => f.name == 'word/document.xml',
        orElse: () => throw Exception('Invalid DOCX'),
      );
      final xmlString = utf8.decode(docFile.content as List<int>);
      final document = XmlDocument.parse(xmlString);
      final paragraphs = document.findAllElements('w:p');
      final buffer = StringBuffer();
      for (final p in paragraphs) {
        final textElements = p.findAllElements('w:t');
        final line = textElements.map((e) => e.innerText).join('');
        if (line.isNotEmpty) buffer.writeln(line);
      }
      extracted = buffer.toString();
    } else if (ext == 'odt') {
      final archive = ZipDecoder().decodeBytes(await sourceFile.readAsBytes());
      final content = archive.findFile('content.xml')!;
      final xml = XmlDocument.parse(utf8.decode(content.content as List<int>));
      extracted = xml.descendants
          .whereType<XmlElement>()
          .where((e) => e.name.local == 'p' || e.name.local == 'h')
          .map((e) => e.innerText)
          .join('\n');
    } else if (ext == 'txt') {
      return StorageService().saveFromFile(
        source: sourceFile,
        originalName: originalName,
        targetExtension: 'txt',
        explicitDestinationPath: outputPath,
      );
    } else {
      return OfficeBridge.convert(
        source: sourceFile,
        target: 'txt:Text (encoded):UTF8',
        outputPath: outputPath,
      );
    }

    return await StorageService().saveConvertedFile(
      originalName: originalName,
      targetExtension: 'txt',
      bytes: utf8.encode(extracted),
      explicitDestinationPath: outputPath,
    );
  }
}
