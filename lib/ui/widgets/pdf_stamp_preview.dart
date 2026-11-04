import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf_manipulator/io.dart';
import 'package:pdf_manipulator/pdf_manipulator.dart';
import '../../core/theme/app_theme.dart';
import '../../models/pdf_layout_options.dart';
import '../../services/pdf/pdf_engine.dart';
import '../../services/pdf/pdf_extended_tools.dart';

/// Renders a private single-page edit through the same export adapter. This
/// avoids a second, subtly different crop/rotation transform in the widget.
class PdfStampPreview extends StatefulWidget {
  final String source;
  final int page;
  final Map<String, Object> options;
  final Widget original;
  final bool enabled;
  const PdfStampPreview({
    super.key,
    required this.source,
    required this.page,
    required this.options,
    required this.original,
    this.enabled = true,
  });
  @override
  State<PdfStampPreview> createState() => _PdfStampPreviewState();
}

class _PdfStampPreviewState extends State<PdfStampPreview> {
  Timer? _timer;
  Uint8List? _image;
  String? _error;
  bool _running = false;
  int _revision = 0;
  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(covariant PdfStampPreview old) {
    super.didUpdateWidget(old);
    if (old.source != widget.source ||
        old.page != widget.page ||
        old.enabled != widget.enabled ||
        old.options.toString() != widget.options.toString()) {
      _image = null;
      _error = null;
      _schedule();
    }
  }

  void _schedule() {
    _revision++;
    _timer?.cancel();
    if (widget.enabled)
      _timer = Timer(const Duration(milliseconds: 350), _render);
  }

  Future<void> _render() async {
    if (_running || !widget.enabled) return;
    final revision = _revision,
        source = widget.source,
        options = Map<String, Object>.from(widget.options);
    _running = true;
    if (mounted) setState(() => _error = null);
    try {
      final image = await Isolate.run(
        _StampRequest(source, widget.page, options).render,
      );
      if (mounted && revision == _revision && widget.enabled)
        setState(() => _image = image);
    } catch (error) {
      if (mounted && revision == _revision)
        setState(
          () =>
              _error = 'Preview unavailable: ${PdfEngine.errorMessage(error)}',
        );
    } finally {
      _running = false;
      if (mounted) {
        setState(() {});
        if (revision != _revision && widget.enabled)
          _timer = Timer(const Duration(milliseconds: 350), _render);
      }
    }
  }

  @override
  void dispose() {
    _revision++;
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: _image == null
            ? widget.original
            : Image.memory(_image!, fit: BoxFit.contain, gaplessPlayback: true),
      ),
      const SizedBox(height: 4),
      Text(
        _error ??
            (_running
                ? 'Updating preview…'
                : _image == null
                ? 'Preparing watermark preview…'
                : 'Page ${widget.page + 1} · exported appearance'),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppTheme.muted, fontSize: 11),
      ),
    ],
  );
}

// A bound method on a data-only request avoids serializing the widget State,
// timer and render tree through a closure's enclosing async context.
class _StampRequest {
  final String source;
  final int page;
  final Map<String, Object> options;
  _StampRequest(this.source, this.page, this.options);
  Future<Uint8List> render() => _renderStamp(source, page, options);
}

Future<Uint8List> _renderStamp(
  String source,
  int page,
  Map<String, Object> options,
) async {
  final temp = await Directory.systemTemp.createTemp('converto-stamp-preview-');
  try {
    final single = await PdfEngine.extractPages(
      sourceFile: File(source),
      expression: '${page + 1}',
      outputPath: '${temp.path}/page.pdf',
    );
    final layout = PdfLayoutOptions.fromMap({...options, 'pages': ''});
    final opacity = double.parse('${options['opacity'] ?? '.25'}');
    late File output;
    if (options['watermarkKind'] == 'image') {
      output = await PdfExtendedTools.imageWatermark(
        sourceFile: single,
        imageFile: File('${options['watermarkImage']}'),
        outputPath: '${temp.path}/preview.pdf',
        opacity: opacity,
        layout: layout,
      );
    } else {
      output = await PdfEngine.watermark(
        sourceFile: single,
        text: '${options['text'] ?? ''}',
        outputPath: '${temp.path}/preview.pdf',
        opacity: opacity,
        angle: double.parse('${options['angle'] ?? 45}'),
        fontSize: double.parse('${options['fontSize'] ?? 54}'),
        layout: layout,
      );
    }
    final pdf = Pdf();
    try {
      final doc = await pdf.open(FileSource(output));
      try {
        await for (final page in doc.render(
          pages: const PdfPages.single(0),
          size: const PdfRenderSize(maxWidth: 700, maxHeight: 700),
        )) {
          return page.data;
        }
      } finally {
        await doc.dispose();
      }
    } finally {
      await pdf.dispose();
    }
    throw StateError('The page could not be rendered.');
  } finally {
    await PdfEngine.dispose();
    await temp.delete(recursive: true);
  }
}
