import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../services/local_storage_service.dart';

Future<({String path, Uint8List? bytes})?> pickImage(
  LocalStorageService storage, {
  bool withData = true,
}) async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.image,
    allowMultiple: false,
    withData: withData,
  );
  if (result == null || result.files.isEmpty) return null;

  final picked = result.files.single;
  final bytes = picked.bytes;
  final path =
      picked.path ??
      (bytes == null ? null : (await storage.saveTemporaryImage(bytes)).path);
  return path == null ? null : (path: path, bytes: bytes);
}
