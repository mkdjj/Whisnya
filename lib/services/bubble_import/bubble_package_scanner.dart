import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;

import 'bubble_import_models.dart';

final class BubblePackageScanner {
  static const maxZipBytes = 30 * 1024 * 1024;
  static const maxExpandedBytes = 80 * 1024 * 1024;
  static const maxFileCount = 200;
  static const maxFileBytes = 20 * 1024 * 1024;
  static const maxImageSide = 8192;

  Future<BubblePackageScanResult> scan({
    required Uint8List bytes,
    required String originalFileName,
  }) async {
    if (bytes.length > maxZipBytes) {
      throw BubblePackageException('ZIP 超过 30 MiB 限制');
    }

    late final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes, verify: true);
    } catch (_) {
      throw BubblePackageException('不是有效的 ZIP 资源包');
    }

    final entries = archive.files.where((entry) => entry.isFile).toList();
    if (entries.length > maxFileCount) {
      throw BubblePackageException('文件数量超过 200 个');
    }

    var expandedBytes = 0;
    for (final entry in archive.files) {
      if (entry.isSymbolicLink) {
        throw BubblePackageException('ZIP 包含符号链接：${entry.name}');
      }
      _safeRelativePath(entry.name);
      if (!entry.isFile) continue;
      if (entry.size > maxFileBytes) {
        throw BubblePackageException('单个文件超过 20 MiB：${entry.name}');
      }
      expandedBytes += entry.size;
      if (expandedBytes > maxExpandedBytes) {
        throw BubblePackageException('解压后总大小超过 80 MiB');
      }
    }

    final temp = await Directory.systemTemp.createTemp('whisnya_bubble_');
    final files = <BubblePackageFile>[];
    final warnings = <String>[];
    try {
      for (final entry in entries) {
        final relativePath = _safeRelativePath(entry.name);
        if (!_isSupported(relativePath)) {
          warnings.add('已忽略不支持的文件：$relativePath');
          continue;
        }

        final content = Uint8List.fromList(entry.content as List<int>);
        final target = File(
          '${temp.path}${Platform.pathSeparator}${relativePath.replaceAll('/', Platform.pathSeparator)}',
        );
        await target.parent.create(recursive: true);
        await target.writeAsBytes(content, flush: true);

        final isImage = _isImage(relativePath);
        int? width;
        int? height;
        var animated = false;
        if (isImage && !relativePath.toLowerCase().endsWith('.svg')) {
          img.Image? decoded;
          try {
            decoded = img.decodeImage(content);
          } catch (_) {
            decoded = null;
          }
          if (decoded == null) {
            warnings.add('无法解码图片：$relativePath');
          } else {
            width = decoded.width;
            height = decoded.height;
            animated = decoded.numFrames > 1;
            if (width > maxImageSide || height > maxImageSide) {
              throw BubblePackageException('图片边长超过 8192：$relativePath');
            }
          }
        }

        files.add(
          BubblePackageFile(
            relativePath: relativePath,
            file: target,
            isImage: isImage,
            width: width,
            height: height,
            isNinePatch: relativePath.toLowerCase().endsWith('.9.png'),
            isAnimated: animated,
          ),
        );
      }

      if (files.isEmpty) {
        throw BubblePackageException('资源包中没有支持的气泡资源');
      }
      return BubblePackageScanResult(
        originalFileName: _baseName(originalFileName),
        tempDirectory: temp,
        files: List.unmodifiable(files),
        warnings: List.unmodifiable(warnings),
      );
    } catch (_) {
      if (await temp.exists()) await temp.delete(recursive: true);
      rethrow;
    }
  }

  static bool _isSupported(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.svg') ||
        lower.endsWith('.json') ||
        lower.endsWith('.xml');
  }

  static bool _isImage(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.svg');
  }

  static String _safeRelativePath(String name) {
    final normalized = name.replaceAll('\\', '/');
    if (normalized.startsWith('/') ||
        RegExp(r'^[A-Za-z]:').hasMatch(normalized)) {
      throw BubblePackageException('ZIP 包含绝对路径：$name');
    }
    final parts = normalized.split('/');
    if (parts.contains('..')) {
      throw BubblePackageException('ZIP 路径试图越界：$name');
    }
    final safe = parts
        .where((part) => part.isNotEmpty && part != '.')
        .join('/');
    if (safe.isEmpty) throw BubblePackageException('ZIP 包含空路径');
    return safe;
  }

  static String _baseName(String path) =>
      path.replaceAll('\\', '/').split('/').last;
}
