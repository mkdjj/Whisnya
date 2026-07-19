import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_svg/flutter_svg.dart';
import 'package:image/image.dart' as img;

import '../../models/chat_bubble_preset.dart';
import '../../models/chat_bubble_theme.dart';
import '../local_storage_service.dart';
import 'bubble_import_models.dart';
import 'bubble_nine_patch_parser.dart';

final class BubblePackageImportService {
  BubblePackageImportService({
    required this.storage,
    BubbleNinePatchParser? ninePatchParser,
  }) : _ninePatchParser = ninePatchParser ?? BubbleNinePatchParser();

  final LocalStorageService storage;
  final BubbleNinePatchParser _ninePatchParser;

  Future<ChatBubblePreset> import(
    BubblePackageMapping mapping, {
    String? presetId,
  }) async {
    _validateMapping(mapping);
    final roleSource = mapping.scan.find(mapping.rolePath)!;
    final userSource = mapping.userMode == BubblePackageUserImageMode.manual
        ? mapping.scan.find(mapping.userPath)
        : null;
    if (mapping.userMode == BubblePackageUserImageMode.manual &&
        userSource == null) {
      throw BubblePackageException('请选择有效的用户侧气泡图片');
    }

    final id = _safeId(
      presetId ?? 'bubble_${DateTime.now().microsecondsSinceEpoch}',
    );
    final root = await storage.appDataDirectory;
    final skins = Directory(
      '${root.path}${Platform.pathSeparator}media${Platform.pathSeparator}bubble_skins',
    );
    await skins.create(recursive: true);
    final target = Directory('${skins.path}${Platform.pathSeparator}$id');
    if (await target.exists()) {
      throw BubblePackageException('气泡预设 ID 已存在');
    }
    final temporary = Directory(
      '${skins.path}${Platform.pathSeparator}.import_$id'
      '_${DateTime.now().microsecondsSinceEpoch}',
    );
    await temporary.create();
    var moved = false;
    try {
      final role = await _convert(roleSource);
      final user = switch (mapping.userMode) {
        BubblePackageUserImageMode.manual => await _convert(userSource!),
        BubblePackageUserImageMode.mirrorRole => _mirror(role),
        BubblePackageUserImageMode.shareRole => role,
      };
      final previewSource = mapping.scan.find(mapping.candidate.previewPath);
      final preview = previewSource == null
          ? _preview(role)
          : await _convert(previewSource);

      await _writePng(temporary, 'role.png', role.bytes);
      await _writePng(temporary, 'user.png', user.bytes);
      await _writePng(temporary, 'preview.png', preview.bytes);

      final now = DateTime.now().toUtc();
      final manifest = <String, dynamic>{
        'format': 'whisnya-bubble',
        'formatVersion': 1,
        'name': mapping.name.trim(),
        'author': mapping.candidate.author ?? '',
        'license': mapping.candidate.license ?? '',
        'description': mapping.candidate.sourceDescription ?? '',
        'roleImage': 'role.png',
        'userImage': 'user.png',
        'previewImage': 'preview.png',
        'stretchRegion': mapping.stretchRegion.toJson(),
        'fillRegion': mapping.fillRegion.toJson(),
        'textPadding': mapping.textPadding.toJson(),
        'fillColor': mapping.fillColor,
        'fillOpacity': mapping.opacity,
        'textColor': mapping.textColor,
      };
      final originalFiles = <String>{
        roleSource.relativePath,
        if (userSource != null) userSource.relativePath,
        if (previewSource != null) previewSource.relativePath,
      }.toList();
      final sourceInfo = <String, dynamic>{
        'originalFileName': mapping.scan.originalFileName,
        'detectedFormat': mapping.candidate.detectedFormat,
        'recognitionLevel': mapping.candidate.level.name,
        'importedAt': now.toIso8601String(),
        'originalFiles': originalFiles,
      };
      await _writeJson(temporary, 'manifest.json', manifest);
      await _writeJson(temporary, 'source_info.json', sourceInfo);

      await temporary.rename(target.path);
      moved = true;
      final roleSkin = _skin(target, 'role.png', role, mapping);
      final userSkin = _skin(target, 'user.png', user, mapping);
      final preset = ChatBubblePreset(
        id: id,
        name: mapping.name.trim(),
        appearance: ChatBubbleAppearance(
          backgroundColor: mapping.fillColor,
          textColor: mapping.textColor,
          opacity: mapping.opacity,
          imageSkin: roleSkin,
        ),
        userAppearance: ChatBubbleAppearance(
          backgroundColor: mapping.fillColor,
          textColor: mapping.textColor,
          opacity: mapping.opacity,
          imageSkin: userSkin,
        ),
        author: mapping.candidate.author ?? '',
        license: mapping.candidate.license ?? '',
        sourceDescription: mapping.candidate.sourceDescription ?? '',
        createdAt: now,
        updatedAt: now,
      );
      final settings = await storage.loadChatBubblePresets();
      if (settings.presetById(id) != null) {
        throw BubblePackageException('气泡预设 ID 已存在');
      }
      await storage.saveChatBubblePresets(
        settings.copyWith(presets: [...settings.presets, preset]),
      );
      return preset;
    } catch (error) {
      final directory = moved ? target : temporary;
      if (await directory.exists()) await directory.delete(recursive: true);
      if (error is BubblePackageException || error is StorageException) {
        rethrow;
      }
      throw BubblePackageException('转换气泡资源失败：$error');
    }
  }

