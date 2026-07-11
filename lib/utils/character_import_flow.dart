import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/ai_provider.dart';
import '../models/app_character.dart';
import '../services/local_storage_service.dart';
import 'app_i18n.dart';
import 'role_import_parser.dart';
import 'snack.dart';

class CharacterImportSource {
  const CharacterImportSource({
    required this.name,
    required this.bytes,
    this.contentType = '',
  });

  final String name;
  final Uint8List bytes;
  final String contentType;
}

class CharacterImportFailure {
  const CharacterImportFailure(this.source, this.reason);

  final String source;
  final String reason;
}

class CharacterImportResult {
  const CharacterImportResult({
    this.imported = const [],
    this.failures = const [],
  });

  final List<AppCharacter> imported;
  final List<CharacterImportFailure> failures;
}

Future<bool> showCharacterImportFlow({
  required BuildContext context,
  required LocalStorageService storage,
}) async {
  final mode = await _chooseCharacterImportMode(context);
  if (mode == null || !context.mounted) return false;

  final service = CharacterImportService(storage);
  CharacterImportResult result;
  switch (mode) {
    case _CharacterImportMode.files:
      result = await _importPickedFiles(context, service, const [
        'json',
        'zip',
        'txt',
        'md',
      ]);
    case _CharacterImportMode.png:
      result = await _importPickedFiles(context, service, const ['png']);
    case _CharacterImportMode.url:
      final url = await _askImportUrl(context);
      if (url == null || url.trim().isEmpty) return false;
      result = await service.importUrl(url.trim());
  }

  if (!context.mounted) return result.imported.isNotEmpty;
  await _showCharacterImportResult(context, result);
  return result.imported.isNotEmpty;
}

class CharacterImportService {
  CharacterImportService(this.storage);

  static const maxZipBytes = 50 * 1024 * 1024;
  static const maxJsonBytes = 5 * 1024 * 1024;
  static const maxUrlBytes = 20 * 1024 * 1024;

  final LocalStorageService storage;
  int _sequence = 0;

  Future<CharacterImportResult> importSources(
    List<CharacterImportSource> sources,
  ) async {
    final imported = <AppCharacter>[];
    final failures = <CharacterImportFailure>[];
    final usedNames = (await storage.loadCharacters())
        .map((character) => character.name.trim())
        .where((name) => name.isNotEmpty)
        .toSet();

    for (final source in sources) {
      try {
        final result = await _importSource(source, usedNames);
        imported.addAll(result.imported);
        failures.addAll(result.failures);
      } on _CharacterImportException catch (error) {
        failures.add(CharacterImportFailure(source.name, error.message));
      } catch (error) {
        failures.add(CharacterImportFailure(source.name, error.toString()));
      }
    }

    return CharacterImportResult(imported: imported, failures: failures);
  }

