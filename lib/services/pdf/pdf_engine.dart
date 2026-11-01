import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdf_manipulator/io.dart';
import 'package:pdf_manipulator/pdf_manipulator.dart';

import '../../core/utils/file_utils.dart';
import '../storage_service.dart';
import 'page_number_bridge.dart';

/// One bundled, entirely local PDF engine for the operations the old
/// converter could not do on its own.
///
/// It replaces the Ghostscript / pdfunite / pdftoppm requirements for:
/// merge, watermark, page rendering, split, compress, rotate, protect, and
/// unlock. Everything runs on the user's machine; no network calls and no
/// per-file quotas.
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
    String? outputDirectory,
    String? firstPageOutputPath,
    void Function(double progress)? onProgress,
  }) async {
    final format = targetFormat.replaceAll('.', '').toLowerCase();
    if (dpi < 1) throw ArgumentError('DPI must be positive.');
    if (maxPages != null && maxPages < 1)
      throw ArgumentError('Page limit must be positive.');
    final ext = format == 'jpeg' ? 'jpg' : format;
    if (ext != 'png' && ext != 'jpg') {
      throw ArgumentError(
        'PDF page export supports PNG or JPG, not .$targetFormat.',
      );
    }

    final outputDir = outputDirectory != null
        ? Directory(outputDirectory)
        : await StorageService().getOutputDirectory();
    if (!outputDir.existsSync()) {
      outputDir.createSync(recursive: true);
    }

    final doc = await _instance.open(FileSource(sourceFile));
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
        var probe = 1;
        var lastFit = 0;

        while (probe <= remaining) {
          final counter = _CountingSink();
          await _instance.extractPages(
            FileSource(sourceFile),
            counter,
            pages: List.generate(probe, (i) => start + i),
          );
          if (counter.length <= maxBytes) {
            lastFit = probe;
            probe *= 2;
          } else {
            break;
          }
        }

        var low = lastFit > 0 ? lastFit : 1;
        var high = probe.clamp(1, remaining);
        var best = lastFit;
        while (low <= high) {
          final middle = (low + high) ~/ 2;
          final counter = _CountingSink();
          await _instance.extractPages(
            FileSource(sourceFile),
            counter,
            pages: List.generate(middle, (i) => start + i),
          );
          if (counter.length <= maxBytes) {
            best = middle;
            low = middle + 1;
          } else {
            high = middle - 1;
          }
        }

        if (best == 0) {
          throw ArgumentError(
            'Page ${start + 1} cannot fit in $maxBytes bytes. Increase --size.',
          );
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
