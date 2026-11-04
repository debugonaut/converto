import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdf_manipulator/io.dart';
import 'package:pdf_manipulator/pdf_manipulator.dart';

import '../../core/utils/file_utils.dart';
import '../../models/pdf_layout_options.dart';
import '../storage_service.dart';
import 'page_number_bridge.dart';
import 'pdf_extended_tools.dart';

/// One bundled, entirely local PDF engine for the operations the old
/// converter could not do on its own.
///
/// It replaces the Ghostscript / pdfunite / pdftoppm requirements for:
/// merge, watermark, page rendering, split, compress, rotate, protect,
/// unlock, extract, compare, repair/sanitize, signing, OCR orchestration,
/// and HTML/Markdown/Office export. Everything runs on the user's machine;
/// no network calls and no per-file quotas. Optional helpers (Tesseract,
/// cwebp) are detected locally and never downloaded.
class PdfEngine {
  static Pdf? _pdf;

  static Pdf get _instance => _pdf ??= Pdf();

  static Future<void> dispose() async {
    final pdf = _pdf;
    _pdf = null;
    await pdf?.dispose();
  }

  static String errorMessage(Object error) =>
      error is PdfError ? error.message : error.toString();

  static Future<int> pageCount(File sourceFile) async {
    final doc = await _instance.open(FileSource(sourceFile));
    try {
      return doc.pageCount;
    } finally {
      await doc.dispose();
    }
  }

  static Future<String> extractText(File sourceFile) async {
    final doc = await _instance.open(FileSource(sourceFile));
    try {
      return await doc.extract(pages: const PdfPages.all());
    } finally {
      await doc.dispose();
    }
  }

  /// Extracts the whole document as `txt`, `md` (Markdown), or `html`.
  ///
  /// The bundled engine converts layout, headings, lists, tables, and
  /// images locally; nothing is uploaded.
  static Future<String> extractAs(
    File sourceFile,
    String format, {
    String? password,
  }) async {
    final target = switch (format.replaceAll('.', '').toLowerCase()) {
      'txt' || 'text' => PdfExtractionFormat.text,
      'md' || 'markdown' => PdfExtractionFormat.markdown,
      'html' || 'htm' => PdfExtractionFormat.html,
      'plain' => PdfExtractionFormat.plainText,
      _ => throw ArgumentError(
        'PDF export supports txt, md, or html, not .$format.',
      ),
    };

    final doc = await _instance.open(
      FileSource(sourceFile),
      password: password,
    );
    try {
      return await doc.extract(pages: const PdfPages.all(), format: target);
    } finally {
      await doc.dispose();
    }
  }

  /// Digitally signs a PDF with a local PKCS#12 bundle or PEM cert/key.
  ///
  /// The private key never leaves the machine. The source is only read;
  /// a separate signed PDF is written.
  static Future<File> sign({
    required File sourceFile,
    String? p12Path,
    String? p12Password,
    String? certPath,
    String? keyPath,
    String? reason,
    String? location,
    String? outputPath,
    void Function(double progress)? onProgress,
  }) async {
    if (p12Path == null && (certPath == null || keyPath == null)) {
      throw ArgumentError(
        'Provide a .p12/.pfx bundle, or both a certificate and key PEM.',
      );
    }

    PdfSigningCredentials credentials;
    if (p12Path != null) {
      final bundle = File(p12Path);
      if (!bundle.existsSync()) {
        throw ArgumentError('Signing bundle not found: ${bundle.path}');
      }
      credentials = PdfSigningCredentials.pkcs12(
        await bundle.readAsBytes(),
        p12Password ?? '',
      );
    } else {
      final cert = File(certPath!);
      final key = File(keyPath!);
      if (!cert.existsSync()) {
        throw ArgumentError('Certificate not found: ${cert.path}');
      }
      if (!key.existsSync()) {
        throw ArgumentError('Private key not found: ${key.path}');
      }
      credentials = PdfSigningCredentials.pem(
        await cert.readAsString(),
        await key.readAsString(),
      );
    }

    final base = FileUtils.getBaseNameWithoutExtension(sourceFile.path);
    final output = await StorageService().resolveOutputFile(
      originalName: '${base}_signed',
      targetExtension: 'pdf',
      explicitDestinationPath: outputPath,
    );

    onProgress?.call(0.1);
    Future<void> writeSignature(File input) async {
      await _writeAtomically(output, (sink) async {
        await _instance.sign(
          FileSource(input),
          sink,
          credentials: credentials,
          reason: reason,
          location: location,
        );
      });
    }

    try {
      await writeSignature(sourceFile);
    } catch (originalError) {
      // Older and third-party PDFs sometimes have a trailer without /Size;
      // signing is stricter than rendering. Rebuild a private copy first so
      // the user never has to know about the malformed trailer.
      final staging = await Directory.systemTemp.createTemp('converto-sign-');
      try {
        final repaired = await repair(
          sourceFile: sourceFile,
          outputPath: '${staging.path}${Platform.pathSeparator}repaired.pdf',
        );
        onProgress?.call(0.5);
        await writeSignature(repaired);
      } catch (_) {
        throw originalError;
      } finally {
        if (staging.existsSync()) await staging.delete(recursive: true);
      }
    }
    onProgress?.call(1.0);
    return output;
  }

