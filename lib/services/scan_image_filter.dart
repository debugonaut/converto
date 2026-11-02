import 'package:image/image.dart' as img;
import '../models/scan_options.dart';

/// The same pixel transform is used for the bounded preview and saved pages.
class ScanImageFilter {
  static img.Image apply(img.Image source, ScanOptions options) {
    options.validate();
    final result = img.Image(width: source.width, height: source.height);
    int adjust(num value) =>
        ((value - 127.5) * options.contrast + 127.5 + options.brightness * 255)
            .round()
            .clamp(0, 255);
    for (final pixel in source) {
      // Transparent areas of a source belong to white paper, not black ink.
      final alpha = pixel.aNormalized;
      final r = pixel.rNormalized * 255 * alpha + 255 * (1 - alpha);
      final g = pixel.gNormalized * 255 * alpha + 255 * (1 - alpha);
      final b = pixel.bNormalized * 255 * alpha + 255 * (1 - alpha);
      if (options.mode == ScanColorMode.color) {
        result.setPixelRgb(pixel.x, pixel.y, adjust(r), adjust(g), adjust(b));
      } else {
        var value = adjust(.299 * r + .587 * g + .114 * b);
        if (options.mode == ScanColorMode.blackAndWhite) {
          value = value >= options.threshold * 255 ? 255 : 0;
        }
        result.setPixelRgb(pixel.x, pixel.y, value, value, value);
      }
    }
    return result;
  }
}
