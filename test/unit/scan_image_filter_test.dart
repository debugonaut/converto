import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:converto/models/scan_options.dart';
import 'package:converto/services/scan_image_filter.dart';

void main() {
  test('contrast separates faded ink from paper and brightness lifts both', () {
    final source = img.Image(width: 2, height: 1)
      ..setPixelRgb(0, 0, 80, 80, 80)
      ..setPixelRgb(1, 0, 190, 190, 190);
    final contrast = ScanImageFilter.apply(
      source,
      const ScanOptions(contrast: 2),
    );
    expect(contrast.getPixel(0, 0).r, lessThan(80));
    expect(contrast.getPixel(1, 0).r, greaterThan(190));
    final brighter = ScanImageFilter.apply(
      source,
      const ScanOptions(contrast: 1, brightness: .1),
    );
    expect(brighter.getPixel(0, 0).r, closeTo(106, 1));
    expect(brighter.getPixel(1, 0).r, closeTo(216, 1));
    expect(source.getPixel(0, 0).r, 80);
  });

  test(
    'color, grayscale, and black/white modes have distinct pixel output',
    () {
      final source = img.Image(width: 2, height: 1)
        ..setPixelRgb(0, 0, 220, 50, 30)
        ..setPixelRgb(1, 0, 210, 210, 210);
      final color = ScanImageFilter.apply(
        source,
        const ScanOptions(mode: ScanColorMode.color, contrast: 1),
      );
      expect(color.getPixel(0, 0).r, 220);
      expect(color.getPixel(0, 0).g, 50);
      final gray = ScanImageFilter.apply(
        source,
        const ScanOptions(contrast: 1),
      );
      expect(gray.getPixel(0, 0).r, gray.getPixel(0, 0).g);
      expect(gray.getPixel(0, 0).g, gray.getPixel(0, 0).b);
      final blackWhite = ScanImageFilter.apply(
        source,
        const ScanOptions(mode: ScanColorMode.blackAndWhite, contrast: 1),
      );
      expect(blackWhite.getPixel(0, 0).r, 0);
      expect(blackWhite.getPixel(1, 0).r, 255);
    },
  );

  test('alpha is composited onto white paper before filtering', () {
    final source = img.Image(width: 2, height: 1, numChannels: 4)
      ..setPixelRgba(0, 0, 0, 0, 0, 0)
      ..setPixelRgba(1, 0, 0, 0, 0, 128);
    final result = ScanImageFilter.apply(
      source,
      const ScanOptions(contrast: 1),
    );
    expect(result.getPixel(0, 0).r, 255);
    expect(result.getPixel(1, 0).r, closeTo(127, 1));
    expect(result.numChannels, 3);
  });

  test('invalid scan values are rejected rather than silently clamped', () {
    for (final values in <Map<String, Object>>[
      {'contrast': double.nan},
      {'contrast': 0},
      {'contrast': 4},
      {'brightness': double.infinity},
      {'brightness': -1},
      {'threshold': 0},
      {'threshold': 1},
      {'scanMode': 'unknown'},
      {'dpi': 'wrong'},
      {'dpi': 600},
    ]) {
      expect(
        () => ScanOptions.fromMap(values),
        throwsArgumentError,
        reason: '$values',
      );
    }
  });
}
