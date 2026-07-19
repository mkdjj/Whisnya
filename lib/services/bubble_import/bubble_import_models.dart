import 'dart:io';
import 'dart:typed_data';

import '../../models/chat_bubble_theme.dart';

enum BubblePackageRecognitionLevel { exact, probable, partial, failed }

enum BubblePackageUserImageMode { manual, mirrorRole, shareRole }

final class BubblePackageException implements Exception {
  BubblePackageException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class BubblePackageFile {
  const BubblePackageFile({
    required this.relativePath,
    required this.file,
    required this.isImage,
    this.width,
    this.height,
    this.isNinePatch = false,
    this.isAnimated = false,
  });

  final String relativePath;
  final File file;
  final bool isImage;
  final int? width;
  final int? height;
  final bool isNinePatch;
  final bool isAnimated;

  String get fileName => relativePath.split('/').last;

  String get extension {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.9.png')) return '.9.png';
    final dot = lower.lastIndexOf('.');
    return dot < 0 ? '' : lower.substring(dot);
  }
}

final class BubblePackageScanResult {
  const BubblePackageScanResult({
    required this.originalFileName,
    required this.tempDirectory,
    required this.files,
    this.warnings = const [],
  });

  final String originalFileName;
  final Directory tempDirectory;
  final List<BubblePackageFile> files;
  final List<String> warnings;

  int get imageCount => files.where((file) => file.isImage).length;

  int get configCount => files.where((file) => !file.isImage).length;

  BubblePackageFile? find(String? relativePath) {
    if (relativePath == null) return null;
    final wanted = relativePath.replaceAll('\\', '/').toLowerCase();
    for (final file in files) {
      if (file.relativePath.toLowerCase() == wanted) return file;
    }
    return null;
  }

  Future<void> dispose() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  }
}

final class BubbleNinePatchData {
  const BubbleNinePatchData({
    required this.imageBytes,
    required this.stretchRegion,
    required this.textPadding,
  });

  final Uint8List imageBytes;
  final BubbleNormalizedRect stretchRegion;
  final BubbleContentInsets textPadding;
}

final class BubblePackageCandidate {
  const BubblePackageCandidate({
    required this.level,
    required this.detectedFormat,
    this.name,
    this.rolePath,
    this.userPath,
    this.previewPath,
    this.stretchRegion,
    this.fillRegion,
    this.textPadding,
    this.fillColor,
    this.textColor,
    this.opacity,
    this.author,
    this.license,
    this.sourceDescription,
    this.reasons = const [],
    this.warnings = const [],
  });

  final BubblePackageRecognitionLevel level;
  final String detectedFormat;
  final String? name;
  final String? rolePath;
  final String? userPath;
  final String? previewPath;
  final BubbleNormalizedRect? stretchRegion;
  final BubbleNormalizedRect? fillRegion;
  final BubbleContentInsets? textPadding;
  final int? fillColor;
  final int? textColor;
  final double? opacity;
  final String? author;
  final String? license;
  final String? sourceDescription;
  final List<String> reasons;
  final List<String> warnings;
}

final class BubblePackageMapping {
  const BubblePackageMapping({
    required this.scan,
    required this.candidate,
    required this.name,
    required this.rolePath,
    required this.userMode,
    this.userPath,
    required this.stretchRegion,
    required this.fillRegion,
    required this.textPadding,
    required this.fillColor,
    required this.textColor,
    required this.opacity,
  });

  final BubblePackageScanResult scan;
  final BubblePackageCandidate candidate;
  final String name;
  final String rolePath;
  final BubblePackageUserImageMode userMode;
  final String? userPath;
  final BubbleNormalizedRect stretchRegion;
  final BubbleNormalizedRect fillRegion;
  final BubbleContentInsets textPadding;
  final int fillColor;
  final int textColor;
  final double opacity;
}
