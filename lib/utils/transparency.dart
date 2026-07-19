double opacityToTransparency(num opacity) => 1 - opacity.clamp(0, 1).toDouble();

double transparencyToOpacity(num transparency) =>
    1 - transparency.clamp(0, 1).toDouble();
