import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:xml/xml.dart';

import '../../models/chat_bubble_theme.dart';
import 'bubble_import_models.dart';
import 'bubble_nine_patch_parser.dart';

final class BubblePackageDetector {
  BubblePackageDetector({BubbleNinePatchParser? ninePatchParser})
    : _ninePatchParser = ninePatchParser ?? BubbleNinePatchParser();

  final BubbleNinePatchParser _ninePatchParser;

  Future<BubblePackageCandidate> detect(BubblePackageScanResult scan) async {
    final manifest = scan.files
        .where((file) => file.fileName.toLowerCase() == 'manifest.json')
        .firstOrNull;
    if (manifest != null) {
      final value = await _readJson(manifest);
      if (value?['format'] == 'whisnya-bubble') {
        return _detectManifest(scan, manifest, value!);
      }
    }

    final images = scan.files
        .where((file) => file.isImage && !file.isAnimated)
        .where((file) => !_isPreview(file.fileName))
        .toList();
    if (images.isEmpty) {
      return const BubblePackageCandidate(
        level: BubblePackageRecognitionLevel.failed,
        detectedFormat: 'unknown',
        reasons: ['没有可用的静态 PNG、WebP 或 SVG 图片'],
      );
    }

    final ninePatch = images.where((file) => file.isNinePatch).toList();
    if (ninePatch.isNotEmpty) return _detectNinePatch(scan, ninePatch);

    final byNames = _pairByFileName(images);
    if (byNames != null) {
      return BubblePackageCandidate(
        level: BubblePackageRecognitionLevel.probable,
        detectedFormat: 'filename-pattern',
        name: _packageName(scan.originalFileName),
        rolePath: byNames.$1.relativePath,
        userPath: byNames.$2.relativePath,
        previewPath: _previewPath(scan),
        reasons: [
          '角色侧文件名匹配：${byNames.$1.fileName}',
          '用户侧文件名匹配：${byNames.$2.fileName}',
        ],
      );
    }

    final config = await _detectCommonConfig(scan);
    if (config != null) return config;

    if (images.length >= 2) {
      var bestScore = 0.0;
      (BubblePackageFile, BubblePackageFile)? best;
      for (var i = 0; i < images.length; i++) {
        for (var j = i + 1; j < images.length; j++) {
          final first = images[i];
          final second = images[j];
          if (!_similarDimensions(first, second) ||
              first.extension == '.svg' ||
              second.extension == '.svg') {
            continue;
          }
          final score = mirrorSimilarity(
            await first.file.readAsBytes(),
            await second.file.readAsBytes(),
          );
          if (score > bestScore) {
            bestScore = score;
            best = (first, second);
          }
        }
      }
      if (best != null && bestScore >= .8) {
        return BubblePackageCandidate(
          level: BubblePackageRecognitionLevel.probable,
          detectedFormat: 'image-similarity',
          name: _packageName(scan.originalFileName),
          rolePath: best.$1.relativePath,
          userPath: best.$2.relativePath,
          previewPath: _previewPath(scan),
          reasons: [
            '两张图片尺寸接近',
            '水平镜像相似度 ${(bestScore * 100).toStringAsFixed(1)}%',
          ],
        );
      }
    }

    return BubblePackageCandidate(
      level: BubblePackageRecognitionLevel.partial,
      detectedFormat: 'image-assets',
      name: _packageName(scan.originalFileName),
      rolePath: images.first.relativePath,
      previewPath: _previewPath(scan),
      reasons: ['发现 ${images.length} 张图片，但无法可靠确定角色侧和用户侧'],
    );
  }

