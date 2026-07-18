class ImageCropRegion {
  const ImageCropRegion({
    this.x = 0,
    this.y = 0,
    this.width = 1,
    this.height = 1,
    this.sourceAspectRatio = 1,
  });

  static const full = ImageCropRegion();

  final double x;
  final double y;
  final double width;
  final double height;
  final double sourceAspectRatio;

  bool get isFull => x <= 0 && y <= 0 && width >= 1 && height >= 1;

  factory ImageCropRegion.fromPixels({
    required int sourceWidth,
    required int sourceHeight,
    required int x,
    required int y,
    required int width,
    required int height,
  }) {
    return ImageCropRegion(
      x: x / sourceWidth,
      y: y / sourceHeight,
      width: width / sourceWidth,
      height: height / sourceHeight,
      sourceAspectRatio: sourceWidth / sourceHeight,
    );
  }

  factory ImageCropRegion.fromJson(Object? json) {
    if (json is! Map) return full;
    return ImageCropRegion(
      x: jsonDouble(json['x'], 0),
      y: jsonDouble(json['y'], 0),
      width: jsonDouble(json['width'], 1),
      height: jsonDouble(json['height'], 1),
      sourceAspectRatio: jsonDouble(json['sourceAspectRatio'], 1),
    );
  }

  Map<String, dynamic> toJson() => {
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'sourceAspectRatio': sourceAspectRatio,
  };
}

double jsonDouble(Object? value, double fallback) =>
    value is num ? value.toDouble() : fallback;
