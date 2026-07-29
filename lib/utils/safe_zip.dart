import 'dart:typed_data';

import 'package:archive/archive.dart';

final class SafeZipException implements Exception {
  const SafeZipException(this.message);

  final String message;

  @override
  String toString() => message;
}

Archive decodeSafeZip(
  Uint8List bytes, {
  int maxZipBytes = 50 * 1024 * 1024,
  int maxExpandedBytes = 200 * 1024 * 1024,
  int maxFileCount = 500,
  int maxFileBytes = 100 * 1024 * 1024,
}) {
  if (bytes.length > maxZipBytes) {
    throw const SafeZipException('ZIP 文件过大');
  }

  late final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes, verify: true);
  } catch (_) {
    throw const SafeZipException('不是有效的 ZIP 文件');
  }
  if (archive.files.length > maxFileCount) {
    throw const SafeZipException('ZIP 文件数量过多');
  }

  var expandedBytes = 0;
  for (final entry in archive.files) {
    if (entry.isSymbolicLink) {
      throw SafeZipException('ZIP 包含符号链接：${entry.name}');
    }
    _validatePath(entry.name);
    if (!entry.isFile) continue;
    if (entry.size < 0 || entry.size > maxFileBytes) {
      throw SafeZipException('ZIP 单个文件过大：${entry.name}');
    }
    expandedBytes += entry.size;
    if (expandedBytes > maxExpandedBytes) {
      throw const SafeZipException('ZIP 解压后总大小过大');
    }
  }
  return archive;
}

void _validatePath(String name) {
  final normalized = name.replaceAll('\\', '/');
  final parts = normalized.split('/');
  final hasName = parts.any((part) => part.isNotEmpty && part != '.');
  if (normalized.isEmpty ||
      normalized.startsWith('/') ||
      normalized.contains(':') ||
      parts.contains('..') ||
      !hasName ||
      name.contains('\x00')) {
    throw SafeZipException('ZIP 包含不安全路径：$name');
  }
}