  Future<CharacterImportResult> importUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      return const CharacterImportResult(
        failures: [CharacterImportFailure('url', '请输入有效 URL。')],
      );
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return const CharacterImportResult(
        failures: [CharacterImportFailure('url', '当前仅支持 HTTP/HTTPS 文件直链。')],
      );
    }

    final client = http.Client();
    try {
      final request = http.Request('GET', uri)..followRedirects = true;
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return CharacterImportResult(
          failures: [
            CharacterImportFailure('url', '下载失败：HTTP ${response.statusCode}。'),
          ],
        );
      }
      final length = response.contentLength;
      if (length != null && length > maxUrlBytes) {
        return const CharacterImportResult(
          failures: [CharacterImportFailure('url', '文件过大，暂不支持导入。')],
        );
      }

      var total = 0;
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 30),
      )) {
        total += chunk.length;
        if (total > maxUrlBytes) {
          return const CharacterImportResult(
            failures: [CharacterImportFailure('url', '文件过大，暂不支持导入。')],
          );
        }
        builder.add(chunk);
      }

      final source = CharacterImportSource(
        name: _urlFileName(response.request?.url ?? uri),
        bytes: builder.takeBytes(),
        contentType: response.headers['content-type'] ?? '',
      );
      return importSources([source]);
    } on TimeoutException {
      return const CharacterImportResult(
        failures: [CharacterImportFailure('url', '下载超时，请稍后重试。')],
      );
    } catch (error) {
      return CharacterImportResult(
        failures: [CharacterImportFailure('url', '下载失败：$error')],
      );
    } finally {
      client.close();
    }
  }

  Future<CharacterImportResult> _importSource(
    CharacterImportSource source,
    Set<String> usedNames,
  ) async {
    final format = _detectFormat(source);
    return switch (format) {
      _ImportFormat.zip => _importZip(source, usedNames),
      _ImportFormat.png => _importPng(source, usedNames),
      _ImportFormat.unsupportedImage => throw const _CharacterImportException(
        'JPG 图片不能作为角色卡导入，请使用 JSON 或带内嵌角色数据的 PNG 角色卡。',
      ),
      _ImportFormat.json => _importJson(source.bytes, source.name, usedNames),
      _ImportFormat.text => _importText(source, usedNames),
      _ImportFormat.html => _importHtml(source, usedNames),
      null => throw const _CharacterImportException(
        '当前仅支持角色卡文件直链，请复制 JSON/PNG/ZIP/TXT/MD 文件下载链接。',
      ),
    };
  }

  Future<CharacterImportResult> _importZip(
    CharacterImportSource source,
    Set<String> usedNames,
  ) async {
    if (source.bytes.length > maxZipBytes) {
      throw const _CharacterImportException('文件过大，暂不支持导入。');
    }

    final archive = ZipDecoder().decodeBytes(source.bytes);
    if (archive.findFile('character.json') != null) {
      final character = await storage.importCharacterPackage(source.bytes);
      final renamed = await _renameIfNeeded(character, usedNames);
      return CharacterImportResult(imported: [renamed]);
    }

    final imported = <AppCharacter>[];
    final failures = <CharacterImportFailure>[];
    final jsonFiles = archive.files.where(
      (file) => file.isFile && _extension(file.name) == 'json',
    );

    for (final file in jsonFiles) {
      final bytes = _archiveBytes(file);
      if (bytes.length > maxJsonBytes) {
        failures.add(CharacterImportFailure(file.name, '角色卡 JSON 过大。'));
        continue;
      }
      try {
        imported.addAll(
          (await _importJson(bytes, file.name, usedNames)).imported,
        );
      } on _CharacterImportException catch (error) {
        failures.add(CharacterImportFailure(file.name, error.message));
      } catch (_) {
        failures.add(CharacterImportFailure(file.name, 'JSON 格式错误。'));
      }
    }

    if (imported.isEmpty && failures.isEmpty) {
      throw const _CharacterImportException('ZIP 中未找到可识别的角色卡 JSON。');
    }
    return CharacterImportResult(imported: imported, failures: failures);
  }

  Future<CharacterImportResult> _importPng(
    CharacterImportSource source,
    Set<String> usedNames,
  ) async {
    for (final text in _pngTextValues(source.bytes)) {
      final jsonText = _decodeMaybeBase64(text);
      if (jsonText == null) continue;
      try {
        return _importJson(
          Uint8List.fromList(utf8.encode(jsonText)),
          source.name,
          usedNames,
          imageBytes: source.bytes,
        );
      } catch (_) {
        // Try the next PNG metadata field.
      }
    }
    throw const _CharacterImportException('该 PNG 未检测到内嵌角色卡数据。');
  }

  Future<CharacterImportResult> _importJson(
    Uint8List bytes,
    String sourceName,
    Set<String> usedNames, {
    Uint8List? imageBytes,
  }) async {
    if (bytes.length > maxJsonBytes) {
      throw const _CharacterImportException('角色卡 JSON 过大。');
    }
    final decoded = _decodeJson(bytes);
    final maps = switch (decoded) {
      Map<String, dynamic> map => [map],
      List<dynamic> list => list.whereType<Map<String, dynamic>>().toList(),
      _ => const <Map<String, dynamic>>[],
    };
    if (maps.isEmpty) {
      throw const _CharacterImportException('未识别到有效角色卡字段。');
    }

    final imported = <AppCharacter>[];
    for (final map in maps) {
      final parsed = RoleImportParser.parseJson(map);
      _ensureUseful(parsed, '未识别到有效角色卡字段。');
      imported.add(
        await _saveParsed(
          parsed,
          _fileTitle(sourceName),
          usedNames,
          imageBytes: imageBytes,
        ),
      );
    }
    return CharacterImportResult(imported: imported);
  }

  Future<CharacterImportResult> _importText(
    CharacterImportSource source,
    Set<String> usedNames,
  ) async {
    final parsed = RoleImportParser.parse(
      utf8.decode(source.bytes, allowMalformed: true),
    );
    _ensureUseful(parsed, '未识别到名称、简介、性格等角色字段。');
    return CharacterImportResult(
      imported: [await _saveParsed(parsed, _fileTitle(source.name), usedNames)],
    );
  }

  Future<CharacterImportResult> _importHtml(
    CharacterImportSource source,
    Set<String> usedNames,
  ) async {
    final parsed = parsePromptPageHtmlForImport(
      utf8.decode(source.bytes, allowMalformed: true),
    );
    if (parsed == null) {
      throw const _CharacterImportException('该网页未找到可导入的角色卡或提示词内容。');
    }
    return CharacterImportResult(
      imported: [await _saveParsed(parsed, _fileTitle(source.name), usedNames)],
    );
  }

  Future<AppCharacter> _saveParsed(
    ParsedRoleFields parsed,
    String fallbackName,
    Set<String> usedNames, {
    Uint8List? imageBytes,
  }) async {
    final now = DateTime.now();
    final id = 'character_${now.microsecondsSinceEpoch}_${_sequence++}';
    final name = _uniqueName(
      parsed.name.trim().isEmpty ? fallbackName : parsed.name.trim(),
      usedNames,
    );
    final imagePath = imageBytes == null
        ? ''
        : await storage.saveMediaImage(
            folder: 'avatars',
            characterId: id,
            bytes: imageBytes,
          );
    final character = AppCharacter(
      id: id,
      name: name,
      avatar: imagePath,
      backgroundImage: imagePath,
      backgroundImageOpacity: 1,
      backgroundBlur: 0,
      bubbleOpacity: 0.92,
      inputOpacity: 0.92,
      description: parsed.description,
      personality: parsed.personality,
      background: parsed.background,
      speakingStyle: parsed.speakingStyle,
      openingMessage: parsed.openingMessage,
      extraPrompt: parsed.extraPrompt,
      defaultProvider: AiProvider.deepseek,
      createdAt: now,
      updatedAt: now,
      lastUsedAt: now,
    );
    await storage.saveCharacter(character);
    usedNames.add(name);
    return character;
  }

  Future<AppCharacter> _renameIfNeeded(
    AppCharacter character,
    Set<String> usedNames,
  ) async {
    final name = _uniqueName(character.name, usedNames);
    final renamed = name == character.name
        ? character
        : character.copyWith(name: name);
    if (renamed.name != character.name) {
      await storage.saveCharacter(renamed);
    }
    usedNames.add(renamed.name);
    return renamed;
  }

  dynamic _decodeJson(Uint8List bytes) {
    try {
      return jsonDecode(_stripBom(utf8.decode(bytes)));
    } on FormatException {
      throw const _CharacterImportException('JSON 格式错误。');
    }
  }

  void _ensureUseful(ParsedRoleFields parsed, String message) {
    final hasContent = [
      parsed.description,
      parsed.personality,
      parsed.background,
      parsed.speakingStyle,
      parsed.openingMessage,
      parsed.extraPrompt,
    ].any((value) => value.trim().isNotEmpty);
    if (!hasContent) {
      throw _CharacterImportException(message);
    }
  }
}

