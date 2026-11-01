import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import '../../core/theme/app_theme.dart';
import '../../models/edit_options.dart';
import '../../models/gui/file_preview.dart';
import 'crop_overlay.dart';

class ImageEditPreview extends StatefulWidget {
  final FilePreview source;
  final ImageEditOptions options;
  final bool selectingCrop;
  final bool enabled;
  final ValueChanged<Rect>? onCrop;
  const ImageEditPreview({
    super.key,
    required this.source,
    required this.options,
    this.selectingCrop = false,
    this.enabled = true,
    this.onCrop,
  });
  @override
  State<ImageEditPreview> createState() => _ImageEditPreviewState();
}

class _ImageEditPreviewState extends State<ImageEditPreview> {
  Future<_EditedImage>? _image;
  Timer? _debounce;
  String _key = '';
  String _startedKey = '';
  bool _rendering = false;
  @override
  void initState() {
    super.initState();
    _schedule(immediate: true);
  }

  @override
  void didUpdateWidget(covariant ImageEditPreview old) {
    super.didUpdateWidget(old);
    _schedule();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _schedule({bool immediate = false}) {
    final o = widget.options;
    final key =
        '${identityHashCode(widget.source.image)}:${widget.source.width}:${widget.source.height}:${o.rotationDegrees}:${o.flipHorizontal}:${o.flipVertical}:${widget.selectingCrop ? 'crop' : '${o.cropX}:${o.cropY}:${o.cropWidth}:${o.cropHeight}:${o.targetWidth}:${o.targetHeight}'}';
    if (key == _key) return;
    _key = key;
    _debounce?.cancel();
    void update() {
      if (!mounted || _rendering || _startedKey == _key) return;
      final source = widget.source,
          options = widget.options,
          selecting = widget.selectingCrop;
      _startedKey = _key;
      _rendering = true;
      final render = _renderEditedImage(source, options, selecting).catchError(
        (Object error) => const _EditedImage(
          null,
          1,
          1,
          'Edit preview unavailable. Reset the options and retry.',
        ),
      );
      setState(() {
        _image = render;
      });
      unawaited(
        render.then((_) {
          _rendering = false;
          // Coalesce rapid control changes into one latest render. Never spawn
          // concurrent edit workers or build a queue of obsolete transforms.
          if (mounted && _startedKey != _key) update();
        }),
      );
    }

    if (immediate)
      update();
    else {
      _debounce = Timer(const Duration(milliseconds: 140), update);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_EditedImage>(
    future: _image,
    builder: (context, snapshot) {
      final data = snapshot.data;
      if (data == null)
        return const Center(
          child: Text(
            'Preparing edit preview…',
            style: TextStyle(color: AppTheme.muted),
          ),
        );
      if (data.error != null)
        return Center(
          child: Text(
            data.error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
            textAlign: TextAlign.center,
          ),
        );
      return Column(
        children: [
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: data.width / data.height,
                child: widget.selectingCrop && widget.onCrop != null
                    ? CropOverlay(
                        enabled: widget.enabled,
                        rectangle: widget.options.hasCrop
                            ? Rect.fromLTWH(
                                widget.options.cropX! / data.width,
                                widget.options.cropY! / data.height,
                                widget.options.cropWidth! / data.width,
                                widget.options.cropHeight! / data.height,
                              )
                            : const Rect.fromLTWH(0, 0, 1, 1),
                        onChanged: widget.onCrop!,
                        child: Image.memory(
                          data.image!,
                          fit: BoxFit.fill,
                          gaplessPlayback: true,
                        ),
                      )
                    : Image.memory(
                        data.image!,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${data.width} × ${data.height} px${widget.selectingCrop ? ' · drag to crop' : ' output'}',
            style: const TextStyle(color: AppTheme.muted, fontSize: 11),
          ),
        ],
      );
    },
  );
}

// Keep the isolate closure outside widget scope so no State, binding or native
// UI objects are captured with the bounded preview data.
Future<_EditedImage> _renderEditedImage(
  FilePreview source,
  ImageEditOptions options,
  bool selecting,
) => Isolate.run(
  () => _edit(source.image!, source.width, source.height, options, selecting),
);

class _EditedImage {
  final Uint8List? image;
  final int width;
  final int height;
  final String? error;
  const _EditedImage(this.image, this.width, this.height, [this.error]);
}

_EditedImage _edit(
  Uint8List bytes,
  double originalWidth,
  double originalHeight,
  ImageEditOptions options,
  bool selecting,
) {
  var image = img.decodePng(bytes);
  if (image == null)
    return const _EditedImage(null, 1, 1, 'Preview cannot be decoded.');
  var width = originalWidth.round(), height = originalHeight.round();
  if (options.rotationDegrees % 180 != 0) {
    final old = width;
    width = height;
    height = old;
  }
  if (options.rotationDegrees != 0)
    image = img.copyRotate(image, angle: options.rotationDegrees);
  if (options.flipHorizontal)
    image = img.copyFlip(image, direction: img.FlipDirection.horizontal);
  if (options.flipVertical)
    image = img.copyFlip(image, direction: img.FlipDirection.vertical);
  if (!selecting && options.hasCrop) {
    if (options.cropX! < 0 ||
        options.cropY! < 0 ||
        options.cropWidth! < 1 ||
        options.cropHeight! < 1 ||
        options.cropX! + options.cropWidth! > width ||
        options.cropY! + options.cropHeight! > height) {
      return const _EditedImage(
        null,
        1,
        1,
        'Crop rectangle must fit inside the rotated image.',
      );
    }
    final scaleX = image.width / width, scaleY = image.height / height;
    final x = (options.cropX! * scaleX).round().clamp(0, image.width - 1);
    final y = (options.cropY! * scaleY).round().clamp(0, image.height - 1);
    image = img.copyCrop(
      image,
      x: x,
      y: y,
      width: (options.cropWidth! * scaleX).round().clamp(1, image.width - x),
      height: (options.cropHeight! * scaleY).round().clamp(1, image.height - y),
    );
    width = options.cropWidth!;
    height = options.cropHeight!;
  }
  if (!selecting &&
      (options.targetWidth != null || options.targetHeight != null)) {
    if ((options.targetWidth ?? 1) < 1 || (options.targetHeight ?? 1) < 1)
      return const _EditedImage(null, 1, 1, 'Dimensions must be positive.');
    final newWidth =
        options.targetWidth ?? (width * options.targetHeight! / height).round();
    final newHeight =
        options.targetHeight ?? (height * options.targetWidth! / width).round();
    width = math.max(1, newWidth);
    height = math.max(1, newHeight);
  }
  final scale = math.min(1.0, 1200 / math.max(width, height));
  final renderWidth = math.max(1, (width * scale).round()),
      renderHeight = math.max(1, (height * scale).round());
  image = img.copyResize(image, width: renderWidth, height: renderHeight);
  return _EditedImage(Uint8List.fromList(img.encodePng(image)), width, height);
}
