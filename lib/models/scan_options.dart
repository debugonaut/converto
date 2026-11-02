enum ScanColorMode { color, grayscale, blackAndWhite }

class ScanOptions {
  final ScanColorMode mode;
  final double contrast;
  final double brightness;
  final double threshold;
  final int dpi;

  const ScanOptions({
    this.mode = ScanColorMode.grayscale,
    this.contrast = 1.2,
    this.brightness = 0,
    this.threshold = .6,
    this.dpi = 150,
  });

  factory ScanOptions.fromMap(Map<String, Object> values) {
    double number(String name, double fallback) {
      final raw = values[name];
      final value = raw == null ? fallback : double.tryParse('$raw');
      if (value == null || !value.isFinite) {
        throw ArgumentError('Enter a valid $name.');
      }
      return value;
    }

    final mode = values['scanMode'] ?? 'grayscale';
    final options = ScanOptions(
      mode: switch (mode) {
        'color' => ScanColorMode.color,
        'grayscale' => ScanColorMode.grayscale,
        'blackAndWhite' => ScanColorMode.blackAndWhite,
        _ => throw ArgumentError(
          'Choose color, grayscale, or black and white.',
        ),
      },
      contrast: number('contrast', 1.2),
      brightness: number('brightness', 0),
      threshold: number('threshold', .6),
      dpi: values['dpi'] == null ? 150 : int.tryParse('${values['dpi']}') ?? 0,
    );
    options.validate();
    return options;
  }

  void validate() {
    if (!contrast.isFinite || contrast < .5 || contrast > 3) {
      throw ArgumentError('Contrast must be from 50% to 300%.');
    }
    if (!brightness.isFinite || brightness < -.5 || brightness > .5) {
      throw ArgumentError('Brightness must be from -50% to 50%.');
    }
    if (!threshold.isFinite || threshold < .1 || threshold > .9) {
      throw ArgumentError('Black and white cutoff must be from 10% to 90%.');
    }
    if (dpi < 72 || dpi > 300) {
      throw ArgumentError('Scan resolution must be from 72 to 300 DPI.');
    }
  }

  String get previewKey => '${mode.name}:$contrast:$brightness:$threshold';
}