  Future<_ConvertedImage> _convert(BubblePackageFile source) async {
    if (!source.isImage || source.isAnimated) {
      throw BubblePackageException('不支持动态或非图片资源：${source.fileName}');
    }
    final bytes = await source.file.readAsBytes();
    if (source.isNinePatch) {
      final parsed = _ninePatchParser.parse(bytes);
      return _decodedPng(parsed.imageBytes, source.fileName);
    }
    if (source.extension == '.svg') return _svg(bytes, source.fileName);
    if (source.extension == '.webp') {
      final decoded = img.decodeWebP(bytes);
      if (decoded == null || decoded.numFrames > 1) {
        throw BubblePackageException('无法转换静态 WebP：${source.fileName}');
      }
      return _decodedPng(
        Uint8List.fromList(img.encodePng(decoded)),
        source.fileName,
      );
    }
    return _decodedPng(bytes, source.fileName);
  }

  Future<_ConvertedImage> _svg(Uint8List bytes, String name) async {
    try {
      final info = await vg.loadPicture(SvgBytesLoader(bytes), null);
      final width = info.size.width.ceil().clamp(1, 4096);
      final height = info.size.height.ceil().clamp(1, 4096);
      if (!info.size.width.isFinite ||
          !info.size.height.isFinite ||
          info.size.width <= 0 ||
          info.size.height <= 0 ||
          info.size.width > 8192 ||
          info.size.height > 8192) {
        info.picture.dispose();
        throw BubblePackageException('SVG 尺寸无效：$name');
      }
      final image = await info.picture.toImage(width, height);
      info.picture.dispose();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) throw BubblePackageException('SVG 渲染失败：$name');
      return _decodedPng(data.buffer.asUint8List(), name);
    } on BubblePackageException {
      rethrow;
    } catch (_) {
      throw BubblePackageException('SVG 渲染失败：$name');
    }
  }

  static _ConvertedImage _decodedPng(Uint8List bytes, String name) {
    final decoded = img.decodePng(bytes);
    if (decoded == null ||
        decoded.width > 8192 ||
        decoded.height > 8192 ||
        decoded.numFrames > 1) {
      throw BubblePackageException('PNG 无效或尺寸超限：$name');
    }
    return (bytes: bytes, width: decoded.width, height: decoded.height);
  }

  static _ConvertedImage _mirror(_ConvertedImage source) {
    final decoded = img.decodePng(source.bytes)!;
    final flipped = img.flipHorizontal(decoded);
    return (
      bytes: Uint8List.fromList(img.encodePng(flipped)),
      width: flipped.width,
      height: flipped.height,
    );
  }

  static _ConvertedImage _preview(_ConvertedImage source) {
    final decoded = img.decodePng(source.bytes)!;
    final width = decoded.width > 480 ? 480 : decoded.width;
    final preview = width == decoded.width
        ? decoded
        : img.copyResize(
            decoded,
            width: width,
            height: (decoded.height * width / decoded.width).round(),
          );
    return (
      bytes: Uint8List.fromList(img.encodePng(preview)),
      width: preview.width,
      height: preview.height,
    );
  }

  static ChatBubbleImageSkin _skin(
    Directory target,
    String fileName,
    _ConvertedImage image,
    BubblePackageMapping mapping,
  ) => ChatBubbleImageSkin(
    imagePath: '${target.path}${Platform.pathSeparator}$fileName',
    imageWidth: image.width,
    imageHeight: image.height,
    stretchRegion: mapping.stretchRegion,
    fillRegion: mapping.fillRegion,
    textPadding: mapping.textPadding,
    mirrorForUser: false,
  );

  static void _validateMapping(BubblePackageMapping mapping) {
    if (mapping.name.trim().isEmpty ||
        mapping.scan.find(mapping.rolePath) == null) {
      throw BubblePackageException('名称或角色侧气泡图片无效');
    }
    if (!_validRect(mapping.stretchRegion) ||
        !_validRect(mapping.fillRegion) ||
        [
          mapping.textPadding.left,
          mapping.textPadding.top,
          mapping.textPadding.right,
          mapping.textPadding.bottom,
        ].any((value) => value < 0)) {
      throw BubblePackageException('拉伸、填充区域或文字边距无效');
    }
  }

  static bool _validRect(BubbleNormalizedRect rect) =>
      rect.left >= 0 &&
      rect.top >= 0 &&
      rect.right <= 1 &&
      rect.bottom <= 1 &&
      rect.left < rect.right &&
      rect.top < rect.bottom;

  static String _safeId(String value) {
    final safe = value.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    if (safe.isEmpty) throw BubblePackageException('气泡预设 ID 无效');
    return safe;
  }

  static Future<void> _writePng(
    Directory directory,
    String name,
    Uint8List bytes,
  ) => File(
    '${directory.path}${Platform.pathSeparator}$name',
  ).writeAsBytes(bytes, flush: true);

  static Future<void> _writeJson(
    Directory directory,
    String name,
    Map<String, dynamic> value,
  ) => File('${directory.path}${Platform.pathSeparator}$name').writeAsString(
    const JsonEncoder.withIndent('  ').convert(value),
    flush: true,
  );
}

typedef _ConvertedImage = ({Uint8List bytes, int width, int height});