  /// Compares two PDFs locally.
  ///
  /// Text is compared per page first; pages without a text layer fall back
  /// to a low-DPI pixel comparison so scans are still caught.
  static Future<PdfCompareResult> compare({
    required File leftFile,
    required File rightFile,
    String? leftPassword,
    String? rightPassword,
    int dpi = 72,
    double pixelThreshold = 0.002,
    String? reportPath,
  }) async {
    if (dpi < 36) throw ArgumentError('Comparison DPI must be at least 36.');
    if (pixelThreshold < 0 || pixelThreshold > 1) {
      throw ArgumentError('Pixel threshold must be between 0 and 1.');
    }

    File? report;
    if (reportPath != null) {
      report = await StorageService().resolveOutputFile(
        originalName:
            '${FileUtils.getBaseNameWithoutExtension(leftFile.path)}_vs_'
            '${FileUtils.getBaseNameWithoutExtension(rightFile.path)}',
        targetExtension: 'html',
        explicitDestinationPath: reportPath,
      );
    }

    final left = await _instance.open(
      FileSource(leftFile),
      password: leftPassword,
    );
    final changed = <int>[];
    final details = <String>[];
    final reportPages = <_CompareReportPage>[];
    final leftPages = left.pageCount;
    var rightPages = 0;

    try {
      final right = await _instance.open(
        FileSource(rightFile),
        password: rightPassword,
      );
      rightPages = right.pageCount;
      try {
        final shared = math.min(leftPages, rightPages);
        for (var index = 0; index < shared; index++) {
          final leftText = _normalizeText(
            await left.extract(
              pages: PdfPages.single(index),
              format: PdfExtractionFormat.plainText,
            ),
          );
          final rightText = _normalizeText(
            await right.extract(
              pages: PdfPages.single(index),
              format: PdfExtractionFormat.plainText,
            ),
          );

          final leftBytes = await _renderPage(left, index, dpi);
          final rightBytes = await _renderPage(right, index, dpi);
          final reasons = <String>[];
          img.Image? leftImage;
          img.Image? rightImage;
          if (leftText != rightText) {
            reasons.add(_describeTextDiff(leftText, rightText));
          }

          if (leftBytes == null || rightBytes == null) {
            if (leftBytes != rightBytes) {
              reasons.add('could not render one page');
            }
          } else if (!_sameBytes(leftBytes, rightBytes)) {
            leftImage = img.decodePng(leftBytes);
            rightImage = img.decodePng(rightBytes);
            if (leftImage == null || rightImage == null) {
              reasons.add('could not decode a page image');
            } else {
              final ratio = _pixelDifference(leftImage, rightImage);
              if (ratio > pixelThreshold) {
                reasons.add(
                  '${(ratio * 100).toStringAsFixed(2)}% pixels differ',
                );
              }
            }
          }

          if (reasons.isNotEmpty) {
            changed.add(index);
            details.add('Page ${index + 1}: ${reasons.join(', ')}');
          }

          if (report != null && reasons.isNotEmpty) {
            leftImage ??= leftBytes == null ? null : img.decodePng(leftBytes);
            rightImage ??= rightBytes == null
                ? null
                : img.decodePng(rightBytes);
            final regions = leftImage != null && rightImage != null
                ? _diffRegions(leftImage, rightImage)
                : const <_DiffRect>[];
            reportPages.add(
              _CompareReportPage(
                page: index + 1,
                leftPng: leftBytes == null
                    ? null
                    : _annotateDiff(leftBytes, leftImage, regions),
                rightPng: rightBytes == null
                    ? null
                    : _annotateDiff(rightBytes, rightImage, regions),
                summary: reasons.join(', '),
              ),
            );
          }
        }

        if (leftPages != rightPages) {
          details.add('Page count differs: $leftPages vs $rightPages');
          if (report != null) {
            // Extra pages are part of the difference, so show which side owns
            // them instead of leaving the report with nothing to render.
            final longest = math.max(leftPages, rightPages);
            for (var index = shared; index < longest; index++) {
              final inLeft = index < leftPages;
              final inRight = index < rightPages;
              reportPages.add(
                _CompareReportPage(
                  page: index + 1,
                  leftPng: inLeft ? await _renderPage(left, index, dpi) : null,
                  rightPng: inRight
                      ? await _renderPage(right, index, dpi)
                      : null,
                  summary: inLeft && !inRight
                      ? 'Extra page: present only in the left PDF'
                      : !inLeft && inRight
                      ? 'Extra page: present only in the right PDF'
                      : 'Page present in both PDFs',
                ),
              );
            }
          }
        }
      } finally {
        await right.dispose();
      }
    } finally {
      await left.dispose();
    }

    final result = PdfCompareResult(
      leftPages: leftPages,
      rightPages: rightPages,
      changedPages: changed,
      details: details,
      report: report,
    );
    if (report != null) {
      final html = _buildCompareReport(
        leftFile: leftFile,
        rightFile: rightFile,
        result: result,
        pages: reportPages,
      );
      await StorageService.writeAtomically(
        report,
        (temp) => temp.writeAsString(html, flush: true),
      );
    }
    return result;
  }

  /// Rewrites a PDF through the engine to rebuild broken cross-reference
  /// tables and object streams. With [sanitize], it also strips metadata,
  /// JavaScript, and embedded files.
  static Future<File> repair({
    required File sourceFile,
    bool sanitize = false,
    String? password,
    String? outputPath,
    void Function(double progress)? onProgress,
  }) async {
    final base = FileUtils.getBaseNameWithoutExtension(sourceFile.path);
    final output = await StorageService().resolveOutputFile(
      originalName: '${base}_repaired',
      targetExtension: 'pdf',
      explicitDestinationPath: outputPath,
    );

    onProgress?.call(0.2);
    final editor = await _instance.edit(
      FileSource(sourceFile),
      password: password,
    );
    try {
      if (sanitize) {
        await editor.sanitize(
          const PdfSanitizeOptions(
            metadata: true,
            javascript: true,
            embeddedFiles: true,
          ),
        );
      }
      await _writeAtomically(output, (sink) async {
        await editor.save(
          sink,
          options: const PdfSaveOptions.fullRewrite(
            compress: true,
            garbageCollect: true,
          ),
        );
      });
    } finally {
      await editor.dispose();
    }
    onProgress?.call(1.0);
    return output;
  }

  /// Extracts a text layer with a locally installed Tesseract OCR.
  ///
  /// Tesseract is optional and detected at runtime; Converto never downloads
  /// it. With [searchablePdf], a PDF containing the recognized text layer is
  /// also written.
  static Future<PdfOcrResult> ocr({
    required File sourceFile,
    String language = 'eng',
    int dpi = 300,
    bool searchablePdf = false,
    String? password,
    String? outputPath,
    String? pdfOutputPath,
    void Function(double progress)? onProgress,
  }) async {
    if (dpi < 72) throw ArgumentError('OCR DPI must be at least 72.');
    final tesseract = await _findTesseract();
    if (tesseract == null) {
      throw PdfToolUnavailable(
        'OCR needs a local Tesseract installation. Install it with your '
        'package manager (macOS: brew install tesseract; Linux: apt install '
        'tesseract-ocr; Windows: winget install UB-Mannheim.TesseractOCR). '
        'Converto never downloads it for you.',
      );
    }

    final base = FileUtils.getBaseNameWithoutExtension(sourceFile.path);
    final textFile = await StorageService().resolveOutputFile(
      originalName: '${base}_ocr',
      targetExtension: 'txt',
      explicitDestinationPath: outputPath,
    );
    final temporary = await Directory.systemTemp.createTemp('converto-ocr-');
    final pagePdfs = <File>[];

    try {
      final images = await renderPages(
        sourceFile: sourceFile,
        targetFormat: 'png',
        dpi: dpi,
        password: password,
        outputDirectory: temporary.path,
        onProgress: (p) => onProgress?.call(p * 0.5),
      );

      final text = StringBuffer();
      for (var index = 0; index < images.length; index++) {
        final image = images[index];
        final result = await Process.run(tesseract, [
          image.path,
          'stdout',
          '-l',
          language,
        ]);
        if (result.exitCode != 0) {
          throw PdfToolUnavailable(
            'OCR failed on page ${index + 1}: ${result.stderr.toString().trim()}',
          );
        }
        final pageText = result.stdout.toString();
        if (index > 0) text.write('\n\f\n');
        text.write(pageText);

        if (searchablePdf) {
          final pageBase =
              '${temporary.path}${Platform.pathSeparator}searchable_$index';
          final pdfResult = await Process.run(tesseract, [
            image.path,
            pageBase,
            '-l',
            language,
            'pdf',
          ]);
          if (pdfResult.exitCode != 0) {
            throw PdfToolUnavailable(
              'OCR PDF failed on page ${index + 1}: ${pdfResult.stderr.toString().trim()}',
            );
          }
          final pagePdf = File('$pageBase.pdf');
          if (!pagePdf.existsSync()) {
            throw PdfToolUnavailable(
              'OCR did not produce a PDF for page ${index + 1}.',
            );
          }
          pagePdfs.add(pagePdf);
        }
        onProgress?.call(0.5 + 0.4 * ((index + 1) / images.length));
      }

      final extracted = text.toString();
      await StorageService.writeAtomically(
        textFile,
        (temp) => temp.writeAsString(extracted, flush: true),
      );

      File? searchable;
      if (searchablePdf) {
        searchable = await StorageService().resolveOutputFile(
          originalName: '${base}_ocr',
          targetExtension: 'pdf',
          explicitDestinationPath: pdfOutputPath,
        );
        await _writeAtomically(searchable, (sink) async {
          await _instance.merge(pagePdfs.map(FileSource.new).toList(), sink);
        });
      }

      onProgress?.call(1.0);
      return PdfOcrResult(
        textFile: textFile,
        pdfFile: searchable,
        pageCount: images.length,
        characters: extracted.length,
      );
    } finally {
      if (temporary.existsSync()) {
        await temporary.delete(recursive: true);
      }
    }
  }