enum _CharacterImportMode { files, png, url }

enum _ImportFormat { zip, png, json, text, html, unsupportedImage }

class _CharacterImportException implements Exception {
  const _CharacterImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

Future<_CharacterImportMode?> _chooseCharacterImportMode(BuildContext context) {
  return showDialog<_CharacterImportMode>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.t('选择导入方式')),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _importOptionTile(
                context,
                icon: Icons.description_outlined,
                title: '从文件导入角色卡',
                subtitle: '支持 JSON / ZIP / TXT / MD',
                mode: _CharacterImportMode.files,
              ),
              _importOptionTile(
                context,
                icon: Icons.image_outlined,
                title: '导入 PNG 角色卡',
                subtitle: '支持带内嵌角色数据的 PNG 图片',
                mode: _CharacterImportMode.png,
              ),
              _importOptionTile(
                context,
                icon: Icons.link,
                title: '从 URL 导入角色卡',
                subtitle: '粘贴 JSON / PNG / ZIP / TXT / MD 文件直链',
                mode: _CharacterImportMode.url,
              ),
              const Divider(height: 28),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  context.t('支持 Whisnya 角色包、酒馆 JSON/PNG 角色卡、TXT/MD 设定文本和文件直链。'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.t('取消')),
        ),
      ],
    ),
  );
}

