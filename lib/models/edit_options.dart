class ImageEditOptions {
  final int rotationDegrees; // 0, 90, 180, 270
  final bool flipHorizontal;
  final bool flipVertical;
  final int compressionQuality; // 1 to 100
  final int? cropX;
  final int? cropY;
  final int? cropWidth;
  final int? cropHeight;
  final int? targetWidth;
  final int? targetHeight;

  const ImageEditOptions({
    this.rotationDegrees = 0,
    this.flipHorizontal = false,
    this.flipVertical = false,
    this.compressionQuality = 85,
    this.cropX,
    this.cropY,
    this.cropWidth,
    this.cropHeight,
    this.targetWidth,
    this.targetHeight,
  });

  bool get hasCrop =>
      cropX != null && cropY != null && cropWidth != null && cropHeight != null;

  ImageEditOptions copyWith({
    int? rotationDegrees,
    bool? flipHorizontal,
    bool? flipVertical,
    int? compressionQuality,
    int? cropX,
    int? cropY,
    int? cropWidth,
    int? cropHeight,
    int? targetWidth,
    int? targetHeight,
  }) {
    return ImageEditOptions(
      rotationDegrees: rotationDegrees ?? this.rotationDegrees,
      flipHorizontal: flipHorizontal ?? this.flipHorizontal,
      flipVertical: flipVertical ?? this.flipVertical,
      compressionQuality: compressionQuality ?? this.compressionQuality,
      cropX: cropX ?? this.cropX,
      cropY: cropY ?? this.cropY,
      cropWidth: cropWidth ?? this.cropWidth,
      cropHeight: cropHeight ?? this.cropHeight,
      targetWidth: targetWidth ?? this.targetWidth,
      targetHeight: targetHeight ?? this.targetHeight,
    );
  }
}

class PdfEditOptions {
  final String? watermarkText;
  final double watermarkOpacity; // 0.1 to 1.0
  final double watermarkAngle; // degrees
  final String? splitPageRanges; // e.g. "1-3, 5, 8-10"
  final bool extractAllPagesAsIndividualPdfs;
  final int rasterDpi; // 72, 150, 300

  const PdfEditOptions({
    this.watermarkText,
    this.watermarkOpacity = 0.3,
    this.watermarkAngle = -45.0,
    this.splitPageRanges,
    this.extractAllPagesAsIndividualPdfs = false,
    this.rasterDpi = 200,
  });
}