  /// Whether a local encoder can actually write WebP right now.
  static Future<bool> hasWebpEncoder() => _hasWebpEncoder();

  /// Returns the Tesseract executable version, or null when it is absent.
  static Future<String?> tesseractVersion() async {
    final tesseract = await _findTesseract();
    if (tesseract == null) return null;
    final result = await Process.run(tesseract, ['--version']);
    if (result.exitCode != 0) return null;
    return result.stdout.toString().split('\n').first.trim();
  }

  static Future<File> merge({
    required List<File> files,
    String? outputPath,
    String? outputName,
    void Function(double progress)? onProgress,
  }) async {
    if (files.isEmpty) {
      throw ArgumentError('Merge requires at least one PDF.');
    }

    final output = await StorageService().resolveOutputFile(
      originalName: outputName ?? 'merged',
      targetExtension: 'pdf',
      explicitDestinationPath: outputPath,
    );

    onProgress?.call(0.1);
    await _writeAtomically(output, (sink) async {
      await _instance.merge(files.map(FileSource.new).toList(), sink);
    });
    onProgress?.call(1.0);
    return output;
  }

  static Future<File> watermark({
    required File sourceFile,
    required String text,
    double opacity = 0.25,
    double angle = 45,
    double fontSize = 54,
    PdfLayoutOptions? layout,
    String? outputPath,
    void Function(double progress)? onProgress,
  }) async {
    final base = FileUtils.getBaseNameWithoutExtension(sourceFile.path);
    if (text.trim().isEmpty ||
        !opacity.isFinite ||
        opacity < 0 ||
        opacity > 1 ||
        !angle.isFinite ||
        !fontSize.isFinite ||
        fontSize <= 0) {
      throw ArgumentError(
        'Watermark needs text, opacity 0-1 and finite angle/font size.',
      );
    }
    final output = await StorageService().resolveOutputFile(
      originalName: '${base}_watermarked',
      targetExtension: 'pdf',
      explicitDestinationPath: outputPath,
    );

    if (layout != null)
      return PdfExtendedTools.textWatermark(
        sourceFile: sourceFile,
        outputPath: output.path,
        text: text,
        opacity: opacity,
        angle: angle,
        fontSize: fontSize,
        layout: layout,
        onProgress: onProgress,
      );

    onProgress?.call(0.2);
    await _writeAtomically(output, (sink) async {
      await _instance.watermark(
        FileSource(sourceFile),
        sink,
        text: text,
        style: PdfWatermarkStyle(
          opacity: opacity,
          rotation: angle,
          fontSize: fontSize,
        ),
      );
    });
    onProgress?.call(1.0);
    return output;
  }

  /// Yields one rendered page at a time, retaining its displayed PDF dimensions.
  static Stream<PdfRasterPage> rasterizePages({
    required File sourceFile,
    int dpi = 150,
  }) async* {
    if (dpi < 1) throw ArgumentError('DPI must be positive.');
    final doc = await _instance.open(FileSource(sourceFile));
    try {
      for (var index = 0; index < doc.pageCount; index++) {
        final info = doc.pages[index];
        Uint8List? bytes;
        await for (final page in doc.render(
          pages: PdfPages.single(index),
          size: PdfRenderSize(
            maxWidth: math.max(1, (info.effectiveWidth * dpi / 72).round()),
            maxHeight: math.max(1, (info.effectiveHeight * dpi / 72).round()),
          ),
        )) {
          bytes = page.data;
          break;
        }
        if (bytes == null || bytes.isEmpty) {
          throw StateError('Page ${index + 1} did not render.');
        }
        yield PdfRasterPage(
          bytes,
          info.effectiveWidth,
          info.effectiveHeight,
          doc.pageCount,
        );
      }
    } finally {
      await doc.dispose();
    }
  }

  /// Renders pages, writing one image per page.
  ///
  /// [maxPages] limits the work (used by the single-file converter); null
  /// renders the whole document.
  /// [outputDirectory] is optional; the default Converto output folder is
  /// used when it is omitted.
  static Future<List<File>> renderPages({
    required File sourceFile,
    String targetFormat = 'png',
    int dpi = 150,
    int? maxPages,
    String? password,
    String? outputDirectory,
    String? firstPageOutputPath,
    void Function(double progress)? onProgress,
  }) async {
    final format = targetFormat.replaceAll('.', '').toLowerCase();
    if (dpi < 1) throw ArgumentError('DPI must be positive.');
    if (maxPages != null && maxPages < 1)
      throw ArgumentError('Page limit must be positive.');
    final ext = format == 'jpeg' ? 'jpg' : format;
    if (ext != 'png' && ext != 'jpg' && ext != 'webp') {
      throw ArgumentError(
        'PDF page export supports PNG, JPG, or WebP, not .$targetFormat.',
      );
    }
    if (ext == 'webp' && !await _hasWebpEncoder()) {
      throw PdfToolUnavailable(
        'PDF to WebP needs a working local encoder. Install cwebp (Google '
        'WebP tools) or ImageMagick with WebP support. Converto never writes '
        'PNG bytes under a .webp name and never downloads an encoder.',
      );
    }

    final outputDir = outputDirectory != null
        ? Directory(outputDirectory)
        : await StorageService().getOutputDirectory();
    if (!outputDir.existsSync()) {
      outputDir.createSync(recursive: true);
    }

    final doc = await _instance.open(
      FileSource(sourceFile),
      password: password,
    );
    final base = FileUtils.getBaseNameWithoutExtension(sourceFile.path);
    final results = <File>[];
    final newlyCreated = <File>[];

    final limit = maxPages == null
        ? doc.pageCount
        : (maxPages < doc.pageCount ? maxPages : doc.pageCount);

    try {
      for (var index = 0; index < limit; index++) {
        final info = doc.pages[index];
        final width = (info.effectiveWidth * dpi / 72).round();
        final height = (info.effectiveHeight * dpi / 72).round();

        var pageBytes = Uint8List(0);
        await for (final page in doc.render(
          pages: PdfPages.single(index),
          size: PdfRenderSize(maxWidth: width, maxHeight: height),
        )) {
          pageBytes = page.data;
          break;
        }
        if (pageBytes.isEmpty)
          throw StateError('Page ${index + 1} did not render.');

        final output = index == 0 && firstPageOutputPath != null
            ? await StorageService().resolveOutputFile(
                originalName: '${base}_page_1',
                targetExtension: ext,
                explicitDestinationPath: firstPageOutputPath,
              )
            : File(
                FileUtils.getUniqueFilePath(
                  outputDir.path,
                  '${FileUtils.sanitizeFileName(base)}_page_${index + 1}.$ext',
                ),
              );
        if (!output.existsSync()) newlyCreated.add(output);

        if (ext == 'jpg') {
          final decoded = img.decodePng(pageBytes);
          if (decoded == null) {
            throw Exception('Could not convert page ${index + 1} to JPG.');
          }
          await StorageService.writeAtomically(
            output,
            (temp) => temp.writeAsBytes(
              img.encodeJpg(decoded, quality: 90),
              flush: true,
            ),
          );
        } else if (ext == 'webp') {
          final tempPng = File('${output.path}.source.png');
          final encoded = File('${output.path}.encoded.webp');
          try {
            await tempPng.writeAsBytes(pageBytes, flush: true);
            if (!await _encodeWebp(tempPng.path, encoded.path)) {
              throw PdfToolUnavailable(
                'Could not encode page ${index + 1} as WebP. Check that cwebp '
                'or ImageMagick with WebP support is available.',
              );
            }
            // Only replace an existing destination after a valid WebP exists.
            await StorageService.writeAtomically(
              output,
              (temp) => encoded.copy(temp.path),
            );
          } finally {
            if (tempPng.existsSync()) tempPng.deleteSync();
            if (encoded.existsSync()) encoded.deleteSync();
          }
        } else {
          await StorageService.writeAtomically(
            output,
            (temp) => temp.writeAsBytes(pageBytes, flush: true),
          );
        }

        results.add(output);
        onProgress?.call((index + 1) / limit);
      }
    } catch (_) {
      _deleteFiles(newlyCreated);
      rethrow;
    } finally {
      await doc.dispose();
    }

    return results;
  }

