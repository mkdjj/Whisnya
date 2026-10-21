import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../services/local_storage_service.dart';
import 'image_picker.dart';

/// Keep API payloads and thumbnail decoding bounded; originals stay untouched.
Future<String?> pickChatImage(
  LocalStorageService storage,
  String ownerId,
) async {
  final picked = await pickImage(storage, withData: false);
  if (picked == null) return null;
  final file = File(picked.path);
  if (await file.length() > 20 * 1024 * 1024) {
    throw const FormatException('图片请控制在 20 MB 以内');
  }
  final bytes = await compute(_prepareImage, await file.readAsBytes());
  return storage.saveMediaImage(
    folder: 'chat_images',
    characterId: ownerId,
    bytes: bytes,
  );
}

Uint8List _prepareImage(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const FormatException('无法读取图片，请选择 JPG、PNG 或 WebP');
  var image = img.bakeOrientation(decoded);
  if (image.width > 1600 || image.height > 1600) {
    image = img.copyResize(
      image,
      width: image.width >= image.height ? 1600 : null,
      height: image.height > image.width ? 1600 : null,
    );
  }
  if (image.hasAlpha) {
    final background = img.Image(width: image.width, height: image.height);
    img.fill(background, color: img.ColorRgb8(255, 255, 255));
    image = img.compositeImage(background, image);
  }
  return img.encodeJpg(image, quality: 85);
}
