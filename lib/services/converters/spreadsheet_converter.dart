import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'package:excel/excel.dart' as xl;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../core/utils/file_utils.dart';
import '../../models/edit_options.dart';
import '../storage_service.dart';
import '../office_bridge.dart';
import '../pdf/pdf_text.dart';
import 'base_converter.dart';

class SpreadsheetConverter extends BaseConverter {
  @override
  String get name => 'Spreadsheet Engine (Android & Windows)';

  @override
  List<String> get supportedSourceFormats => ['xlsx', 'xls', 'csv'];

  @override
  List<String> get supportedTargetFormats => ['pdf', 'csv'];

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

    if (cleanExt == 'xls') {
      return OfficeBridge.convert(
        source: sourceFile,
        target: cleanTarget == 'pdf'
            ? 'pdf:calc_pdf_Export'
            : 'csv:Text - txt - csv (StarCalc):44,34,76',
        outputPath: outputPath,
      );
    }
    if (cleanExt == 'xlsx') await OfficeBridge.validate(sourceFile);
    onProgress?.call(0.1);

    if (cleanTarget == 'csv') {
      return await _exportToCsv(
        sourceFile,
        originalName,
        cleanExt,
        outputPath: outputPath,
        onProgress: onProgress,
      );
    }

    if (cleanTarget == 'pdf') {
      return await _exportToPdf(
        sourceFile,
        originalName,
        cleanExt,
        outputPath: outputPath,
        onProgress: onProgress,
      );
    }

    throw Exception('Unsupported conversion from .$cleanExt to .$cleanTarget');
  }

  /// Exports spreadsheet sheet data to PDF with vector tables
  Future<File> _exportToPdf(
    File sourceFile,
    String originalName,
    String ext, {
    String? outputPath,
    void Function(double progress)? onProgress,
  }) async {
    final sheets = <String, List<List<String>>>{};
    onProgress?.call(0.3);
    if (ext == 'csv') {
      final content = await FileUtils.readLocalText(sourceFile);
      final rows = CsvToListConverter(
        eol: content.contains('\r\n') ? '\r\n' : '\n',
        shouldParseNumbers: false,
      ).convert(content.replaceFirst('\ufeff', ''));
      sheets[originalName] = rows
          .map((r) => r.map((c) => c.toString()).toList())
          .toList();
    } else {
      final excel = _decodeWorkbook(await sourceFile.readAsBytes());
      for (final entry in excel.tables.entries) {
        sheets[entry.key] = entry.value.rows
            .map(
              (row) =>
                  row.map((cell) => cell?.value?.toString() ?? '').toList(),
            )
            .toList();
      }
      if (sheets.isEmpty) throw StateError('Spreadsheet has no sheets.');
    }
    onProgress?.call(0.6);
    if (PdfText.needsUnicodeFont(originalName) ||
        sheets.values.any(
          (rows) => rows.any((row) => row.any(PdfText.needsUnicodeFont)),
        )) {
      return OfficeBridge.convert(
        source: sourceFile,
        target: 'pdf:calc_pdf_Export',
        outputPath: outputPath,
      );
    }
    final pdf = pw.Document();
    for (final entry in sheets.entries) {
      final tableData = entry.value;
      if (tableData.isEmpty || tableData.every((r) => r.isEmpty))
        tableData.add(['Empty Spreadsheet']);
      final maxCols = tableData
          .map((r) => r.length)
          .reduce((a, b) => a > b ? a : b);
      final normalizedData = tableData
          .map((r) => [...r, ...List.filled(maxCols - r.length, '')])
          .toList();
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(24),
          build: (_) => [
            pw.Header(
              level: 0,
              text: sheets.length == 1
                  ? originalName
                  : '$originalName - ${entry.key}',
              textStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 14,
              ),
            ),
            pw.SizedBox(height: 10),
            pw.TableHelper.fromTextArray(
              data: normalizedData,
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              headerStyle: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
              ),
              cellStyle: const pw.TextStyle(fontSize: 8),
              cellPadding: const pw.EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 3,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey200,
              ),
            ),
          ],
        ),
      );
    }
    onProgress?.call(0.9);
    final pdfBytes = await pdf.save();

    return await StorageService().saveConvertedFile(
      originalName: originalName,
      targetExtension: 'pdf',
      bytes: pdfBytes,
      explicitDestinationPath: outputPath,
    );
  }

  /// Exports Excel sheets to standard CSV
  Future<File> _exportToCsv(
    File sourceFile,
    String originalName,
    String ext, {
    String? outputPath,
    void Function(double progress)? onProgress,
  }) async {
    if (ext == 'csv') {
      // Already CSV
      return StorageService().saveFromFile(
        source: sourceFile,
        originalName: originalName,
        targetExtension: 'csv',
        explicitDestinationPath: outputPath,
      );
    }

    final bytes = await sourceFile.readAsBytes();
    final excel = _decodeWorkbook(bytes);
    final firstSheet = excel.tables.values.firstOrNull;
    if (excel.tables.length > 1) {
      stderr.writeln(
        'CSV exports the first sheet (${excel.tables.keys.first}) of ${excel.tables.length}. PDF includes every sheet.',
      );
    }

    if (firstSheet == null) {
      throw Exception('Spreadsheet contains no sheets');
    }

    final List<List<dynamic>> rows = [];
    for (final r in firstSheet.rows) {
      rows.add(r.map((c) => c?.value?.toString() ?? '').toList());
    }

    final csvString = const ListToCsvConverter().convert(rows);
    return await StorageService().saveConvertedFile(
      originalName: originalName,
      targetExtension: 'csv',
      bytes: utf8.encode(csvString),
      explicitDestinationPath: outputPath,
    );
  }

  xl.Excel _decodeWorkbook(List<int> bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    if (archive.findFile('xl/styles.xml') == null) {
      final defaults = ZipDecoder().decodeBytes(xl.Excel.createExcel().save()!);
      final styles = defaults.findFile('xl/styles.xml')!;
      archive.addFile(
        ArchiveFile('xl/styles.xml', styles.size, styles.content),
      );
      final relations = archive.findFile('xl/_rels/workbook.xml.rels')!;
      final xml = XmlDocument.parse(
        utf8.decode(relations.content as List<int>),
      );
      if (!xml
          .findAllElements('Relationship')
          .any((e) => (e.getAttribute('Type') ?? '').endsWith('/styles'))) {
        final ids = xml
            .findAllElements('Relationship')
            .map((e) => e.getAttribute('Id'))
            .toSet();
        var nextId = 1;
        while (ids.contains('rId$nextId')) {
          nextId++;
        }
        xml.rootElement.children.add(
          XmlElement(XmlName('Relationship'), [
            XmlAttribute(XmlName('Id'), 'rId$nextId'),
            XmlAttribute(
              XmlName('Type'),
              'http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles',
            ),
            XmlAttribute(XmlName('Target'), 'styles.xml'),
          ]),
        );
        final content = utf8.encode(xml.toXmlString());
        archive.addFile(ArchiveFile(relations.name, content.length, content));
      }
      return xl.Excel.decodeBytes(ZipEncoder().encode(archive)!);
    }
    return xl.Excel.decodeBytes(bytes);
  }
}