  /// Splits a PDF into chunks of [every] pages.
  static Future<List<File>> splitEvery({
    required File sourceFile,
    int every = 1,
    String? outputDirectory,
    void Function(double progress)? onProgress,
  }) async {
    if (every < 1) {
      throw ArgumentError('Pages per part must be at least 1.');
    }

    final total = await pageCount(sourceFile);
    final base = FileUtils.getBaseNameWithoutExtension(sourceFile.path);
    final directory = await _resolveDirectory(outputDirectory);
    final parts = <File>[];

    try {
      for (var start = 0; start < total; start += every) {
        final end = (start + every).clamp(0, total);
        final output = File(
          FileUtils.getUniqueFilePath(
            directory.path,
            '${base}_part${parts.length + 1}.pdf',
          ),
        );
        await _writeAtomically(output, (sink) async {
          await _instance.extractPages(
            FileSource(sourceFile),
            sink,
            pages: List.generate(end - start, (i) => start + i),
          );
        });
        parts.add(output);
        onProgress?.call(end / total);
      }
    } catch (_) {
      _deleteFiles(parts);
      rethrow;
    }

    return parts;
  }

  /// Splits by a one-based expression such as `1-3, 5, 8-10`.
  /// Each comma-separated group becomes its own PDF.
  static Future<List<File>> splitExpression({
    required File sourceFile,
    required String expression,
    String? outputDirectory,
    void Function(double progress)? onProgress,
  }) async {
    final total = await pageCount(sourceFile);
    final groups = parsePageGroups(expression, total);
    final base = FileUtils.getBaseNameWithoutExtension(sourceFile.path);
    final directory = await _resolveDirectory(outputDirectory);
    final parts = <File>[];

    try {
      for (final pages in groups) {
        final output = File(
          FileUtils.getUniqueFilePath(
            directory.path,
            '${base}_part${parts.length + 1}.pdf',
          ),
        );
        await _writeAtomically(output, (sink) async {
          await _instance.extractPages(
            FileSource(sourceFile),
            sink,
            pages: pages,
          );
        });
        parts.add(output);
        onProgress?.call(parts.length / groups.length);
      }
    } catch (_) {
      _deleteFiles(parts);
      rethrow;
    }

    return parts;
  }

  static Future<File> compress({
    required File sourceFile,
    String level = 'ebook',
    String? outputPath,
    void Function(double progress)? onProgress,
  }) async {
    final policy = switch (level.toLowerCase()) {
      'screen' => PdfImagePolicy.screen,
      'ebook' => PdfImagePolicy.ebook,
      'print' => PdfImagePolicy.print,
      'lossless' => PdfImagePolicy.lossless,
      _ => throw ArgumentError(
        'Compression level must be screen, ebook, print, or lossless.',
      ),
    };

    final base = FileUtils.getBaseNameWithoutExtension(sourceFile.path);
    final output = await StorageService().resolveOutputFile(
      originalName: '${base}_compressed',
      targetExtension: 'pdf',
      explicitDestinationPath: outputPath,
    );

    onProgress?.call(0.2);
    await StorageService.writeAtomically(output, (temp) async {
      final sink = await FileSink.create(temp);
      try {
        await _instance.compress(FileSource(sourceFile), sink, images: policy);
      } finally {
        await sink.close();
      }
      // Optimizing must never make a file larger, including tiny vector PDFs.
      if (await temp.length() >= await sourceFile.length()) {
        await sourceFile.copy(temp.path);
      }
    });
    onProgress?.call(1.0);
    return output;
  }

  /// Crops every page by the given margins, in points.
  static Future<File> crop({
    required File sourceFile,
    double left = 0,
    double top = 0,
    double right = 0,
    double bottom = 0,
    String? outputPath,
    void Function(double progress)? onProgress,
  }) async {
    if ([left, top, right, bottom].any((n) => !n.isFinite || n < 0)) {
      throw ArgumentError('Crop margins cannot be negative.');
    }
    if (left == 0 && top == 0 && right == 0 && bottom == 0) {
      throw ArgumentError('Set at least one crop margin.');
    }

    final base = FileUtils.getBaseNameWithoutExtension(sourceFile.path);
    final output = await StorageService().resolveOutputFile(
      originalName: '${base}_cropped',
      targetExtension: 'pdf',
      explicitDestinationPath: outputPath,
    );

    final editor = await _instance.edit(FileSource(sourceFile));
    try {
      final doc = await _instance.open(FileSource(sourceFile));
      try {
        if (doc.pages.any(
          (page) =>
              left + right >= page.effectiveWidth ||
              top + bottom >= page.effectiveHeight,
        )) {
          throw ArgumentError('Crop margins must leave a positive page area.');
        }
      } finally {
        await doc.dispose();
      }
      onProgress?.call(0.2);
      await editor.cropMargins(
        left: left,
        right: right,
        top: top,
        bottom: bottom,
      );
      await _writeAtomically(output, (sink) async {
        await editor.save(sink);
      });
      onProgress?.call(1.0);
    } finally {
      await editor.dispose();
    }
    return output;
  }

  static Future<File> rotate({
    required File sourceFile,
    int degrees = 90,
    String? outputPath,
    void Function(double progress)? onProgress,
  }) async {
    if (degrees % 90 != 0) {
      throw ArgumentError('Rotation must be 90, 180, or 270 degrees.');
    }

    final base = FileUtils.getBaseNameWithoutExtension(sourceFile.path);
    final output = await StorageService().resolveOutputFile(
      originalName: '${base}_rotated',
      targetExtension: 'pdf',
      explicitDestinationPath: outputPath,
    );

    onProgress?.call(0.2);
    await _writeAtomically(output, (sink) async {
      await _instance.rotateAllPages(
        FileSource(sourceFile),
        sink,
        degrees: degrees,
      );
    });
    onProgress?.call(1.0);
    return output;
  }

  static Future<File> protect({
    required File sourceFile,
    required String password,
    String? ownerPassword,
    String? outputPath,
  }) async {
    if (password.isEmpty) {
      throw ArgumentError('A password is required.');
    }

    final base = FileUtils.getBaseNameWithoutExtension(sourceFile.path);
    final output = await StorageService().resolveOutputFile(
      originalName: '${base}_protected',
      targetExtension: 'pdf',
      explicitDestinationPath: outputPath,
    );

    await _writeAtomically(output, (sink) async {
      await _instance.encrypt(
        FileSource(sourceFile),
        sink,
        encryption: PdfEncryptionConfig(
          ownerPassword: ownerPassword?.isNotEmpty == true
              ? ownerPassword!
              : password,
          userPassword: password,
        ),
      );
    });
    return output;
  }

  static Future<File> unlock({
    required File sourceFile,
    required String password,
    String? outputPath,
  }) async {
    final base = FileUtils.getBaseNameWithoutExtension(sourceFile.path);
    final output = await StorageService().resolveOutputFile(
      originalName: '${base}_unlocked',
      targetExtension: 'pdf',
      explicitDestinationPath: outputPath,
    );

    await _writeAtomically(output, (sink) async {
      await _instance.decrypt(FileSource(sourceFile), sink, password: password);
    });
    return output;
  }