  double mirrorSimilarity(Uint8List firstBytes, Uint8List secondBytes) {
    final first = img.decodeImage(firstBytes);
    final second = img.decodeImage(secondBytes);
    if (first == null || second == null) return 0;
    final a = img.copyResize(first, width: 64, height: 64);
    final b = img.flipHorizontal(img.copyResize(second, width: 64, height: 64));
    var difference = 0.0;
    for (var y = 0; y < 64; y++) {
      for (var x = 0; x < 64; x++) {
        final pa = a.getPixel(x, y);
        final pb = b.getPixel(x, y);
        difference += (pa.r - pb.r).abs();
        difference += (pa.g - pb.g).abs();
        difference += (pa.b - pb.b).abs();
        difference += (pa.a - pb.a).abs();
      }
    }
    return (1 - difference / (64 * 64 * 4 * 255)).clamp(0, 1);
  }

  BubblePackageCandidate _detectManifest(
    BubblePackageScanResult scan,
    BubblePackageFile manifest,
    Map<String, dynamic> value,
  ) {
    if (value['formatVersion'] != 1) {
      return const BubblePackageCandidate(
        level: BubblePackageRecognitionLevel.failed,
        detectedFormat: 'whisnya-manifest',
        reasons: ['Whisnya manifest 版本不是 1'],
      );
    }
    final role = _referencedFile(scan, manifest, value['roleImage']);
    if (role == null || !role.isImage || role.isAnimated) {
      return const BubblePackageCandidate(
        level: BubblePackageRecognitionLevel.failed,
        detectedFormat: 'whisnya-manifest-v1',
        reasons: ['manifest 的 roleImage 不存在或不是支持的静态图片'],
      );
    }
    final user = _referencedFile(scan, manifest, value['userImage']);
    final preview = _referencedFile(scan, manifest, value['previewImage']);
    final stretch = _rect(value['stretchRegion']);
    final fill = _rect(value['fillRegion']);
    final padding = _insets(value['textPadding']);
    final invalidRegion = value['stretchRegion'] != null && stretch == null;
    final hasUserReference = value['userImage'] is String;
    final userInvalid = hasUserReference && (user == null || !user.isImage);
    final complete = user != null && !invalidRegion && !userInvalid;
    return BubblePackageCandidate(
      level: complete
          ? BubblePackageRecognitionLevel.exact
          : BubblePackageRecognitionLevel.partial,
      detectedFormat: 'whisnya-manifest-v1',
      name: _text(value['name']) ?? _packageName(scan.originalFileName),
      rolePath: role.relativePath,
      userPath: user?.relativePath,
      previewPath: preview?.relativePath,
      stretchRegion: stretch,
      fillRegion: fill,
      textPadding: padding,
      fillColor: _color(value['fillColor']),
      textColor: _color(value['textColor']),
      opacity: _number(value['fillOpacity'])?.clamp(0, 1),
      author: _text(value['author']),
      license: _text(value['license']),
      sourceDescription: _text(value['description']),
      reasons: const ['识别到 Whisnya 标准 manifest v1'],
      warnings: [
        if (user == null) 'manifest 未提供有效 userImage，需要用户选择处理方式',
        if (invalidRegion) 'stretchRegion 无效，已留给映射向导设置',
      ],
    );
  }

  Future<BubblePackageCandidate> _detectNinePatch(
    BubblePackageScanResult scan,
    List<BubblePackageFile> files,
  ) async {
    final warnings = <String>[];
    BubbleNinePatchData? parsed;
    for (final file in files) {
      try {
        parsed ??= _ninePatchParser.parse(await file.file.readAsBytes());
      } on BubblePackageException catch (error) {
        warnings.add('${file.fileName}：${error.message}');
      }
    }
    final pair = _pairByFileName(files);
    final role = pair?.$1 ?? files.first;
    final user = pair?.$2;
    final exact = files.length >= 2 && pair != null && parsed != null;
    return BubblePackageCandidate(
      level: exact
          ? BubblePackageRecognitionLevel.exact
          : BubblePackageRecognitionLevel.partial,
      detectedFormat: 'android-nine-patch',
      name: _packageName(scan.originalFileName),
      rolePath: role.relativePath,
      userPath: user?.relativePath,
      previewPath: _previewPath(scan),
      stretchRegion: parsed?.stretchRegion,
      textPadding: parsed?.textPadding,
      reasons: [
        '识别到 ${files.length} 张 Android .9.png',
        if (pair != null) '文件名明确区分角色侧和用户侧',
        if (parsed != null) '已读取拉伸区域和内容区域标记',
      ],
      warnings: warnings,
    );
  }

