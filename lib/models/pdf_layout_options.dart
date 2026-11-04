import 'dart:math' as math;

/// Run-local layout in the displayed page's coordinate system.
class PdfLayoutOptions {
  final String pages;
  final String position;
  final int startNumber;
  final double margin;
  final double imageWidthPercent;
  const PdfLayoutOptions({
    this.pages = '',
    this.position = 'center',
    this.startNumber = 1,
    this.margin = 20,
    this.imageWidthPercent = 25,
  });
  static const positions = [
    'center',
    'topLeft',
    'topRight',
    'bottomLeft',
    'bottomRight',
  ];
  factory PdfLayoutOptions.fromMap(Map<String, Object> map) {
    double number(String name, double fallback) {
      final raw = '${map[name] ?? ''}';
      if (raw.isEmpty) return fallback;
      final n = double.tryParse(raw);
      if (n == null || !n.isFinite) throw ArgumentError('Enter a valid $name.');
      return n;
    }

    final raw = '${map['startNumber'] ?? '1'}';
    final start = int.tryParse(raw);
    if (start == null) throw ArgumentError('Enter a whole starting number.');
    final options = PdfLayoutOptions(
      pages: '${map['pages'] ?? ''}',
      position: '${map['position'] ?? 'center'}',
      startNumber: start,
      margin: number('margin', 20),
      imageWidthPercent: number('imageWidthPercent', 25),
    );
    options.validate();
    return options;
  }
  void validate() {
    if (!positions.contains(position))
      throw ArgumentError('Choose a valid page position.');
    if (startNumber < 1 || startNumber > 1000000000)
      throw ArgumentError('Starting number must be between 1 and 1000000000.');
    if (!margin.isFinite || margin < 0)
      throw ArgumentError('Margin must be a non-negative number.');
    if (!imageWidthPercent.isFinite ||
        imageWidthPercent <= 0 ||
        imageWidthPercent > 100)
      throw ArgumentError('Image width must be between 0 and 100 percent.');
  }

  ({double left, double top, double width, double height}) imageBounds(
    double pageWidth,
    double pageHeight,
    double aspect,
  ) {
    validate();
    if (pageWidth <= 2 * margin ||
        pageHeight <= 2 * margin ||
        !aspect.isFinite ||
        aspect <= 0)
      throw ArgumentError('Margin must leave room on every selected page.');
    var width = math.min(
          pageWidth * imageWidthPercent / 100,
          pageWidth - 2 * margin,
        ),
        height = width / aspect;
    if (height > pageHeight - 2 * margin) {
      height = pageHeight - 2 * margin;
      width = height * aspect;
    }
    return (
      left: position == 'center'
          ? (pageWidth - width) / 2
          : position.endsWith('Right')
          ? pageWidth - margin - width
          : margin,
      top: position == 'center'
          ? (pageHeight - height) / 2
          : position.startsWith('bottom')
          ? pageHeight - margin - height
          : margin,
      width: width,
      height: height,
    );
  }
}