  /// Parses a one-based page expression into zero-based page groups.
  /// Each comma-separated group is an independent output.
  static List<List<int>> parsePageGroups(String expression, int pageCount) {
    final groups = <List<int>>[];

    for (final raw in expression.split(',')) {
      final part = raw.trim();
      if (part.isEmpty) {
        throw const FormatException('Empty page selection.');
      }

      final dash = part.indexOf('-');
      if (dash == -1) {
        final page = int.tryParse(part);
        if (page == null || page < 1 || page > pageCount) {
          throw FormatException('Page "$part" is outside 1-$pageCount.');
        }
        groups.add([page - 1]);
        continue;
      }

      final start = int.tryParse(part.substring(0, dash).trim());
      final end = int.tryParse(part.substring(dash + 1).trim());
      if (start == null ||
          end == null ||
          start < 1 ||
          end < start ||
          end > pageCount) {
        throw FormatException('Range "$part" is outside 1-$pageCount.');
      }
      groups.add(List.generate(end - start + 1, (i) => start - 1 + i));
    }

    return groups;
  }

  /// Extracts pages into one PDF, preserving the order given.
  static Future<File> extractPages({
    required File sourceFile,
    required String expression,
    String? outputPath,
    String? suffix,
    void Function(double progress)? onProgress,
  }) async {
    final total = await pageCount(sourceFile);
    final pages = parsePageList(expression, total);
    return _extractToFile(
      sourceFile: sourceFile,
      pages: pages,
      outputPath: outputPath,
      suffix: suffix ?? 'extracted',
      onProgress: onProgress,
    );
  }

  /// Reorders pages into [order] (one-based), e.g. `3,1,2`.
  static Future<File> organize({
    required File sourceFile,
    required String order,
    String? outputPath,
    void Function(double progress)? onProgress,
  }) async {
    final total = await pageCount(sourceFile);
    final pages = parsePageList(order, total);
    return _extractToFile(
      sourceFile: sourceFile,
      pages: pages,
      outputPath: outputPath,
      suffix: 'organized',
      onProgress: onProgress,
    );
  }

  /// Removes pages (one-based selection) and keeps the rest in order.
  static Future<File> deletePages({
    required File sourceFile,
    required String expression,
    String? outputPath,
    void Function(double progress)? onProgress,
  }) async {
    final total = await pageCount(sourceFile);
    final remove = parsePageList(expression, total).toSet();
    final keep = [
      for (var i = 0; i < total; i++)
        if (!remove.contains(i)) i,
    ];
    if (keep.isEmpty) {
      throw ArgumentError('That selection would delete every page.');
    }
    return _extractToFile(
      sourceFile: sourceFile,
      pages: keep,
      outputPath: outputPath,
      suffix: 'pages-removed',
      onProgress: onProgress,
    );
  }

  /// Splits so every part stays at or under [maxBytes].
  ///
  /// It probes candidate page counts with the engine before writing, so a
  /// single oversized page still becomes its own part.
  static Future<List<File>> splitBySize({
    required File sourceFile,
    required int maxBytes,
    bool allowOversizedPages = false,
    String? outputDirectory,
    void Function(double progress)? onProgress,
  }) async {
    if (maxBytes < 1) {
      throw ArgumentError('Size limit must be at least 1 byte.');
    }

    final total = await pageCount(sourceFile);
    final base = FileUtils.getBaseNameWithoutExtension(sourceFile.path);
    final directory = await _resolveDirectory(outputDirectory);
    final parts = <File>[];

    try {
      var start = 0;
      while (start < total) {
        final remaining = total - start;
        // Seed the search with the average bytes per page. Most PDFs have a
        // fairly even page size, so this lands close to the answer and cuts
        // the number of trial extractions sharply.
        final averageBytes = sourceFile.lengthSync() / math.max(total, 1);
        final estimate = (maxBytes / math.max(averageBytes, 1)).floor().clamp(
          1,
          remaining,
        );

        Future<bool> fits(int count) async {
          final counter = _CountingSink();
          await _instance.extractPages(
            FileSource(sourceFile),
            counter,
            pages: List.generate(count, (i) => start + i),
          );
          return counter.length <= maxBytes;
        }

        var low = 1;
        var high = remaining;
        var best = 0;
        if (await fits(estimate)) {
          best = estimate;
          low = estimate + 1;
        } else {
          high = estimate - 1;
        }
        while (low <= high) {
          final middle = (low + high) ~/ 2;
          if (await fits(middle)) {
            best = middle;
            low = middle + 1;
          } else {
            high = middle - 1;
          }
        }

        if (best == 0) {
          if (allowOversizedPages) {
            best = 1;
          } else {
            throw ArgumentError(
              'Page ${start + 1} cannot fit in $maxBytes bytes. Increase --size.',
            );
          }
        }

        final output = File(
          FileUtils.getUniqueFilePath(
            directory.path,
            '${base}_part${parts.length + 1}.pdf',
          ),
        );
        await _writeAtomically(output, (sink) async {
          await _instance.extractPages(
            FileSource(sourceFile),
            sink,
            pages: List.generate(best, (i) => start + i),
          );
        });
        parts.add(output);
        start += best;
        onProgress?.call(start / total);
      }
    } catch (_) {
      _deleteFiles(parts);
      rethrow;
    }

    return parts;
  }

  /// Writes `Page X of N` in the bottom-right corner of every page.
  static Future<File> pageNumbers({
    required File sourceFile,
    PdfLayoutOptions? layout,
    String? outputPath,
    void Function(double progress)? onProgress,
  }) async {
    final total = await pageCount(sourceFile);
    final base = FileUtils.getBaseNameWithoutExtension(sourceFile.path);
    final output = await StorageService().resolveOutputFile(
      originalName: '${base}_numbered',
      targetExtension: 'pdf',
      explicitDestinationPath: outputPath,
    );

    if (layout != null)
      return PdfExtendedTools.textWatermark(
        sourceFile: sourceFile,
        outputPath: output.path,
        text: '',
        opacity: .9,
        angle: 0,
        fontSize: 9,
        layout: layout,
        numbers: true,
        onProgress: onProgress,
      );

    await withPageNumberEditor(FileSource(sourceFile), (editor) async {
      for (var index = 0; index < total; index++) {
        await editor.addWatermark(
          index,
          'Page ${index + 1} of $total',
          style: const PdfWatermarkStyle(
            fontSize: 9,
            opacity: 0.9,
            rotation: 0,
            color: PdfColor.black,
          ),
          position: const PdfWatermarkPosition.corner(
            PdfCorner.bottomRight,
            marginX: 24,
            marginY: 20,
          ),
        );
        onProgress?.call((index + 1) / total);
      }
      await _writeAtomically(output, (sink) async {
        await editor.save(sink);
      });
    });
    return output;
  }

  static Future<PdfInfo> info(File sourceFile, {String? password}) async {
    final doc = await _instance.open(
      FileSource(sourceFile),
      password: password,
    );
    try {
      final first = doc.pages.isEmpty ? null : doc.pages.first;
      var signatures = <PdfSignatureInfo>[];
      try {
        signatures = await doc.signatures;
      } catch (_) {
        // Some malformed signature dictionaries should not block inspection.
      }
      bool? signaturesValid;
      if (signatures.isNotEmpty) {
        try {
          signaturesValid = await doc.verifySignatures();
        } catch (_) {
          signaturesValid = null;
        }
      }
      return PdfInfo(
        file: sourceFile,
        pageCount: doc.pageCount,
        version: doc.version,
        title: doc.title,
        author: doc.author,
        subject: doc.subject,
        isEncrypted: doc.isEncrypted,
        isTagged: doc.isTagged,
        firstPageWidth: first?.effectiveWidth ?? 0,
        firstPageHeight: first?.effectiveHeight ?? 0,
        rotation: first?.rotation ?? 0,
        signatureSummaries: [
          for (final signature in signatures)
            '${signature.signerName ?? 'Unknown signer'} · '
                '${signature.isValid ? 'valid' : 'unverified'}'
                '${signature.signingTime == null ? '' : ' · ${signature.signingTime!.toIso8601String().split('T').first}'}',
        ],
        signaturesValid: signaturesValid,
      );
    } finally {
      await doc.dispose();
    }
  }