Widget _importOptionTile(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String subtitle,
  required _CharacterImportMode mode,
}) {
  return ListTile(
    leading: Icon(icon),
    title: Text(context.t(title)),
    subtitle: Text(context.t(subtitle)),
    onTap: () => Navigator.of(context).pop(mode),
  );
}

Future<CharacterImportResult> _importPickedFiles(
  BuildContext context,
  CharacterImportService service,
  List<String> extensions,
) async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: extensions,
    allowMultiple: true,
    withData: true,
  );
  if (result == null || result.files.isEmpty) {
    return const CharacterImportResult();
  }

  final sources = <CharacterImportSource>[];
  final failures = <CharacterImportFailure>[];
  for (final picked in result.files) {
    final name = picked.name;
    try {
      final bytes =
          picked.bytes ??
          (picked.path == null ? null : await File(picked.path!).readAsBytes());
      if (bytes == null) {
        failures.add(CharacterImportFailure(name, '无法读取文件。'));
      } else {
        sources.add(CharacterImportSource(name: name, bytes: bytes));
      }
    } catch (error) {
      failures.add(CharacterImportFailure(name, '读取本地文件失败：$error'));
    }
  }

  final imported = await service.importSources(sources);
  return CharacterImportResult(
    imported: imported.imported,
    failures: [...failures, ...imported.failures],
  );
}

Future<String?> _askImportUrl(BuildContext context) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.t('从 URL 导入角色卡')),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(
          labelText: context.t('文件直链'),
          hintText: 'https://example.com/role.json',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.t('取消')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text.trim()),
          child: Text(context.t('确认')),
        ),
      ],
    ),
  ).whenComplete(controller.dispose);
}

Future<void> _showCharacterImportResult(
  BuildContext context,
  CharacterImportResult result,
) async {
  if (result.imported.isEmpty && result.failures.isEmpty) return;

  final message = result.failures.isEmpty
      ? (result.imported.length == 1
            ? '已导入角色：${result.imported.single.name}'
            : '已导入 ${result.imported.length} 个角色')
      : '已导入 ${result.imported.length} 个，失败 ${result.failures.length} 个';
  context.showSnack(message);

  if (result.failures.isEmpty) return;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.t('查看失败原因')),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final failure in result.failures)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('${failure.source}：${context.t(failure.reason)}'),
                ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.t('关闭')),
        ),
      ],
    ),
  );
}

_ImportFormat? _detectFormat(CharacterImportSource source) {
  final bytes = source.bytes;
  final contentType = source.contentType.toLowerCase();
  final extension = _extension(source.name);
  if (_hasZipHeader(bytes)) return _ImportFormat.zip;
  if (_hasPngHeader(bytes)) return _ImportFormat.png;
  if (_hasJpegHeader(bytes) || _hasWebpHeader(bytes)) {
    return _ImportFormat.unsupportedImage;
  }
  if (contentType.contains('zip') || extension == 'zip') {
    return _ImportFormat.zip;
  }
  if (contentType.contains('png') || extension == 'png') {
    return _ImportFormat.png;
  }
  if (contentType.contains('jpeg') ||
      contentType.contains('jpg') ||
      contentType.contains('webp') ||
      extension == 'jpg' ||
      extension == 'jpeg' ||
      extension == 'webp') {
    return _ImportFormat.unsupportedImage;
  }
  if (contentType.contains('json') || extension == 'json') {
    return _ImportFormat.json;
  }
  if (extension == 'txt' ||
      extension == 'md' ||
      contentType.startsWith('text/plain') ||
      contentType.contains('markdown')) {
    return _ImportFormat.text;
  }
  if (_looksLikeHtml(bytes) || contentType.contains('html')) {
    return _ImportFormat.html;
  }
  final text = utf8
      .decode(
        bytes.take(math.min(bytes.length, 64)).toList(),
        allowMalformed: true,
      )
      .trimLeft();
  if (text.startsWith('{') || text.startsWith('[')) return _ImportFormat.json;
  if (text.isNotEmpty) return _ImportFormat.text;
  return null;
}