  Future<BubblePackageCandidate?> _detectCommonConfig(
    BubblePackageScanResult scan,
  ) async {
    for (final config in scan.files.where((file) => !file.isImage)) {
      final fields = await _configFields(config);
      if (fields.isEmpty) continue;
      final roleValue = _first(fields, const [
        'roleimage',
        'leftimage',
        'incomingimage',
        'receiveimage',
      ]);
      final userValue = _first(fields, const [
        'userimage',
        'rightimage',
        'outgoingimage',
        'sendimage',
      ]);
      final role = _referencedFile(scan, config, roleValue);
      final user = _referencedFile(scan, config, userValue);
      if (role == null) continue;
      return BubblePackageCandidate(
        level: user == null
            ? BubblePackageRecognitionLevel.partial
            : BubblePackageRecognitionLevel.exact,
        detectedFormat: 'common-${config.extension.substring(1)}-config',
        name: _packageName(scan.originalFileName),
        rolePath: role.relativePath,
        userPath: user?.relativePath,
        previewPath: _previewPath(scan),
        reasons: ['配置文件 ${config.fileName} 指定了气泡图片'],
      );
    }
    return null;
  }

  static Future<Map<String, dynamic>?> _readJson(BubblePackageFile file) async {
    try {
      final value = jsonDecode(await file.file.readAsString());
      return value is Map<String, dynamic> ? value : null;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, String>> _configFields(
    BubblePackageFile file,
  ) async {
    try {
      if (file.extension == '.json') {
        final value = jsonDecode(await file.file.readAsString());
        final result = <String, String>{};
        void visit(Object? node) {
          if (node is Map) {
            for (final entry in node.entries) {
              if (entry.value is String || entry.value is num) {
                result[entry.key.toString().toLowerCase()] = entry.value
                    .toString();
              }
              visit(entry.value);
            }
          } else if (node is List) {
            for (final child in node) {
              visit(child);
            }
          }
        }

        visit(value);
        return result;
      }
      final document = XmlDocument.parse(await file.file.readAsString());
      return {
        for (final element in document.descendants.whereType<XmlElement>())
          if (element.innerText.trim().isNotEmpty)
            element.localName.toLowerCase(): element.innerText.trim(),
      };
    } catch (_) {
      return const {};
    }
  }

  static BubblePackageFile? _referencedFile(
    BubblePackageScanResult scan,
    BubblePackageFile config,
    Object? rawPath,
  ) {
    if (rawPath is! String || rawPath.trim().isEmpty) return null;
    final reference = rawPath.trim().replaceAll('\\', '/');
    if (reference.startsWith('/') ||
        RegExp(r'^[A-Za-z]:').hasMatch(reference) ||
        reference.split('/').contains('..')) {
      return null;
    }
    final slash = config.relativePath.lastIndexOf('/');
    final parent = slash < 0 ? '' : config.relativePath.substring(0, slash + 1);
    return scan.find('$parent$reference');
  }

  static (BubblePackageFile, BubblePackageFile)? _pairByFileName(
    List<BubblePackageFile> files,
  ) {
    BubblePackageFile? role;
    BubblePackageFile? user;
    var roleScore = 0;
    var userScore = 0;
    for (final file in files) {
      final normalized = _normalizedName(file.fileName);
      final nextRole = _keywordScore(normalized, _roleKeywords);
      final nextUser = _keywordScore(normalized, _userKeywords);
      if (nextRole > nextUser && nextRole > roleScore) {
        role = file;
        roleScore = nextRole;
      }
      if (nextUser > nextRole && nextUser > userScore) {
        user = file;
        userScore = nextUser;
      }
    }
    return role == null || user == null || identical(role, user)
        ? null
        : (role, user);
  }

  static int _keywordScore(String name, List<String> keywords) {
    var score = 0;
    for (final keyword in keywords) {
      if (name.contains(keyword) && keyword.length > score) {
        score = keyword.length;
      }
    }
    return score;
  }

  static bool _isPreview(String name) {
    final normalized = _normalizedName(name);
    return _previewKeywords.any(normalized.contains);
  }

  static String? _previewPath(BubblePackageScanResult scan) => scan.files
      .where((file) => file.isImage && _isPreview(file.fileName))
      .firstOrNull
      ?.relativePath;

  static bool _similarDimensions(
    BubblePackageFile first,
    BubblePackageFile second,
  ) {
    if (first.width == null ||
        first.height == null ||
        second.width == null ||
        second.height == null) {
      return false;
    }
    return (first.width! - second.width!).abs() <=
            math.max(first.width!, second.width!) * .1 &&
        (first.height! - second.height!).abs() <=
            math.max(first.height!, second.height!) * .1;
  }

  static BubbleNormalizedRect? _rect(Object? value) {
    if (value is! Map) return null;
    final left = _number(value['left']);
    final top = _number(value['top']);
    final right = _number(value['right']);
    final bottom = _number(value['bottom']);
    if (left == null ||
        top == null ||
        right == null ||
        bottom == null ||
        left < 0 ||
        top < 0 ||
        right > 1 ||
        bottom > 1 ||
        left >= right ||
        top >= bottom) {
      return null;
    }
    return BubbleNormalizedRect(
      left: left,
      top: top,
      right: right,
      bottom: bottom,
    );
  }

  static BubbleContentInsets? _insets(Object? value) {
    if (value is! Map) return null;
    final left = _number(value['left']);
    final top = _number(value['top']);
    final right = _number(value['right']);
    final bottom = _number(value['bottom']);
    if (left == null ||
        top == null ||
        right == null ||
        bottom == null ||
        left < 0 ||
        top < 0 ||
        right < 0 ||
        bottom < 0) {
      return null;
    }
    return BubbleContentInsets(
      left: left,
      top: top,
      right: right,
      bottom: bottom,
    );
  }

  static double? _number(Object? value) => switch (value) {
    num number => number.toDouble(),
    String text => double.tryParse(text),
    _ => null,
  };

  static int? _color(Object? value) {
    if (value is int) return value;
    if (value is! String) return null;
    final text = value.replaceFirst('#', '');
    final parsed = int.tryParse(text, radix: 16);
    if (parsed == null) return null;
    return text.length == 6 ? 0xff000000 | parsed : parsed;
  }

  static String? _text(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;

  static String? _first(Map<String, String> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value != null) return value;
    }
    return null;
  }

  static String _normalizedName(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');

  static String _packageName(String fileName) =>
      fileName.replaceFirst(RegExp(r'\.zip$', caseSensitive: false), '');
}

const _roleKeywords = [
  'senderleft',
  'bubbleleft',
  'chatleft',
  'msgleft',
  'assistant',
  'incoming',
  'received',
  'receive',
  'friend',
  'other',
  'role',
  'recv',
  'left',
  'ai',
  '对方',
  '接收',
  '角色',
  '左',
];

const _userKeywords = [
  'senderright',
  'bubbleright',
  'chatright',
  'msgright',
  'outgoing',
  'right',
  'owner',
  'user',
  'self',
  'mine',
  'sent',
  'send',
  'me',
  '自己',
  '发送',
  '我的',
  '右',
];

const _previewKeywords = [
  'thumbnail',
  'preview',
  'thumb',
  'cover',
  'sample',
  'demo',
  'icon',
  '预览',
  '封面',
];