  /// Converts a PDF to Word, Excel, or PowerPoint — entirely on-device.
  static Future<File> convertToOffice({
    required File sourceFile,
    required String format,
    String? outputPath,
    String? password,
    void Function(double progress)? onProgress,
  }) async {
    final ext = format.replaceAll('.', '').toLowerCase();
    final target = switch (ext) {
      'docx' => PdfDocumentFormat.docx,
      'xlsx' => PdfDocumentFormat.xlsx,
      'pptx' => PdfDocumentFormat.pptx,
      _ => throw ArgumentError('PDF to Office supports docx, xlsx, or pptx.'),
    };

    final base = FileUtils.getBaseNameWithoutExtension(sourceFile.path);
    final output = await StorageService().resolveOutputFile(
      originalName: base,
      targetExtension: ext,
      explicitDestinationPath: outputPath,
    );

    onProgress?.call(0.2);
    await _writeAtomically(output, (sink) async {
      await _instance.convertTo(
        FileSource(sourceFile),
        sink,
        format: target,
        password: password,
      );
    });
    onProgress?.call(1.0);
    return output;
  }

  static Future<File> convertToPdfA({
    required File sourceFile,
    int level = 2,
    String? outputPath,
    void Function(double progress)? onProgress,
  }) async {
    if (level < 1 || level > 3) {
      throw ArgumentError('PDF/A level must be 1, 2, or 3.');
    }

    final base = FileUtils.getBaseNameWithoutExtension(sourceFile.path);
    final output = await StorageService().resolveOutputFile(
      originalName: '${base}_pdfa',
      targetExtension: 'pdf',
      explicitDestinationPath: outputPath,
    );

    onProgress?.call(0.2);
    await _writeAtomically(output, (sink) async {
      await _instance.convertToPdfA(FileSource(sourceFile), sink, level: level);
    });
    onProgress?.call(1.0);
    return output;
  }

  /// Permanently redacts every occurrence of [query]. Text-based PDFs only;
  /// scanned pages need OCR before this can find anything.
  static Future<PdfRedactResult> redactText({
    required File sourceFile,
    required String query,
    String? outputPath,
    void Function(double progress)? onProgress,
  }) async {
    if (query.trim().isEmpty) {
      throw ArgumentError('Redaction text cannot be empty.');
    }

    final doc = await _instance.open(FileSource(sourceFile));
    final matches = <int, List<PdfRect>>{};
    try {
      for (var page = 0; page < doc.pageCount; page++) {
        final results = await doc.search(
          query: query,
          pages: PdfPages.single(page),
        );
        if (results.isNotEmpty) {
          matches[page] = [for (final result in results) result.rect];
        }
      }
    } finally {
      await doc.dispose();
    }

    final count = matches.values.fold<int>(0, (sum, r) => sum + r.length);
    if (count == 0) {
      throw ArgumentError(
        'No matches for "$query". Scanned PDFs need OCR first.',
      );
    }

    final base = FileUtils.getBaseNameWithoutExtension(sourceFile.path);
    final output = await StorageService().resolveOutputFile(
      originalName: '${base}_redacted',
      targetExtension: 'pdf',
      explicitDestinationPath: outputPath,
    );

    final editor = await _instance.edit(FileSource(sourceFile));
    try {
      for (final entry in matches.entries) {
        for (final rect in entry.value) {
          await editor.addRedaction(entry.key, rect);
        }
      }
      await editor.applyRedactions();
      await _writeAtomically(output, (sink) async {
        await editor.save(sink);
      });
    } finally {
      await editor.dispose();
    }

    onProgress?.call(1.0);
    return PdfRedactResult(file: output, matches: count);
  }

  static Future<File> _extractToFile({
    required File sourceFile,
    required List<int> pages,
    required String suffix,
    String? outputPath,
    void Function(double progress)? onProgress,
  }) async {
    final base = FileUtils.getBaseNameWithoutExtension(sourceFile.path);
    final output = await StorageService().resolveOutputFile(
      originalName: '${base}_$suffix',
      targetExtension: 'pdf',
      explicitDestinationPath: outputPath,
    );

    onProgress?.call(0.2);
    await _writeAtomically(output, (sink) async {
      await _instance.extractPages(FileSource(sourceFile), sink, pages: pages);
    });
    onProgress?.call(1.0);
    return output;
  }

  /// Parses a one-based selection into zero-based indices, preserving order.
  static List<int> parsePageList(String expression, int pageCount) {
    return parsePageGroups(
      expression,
      pageCount,
    ).expand((group) => group).toList(growable: false);
  }

