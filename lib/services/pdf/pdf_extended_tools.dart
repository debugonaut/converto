import 'dart:io';
import 'dart:math' as math;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pdf_manipulator/io.dart';
import 'package:pdf_manipulator/pdf_manipulator.dart';
import '../../models/pdf_layout_options.dart';
import '../storage_service.dart';
import 'pdf_engine.dart';
import 'pdf_rewrite_inspection.dart';
import 'page_number_bridge.dart';

/// Small adapters for local operations not exposed by the original app.
class PdfExtendedTools {
  static Future<File> _destination(File source, String path) async {
    if (p.equals(
      p.normalize(source.absolute.path),
      p.normalize(File(path).absolute.path),
    ))
      throw ArgumentError(
        'Choose a new output file; the source must stay unchanged.',
      );
    return File(path);
  }

  static Future<void> _save(
    PdfEditor editor,
    File output, {
    Future<void> Function(File)? verify,
  }) => StorageService.writeAtomically(output, (temporary) async {
    final sink = await FileSink.create(temporary);
    try {
      await editor.save(
        sink,
        options: const PdfSaveOptions.fullRewrite(
          compress: true,
          garbageCollect: true,
        ),
      );
    } finally {
      await sink.close();
    }
    await verify?.call(temporary);
  });
  static Future<File> clean({
    required File sourceFile,
    required String outputPath,
    bool metadata = true,
    bool javascript = true,
    bool attachments = true,
    String? password,
  }) async {
    if (!metadata && !javascript && !attachments)
      throw ArgumentError('Choose at least one kind of content to remove.');
    final output = await _destination(sourceFile, outputPath), pdf = Pdf();
    try {
      final editor = await pdf.edit(FileSource(sourceFile), password: password);
      try {
        // The native rewrite does not automatically carry the source Info
        // dictionary. Keep the supported fields when metadata is unselected.
        if (!metadata) {
          final doc = await pdf.open(
            FileSource(sourceFile),
            password: password,
          );
          try {
            if (doc.title?.isNotEmpty ?? false)
              await editor.setTitle(doc.title!);
            if (doc.author?.isNotEmpty ?? false)
              await editor.setAuthor(doc.author!);
            if (doc.subject?.isNotEmpty ?? false)
              await editor.setSubject(doc.subject!);
            if (doc.producer?.isNotEmpty ?? false)
              await editor.setProducer(doc.producer!);
            if (doc.creationDate?.isNotEmpty ?? false)
              await editor.setCreationDate(doc.creationDate!);
          } finally {
            await doc.dispose();
          }
        }
        await editor.sanitize(
          PdfSanitizeOptions(
            metadata: metadata,
            javascript: javascript,
            embeddedFiles: attachments,
          ),
        );
        await _save(
          editor,
          output,
          verify: (file) async {
            final rewritten = await PdfRewriteInspection.read(file);
            if (attachments &&
                rewritten.containsAnyName({
                  '/AF',
                  '/EF',
                  '/EmbeddedFile',
                  '/EmbeddedFiles',
                  '/FileAttachment',
                })) {
              throw ArgumentError(
                'This PDF uses attachments that cannot be safely removed.',
              );
            }
            if (javascript &&
                rewritten.containsAnyName({'/JavaScript', '/JS'})) {
              throw ArgumentError(
                'This PDF uses JavaScript that cannot be safely removed.',
              );
            }
            if (metadata && rewritten.containsAnyName({'/Metadata'})) {
              throw ArgumentError(
                'This PDF uses metadata that cannot be safely removed.',
              );
            }
          },
        );
      } finally {
        await editor.dispose();
      }
    } finally {
      await pdf.dispose();
    }
    return output;
  }

