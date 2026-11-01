import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../core/utils/file_utils.dart';
import '../../models/edit_options.dart';
import '../storage_service.dart';
import '../local_process.dart';
import 'base_converter.dart';

class ImageConverter extends BaseConverter {
  @override
  String get name => 'Image Processing Engine';

  @override
  List<String> get supportedSourceFormats => [
    'jpg',
    'jpeg',
    'png',
    'webp',
    'bmp',
    'gif',
    'tiff',
    'tif',
    'ico',
  ];

  @override
  List<String> get supportedTargetFormats => [
    'pdf',
    'png',
    'jpg',
    'jpeg',
    'webp',
    'bmp',
    'tiff',
    'gif',
    'ico',
  ];

  @override
  Future<File> convert({
    required File sourceFile,
    required String targetFormat,
    ImageEditOptions? imageOptions,
    PdfEditOptions? pdfOptions,
    String? outputPath,
    void Function(double progress)? onProgress,
  }) async {
    onProgress?.call(0.1);
    final cleanTarget = targetFormat.replaceAll('.', '').toLowerCase();
    if (!supportedTargetFormats.contains(cleanTarget)) {
      throw ArgumentError('Unsupported image output .$cleanTarget.');
    }
    final quality = imageOptions?.compressionQuality ?? 85;
    if (quality < 1 || quality > 100)
      throw ArgumentError('Quality must be 1-100.');
    final bytes = await sourceFile.readAsBytes();

    final options = imageOptions ?? const ImageEditOptions();
    if (cleanTarget == 'pdf' &&
        img.JpegDecoder().isValidFile(bytes) &&
        options.rotationDegrees == 0 &&
        !options.flipHorizontal &&
        !options.flipVertical &&
        !options.hasCrop &&
        options.targetWidth == null &&
        options.targetHeight == null) {
      // Embed original JPEG bytes: no decode/re-encode cycle or generation loss.
      final pdf = pw.Document();
      final provider = pw.MemoryImage(bytes);
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(20),
          build: (_) =>
              pw.Center(child: pw.Image(provider, fit: pw.BoxFit.contain)),
        ),
      );
      final result = await StorageService().saveConvertedFile(
        originalName: FileUtils.getBaseNameWithoutExtension(sourceFile.path),
        targetExtension: 'pdf',
        bytes: await pdf.save(),
        explicitDestinationPath: outputPath,
      );
      onProgress?.call(1);
      return result;
    }

    onProgress?.call(0.3);
    // Decode image
    final decoder = img.findDecoderForData(bytes);
    // image 4.3's TIFF decoder requires frame: 0 to collect every page;
    // its default null frame decodes only the first one.
    img.Image? decoded = decoder is img.TiffDecoder
        ? decoder.decode(bytes, frame: 0)
        : decoder?.decode(bytes);
    if (decoded == null) {
      throw Exception('Failed to decode image from ${sourceFile.path}');
    }
    if (decoder is img.IcoDecoder && decoded.frames.length > 1) {
      // ICO entries are resolutions of one icon, rather than document pages.
      final best = decoded.frames.reduce(
        (a, b) => a.width * a.height >= b.width * b.height ? a : b,
      );
      decoded = img.Image.from(best, noAnimation: true);
    }
    if (decoded.exif.imageIfd.hasOrientation &&
        decoded.exif.imageIfd.orientation != 1) {
      decoded = img.bakeOrientation(decoded);
    }

    onProgress?.call(0.5);
    // Apply transformations if options provided
    if (imageOptions != null) {
      decoded = _applyTransformations(decoded, imageOptions);
    }

    onProgress?.call(0.7);

    // If target is PDF, generate vector PDF with embedded image
    if (cleanTarget == 'pdf') {
      final pdfFile = await convertImagesToPdf(
        images: decoded.frames,
        originalName: FileUtils.getBaseNameWithoutExtension(sourceFile.path),
        outputPath: outputPath,
      );
      onProgress?.call(1.0);
      return pdfFile;
    }

    if (cleanTarget == 'webp') {
      final codec = Platform.environment['CONVERTO_DISABLE_HELPERS'] == '1'
          ? null
          : LocalProcess.find('cwebp');
      if (codec == null) {
        throw UnsupportedError(
          'WebP encoding requires local cwebp. WebP input decoding is built in. No encoder is downloaded.',
        );
      }
      final temp = await Directory.systemTemp.createTemp('converto-webp-');
      try {
        final input = File('${temp.path}/input.png');
        await input.writeAsBytes(img.encodePng(decoded));
        final generated = File('${temp.path}/result.webp');
        await LocalProcess.run(codec, [
          '-quiet',
          '-q',
          '$quality',
          input.path,
          '-o',
          generated.path,
        ]);
        final result = await StorageService().saveFromFile(
          source: generated,
          originalName: FileUtils.getBaseNameWithoutExtension(sourceFile.path),
          targetExtension: 'webp',
          explicitDestinationPath: outputPath,
        );
        onProgress?.call(1);
        return result;
      } finally {
        await temp.delete(recursive: true);
      }
    }

    // Otherwise encode to target image format
    final encodedBytes = _encodeImage(
      image: decoded,
      targetFormat: cleanTarget,
      quality: imageOptions?.compressionQuality ?? 85,
    );

    onProgress?.call(0.9);
    final savedFile = await StorageService().saveConvertedFile(
      originalName: FileUtils.getBaseNameWithoutExtension(sourceFile.path),
      targetExtension: cleanTarget,
      bytes: encodedBytes,
      explicitDestinationPath: outputPath,
    );

    onProgress?.call(1.0);
    return savedFile;
  }

  img.Image _applyTransformations(img.Image src, ImageEditOptions options) {
    if ((options.targetWidth != null && options.targetWidth! < 1) ||
        (options.targetHeight != null && options.targetHeight! < 1)) {
      throw ArgumentError('Image dimensions must be positive.');
    }
    var result = src;

    // 1. Rotation
    if (options.rotationDegrees != 0) {
      result = img.copyRotate(result, angle: options.rotationDegrees);
    }

    // 2. Flips
    if (options.flipHorizontal) {
      result = img.copyFlip(result, direction: img.FlipDirection.horizontal);
    }
    if (options.flipVertical) {
      result = img.copyFlip(result, direction: img.FlipDirection.vertical);
    }

    // 3. Crop
    if (options.hasCrop) {
      if (options.cropX! < 0 ||
          options.cropY! < 0 ||
          options.cropWidth! < 1 ||
          options.cropHeight! < 1 ||
          options.cropX! + options.cropWidth! > result.width ||
          options.cropY! + options.cropHeight! > result.height) {
        throw ArgumentError('Crop rectangle must fit inside the image.');
      }
      result = img.copyCrop(
        result,
        x: options.cropX!,
        y: options.cropY!,
        width: options.cropWidth!,
        height: options.cropHeight!,
      );
    }

    // 4. Resize
    if (options.targetWidth != null || options.targetHeight != null) {
      result = img.copyResize(
        result,
        width: options.targetWidth,
        height: options.targetHeight,
        interpolation: img.Interpolation.linear,
      );
    }

    return result;
  }

  List<int> _encodeImage({
    required img.Image image,
    required String targetFormat,
    required int quality,
  }) {
    switch (targetFormat) {
      case 'png':
        return img.encodePng(image, level: 6);
      case 'jpg':
      case 'jpeg':
        return img.encodeJpg(image, quality: quality);
      case 'gif':
        return img.encodeGif(image);
      case 'ico':
        return img.encodeIco(image);
      case 'bmp':
        return img.encodeBmp(image);
      case 'tiff':
        return img.encodeTiff(image);
      default:
        throw ArgumentError('Unsupported image output .$targetFormat.');
    }
  }

  /// Converts single or multiple images into a merged PDF document
  Future<File> convertImagesToPdf({
    required List<img.Image> images,
    required String originalName,
    String? outputPath,
    PdfPageFormat pageFormat = PdfPageFormat.a4,
  }) async {
    if (images.isEmpty) throw ArgumentError('No decoded images to merge.');
    final pdf = pw.Document();

    for (final image in images) {
      final pdfImage = pw.ImageImage(image);

      pdf.addPage(
        pw.Page(
          pageFormat: pageFormat,
          margin: const pw.EdgeInsets.all(20),
          build: (pw.Context context) {
            return pw.Center(child: pw.Image(pdfImage, fit: pw.BoxFit.contain));
          },
        ),
      );
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
