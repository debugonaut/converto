import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import '../../core/theme/app_theme.dart';
import '../../models/scan_options.dart';
import '../../services/scan_image_filter.dart';

class ScanPreview extends StatefulWidget {
  final Uint8List image;
  final ScanOptions options;
  const ScanPreview({super.key, required this.image, required this.options});
  @override
  State<ScanPreview> createState() => _ScanPreviewState();
}

class _ScanPreviewState extends State<ScanPreview> {
  Timer? _debounce;
  Uint8List? _rendered;
  Object? _error;
  bool _working = false;
  int _revision = 0;
  int _startedRevision = -1;

  @override
  void initState() {
    super.initState();
    _schedule(immediate: true);
  }

  @override
  void didUpdateWidget(covariant ScanPreview old) {
    super.didUpdateWidget(old);
    if (!identical(old.image, widget.image) ||
        old.options.previewKey != widget.options.previewKey) {
      // Do not show the previous page while a new source is being filtered.
      if (!identical(old.image, widget.image)) _rendered = null;
      _schedule();
    }
  }

  void _schedule({bool immediate = false}) {
    _revision++;
    _debounce?.cancel();
    if (immediate) {
      unawaited(_render());
    } else {
      _debounce = Timer(const Duration(milliseconds: 140), _render);
    }
  }

  Future<void> _render() async {
    if (!mounted || _working || _startedRevision == _revision) return;
    _working = true;
    final revision = _revision;
    _startedRevision = revision;
    final bytes = widget.image;
    final options = widget.options;
    try {
      final result = await _filterPreview(bytes, options);
      if (mounted && revision == _revision) {
        setState(() {
          _rendered = result;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted && revision == _revision) setState(() => _error = error);
    } finally {
      _working = false;
      if (mounted && revision != _revision) unawaited(_render());
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return const Center(
        child: Text(
          'Scan preview unavailable. Reset the options and retry.',
          style: TextStyle(color: AppTheme.muted),
          textAlign: TextAlign.center,
        ),
      );
    }
    if (_rendered == null) {
      return const Center(
        child: Text(
          'Preparing scan preview…',
          style: TextStyle(color: AppTheme.muted),
        ),
      );
    }
    return Image.memory(
      _rendered!,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      semanticLabel: 'Scanned page preview',
    );
  }
}

// Capture only bounded raster bytes and options in the preview isolate.
Future<Uint8List> _filterPreview(Uint8List bytes, ScanOptions options) =>
    Isolate.run(() {
      final source = img.decodeImage(bytes);
      if (source == null) throw StateError('Cannot decode the preview.');
      final bounded = source.width <= 1000 && source.height <= 1000
          ? source
          : img.copyResize(
              source,
              width: source.width > source.height ? 1000 : null,
              height: source.height >= source.width ? 1000 : null,
              maintainAspect: true,
            );
      return Uint8List.fromList(
        img.encodePng(ScanImageFilter.apply(bounded, options)),
      );
    });