  static Future<File> flatten({
    required File sourceFile,
    required String outputPath,
    bool forms = true,
    bool annotations = true,
    String? password,
  }) async {
    if (!forms && !annotations)
      throw ArgumentError('Choose forms, annotations or both to flatten.');
    final output = await _destination(sourceFile, outputPath), pdf = Pdf();
    try {
      final doc = await pdf.open(FileSource(sourceFile), password: password);
      try {
        final fields = await doc.formFields;
        if (annotations && !forms && fields.isNotEmpty) {
          throw ArgumentError('Choose form flattening too for this PDF.');
        }
        if (forms) {
          for (final field in fields) {
            if (field.type == PdfFormFieldType.unknown ||
                field.type == PdfFormFieldType.signature) {
              throw ArgumentError(
                'This PDF contains an unsupported form field. Its appearance cannot be safely flattened.',
              );
            }
            final value = field.value;
            if (value is PdfTextValue && value.text.runes.any((r) => r > 255))
              throw ArgumentError(
                'Flattening non-Latin form values needs a bundled fallback font; keep this form interactive for now.',
              );
          }
        }
      } finally {
        await doc.dispose();
      }
      final editor = await pdf.edit(FileSource(sourceFile), password: password);
      try {
        if (annotations) {
          // Normalize input before inspecting it so the check works with
          // incremental updates, encrypted inputs and compressed xrefs.
          await output.parent.create(recursive: true);
          final scratch = await output.parent.createTemp('.converto-flatten-');
          try {
            final preflight = File(p.join(scratch.path, 'preflight.pdf'));
            await _save(
              editor,
              preflight,
              verify: (file) async {
                final document = await PdfRewriteInspection.read(file);
                for (final annotation in document.annotations) {
                  if (annotation['/Subtype'] == '/Widget') {
                    if (!forms) {
                      throw ArgumentError(
                        'Choose form flattening too for this PDF.',
                      );
                    }
                  } else if (!document.hasNormalAppearance(annotation)) {
                    throw ArgumentError(
                      'This PDF contains an annotation without a supported appearance.',
                    );
                  }
                }
              },
            );
          } finally {
            await scratch.delete(recursive: true);
          }
        }
        if (forms) await editor.flattenForms();
        if (annotations) await editor.flattenAnnotations();
        await _save(
          editor,
          output,
          verify: (file) async {
            final document = await PdfRewriteInspection.read(file);
            if (document.annotations.any(
              (annotation) =>
                  annotations || annotation['/Subtype'] == '/Widget',
            )) {
              throw ArgumentError(
                'Some selected PDF annotations could not be flattened.',
              );
            }
          },
        );
      } finally {
        await editor.dispose();
      }
    } finally {
      await pdf.dispose();
    }
    return output;
  }

  static Future<List<File>> extractImages({
    required File sourceFile,
    required String outputDirectory,
    void Function(double)? onProgress,
    Future<void> Function()? checkpoint,
  }) async {
    final pdf = Pdf(), outputs = <File>[];
    await Directory(outputDirectory).create(recursive: true);
    try {
      final doc = await pdf.open(FileSource(sourceFile));
      try {
        for (var page = 0; page < doc.pageCount; page++) {
          await checkpoint?.call();
          var index = 0;
          await for (final image in doc.extractImages(
            pages: PdfPages.single(page),
          )) {
            await checkpoint?.call();
            final decoded = img.decodeImage(image.data);
            if (decoded == null)
              throw ArgumentError(
                'An embedded image uses an unsupported encoding. Export rendered pages instead.',
              );
            final bytes = image.data;
            final ext = bytes.length > 2 && bytes[0] == 255 && bytes[1] == 216
                ? 'jpg'
                : bytes.length > 8 && bytes[0] == 137 && bytes[1] == 80
                ? 'png'
                : null;
            if (ext == null)
              throw ArgumentError(
                'An embedded image cannot be exported with its original encoding. Export rendered pages instead.',
              );
            final file = File(
              p.join(
                outputDirectory,
                'page_${(page + 1).toString().padLeft(4, '0')}_image_${(++index).toString().padLeft(3, '0')}.$ext',
              ),
            );
            await file.writeAsBytes(bytes, flush: true);
            outputs.add(file);
          }
          onProgress?.call((page + 1) / doc.pageCount);
        }
      } finally {
        await doc.dispose();
      }
      if (outputs.isEmpty)
        throw ArgumentError(
          'No embedded images were found. Use rendered pages for text or vector PDFs.',
        );
      return outputs;
    } catch (_) {
      for (final file in outputs) {
        if (await file.exists()) await file.delete();
      }
      rethrow;
    } finally {
      await pdf.dispose();
    }
  }

  static Future<File> imageWatermark({
    required File sourceFile,
    required File imageFile,
    required String outputPath,
    double opacity = .25,
    PdfLayoutOptions layout = const PdfLayoutOptions(),
    void Function(double)? onProgress,
  }) async {
    layout.validate();
    if (!opacity.isFinite || opacity < 0 || opacity > 1)
      throw ArgumentError('Opacity must be between 0 and 1.');
    final image = img.decodeImage(await imageFile.readAsBytes());
    if (image == null)
      throw ArgumentError('Choose a readable JPG or PNG watermark image.');
    final output = await _destination(sourceFile, outputPath), pdf = Pdf();
    try {
      final doc = await pdf.open(FileSource(sourceFile));
      final infos = doc.pages;
      await doc.dispose();
      final selected = _pages(layout, infos.length),
          editor = await pdf.edit(FileSource(sourceFile));
      try {
        for (var i = 0; i < selected.length; i++) {
          final page = selected[i], rotation = infos[page].rotation;
          final box =
              await editor.pageCropBox(page) ?? await editor.pageMediaBox(page);
          final rotated = rotation == 90 || rotation == 270;
          final bounds = layout.imageBounds(
            rotated ? box.height : box.width,
            rotated ? box.width : box.height,
            image.width / image.height,
          );
          final bitmap = rotation == 0
              ? image
              : img.copyRotate(image, angle: -rotation);
          await editor.addImageStamp(
            page,
            MemorySource(img.encodePng(bitmap)),
            rect: _displayToPdfRect(box, rotation, bounds),
            opacity: opacity,
          );
          onProgress?.call((i + 1) / selected.length);
        }
        await _save(editor, output);
      } finally {
        await editor.dispose();
      }
    } finally {
      await pdf.dispose();
    }
    return output;
  }