bool _hasZipHeader(Uint8List bytes) {
  return bytes.length >= 4 &&
      bytes[0] == 0x50 &&
      bytes[1] == 0x4b &&
      (bytes[2] == 0x03 || bytes[2] == 0x05 || bytes[2] == 0x07) &&
      (bytes[3] == 0x04 || bytes[3] == 0x06 || bytes[3] == 0x08);
}

bool _hasPngHeader(Uint8List bytes) {
  const header = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  return bytes.length >= header.length &&
      Iterable<int>.generate(header.length).every((i) => bytes[i] == header[i]);
}

bool _hasJpegHeader(Uint8List bytes) {
  return bytes.length >= 3 &&
      bytes[0] == 0xff &&
      bytes[1] == 0xd8 &&
      bytes[2] == 0xff;
}

bool _hasWebpHeader(Uint8List bytes) {
  return bytes.length >= 12 &&
      ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
      ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP';
}

bool _looksLikeHtml(Uint8List bytes) {
  final text = utf8
      .decode(
        bytes.take(math.min(bytes.length, 256)).toList(),
        allowMalformed: true,
      )
      .trimLeft()
      .toLowerCase();
  return text.startsWith('<!doctype html') || text.startsWith('<html');
}

String _extension(String name) {
  final clean = name.split('?').first.split('#').first;
  final index = clean.lastIndexOf('.');
  if (index < 0 || index == clean.length - 1) return '';
  return clean.substring(index + 1).toLowerCase();
}

String _fileTitle(String path) {
  final name = path.split(RegExp(r'[\\/]')).last;
  final title = name.replaceFirst(RegExp(r'\.[^.]+$'), '').trim();
  return title.isEmpty ? '未命名角色' : title;
}

String _urlFileName(Uri uri) {
  final segment = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
  return segment.trim().isEmpty ? 'url' : segment;
}

String _uniqueName(String rawName, Set<String> usedNames) {
  final base = rawName.trim().isEmpty ? '未命名角色' : rawName.trim();
  if (!usedNames.contains(base)) return base;
  var index = 2;
  while (usedNames.contains('$base ($index)')) {
    index++;
  }
  return '$base ($index)';
}

Uint8List _archiveBytes(ArchiveFile file) {
  return Uint8List.fromList((file.content as List<int>));
}

List<String> _pngTextValues(Uint8List bytes) {
  if (!_hasPngHeader(bytes)) return const [];
  final values = <String>[];
  var offset = 8;
  while (offset + 12 <= bytes.length) {
    final length = _uint32(bytes, offset);
    final typeStart = offset + 4;
    final dataStart = offset + 8;
    final dataEnd = dataStart + length;
    if (dataEnd + 4 > bytes.length) break;
    final type = ascii.decode(bytes.sublist(typeStart, typeStart + 4));
    final data = bytes.sublist(dataStart, dataEnd);
    if (type == 'tEXt') {
      final split = data.indexOf(0);
      if (split >= 0) values.add(latin1.decode(data.sublist(split + 1)));
    } else if (type == 'zTXt') {
      final split = data.indexOf(0);
      if (split >= 0 && split + 2 < data.length) {
        try {
          values.add(
            utf8.decode(ZLibDecoder().decodeBytes(data.sublist(split + 2))),
          );
        } catch (_) {}
      }
    } else if (type == 'iTXt') {
      final parsed = _parseInternationalText(data);
      if (parsed != null) values.add(parsed);
    }
    if (type == 'IEND') break;
    offset = dataEnd + 4;
  }
  return values;
}

String? _parseInternationalText(Uint8List data) {
  var offset = data.indexOf(0);
  if (offset < 0 || offset + 2 >= data.length) return null;
  final compressed = data[offset + 1] == 1;
  offset += 3;
  final languageEnd = data.indexOf(0, offset);
  if (languageEnd < 0) return null;
  offset = languageEnd + 1;
  final translatedEnd = data.indexOf(0, offset);
  if (translatedEnd < 0) return null;
  final textBytes = data.sublist(translatedEnd + 1);
  try {
    return utf8.decode(
      compressed ? ZLibDecoder().decodeBytes(textBytes) : textBytes,
    );
  } catch (_) {
    return null;
  }
}

