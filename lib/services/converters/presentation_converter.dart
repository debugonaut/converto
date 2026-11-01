import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
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
import 'pdf_converter.dart';

class PresentationConverter extends BaseConverter {
  @override
  String get name => 'Presentation Engine (Android & Windows)';

  @override
  List<String> get supportedSourceFormats => ['pptx', 'ppt', 'odp'];

  @override
  List<String> get supportedTargetFormats => ['pdf', 'png', 'jpg'];

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
      throw ArgumentError('Unsupported presentation output .$cleanTarget.');
    await OfficeBridge.validate(sourceFile);
    final capabilities = await PlatformDetector.detect();
    if (cleanTarget == 'pdf' && capabilities.hasLibreOfficeCLI) {
      return OfficeBridge.convert(
        source: sourceFile,
        target: 'pdf:impress_pdf_Export',
        outputPath: outputPath,
      );
    }
    // Always generate a PDF in a private temporary directory before rendering.
    // A PNG/JPG destination must never receive intermediate PDF bytes.
    final temp = await Directory.systemTemp.createTemp('converto-slides-');
    try {
      final pdfPath = '${temp.path}/slides.pdf';
      final File pdfFile;
      if (capabilities.hasLibreOfficeCLI) {
        pdfFile = await OfficeBridge.convert(
          source: sourceFile,
          target: 'pdf:impress_pdf_Export',
          outputPath: pdfPath,
        );
      } else if (cleanExt == 'pptx') {
        stderr.writeln(
          'Using text-only PPTX fallback; embedded graphics and original layout are not preserved.',
        );
        pdfFile = await _convertPptxToPdf(
          sourceFile,
          originalName,
          outputPath: pdfPath,
          onProgress: onProgress,
        );
      } else {
        throw UnsupportedError(
          'Presentation .$cleanExt requires a locally installed LibreOffice.',
        );
      }
      if (cleanTarget == 'pdf') {
        return await StorageService().saveFromFile(
          source: pdfFile,
          originalName: originalName,
          targetExtension: 'pdf',
          explicitDestinationPath: outputPath,
        );
      }
      stderr.writeln(
        'Exporting the first slide. Convert to PDF, then use pdf2img to export every slide.',
      );
      return await PdfConverter().convertPdfToImage(
        pdfFile: pdfFile,
        targetFormat: cleanTarget,
        dpi: pdfOptions?.rasterDpi ?? 200,
        outputPath: outputPath,
        onProgress: onProgress,
      );
    } finally {
      await temp.delete(recursive: true);
    }
  }

  Future<File> _convertPptxToPdf(
    File sourceFile,
    String originalName, {
    String? outputPath,
    void Function(double progress)? onProgress,
  }) async {
    onProgress?.call(0.3);
    final bytes = await sourceFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    // Presentation relationships define display order, not filenames.
    final presentation = archive.findFile('ppt/presentation.xml');
    final relationships = archive.findFile('ppt/_rels/presentation.xml.rels');
    if (presentation == null || relationships == null) {
      throw const FormatException(
        'PPTX is missing presentation relationships.',
      );
    }
    final main = XmlDocument.parse(
      utf8.decode(presentation.content as List<int>),
    );
    final rels = XmlDocument.parse(
      utf8.decode(relationships.content as List<int>),
    );
    final targets = {
      for (final rel in rels.descendants.whereType<XmlElement>().where(
        (e) => e.name.local == 'Relationship',
      ))
        rel.getAttribute('Id'): rel.getAttribute('Target'),
    };
    final slideFiles = <ArchiveFile>[];
    for (final id in main.descendants.whereType<XmlElement>().where(
      (e) => e.name.local == 'sldId',
    )) {
      final target =
          targets[id.getAttribute(
            'id',
            namespace:
                'http://schemas.openxmlformats.org/officeDocument/2006/relationships',
          )];
      if (target == null)
        throw const FormatException('Missing PPTX slide relationship.');
      final name = p.posix
          .normalize(p.posix.join('ppt', target))
          .replaceFirst(RegExp(r'^/'), '');
      final slide = archive.findFile(name);
      if (slide == null) throw FormatException('Missing PPTX slide: $name');
      slideFiles.add(slide);
    }

    if (slideFiles.isEmpty) {
      throw Exception('No slides found in PPTX presentation');
    }

    onProgress?.call(0.5);
    final pdf = pw.Document();

    for (int i = 0; i < slideFiles.length; i++) {
      final slideFile = slideFiles[i];
      final xmlString = utf8.decode(slideFile.content as List<int>);
      final document = XmlDocument.parse(xmlString);

      // Extract slide text elements
      final textElements = document.findAllElements('a:t');
      final textLines = textElements
          .map((e) => e.innerText.trim())
          .where((t) => t.isNotEmpty)
          .toList();

      final title = textLines.isNotEmpty ? textLines.first : 'Slide ${i + 1}';
      PdfText.requireBasicFont(textLines.join());
      final bodyPoints = textLines.length > 1
          ? textLines.sublist(1)
          : <String>[];

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(40),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  title,
                  style: pw.TextStyle(
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blueGrey800,
                  ),
                ),
                pw.Divider(thickness: 1.5, color: PdfColors.blueGrey300),
                pw.SizedBox(height: 20),
                for (final point in bodyPoints)
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 4),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('• ', style: const pw.TextStyle(fontSize: 14)),
                        pw.Expanded(
                          child: pw.Text(
                            point,
                            style: const pw.TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                pw.Spacer(),
                pw.Align(
                  alignment: pw.Alignment.bottomRight,
                  child: pw.Text(
                    'Slide ${i + 1} of ${slideFiles.length}',
                    style: const pw.TextStyle(
                      fontSize: 9,
                      color: PdfColors.grey600,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      );

      onProgress?.call(0.5 + (0.4 * ((i + 1) / slideFiles.length)));
    }

    final pdfBytes = await pdf.save();
    return await StorageService().saveConvertedFile(
      originalName: originalName,
      targetExtension: 'pdf',
      bytes: pdfBytes,
      explicitDestinationPath: outputPath,
    );
  }
}
