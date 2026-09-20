import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import '../../models/app_settings.dart';
import '../../models/api_config.dart';
import '../../models/app_character.dart';
import '../../models/chat_session.dart';
import '../../models/chat_message.dart';
import '../../models/chat_summary.dart';
import '../../models/novel_book.dart';
import '../../models/theater.dart';
import '../../models/character_memory_entry.dart';
import '../../models/world_book.dart';
import '../../models/qq_integration_settings.dart';
import '../../models/qq_contact_binding.dart';

String backupPath(String name) {
  final normalized = name.replaceAll('\\', '/');
  final parts = normalized
      .split('/')
      .where((p) => p.isNotEmpty && p != '.')
      .toList();
  if (normalized.startsWith('/') ||
      normalized.contains(':') ||
      normalized.contains('\x00') ||
      parts.contains('..') ||
      parts.isEmpty ||
      parts.any(
        (p) =>
            p.endsWith('.') ||
            p.endsWith(' ') ||
            RegExp(
              r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(\.|$)',
              caseSensitive: false,
            ).hasMatch(p),
      )) {
    throw const FormatException('备份包含危险路径');
  }
  return parts.join('/');
}

Future<String> backupHash(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

Future<void> zipBackupDirectory(Directory source, File output) =>
    Isolate.run(() async {
      final encoder = ZipFileEncoder();
      encoder.create(output.path);
      final compressed = File('${output.path}.deflate');
      try {
        await for (final file in source.list(
          recursive: true,
          followLinks: false,
        )) {
          if (file is! File) continue;
          var crc = 0;
          await file
              .openRead()
              .map((chunk) {
                crc = getCrc32(chunk, crc);
                return chunk;
              })
              .transform(ZLibCodec(raw: true).encoder)
              .pipe(compressed.openWrite());
          final stream = InputFileStream(compressed.path);
          try {
            final entry =
                ArchiveFile.file(
                    file.path
                        .substring(source.path.length + 1)
                        .replaceAll('\\', '/'),
                    await file.length(),
                    _DeflatedFile(stream),
                  )
                  ..compression = CompressionType.deflate
                  ..crc32 = crc;
            encoder.addArchiveFile(entry);
          } finally {
            await stream.close();
          }
        }
      } finally {
        await encoder.close();
        if (await compressed.exists()) await compressed.delete();
      }
    });

class _DeflatedFile extends FileContentStream {
  _DeflatedFile(super.stream);
  @override
  bool get isCompressed => true;
}

class _OutputSink implements Sink<List<int>> {
  _OutputSink(this.output);
  final OutputStream output;
  @override
  void add(List<int> bytes) => output.writeBytes(bytes);
  @override
  void close() => output.flush();
}

class _BoundedOutput extends OutputFileStream {
  _BoundedOutput(String path, this.limit)
    : super.withFileHandle(FileHandle(path, mode: FileAccess.write));
  final int limit;
  int crc = 0;
  void check(int count) {
    if (length + count > limit) throw const FormatException('备份实际解压大小超过限制');
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    final count = length ?? bytes.length;
    check(count);
    crc = getCrc32(
      count == bytes.length ? bytes : bytes.sublist(0, count),
      crc,
    );
    super.writeBytes(bytes, length: count);
  }

  @override
  void writeByte(int value) {
    check(1);
    crc = getCrc32([value], crc);
    super.writeByte(value);
  }
}

Future<void> extractBackupFile(
  File zip,
  Directory staging,
) => Isolate.run(() async {
  const maxFile = 512 * 1024 * 1024;
  const maxTotal = 2 * 1024 * 1024 * 1024;
  if (await zip.length() > maxFile) throw const FormatException('ZIP 文件过大');
  final input = InputFileStream(zip.path);
  try {
    // Validate directory headers before decoding (Archive merges duplicate names).
    final directory = ZipDirectory()..read(input);
    if (directory.fileHeaders.length > 20000) {
      throw const FormatException('文件过多');
    }
    final paths = <String, bool>{};
    for (final header in directory.fileHeaders) {
      if (header.file?.filename != header.filename) {
        throw const FormatException('ZIP 本地路径与目录不一致');
      }
      if (header.file?.crc32 != header.crc32 ||
          header.file?.uncompressedSize != header.uncompressedSize) {
        throw const FormatException('ZIP 本地头与目录校验不一致');
      }
      final name = backupPath(header.filename).toLowerCase();
      final isDir =
          header.filename.endsWith('/') || header.filename.endsWith('\\');
      if ((header.externalFileAttributes >> 16 & 0xf000) == 0xa000 ||
          paths.containsKey(name)) {
        throw const FormatException('重复路径或符号链接');
      }
      paths[name] = isDir;
    }
    for (final name in paths.keys) {
      final parts = name.split('/');
      for (var i = 1; i < parts.length; i++) {
        if (paths[parts.take(i).join('/')] == false) {
          throw const FormatException('文件目录路径冲突');
        }
      }
    }
    input.reset();
    final archive = ZipDecoder().decodeStream(input);
    var total = 0;
    for (final entry in archive.files) {
      if (entry.isSymbolicLink) throw const FormatException('禁止符号链接');
      if (!entry.isFile) continue;
      if (entry.size < 0 || entry.size > maxFile) {
        throw const FormatException('单文件过大');
      }
      final file = File('${staging.path}/${backupPath(entry.name)}');
      await file.parent.create(recursive: true);
      final remaining = maxTotal - total;
      final output = _BoundedOutput(
        file.path,
        remaining < maxFile ? remaining : maxFile,
      );
      try {
        // archive 4.0.9's IO decoder accumulates all decoded chunks in a
        // withCallback sink. Feed native zlib into a non-accumulating sink.
        if (entry.compression == CompressionType.deflate) {
          final compressed = entry.rawContent!.getStream(decompress: false);
          final decoder = ZLibCodec(
            raw: true,
          ).decoder.startChunkedConversion(_OutputSink(output));
          while (!compressed.isEOS) {
            final count = compressed.length < 65536 ? compressed.length : 65536;
            decoder.add(compressed.readBytes(count).toUint8List());
          }
          decoder.close();
        } else {
          entry.writeContent(output);
        }
        if (output.length != entry.size || output.crc != entry.crc32) {
          throw const FormatException('ZIP CRC 或大小不匹配');
        }
        total += output.length;
      } finally {
        await output.close();
      }
    }
  } finally {
    await input.close();
  }
});

Future<dynamic> readBackupJson(File file) async =>
    jsonDecode(await file.readAsString());

Future<List<String>> backupAssetWarnings(Directory root) async {
  final warnings = <String>[];
  Future<void> inspect(dynamic value) async {
    if (value is List) {
      for (final item in value) {
        await inspect(item);
      }
    }
    if (value is! Map) return;
    for (final entry in value.entries) {
      if ({
            'avatar',
            'backgroundImage',
            'globalBackgroundImage',
            'textPath',
          }.contains(entry.key) &&
          entry.value is String) {
        final path = (entry.value as String).replaceAll('\\', '/');
        if (path.isEmpty ||
            path.startsWith('https://') ||
            path.startsWith('http://')) {
          continue;
        }
        final marker = path.lastIndexOf('/app_data/');
        final relative = marker >= 0 ? path.substring(marker + 10) : path;
        if (marker >= 0 ||
            !relative.contains(':') && !relative.startsWith('/')) {
          final safe = backupPath(relative);
          if (!await File('${root.path}/$safe').exists()) {
            if (entry.key == 'textPath') {
              throw const FormatException('小说正文文件缺失');
            }
            warnings.add('缺少可选图片：$safe，将使用默认显示');
          }
        } else {
          if (entry.key == 'textPath') {
            throw const FormatException('小说正文路径不属于备份目录');
          }
          warnings.add('图片路径不属于备份目录，将使用默认显示');
        }
      } else if (entry.value is Map || entry.value is List) {
        await inspect(entry.value);
      }
    }
  }

  for (final name in [
    'settings.json',
    'characters.json',
    'novels.json',
    'theater_sessions.json',
  ]) {
    final file = File('${root.path}/$name');
    if (await file.exists()) await inspect(await readBackupJson(file));
  }
  return warnings;
}

Future<void> validateBackupFiles(Directory directory) async {
  final manifest = await readBackupJson(
    File('${directory.path}/backup_manifest.json'),
  );
  if (manifest is! Map ||
      manifest['format'] != 1 ||
      ![null, 2, 3].contains(manifest['schemaVersion'])) {
    throw const FormatException('不支持的备份清单或版本');
  }
  final files = manifest['files'];
  if (files != null) {
    if (files is! List) throw const FormatException('文件清单格式异常');
    final listed = <String>{};
    for (final item in files) {
      if (item is! Map ||
          item['path'] is! String ||
          item['bytes'] is! int ||
          item['sha256'] is! String) {
        throw const FormatException('文件清单记录异常');
      }
      final path = backupPath(item['path'] as String);
      if (!listed.add(path.toLowerCase())) {
        throw const FormatException('文件清单重复');
      }
      final file = File('${directory.path}/$path');
      if (!await file.exists() ||
          await file.length() != item['bytes'] ||
          await backupHash(file) != item['sha256']) {
        throw FormatException('文件完整性校验失败：$path');
      }
    }
    await for (final file in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (file is File) {
        final path = file.path
            .substring(directory.path.length + 1)
            .replaceAll('\\', '/');
        if (path != 'backup_manifest.json' &&
            !listed.contains(path.toLowerCase())) {
          throw FormatException('未列入清单的文件：$path');
        }
      }
    }
  }
  final characters = <String>{};
  final sessions = <String, String>{};
  final books = <String>{};
  final theaters = <String>{};
  final hasCharacters = await File(
    '${directory.path}/characters.json',
  ).exists();
  for (final name in [
    'characters.json',
    'chat_sessions.json',
    'worldbooks.json',
    'novels.json',
    'theater_sessions.json',
  ]) {
    final file = File('${directory.path}/$name');
    if (!await file.exists()) continue;
    final value = await readBackupJson(file);
    if (value is! List) throw FormatException('$name 必须为列表');
    final ids = <String>{};
    for (final item in value) {
      if (item is! Map ||
          item['id'] is! String ||
          (item['id'] as String).isEmpty ||
          !ids.add(item['id'] as String)) {
        throw FormatException('$name 的 ID 无效或重复');
      }
      final id = item['id'] as String;
      if (backupPath(id) != id || id.contains('/')) {
        throw FormatException('$name ID 路径无效');
      }
      if (name == 'characters.json') characters.add(id);
      if (name == 'worldbooks.json') books.add(id);
      if (name == 'theater_sessions.json') theaters.add(id);
      if (name == 'chat_sessions.json') {
        if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id)) {
          throw const FormatException('会话 ID 无效');
        }
        final count = item['messageCount'];
        if (count != null && (count is! int || count < 0)) {
          throw const FormatException('会话消息计数无效');
        }
        final character = item['characterId'];
        if (character is! String ||
            character.isEmpty ||
            (hasCharacters && !characters.contains(character))) {
          throw const FormatException('会话角色关联异常');
        }
        sessions[id] = character;
        if (!await File('${directory.path}/chats/$id.json').exists()) {
          throw const FormatException('会话聊天文件缺失');
        }
      }
    }
  }
  await for (final file in directory.list(
    recursive: true,
    followLinks: false,
  )) {
    if (file is! File || !file.path.endsWith('.json')) continue;
    final name = file.path
        .substring(directory.path.length + 1)
        .replaceAll('\\', '/');
    final decoded = await readBackupJson(file);
    final value =
        name.startsWith('chats/') &&
            decoded is List &&
            sessions.isEmpty &&
            !await File('${directory.path}/chat_sessions.json').exists()
        ? <String, dynamic>{'messages': decoded}
        : decoded;
    try {
      if (name == 'config/qq_integration.json') {
        QqIntegrationSettings.fromJson(value as Map<String, dynamic>);
      }
      if (name == 'config/qq_contact_bindings.json') {
        for (final item in value as List) {
          QqContactBinding.fromJson(item as Map<String, dynamic>);
        }
      }
      if (name == 'settings.json') {
        AppSettings.fromJson(value as Map<String, dynamic>);
      }
      if (name == 'api_config.json') {
        ApiConfig.fromJson(value as Map<String, dynamic>);
      }
      if (name == 'characters.json') {
        for (final item in value as List) {
          AppCharacter.fromJson(item as Map<String, dynamic>);
        }
      }
      if (name == 'chat_sessions.json') {
        for (final item in value as List) {
          ChatSession.fromJson(item as Map<String, dynamic>);
        }
      }
      if (name == 'novels.json') {
        for (final item in value as List) {
          NovelBook.fromJson(item as Map<String, dynamic>);
        }
      }
      if (name == 'theater_sessions.json') {
        for (final item in value as List) {
          TheaterSession.fromJson(item as Map<String, dynamic>);
        }
      }
      if (name == 'worldbooks.json') {
        for (final item in value as List) {
          WorldBook.fromJson(item as Map<String, dynamic>);
        }
      }
      if (name.startsWith('summaries/')) {
        ChatSummary.fromJson(value as Map<String, dynamic>);
      }
      if (name.startsWith('chats/')) {
        for (final item in (value as Map)['messages'] as List) {
          ChatMessage.fromJson(item as Map<String, dynamic>);
        }
      }
      if (name.startsWith('memories/')) {
        for (final item in value as List) {
          CharacterMemoryEntry.fromJson(item as Map<String, dynamic>);
        }
      }
      if (name.startsWith('worldbook_entries/')) {
        for (final item in value as List) {
          WorldBookEntry.fromJson(item as Map<String, dynamic>);
        }
      }
      if (name.startsWith('theater_messages/')) {
        for (final item in value as List) {
          TheaterMessage.fromJson(item as Map<String, dynamic>);
        }
      }
    } catch (_) {
      throw FormatException('$name 字段类型异常');
    }
    if ([
          'settings.json',
          'api_config.json',
          'config/qq_integration.json',
        ].contains(name) &&
        value is! Map) {
      throw FormatException('$name 格式异常');
    }
    if (name == 'api_config.json' &&
        value is Map &&
        value['endpoints'] != null) {
      final endpoints = value['endpoints'];
      if (endpoints is! List) throw const FormatException('API endpoints 格式异常');
      final ids = <String>{};
      for (final endpoint in endpoints) {
        if (endpoint is! Map ||
            endpoint['id'] is! String ||
            !ids.add(endpoint['id'] as String) ||
            endpoint['baseUrl'] is! String) {
          throw const FormatException('API endpoint 无效');
        }
      }
    }
    if (name.startsWith('chats/') || name.startsWith('summaries/')) {
      if (value is! Map) throw FormatException('$name 必须为对象');
      final id = name.split('/').last.replaceFirst(RegExp(r'\.json$'), '');
      if (sessions.containsKey(id) &&
          (value['sessionId'] != id || value['characterId'] != sessions[id])) {
        throw FormatException('$name 会话映射冲突');
      }
      if (value['sessionId'] != null &&
          value['sessionId'] != '' &&
          value['sessionId'] != id) {
        throw FormatException('$name 会话 ID 冲突');
      }
      if (name.startsWith('chats/')) {
        final messages = value['messages'];
        if (messages is! List) throw FormatException('$name 消息格式异常');
        for (final message in messages) {
          if (message is! Map ||
              message['role'] is! String ||
              message['content'] is! String) {
            throw FormatException('$name 消息字段异常');
          }
          final variants = message['variants'];
          if (variants != null) {
            if (variants is! List ||
                variants.any(
                  (v) =>
                      v is! Map ||
                      v['content'] is! String ||
                      (v['content'] as String).trim().isEmpty,
                )) {
              throw FormatException('$name 候选无效');
            }
            final selected = message['selectedVariantIndex'] ?? 0;
            if (selected is! int ||
                selected < 0 ||
                (variants.isNotEmpty && selected >= variants.length)) {
              throw FormatException('$name 候选索引无效');
            }
          }
        }
      } else if (value['summary'] is! String ||
          (value['summarizedMessageCount'] != null &&
              value['summarizedMessageCount'] is! int)) {
        throw FormatException('$name 总结字段异常');
      }
    }
    if (name.startsWith('memories/') ||
        name.startsWith('worldbook_entries/') ||
        name.startsWith('theater_messages/')) {
      if (value is! List) throw FormatException('$name 必须为列表');
      final owner = name.split('/').last.replaceFirst(RegExp(r'\.json$'), '');
      final ids = <String>{};
      for (final item in value) {
        if (item is! Map ||
            item['id'] is! String ||
            !ids.add(item['id'] as String) ||
            item['content'] is! String) {
          throw FormatException('$name 条目无效');
        }
        if (name.startsWith('memories/') &&
            (item['characterId'] != owner ||
                (hasCharacters && !characters.contains(owner)))) {
          throw FormatException('$name 记忆角色关联异常');
        }
        if (name.startsWith('memories/') &&
            item['scope'] == 'session' &&
            sessions.isNotEmpty &&
            sessions[item['sessionId']] != owner) {
          throw FormatException('$name 记忆会话关联异常');
        }
        if (name.startsWith('worldbook_entries/') &&
            item['worldBookId'] != owner) {
          throw FormatException('$name 世界书条目关联异常');
        }
        if (name.startsWith('theater_messages/') &&
            (item['sessionId'] != owner || !theaters.contains(owner))) {
          throw FormatException('$name 剧场关联异常');
        }
      }
      if (name.startsWith('worldbook_entries/')) {
        final id = name.split('/').last.replaceFirst(RegExp(r'\.json$'), '');
        if (!books.contains(id)) throw FormatException('$name 世界书关联缺失');
      }
    }
  }
}