  static PdfRect _displayToPdfRect(
    PdfRect box,
    int rotation,
    ({double left, double top, double width, double height}) bounds,
  ) {
    final (:left, :top, :width, :height) = bounds;
    final (x, y, w, h) = switch (rotation) {
      90 => (top, left, height, width),
      180 => (box.width - left - width, top, width, height),
      270 => (
        box.width - top - height,
        box.height - left - width,
        height,
        width,
      ),
      _ => (left, box.height - top - height, width, height),
    };
    return PdfRect(x: box.x + x, y: box.y + y, width: w, height: h);
  }

  static List<int> _pages(PdfLayoutOptions options, int total) {
    options.validate();
    return options.pages.trim().isEmpty
        ? List.generate(total, (i) => i)
        : PdfEngine.parsePageList(options.pages, total).toSet().toList();
  }

  static Future<File> textWatermark({
    required File sourceFile,
    required String outputPath,
    required String text,
    double opacity = .25,
    double angle = 45,
    double fontSize = 54,
    PdfLayoutOptions layout = const PdfLayoutOptions(),
    bool numbers = false,
    void Function(double)? onProgress,
  }) async {
    layout.validate();
    if ((!numbers && text.trim().isEmpty) ||
        !opacity.isFinite ||
        opacity < 0 ||
        opacity > 1 ||
        !angle.isFinite ||
        !fontSize.isFinite ||
        fontSize <= 0)
      throw ArgumentError('Enter valid text and watermark layout values.');
    final output = await _destination(sourceFile, outputPath), pdf = Pdf();
    late List<PdfPageInfo> infos;
    try {
      final doc = await pdf.open(FileSource(sourceFile));
      try {
        infos = doc.pages;
      } finally {
        await doc.dispose();
      }
    } finally {
      await pdf.dispose();
    }
    final selected = _pages(layout, infos.length);
    var fields = <double>[];
    await withPageNumberEditor(FileSource(sourceFile), (editor) async {
      for (var i = 0; i < selected.length; i++) {
        final page = selected[i], rotation = infos[page].rotation;
        final box =
            await editor.pageCropBox(page) ?? await editor.pageMediaBox(page);
        final sideways = rotation == 90 || rotation == 270;
        final pageWidth = sideways ? box.height : box.width;
        final pageHeight = sideways ? box.width : box.height;
        final margin = layout.margin;
        if (margin * 2 >= math.min(pageWidth, pageHeight))
          throw ArgumentError('Margin must leave room on every selected page.');
        final label = numbers
            ? 'Page ${layout.startNumber + i} of ${layout.startNumber + selected.length - 1}'
            : text;
        final centered = layout.position == 'center';
        final width = math.min(
          pageWidth - 2 * margin,
          math.max(
            pageWidth * (centered ? .8 : .3),
            fontSize * .55 * label.runes.length,
          ),
        );
        final height = math.min(
          pageHeight - 2 * margin,
          math.max(pageHeight * (centered ? .4 : .08), fontSize * 1.3),
        );
        final rect = _displayToPdfRect(box, rotation, (
          left: centered
              ? (pageWidth - width) / 2
              : layout.position.endsWith('Right')
              ? pageWidth - margin - width
              : margin,
          top: centered
              ? (pageHeight - height) / 2
              : layout.position.startsWith('bottom')
              ? pageHeight - margin - height
              : margin,
          width: width,
          height: height,
        ));
        fields = [rect.x, rect.y, rect.width, rect.height];
        await editor.addWatermark(
          page,
          label,
          style: PdfWatermarkStyle(
            fontSize: fontSize,
            opacity: opacity,
            rotation: angle + rotation,
            color: numbers ? PdfColor.black : PdfColor.gray,
          ),
          position: PdfWatermarkPosition.exact(
            x: rect.x,
            y: rect.y,
            width: rect.width,
            height: rect.height,
          ),
        );
        onProgress?.call((i + 1) / selected.length);
      }
      await StorageService.writeAtomically(output, (temporary) async {
        final sink = await FileSink.create(temporary);
        try {
          await editor.save(sink);
        } finally {
          await sink.close();
        }
      });
    }, positionFields: () => fields);
    return output;
  }
}