String? _decodeMaybeBase64(String text) {
  final trimmed = _stripBom(text.trim());
  if (trimmed.startsWith('{') || trimmed.startsWith('[')) return trimmed;
  for (final candidate in {
    trimmed,
    _padBase64(trimmed),
    _padBase64Url(trimmed),
  }) {
    try {
      final decoded = _stripBom(utf8.decode(base64.decode(candidate)));
      final normalized = decoded.trimLeft();
      if (normalized.startsWith('{') || normalized.startsWith('[')) {
        return decoded;
      }
    } catch (_) {}
  }
  try {
    final decoded = Uri.decodeComponent(trimmed);
    final normalized = decoded.trimLeft();
    if (normalized.startsWith('{') || normalized.startsWith('[')) {
      return decoded;
    }
  } catch (_) {}
  return null;
}

ParsedRoleFields? parsePromptPageHtmlForImport(String html) {
  final fallbackTitle = _htmlTagText(html, 'title');
  for (final match in _jsonLdScriptPattern.allMatches(html)) {
    try {
      final parsed = _findPromptJsonLd(
        jsonDecode(_htmlUnescape(match.group(1)?.trim() ?? '')),
      );
      if (parsed != null) {
        return parsed.name.isEmpty && fallbackTitle.isNotEmpty
            ? ParsedRoleFields(
                name: fallbackTitle,
                description: parsed.description,
                extraPrompt: parsed.extraPrompt,
              )
            : parsed;
      }
    } catch (_) {
      // Ignore unrelated or invalid JSON-LD blocks.
    }
  }
  return null;
}

final _jsonLdScriptPattern = RegExp(
  r'''<script\b[^>]*type=["']application/ld\+json["'][^>]*>(.*?)</script>''',
  caseSensitive: false,
  dotAll: true,
);

ParsedRoleFields? _findPromptJsonLd(
  Object? value, {
  String name = '',
  String description = '',
}) {
  if (value is List) {
    for (final item in value) {
      final parsed = _findPromptJsonLd(
        item,
        name: name,
        description: description,
      );
      if (parsed != null) return parsed;
    }
    return null;
  }
  if (value is! Map) return null;

  final currentName = _jsonText(
    value['name'] ?? value['headline'] ?? value['title'],
  );
  final currentDescription = _jsonText(value['description']);
  final inheritedName = currentName.isEmpty ? name : currentName;
  final inheritedDescription = currentDescription.isEmpty
      ? description
      : currentDescription;

  for (final child in [
    ..._oneOrMany(value['hasPart']),
    ..._oneOrMany(value['@graph']),
  ]) {
    final parsed = _findPromptJsonLd(
      child,
      name: inheritedName,
      description: inheritedDescription,
    );
    if (parsed != null) return parsed;
  }

  final text = _jsonText(value['text']);
  final type = _jsonText(value['additionalType']);
  final format = _jsonText(value['encodingFormat']);
  if (text.isNotEmpty &&
      (type.contains('SoftwareSourceCode') || format.contains('text/plain'))) {
    return ParsedRoleFields(
      name: inheritedName,
      description: inheritedDescription,
      extraPrompt: text,
    );
  }
  return null;
}

Iterable<Object?> _oneOrMany(Object? value) {
  return value is List ? value : [?value];
}

String _jsonText(Object? value) {
  if (value == null) return '';
  if (value is String) return _htmlUnescape(value).trim();
  return value.toString().trim();
}

String _htmlTagText(String html, String tag) {
  final match = RegExp(
    '<$tag\\b[^>]*>(.*?)</$tag>',
    caseSensitive: false,
    dotAll: true,
  ).firstMatch(html);
  return _htmlUnescape(
    match?.group(1)?.replaceAll(RegExp(r'<[^>]+>'), '') ?? '',
  ).trim();
}

String _htmlUnescape(String value) {
  return value
      .replaceAll('&quot;', '"')
      .replaceAll('&#34;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');
}

String _stripBom(String value) {
  return value.startsWith('\ufeff') ? value.substring(1) : value;
}

String _padBase64(String value) {
  return value.padRight(value.length + (4 - value.length % 4) % 4, '=');
}

String _padBase64Url(String value) {
  return _padBase64(value.replaceAll('-', '+').replaceAll('_', '/'));
}

int _uint32(Uint8List bytes, int offset) {
  return (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];
}