  static Future<Directory> _resolveDirectory(String? outputDirectory) async {
    if (outputDirectory == null) {
      return StorageService().getOutputDirectory();
    }
    final directory = Directory(outputDirectory);
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }
    return directory;
  }

  static Future<void> _writeAtomically(
    File output,
    Future<void> Function(FileSink sink) action,
  ) async {
    await StorageService.writeAtomically(output, (temp) async {
      final sink = await FileSink.create(temp);
      try {
        await action(sink);
      } finally {
        await sink.close();
      }
    });
  }

  static void _deleteFiles(List<File> files) {
    for (final file in files) {
      if (file.existsSync()) file.deleteSync();
    }
  }

  static String _normalizeText(String text) =>
      text.replaceAll(RegExp(r'\s+'), ' ').trim();

  static String _describeTextDiff(String left, String right) {
    final leftWords = left.split(' ').where((word) => word.isNotEmpty).toList();
    final rightWords = right
        .split(' ')
        .where((word) => word.isNotEmpty)
        .toList();
    final diff = _wordDiff(leftWords, rightWords);
    if (diff.truncated) {
      return 'text differs (~${leftWords.length} vs ${rightWords.length} words)';
    }

    final counts = <String>[
      if (diff.added.isNotEmpty) '+${diff.added.length}',
      if (diff.removed.isNotEmpty) '-${diff.removed.length}',
    ];
    final sample = <String>[
      for (final word in diff.added.take(4)) '+"$word"',
      for (final word in diff.removed.take(4)) '-"$word"',
    ].join(' ');
    if (counts.isEmpty) return 'text differs';
    return 'text differs (${counts.join(' ')}'
        '${sample.isEmpty ? '' : ': $sample'})';
  }

  static _WordDiff _wordDiff(List<String> left, List<String> right) {
    const cap = 300;
    if (left.length > cap || right.length > cap) {
      return const _WordDiff(truncated: true);
    }

    final rows = left.length;
    final columns = right.length;
    final lengths = List.generate(
      rows + 1,
      (_) => List<int>.filled(columns + 1, 0),
    );
    for (var i = rows - 1; i >= 0; i--) {
      for (var j = columns - 1; j >= 0; j--) {
        lengths[i][j] = left[i].toLowerCase() == right[j].toLowerCase()
            ? lengths[i + 1][j + 1] + 1
            : math.max(lengths[i + 1][j], lengths[i][j + 1]);
      }
    }

    final added = <String>[];
    final removed = <String>[];
    var i = 0;
    var j = 0;
    while (i < rows && j < columns) {
      if (left[i].toLowerCase() == right[j].toLowerCase()) {
        i++;
        j++;
      } else if (lengths[i + 1][j] >= lengths[i][j + 1]) {
        removed.add(left[i++]);
      } else {
        added.add(right[j++]);
      }
    }
    while (i < rows) {
      removed.add(left[i++]);
    }
    while (j < columns) {
      added.add(right[j++]);
    }

    return _WordDiff(added: added, removed: removed);
  }

  static bool _sameBytes(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static Future<Uint8List?> _renderPage(PdfDoc doc, int index, int dpi) async {
    final info = doc.pages[index];
    final width = (info.effectiveWidth * dpi / 72).round().clamp(1, 5000);
    final height = (info.effectiveHeight * dpi / 72).round().clamp(1, 5000);
    await for (final page in doc.render(
      pages: PdfPages.single(index),
      size: PdfRenderSize(maxWidth: width, maxHeight: height),
    )) {
      return page.data;
    }
    return null;
  }

  static double _pixelDifference(img.Image left, img.Image right) {
    if (left.width != right.width || left.height != right.height) return 1;
    final stepX = math.max(1, left.width ~/ 600);
    final stepY = math.max(1, left.height ~/ 600);
    var different = 0;
    var total = 0;
    for (var y = 0; y < left.height; y += stepY) {
      for (var x = 0; x < left.width; x += stepX) {
        final a = left.getPixel(x, y);
        final b = right.getPixel(x, y);
        final delta = (a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs();
        if (delta > 24) different++;
        total++;
      }
    }
    return total == 0 ? 0 : different / total;
  }

  static List<_DiffRect> _diffRegions(img.Image left, img.Image right) {
    if (left.width != right.width || left.height != right.height) {
      return [
        _DiffRect(
          left: 0,
          top: 0,
          right: math.min(left.width, right.width) - 1,
          bottom: math.min(left.height, right.height) - 1,
        ),
      ];
    }

    final tile = math.max(8, math.min(left.width, left.height) ~/ 32);
    final columns = (left.width / tile).ceil();
    final rows = (left.height / tile).ceil();
    final marked = List.generate(
      rows,
      (_) => List<bool>.filled(columns, false),
    );

    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < columns; column++) {
        var changed = 0;
        var total = 0;
        for (
          var y = row * tile;
          y < math.min((row + 1) * tile, left.height);
          y++
        ) {
          for (
            var x = column * tile;
            x < math.min((column + 1) * tile, left.width);
            x++
          ) {
            final a = left.getPixel(x, y);
            final b = right.getPixel(x, y);
            final delta =
                (a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs();
            if (delta > 24) changed++;
            total++;
          }
        }
        if (total > 0 && changed / total > 0.01) {
          marked[row][column] = true;
        }
      }
    }

    final parent = List<int>.generate(rows * columns, (index) => index);
    int find(int index) {
      while (parent[index] != index) {
        parent[index] = parent[parent[index]];
        index = parent[index];
      }
      return index;
    }

    void union(int a, int b) {
      final rootA = find(a);
      final rootB = find(b);
      if (rootA != rootB) parent[rootB] = rootA;
    }

    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < columns; column++) {
        if (!marked[row][column]) continue;
        final index = row * columns + column;
        if (column + 1 < columns && marked[row][column + 1]) {
          union(index, index + 1);
        }
        if (row + 1 < rows && marked[row + 1][column]) {
          union(index, index + columns);
        }
        if (row + 1 < rows &&
            column + 1 < columns &&
            marked[row + 1][column + 1]) {
          union(index, index + columns + 1);
        }
      }
    }

    final bounds = <int, List<int>>{};
    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < columns; column++) {
        if (!marked[row][column]) continue;
        final root = find(row * columns + column);
        final current = bounds[root] ?? [row, column, row, column];
        if (row < current[0]) current[0] = row;
        if (column < current[1]) current[1] = column;
        if (row > current[2]) current[2] = row;
        if (column > current[3]) current[3] = column;
        bounds[root] = current;
      }
    }

    final regions = <_DiffRect>[];
    for (final bound in bounds.values) {
      final region = _DiffRect(
        left: bound[1] * tile,
        top: bound[0] * tile,
        right: math.min((bound[3] + 1) * tile, left.width) - 1,
        bottom: math.min((bound[2] + 1) * tile, left.height) - 1,
      );
      if (region.width >= 4 && region.height >= 4) regions.add(region);
    }
    regions.sort((a, b) => (b.width * b.height).compareTo(a.width * a.height));
    if (regions.length <= 40) return regions;
    return [
      _DiffRect(
        left: 0,
        top: 0,
        right: left.width - 1,
        bottom: left.height - 1,
      ),
    ];
  }

  static Uint8List _annotateDiff(
    Uint8List png,
    img.Image? image,
    List<_DiffRect> regions,
  ) {
    if (image == null || regions.isEmpty) return png;
    final copy = image.clone();
    final marker = img.ColorRgba8(220, 38, 38, 255);
    for (final region in regions) {
      img.drawRect(
        copy,
        x1: region.left,
        y1: region.top,
        x2: region.right,
        y2: region.bottom,
        color: marker,
        thickness: 3,
      );
    }
    return Uint8List.fromList(img.encodePng(copy));
  }

  static String _buildCompareReport({
    required File leftFile,
    required File rightFile,
    required PdfCompareResult result,
    required List<_CompareReportPage> pages,
  }) {
    final out = StringBuffer();
    out.writeln('<!DOCTYPE html>');
    out.writeln('<html lang="en">');
    out.writeln('<head>');
    out.writeln('<meta charset="utf-8">');
    out.writeln(
      '<meta name="viewport" content="width=device-width, initial-scale=1">',
    );
    out.writeln('<title>PDF comparison</title>');
    out.writeln('<style>');
    out.writeln(
      'body{font-family:system-ui,-apple-system,"Segoe UI",sans-serif;'
      'background:#f4f4f5;color:#18181b;margin:0;padding:2rem 1rem}',
    );
    out.writeln(
      'main{max-width:1200px;margin:0 auto}h1{font-size:1.6rem;margin:0 0 .4rem}',
    );
    out.writeln(
      '.meta{color:#52525b;font-size:.9rem;word-break:break-word;margin:0 0 1.2rem}',
    );
    out.writeln(
      '.verdict{display:inline-block;padding:.35rem .65rem;border-radius:6px;'
      'font-weight:600;background:#dcfce7;color:#166534}',
    );
    out.writeln('.verdict.changed{background:#fef3c7;color:#92400e}');
    out.writeln(
      'ul.details{color:#52525b;font-size:.9rem;line-height:1.5;margin:.8rem 0 1.6rem}',
    );
    out.writeln(
      '.page{background:#fff;border:1px solid #d4d4d8;border-radius:10px;'
      'padding:1rem;margin:0 0 1.5rem}',
    );
    out.writeln('h2{font-size:1rem;margin:0 0 .2rem}');
    out.writeln('.reason{color:#9a3412;font-size:.85rem;margin:.2rem 0 .8rem}');
    out.writeln('.pair{display:grid;grid-template-columns:1fr 1fr;gap:1rem}');
    out.writeln('figure{margin:0}');
    out.writeln(
      'figcaption{font-size:.75rem;color:#71717a;margin-bottom:.35rem;'
      'text-transform:uppercase;letter-spacing:.05em}',
    );
    out.writeln(
      'img{display:block;width:100%;height:auto;border:1px solid #e4e4e7;'
      'border-radius:4px;background:#fff}',
    );
    out.writeln(
      '.missing{padding:2rem;border:1px dashed #d4d4d8;border-radius:4px;'
      'color:#71717a;text-align:center}',
    );
    out.writeln(
      '@media(max-width:720px){.pair{grid-template-columns:1fr}body{padding:1rem .5rem}}',
    );
    out.writeln('</style>');
    out.writeln('</head>');
    out.writeln('<body><main>');
    out.writeln('<h1>PDF comparison</h1>');
    out.writeln(
      '<p class="meta">${_escapeHtml(leftFile.path)} '
      '(${result.leftPages} pages) &#8596; '
      '${_escapeHtml(rightFile.path)} (${result.rightPages} pages)</p>',
    );
    final verdict = result.identical
        ? 'Identical on every shared page'
        : [
            if (result.changedPages.isNotEmpty)
              '${result.changedPages.length} changed page${result.changedPages.length == 1 ? '' : 's'}',
            if (result.leftPages != result.rightPages) 'page count differs',
          ].join(' · ');
    out.writeln(
      '<p class="verdict${result.identical ? '' : ' changed'}">'
      '${_escapeHtml(verdict)}'
      '</p>',
    );
    if (result.details.isNotEmpty) {
      out.writeln('<ul class="details">');
      for (final detail in result.details) {
        out.writeln('<li>${_escapeHtml(detail)}</li>');
      }
      out.writeln('</ul>');
    }
    if (pages.isEmpty) {
      out.writeln(
        '<p class="details">No changed pages to display. '
        'The side-by-side view is only generated for changed pages.</p>',
      );
    } else {
      for (final page in pages) {
        out.writeln('<section class="page">');
        out.writeln('<h2>Page ${page.page}</h2>');
        out.writeln('<p class="reason">${_escapeHtml(page.summary)}</p>');
        out.writeln('<div class="pair">');
        out.writeln('<figure><figcaption>Left</figcaption>');
        out.writeln(
          page.leftPng == null
              ? '<div class="missing">Page not present</div>'
              : '<img alt="Left page ${page.page}" src="data:image/png;base64,${base64Encode(page.leftPng!)}">',
        );
        out.writeln('</figure>');
        out.writeln('<figure><figcaption>Right</figcaption>');
        out.writeln(
          page.rightPng == null
              ? '<div class="missing">Page not present</div>'
              : '<img alt="Right page ${page.page}" src="data:image/png;base64,${base64Encode(page.rightPng!)}">',
        );
        out.writeln('</figure>');
        out.writeln('</div></section>');
      }
    }
    out.writeln('</main></body></html>');
    return out.toString();
  }

  static String _escapeHtml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static Future<String?> _findTesseract() async {
    if (Platform.environment['CONVERTO_DISABLE_HELPERS'] == '1') return null;
    try {
      final probe = await Process.run(Platform.isWindows ? 'where' : 'which', [
        'tesseract',
      ]);
      if (probe.exitCode == 0) {
        final found = probe.stdout.toString().trim().split('\n').first.trim();
        if (found.isNotEmpty) return found;
      }
    } catch (_) {}
    try {
      final direct = await Process.run('tesseract', ['--version']);
      if (direct.exitCode == 0) return 'tesseract';
    } catch (_) {}
    return null;
  }

  static Future<bool> _hasWebpEncoder() async {
    if (Platform.environment['CONVERTO_DISABLE_HELPERS'] == '1') return false;

    // An executable being present is not enough: sips --version succeeds on
    // macOS builds that cannot write WebP at all. Probe with a real 2x2 PNG
    // and validate the container before promising PDF-to-WebP support.
    final probe = await Directory.systemTemp.createTemp('converto-webp-probe-');
    try {
      final png = File('${probe.path}${Platform.pathSeparator}probe.png');
      await png.writeAsBytes(
        img.encodePng(img.Image(width: 2, height: 2)),
        flush: true,
      );
      return await _encodeWebp(
        png.path,
        '${probe.path}${Platform.pathSeparator}probe.webp',
      );
    } finally {
      if (probe.existsSync()) await probe.delete(recursive: true);
    }
  }

  static Future<bool> _encodeWebp(String pngPath, String webpPath) async {
    final attempts = <String, List<String>>{
      'cwebp': ['-quiet', '-q', '90', '-o', webpPath, pngPath],
      'magick': [pngPath, webpPath],
    };

    for (final entry in attempts.entries) {
      try {
        final result = await Process.run(entry.key, entry.value);
        if (result.exitCode != 0) continue;
        final encoded = File(webpPath);
        if (!encoded.existsSync()) continue;
        final bytes = await encoded.readAsBytes();
        if (bytes.length >= 12 &&
            bytes[0] == 0x52 &&
            bytes[1] == 0x49 &&
            bytes[2] == 0x46 &&
            bytes[3] == 0x46 &&
            bytes[8] == 0x57 &&
            bytes[9] == 0x45 &&
            bytes[10] == 0x42 &&
            bytes[11] == 0x50) {
          return true;
        }
        if (encoded.existsSync()) encoded.deleteSync();
      } catch (_) {}
    }
    return false;
  }
}

/// A local helper (Tesseract or cwebp) is required but unavailable.
class PdfToolUnavailable implements Exception {
  const PdfToolUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}

class PdfRasterPage {
  final Uint8List png;
  final double width;
  final double height;
  final int pageCount;
  const PdfRasterPage(this.png, this.width, this.height, this.pageCount);
}

class PdfInfo {
  const PdfInfo({
    required this.file,
    required this.pageCount,
    required this.version,
    required this.title,
    required this.author,
    required this.subject,
    required this.isEncrypted,
    required this.isTagged,
    required this.firstPageWidth,
    required this.firstPageHeight,
    required this.rotation,
    required this.signatureSummaries,
    required this.signaturesValid,
  });

  final File file;
  final int pageCount;
  final String version;
  final String? title;
  final String? author;
  final String? subject;
  final bool isEncrypted;
  final bool isTagged;
  final double firstPageWidth;
  final double firstPageHeight;
  final int rotation;
  final List<String> signatureSummaries;
  final bool? signaturesValid;
}

class _DiffRect {
  const _DiffRect({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final int left;
  final int top;
  final int right;
  final int bottom;

  int get width => right - left + 1;
  int get height => bottom - top + 1;
}

class _CompareReportPage {
  const _CompareReportPage({
    required this.page,
    required this.leftPng,
    required this.rightPng,
    required this.summary,
  });

  final int page;
  final Uint8List? leftPng;
  final Uint8List? rightPng;
  final String summary;
}

class _WordDiff {
  const _WordDiff({
    this.added = const [],
    this.removed = const [],
    this.truncated = false,
  });

  final List<String> added;
  final List<String> removed;
  final bool truncated;
}

class PdfCompareResult {
  const PdfCompareResult({
    required this.leftPages,
    required this.rightPages,
    required this.changedPages,
    required this.details,
    this.report,
  });

  final int leftPages;
  final int rightPages;
  final List<int> changedPages;
  final List<String> details;
  final File? report;

  bool get identical =>
      leftPages == rightPages && changedPages.isEmpty && details.isEmpty;
}

class PdfOcrResult {
  const PdfOcrResult({
    required this.textFile,
    required this.pdfFile,
    required this.pageCount,
    required this.characters,
  });

  final File textFile;
  final File? pdfFile;
  final int pageCount;
  final int characters;
}

class PdfRedactResult {
  const PdfRedactResult({required this.file, required this.matches});

  final File file;
  final int matches;
}

class _CountingSink implements DataSink {
  int length = 0;

  @override
  void write(Uint8List chunk) => length += chunk.length;
}
