import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../models/api_config.dart';
import '../models/ai_usage.dart';
import '../models/app_character.dart';
import '../models/app_settings.dart';
import '../models/chat_message.dart';
import '../models/chat_session.dart';
import '../models/chat_summary.dart';
import '../models/novel_book.dart';
import '../models/theater.dart';
import '../utils/password_lock.dart';
import '../utils/role_import_parser.dart';
import 'storage/json_file_store.dart';
import 'storage/media_store.dart';

String restoreAppDataPath(String path, String appDataPath) {
  if (path.trim().isEmpty) {
    return path;
  }
  final normalized = path.replaceAll('\\', '/');
  const marker = '/app_data/';
  final markerIndex = normalized.lastIndexOf(marker);
  if (markerIndex < 0) {
    return path;
  }
  final relative = normalized.substring(markerIndex + marker.length);
  if (relative.isEmpty || relative.startsWith('/')) {
    return path;
  }
  final separator = Platform.pathSeparator;
  return '$appDataPath$separator${relative.replaceAll('/', separator)}';
}

Map<String, dynamic> redactApiKeysForExport(Map<String, dynamic> json) {
  final copy = _jsonCopy(json) as Map<String, dynamic>;
  final endpoints = copy['endpoints'];
  if (endpoints is List) {
    copy['endpoints'] = [
      for (final endpoint in endpoints)
        if (endpoint is Map)
          {..._stringKeyMap(endpoint), 'apiKey': ''}
        else
          endpoint,
    ];
  }
  for (final key in const ['grok', 'deepseek', 'gpt']) {
    final provider = copy[key];
    if (provider is Map) {
      copy[key] = {..._stringKeyMap(provider), 'apiKey': ''};
    }
  }
  return copy;
}

dynamic _jsonCopy(dynamic value) {
  if (value is Map) {
    return {
      for (final entry in value.entries)
        entry.key.toString(): _jsonCopy(entry.value),
    };
  }
  if (value is List) {
    return [for (final item in value) _jsonCopy(item)];
  }
  return value;
}

Map<String, dynamic> _stringKeyMap(Map<dynamic, dynamic> value) {
  return {
    for (final entry in value.entries)
      entry.key.toString(): _jsonCopy(entry.value),
  };
}

class StorageException implements Exception {
  StorageException(this.message);

  final String message;

  @override
  String toString() => message;
}

Future<void> validateBackupDirectory(Directory directory) async {
  final separator = Platform.pathSeparator;
  final manifest = File('${directory.path}${separator}backup_manifest.json');
  if (!await manifest.exists()) {
    throw StorageException('备份文件缺少 backup_manifest.json');
  }
  final manifestJson = await _readBackupJson(manifest);
  if (manifestJson is! Map<String, dynamic>) {
    throw StorageException('备份清单格式异常');
  }

  Future<void> optionalJson(String name, bool Function(dynamic) isValid) async {
    final file = File('${directory.path}$separator$name');
    if (!await file.exists()) return;
    final decoded = await _readBackupJson(file);
    if (!isValid(decoded)) {
      throw StorageException('备份文件 $name 格式异常');
    }
  }

  await optionalJson('settings.json', (value) => value is Map<String, dynamic>);
  await optionalJson(
    'api_config.json',
    (value) => value is Map<String, dynamic>,
  );
  await optionalJson('characters.json', (value) => value is List);
  await optionalJson('novels.json', (value) => value is List);
  await optionalJson('theater_sessions.json', (value) => value is List);
}

Future<dynamic> _readBackupJson(File file) async {
  try {
    return jsonDecode(await file.readAsString());
  } on FormatException {
    throw StorageException('备份文件 JSON 异常：${file.path}');
  } on FileSystemException catch (error) {
    throw StorageException('读取备份文件失败：${error.message}');
  }
}

class LocalStorageService {
  LocalStorageService({
    FlutterSecureStorage? secureStorage,
    Directory? appDataDirectory,
    JsonFileStore? jsonStore,
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage(),
       jsonStore = jsonStore ?? JsonFileStore() {
    _appDataDirectory = appDataDirectory;
  }

  static const _secureApiKeyIndexKey = 'whisnya_api_endpoint_ids';
  static const _secureApiKeyPrefix = 'whisnya_api_key_';

  final FlutterSecureStorage _secureStorage;
  final JsonFileStore jsonStore;
  Directory? _appDataDirectory;
  final _recoveryMessages = <String>[];

  List<String> takeRecoveryMessages() {
    final messages = List<String>.from(_recoveryMessages);
    _recoveryMessages.clear();
    return messages;
  }

  Future<Directory> get appDataDirectory async {
    if (_appDataDirectory != null) {
      await _ensureAppDataDirectories(_appDataDirectory!);
      return _appDataDirectory!;
    }

    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(
      '${documents.path}${Platform.pathSeparator}app_data',
    );
    await _ensureAppDataDirectories(directory);
    _appDataDirectory = directory;
    return directory;
  }

  Future<void> ensureReady() async {
    final directory = await appDataDirectory;
    unawaited(MediaStore(directory).cleanupTemporaryFiles());
  }

  Future<void> _ensureAppDataDirectories(Directory directory) async {
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    for (final name in const [
      'chats',
      'summaries',
      'media',
      'novels',
      'novel_chats',
      'novel_summary_cache',
      'theater_messages',
    ]) {
      await Directory(
        '${directory.path}${Platform.pathSeparator}$name',
      ).create(recursive: true);
    }
  }

  Future<AppSettings> loadSettings() async {
    final file = await _settingsFile();
    final decoded = await _readJson(
      file,
      const AppSettings().toJson(),
      recoverOnInvalid: true,
    );
    if (decoded is! Map<String, dynamic>) {
      throw StorageException('设置文件异常：${file.path}');
    }
    return AppSettings.fromJson(decoded);
  }

  Future<void> saveSettings(AppSettings settings) async {
    await _writeJson(await _settingsFile(), settings.toJson());
  }

  Future<AppSettings?> upgradePrivacyPasswordHashIfNeeded(
    AppSettings settings,
    String password,
  ) async {
    if (!settings.hasPrivacyPassword ||
        !PasswordLock.needsRehash(settings.privacyPasswordHash)) {
      return null;
    }
    final next = settings.copyWith(
      privacyPasswordHash: PasswordLock.hash(
        password,
        settings.privacyPasswordSalt,
      ),
    );
    await saveSettings(next);
    return next;
  }

  Future<ApiConfig> loadApiConfig() async {
    final file = await _apiConfigFile();
    final decoded = await _readJson(file, ApiConfig.defaults().toJson());
    if (decoded is! Map<String, dynamic>) {
      throw StorageException('API 配置文件异常：${file.path}');
    }
    var config = ApiConfig.fromJson(decoded);
    if (_hasApiKeys(config)) {
      await _writeSecureApiKeys(config);
      config = _configWithoutApiKeys(config);
      await _writeJson(file, config.toJson());
    }
    return _withSecureApiKeys(config);
  }

  Future<void> saveApiConfig(ApiConfig config) async {
    await _writeSecureApiKeys(config);
    await _writeJson(
      await _apiConfigFile(),
      _configWithoutApiKeys(config).toJson(),
    );
  }

  Future<List<AiUsageRecord>> loadAiUsageRecords() async {
    final decoded = await _readJson(await _aiUsageFile(), <dynamic>[]);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(AiUsageRecord.fromJson)
        .toList();
  }

  Future<void> saveAiUsageRecord(AiUsageRecord record) async {
    final file = await _aiUsageFile();
    await _enqueueWrite(file, () async {
      final decoded = await _readJsonNow(file, <dynamic>[]);
      final records = decoded is List
          ? decoded
                .whereType<Map<String, dynamic>>()
                .map(AiUsageRecord.fromJson)
                .toList()
          : <AiUsageRecord>[];
      await _writeJsonNow(
        file,
        appendAiUsageRecord(
          records,
          record,
        ).map((item) => item.toJson()).toList(),
      );
    });
  }

  Future<void> recordAiUsage({
    required String requestType,
    required String model,
    required AiUsage usage,
    required List<Map<String, String>> messages,
    required bool summaryUpdated,
  }) => saveAiUsageRecord(
    AiUsageRecord.fromRequest(
      requestType: requestType,
      model: model,
      usage: usage,
      messages: messages,
      summaryUpdated: summaryUpdated,
    ),
  );

  bool _hasApiKeys(ApiConfig config) {
    return config.endpoints.any(
      (endpoint) => endpoint.apiKey.trim().isNotEmpty,
    );
  }

  ApiConfig _configWithoutApiKeys(ApiConfig config) {
    return config.copyWith(
      endpoints: [
        for (final endpoint in config.endpoints) endpoint.copyWith(apiKey: ''),
      ],
    );
  }

  Future<ApiConfig> _withSecureApiKeys(ApiConfig config) async {
    final endpoints = <AiEndpointConfig>[];
    for (final endpoint in config.endpoints) {
      final apiKey = await _secureStorage.read(
        key: _secureApiKeyKey(endpoint.id),
      );
      endpoints.add(
        apiKey == null ? endpoint : endpoint.copyWith(apiKey: apiKey),
      );
    }
    return config.copyWith(endpoints: endpoints);
  }

  Future<void> _writeSecureApiKeys(ApiConfig config) async {
    final previousIds = await _readSecureApiKeyIds();
    final nextIds = <String>{};
    for (final endpoint in config.endpoints) {
      final apiKey = endpoint.apiKey.trim();
      final key = _secureApiKeyKey(endpoint.id);
      if (apiKey.isEmpty) {
        await _secureStorage.delete(key: key);
      } else {
        await _secureStorage.write(key: key, value: apiKey);
        nextIds.add(endpoint.id);
      }
    }
    for (final id in previousIds.difference(nextIds)) {
      await _secureStorage.delete(key: _secureApiKeyKey(id));
    }
    await _writeSecureApiKeyIds(nextIds);
  }

  Future<Set<String>> _readSecureApiKeyIds() async {
    final raw = await _secureStorage.read(key: _secureApiKeyIndexKey);
    if (raw == null || raw.trim().isEmpty) return <String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded.whereType<String>().toSet();
    } on FormatException {
      return <String>{};
    }
    return <String>{};
  }

  Future<void> _writeSecureApiKeyIds(Set<String> ids) async {
    if (ids.isEmpty) {
      await _secureStorage.delete(key: _secureApiKeyIndexKey);
      return;
    }
    final sorted = ids.toList()..sort();
    await _secureStorage.write(
      key: _secureApiKeyIndexKey,
      value: jsonEncode(sorted),
    );
  }

  String _secureApiKeyKey(String endpointId) {
    return '$_secureApiKeyPrefix${base64UrlEncode(utf8.encode(endpointId))}';
  }

  Future<List<AppCharacter>> loadCharacters() async {
    final file = await _charactersFile();
    final decoded = await _readJson(file, <dynamic>[], recoverOnInvalid: true);
    if (decoded is! List) {
      throw StorageException('角色文件异常：${file.path}');
    }
    final characters = decoded
        .whereType<Map<String, dynamic>>()
        .map(AppCharacter.fromJson)
        .where((character) => character.id.isNotEmpty)
        .toList();
    if (characters.isEmpty) {
      await _recoverMissingCharacters(characters);
    }
    return characters..sort((a, b) {
      if (a.isPinned != b.isPinned) {
        return a.isPinned ? -1 : 1;
      }
      return b.lastUsedAt.compareTo(a.lastUsedAt);
    });
  }

  Future<void> saveCharacter(AppCharacter character) async {
    await _updateCharacters((characters) {
      final index = characters.indexWhere((item) => item.id == character.id);
      if (index >= 0) {
        characters[index] = character;
      } else {
        characters.add(character);
      }
      return characters;
    });
  }

  Future<void> markCharacterUsed(String characterId) async {
    await _updateCharacters((characters) {
      final index = characters.indexWhere((item) => item.id == characterId);
      if (index >= 0) {
        characters[index] = characters[index].copyWith(
          lastUsedAt: DateTime.now(),
        );
      }
      return characters;
    });
  }

  Future<void> deleteCharacter(String characterId) async {
    final deleted = <AppCharacter>[];
    await _updateCharacters((characters) {
      deleted.addAll(
        characters.where((character) => character.id == characterId),
      );
      characters.removeWhere((character) => character.id == characterId);
      return characters;
    });
    for (final character in deleted) {
      await _deleteAppMediaFile(character.avatar);
      await _deleteAppMediaFile(character.backgroundImage);
    }
    final chat = await _chatFile(characterId);
    if (await chat.exists()) {
      await chat.delete();
    }
    final summary = await _summaryFile(characterId);
    if (await summary.exists()) {
      await summary.delete();
    }
  }

  Future<ChatSession> loadChat(String characterId) async {
    final file = await _chatFile(characterId);
    final decoded = await _readJson(
      file,
      ChatSession.empty(characterId).toJson(),
    );
    if (decoded is! Map<String, dynamic>) {
      throw StorageException('聊天记录文件异常：${file.path}');
    }
    return ChatSession.fromJson(decoded).copyWith(characterId: characterId);
  }

  Future<void> saveChat(String characterId, List<ChatMessage> messages) async {
    await _writeJson(
      await _chatFile(characterId),
      ChatSession(characterId: characterId, messages: messages).toJson(),
    );
  }

  Future<void> clearChat(String characterId) => saveChat(characterId, const []);

  Future<List<NovelBook>> loadNovels() async {
    final file = await _novelsFile();
    final decoded = await _readJson(file, <dynamic>[], recoverOnInvalid: true);
    if (decoded is! List) {
      throw StorageException('小说文件异常：${file.path}');
    }
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(NovelBook.fromJson)
        .where((book) => book.id.isNotEmpty && book.textPath.isNotEmpty)
        .toList()
      ..sort((a, b) => b.lastOpenedSortTime.compareTo(a.lastOpenedSortTime));
  }

  Future<NovelBook> importNovelText({
    required String title,
    required String content,
  }) async {
    final now = DateTime.now();
    final id = 'novel_${now.microsecondsSinceEpoch}';
    final file = await _novelTextFile(id);
    await file.writeAsString(content, flush: true);
    final book = NovelBook(
      id: id,
      title: title.trim().isEmpty ? '未命名小说' : title.trim(),
      textPath: file.path,
      createdAt: now,
      updatedAt: now,
    );
    await saveNovel(book);
    return book;
  }

  Future<String> loadNovelText(NovelBook book) async {
    final file = File(book.textPath);
    if (!await file.exists()) {
      throw StorageException('小说正文不存在：${book.textPath}');
    }
    return file.readAsString();
  }

  Future<void> saveNovel(NovelBook book) async {
    await _updateNovels((books) {
      final index = books.indexWhere((item) => item.id == book.id);
      if (index >= 0) {
        books[index] = book;
      } else {
        books.add(book);
      }
      return books;
    });
  }

  Future<void> deleteNovel(NovelBook book) async {
    await _updateNovels((books) {
      books.removeWhere((item) => item.id == book.id);
      return books;
    });
    final textFile = File(book.textPath);
    if (await textFile.exists()) {
      await textFile.delete();
    }
    final chat = await _novelChatFile(book.id);
    if (await chat.exists()) {
      await chat.delete();
    }
    final chatSummary = await _summaryFile('novel_chat_${book.id}');
    if (await chatSummary.exists()) await chatSummary.delete();
    await _deleteAppMediaFile(book.chatBackgroundImage);
  }

  Future<ChatSession> loadNovelChat(String novelId) async {
    final file = await _novelChatFile(novelId);
    final decoded = await _readJson(file, ChatSession.empty(novelId).toJson());
    if (decoded is! Map<String, dynamic>) {
      throw StorageException('小说聊天记录异常：${file.path}');
    }
    return ChatSession.fromJson(decoded).copyWith(characterId: novelId);
  }

  Future<void> saveNovelChat(String novelId, List<ChatMessage> messages) async {
    await _writeJson(
      await _novelChatFile(novelId),
      ChatSession(characterId: novelId, messages: messages).toJson(),
    );
  }

  Future<void> clearNovelChat(String novelId) async {
    await saveNovelChat(novelId, const []);
    final summary = await _summaryFile('novel_chat_$novelId');
    if (await summary.exists()) await summary.delete();
  }

  Future<ChatSummary> loadSummary(String characterId) async {
    final file = await _summaryFile(characterId);
    final decoded = await _readJson(
      file,
      ChatSummary.empty(characterId).toJson(),
    );
    if (decoded is! Map<String, dynamic>) {
      throw StorageException('总结文件异常：${file.path}');
    }
    final summary = ChatSummary.fromJson(decoded);
    return summary.characterId.isEmpty
        ? ChatSummary.empty(characterId)
        : summary;
  }

  Future<void> saveSummary(ChatSummary summary) async {
    await _writeJson(await _summaryFile(summary.characterId), summary.toJson());
  }

  Future<List<TheaterSession>> loadTheaterSessions() async {
    final file = await _theaterSessionsFile();
    final decoded = await _readJson(file, <dynamic>[], recoverOnInvalid: true);
    if (decoded is! List) {
      throw StorageException('群聊文件异常：${file.path}');
    }
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(TheaterSession.fromJson)
        .where((session) => session.id.isNotEmpty)
        .toList()
      ..sort((a, b) => b.lastOpenedSortTime.compareTo(a.lastOpenedSortTime));
  }

  Future<void> saveTheaterSession(TheaterSession session) async {
    await _updateTheaterSessions((sessions) {
      final index = sessions.indexWhere((item) => item.id == session.id);
      if (index >= 0) {
        sessions[index] = session;
      } else {
        sessions.add(session);
      }
      return sessions;
    });
  }

  Future<void> deleteTheaterSession(String sessionId) async {
    await _updateTheaterSessions((sessions) {
      sessions.removeWhere((session) => session.id == sessionId);
      return sessions;
    });
    final messages = await _theaterMessagesFile(sessionId);
    if (await messages.exists()) {
      await messages.delete();
    }
  }

  Future<List<TheaterMessage>> loadTheaterMessages(String sessionId) async {
    final file = await _theaterMessagesFile(sessionId);
    final decoded = await _readJson(file, <dynamic>[]);
    if (decoded is! List) {
      throw StorageException('群聊消息文件异常：${file.path}');
    }
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(TheaterMessage.fromJson)
        .where((message) => message.id.isNotEmpty)
        .toList()
      ..sort((a, b) => a.time.compareTo(b.time));
  }

  Future<void> saveTheaterMessages(
    String sessionId,
    List<TheaterMessage> messages,
  ) async {
    await _writeJson(
      await _theaterMessagesFile(sessionId),
      messages.map((message) => message.toJson()).toList(),
    );
  }

  Future<void> clearTheaterMessages(String sessionId) =>
      saveTheaterMessages(sessionId, const []);

  Future<Uint8List> exportCharacterPackage(AppCharacter character) async {
    final archive = Archive();
    final characterJson = character.toJson();

    await _addMediaFile(
      archive,
      sourcePath: character.avatar,
      exportName: 'avatar.jpg',
      json: characterJson,
      jsonKey: 'avatar',
    );
    await _addMediaFile(
      archive,
      sourcePath: character.backgroundImage,
      exportName: 'background.jpg',
      json: characterJson,
      jsonKey: 'backgroundImage',
    );

    archive.addFile(
      ArchiveFile.string(
        'character.json',
        const JsonEncoder.withIndent('  ').convert(characterJson),
      ),
    );
    archive.addFile(
      ArchiveFile.string(
        '角色设定.txt',
        RoleImportParser.formatCharacter(character),
      ),
    );

    final summary = await loadSummary(character.id);
    archive.addFile(
      ArchiveFile.string(
        'summary.json',
        const JsonEncoder.withIndent('  ').convert(summary.toJson()),
      ),
    );

    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  Future<AppCharacter> importCharacterPackage(Uint8List bytes) async {
    final archive = ZipDecoder().decodeBytes(bytes);
    final characterFile = archive.findFile('character.json');
    if (characterFile == null) {
      throw StorageException('角色包缺少 character.json');
    }

    final decoded = jsonDecode(utf8.decode(characterFile.content as List<int>));
    if (decoded is! Map<String, dynamic>) {
      throw StorageException('角色包 character.json 异常');
    }

    final now = DateTime.now();
    final oldId = decoded['id'] as String? ?? '';
    final newId = 'character_${now.microsecondsSinceEpoch}';
    decoded['id'] = newId;
    decoded['isPinned'] = false;
    decoded['createdAt'] = now.toIso8601String();
    decoded['updatedAt'] = now.toIso8601String();
    decoded['lastUsedAt'] = now.toIso8601String();

    decoded['avatar'] = await _importPackagedMedia(
      archive,
      decoded['avatar'] as String?,
      'avatars',
      newId,
    );
    decoded['backgroundImage'] = await _importPackagedMedia(
      archive,
      decoded['backgroundImage'] as String?,
      'backgrounds',
      newId,
    );

    final character = AppCharacter.fromJson(decoded);
    await saveCharacter(character);

    final summaryFile = archive.findFile('summary.json');
    if (summaryFile != null) {
      final summaryJson = jsonDecode(
        utf8.decode(summaryFile.content as List<int>),
      );
      if (summaryJson is Map<String, dynamic>) {
        summaryJson['characterId'] = newId;
        await saveSummary(ChatSummary.fromJson(summaryJson));
      }
    } else if (oldId.isNotEmpty) {
      await saveSummary(ChatSummary.empty(newId));
    }

    return character;
  }

  Future<Uint8List> exportAllData({bool includeApiKeys = false}) async {
    final directory = await appDataDirectory;
    final archive = Archive();
    archive.addFile(
      ArchiveFile.string(
        'backup_manifest.json',
        const JsonEncoder.withIndent(
          '  ',
        ).convert({'format': 1, 'appDataPath': directory.path}),
      ),
    );
    await for (final entity in directory.list(recursive: true)) {
      if (entity is! File) {
        continue;
      }
      var bytes = await entity.readAsBytes();
      final name = entity.path
          .substring(directory.path.length + 1)
          .replaceAll(Platform.pathSeparator, '/');
      if (name == 'api_config.json') {
        try {
          final decoded = jsonDecode(utf8.decode(bytes));
          if (decoded is Map<String, dynamic>) {
            final exportJson = includeApiKeys
                ? (await _withSecureApiKeys(
                    ApiConfig.fromJson(decoded),
                  )).toJson()
                : redactApiKeysForExport(decoded);
            bytes = Uint8List.fromList(
              utf8.encode(
                const JsonEncoder.withIndent('  ').convert(exportJson),
              ),
            );
          }
        } on FormatException {
          // Keep export behavior unchanged for a corrupt API config file.
        }
      }
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  Future<void> importAllData(Uint8List bytes) async {
    final directory = await appDataDirectory;
    final parent = directory.parent;
    final separator = Platform.pathSeparator;
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final temp = Directory('${parent.path}${separator}app_data_import_$stamp');
    final backup = Directory(
      '${parent.path}${separator}app_data_backup_$stamp',
    );
    Directory? movedBackup;

    try {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
      await temp.create(recursive: true);

      final archive = ZipDecoder().decodeBytes(bytes);
      for (final file in archive.files) {
        if (!file.isFile) {
          continue;
        }
        final safeName = file.name.replaceAll('\\', '/');
        final parts = safeName.split('/');
        if (safeName.startsWith('/') || parts.contains('..')) {
          continue;
        }
        final outPath =
            '${temp.path}$separator${safeName.replaceAll('/', separator)}';
        final outFile = File(outPath);
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(file.content as List<int>, flush: true);
      }

      await validateBackupDirectory(temp);

      if (await backup.exists()) {
        await backup.delete(recursive: true);
      }
      if (await directory.exists()) {
        await directory.rename(backup.path);
        movedBackup = backup;
      }
      await temp.rename(directory.path);
      _appDataDirectory = directory;
      await _ensureAppDataDirectories(directory);
      await _repairRestoredAppDataPaths(directory);
      await _migrateApiKeysFromJsonFile(await _apiConfigFile());
      if (movedBackup != null && await movedBackup.exists()) {
        await movedBackup.delete(recursive: true);
      }
    } catch (_) {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
      if (movedBackup != null && await movedBackup.exists()) {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
        await movedBackup.rename(directory.path);
      }
      _appDataDirectory = directory;
      rethrow;
    }
  }

  Future<void> _migrateApiKeysFromJsonFile(File file) async {
    if (!await file.exists()) {
      await _writeSecureApiKeys(ApiConfig.defaults());
      return;
    }
    final decoded = await _readJson(file, ApiConfig.defaults().toJson());
    if (decoded is! Map<String, dynamic>) {
      throw StorageException('API 配置文件异常：${file.path}');
    }
    await saveApiConfig(ApiConfig.fromJson(decoded));
  }

  Future<void> _repairRestoredAppDataPaths(Directory directory) async {
    String fixPath(String path) => restoreAppDataPath(path, directory.path);

    Future<void> updateJson(
      String name,
      void Function(dynamic decoded) update,
    ) async {
      final file = File('${directory.path}${Platform.pathSeparator}$name');
      if (!await file.exists()) {
        return;
      }
      try {
        final decoded = jsonDecode(await file.readAsString());
        update(decoded);
        await _writeJsonNow(file, decoded);
      } on FormatException {
        return;
      }
    }

    await updateJson('settings.json', (decoded) {
      if (decoded is Map<String, dynamic>) {
        decoded['globalBackgroundImage'] = fixPath(
          decoded['globalBackgroundImage'] as String? ?? '',
        );
      }
    });
    await updateJson('characters.json', (decoded) {
      if (decoded is! List) {
        return;
      }
      for (final item in decoded.whereType<Map<String, dynamic>>()) {
        item['avatar'] = fixPath(item['avatar'] as String? ?? '');
        item['backgroundImage'] = fixPath(
          item['backgroundImage'] as String? ?? '',
        );
      }
    });
    await updateJson('novels.json', (decoded) {
      if (decoded is! List) {
        return;
      }
      for (final item in decoded.whereType<Map<String, dynamic>>()) {
        item['textPath'] = fixPath(item['textPath'] as String? ?? '');
        item['chatBackgroundImage'] = fixPath(
          item['chatBackgroundImage'] as String? ?? '',
        );
      }
    });
    await updateJson('theater_sessions.json', (decoded) {
      if (decoded is! List) {
        return;
      }
      for (final item in decoded.whereType<Map<String, dynamic>>()) {
        item['avatar'] = fixPath(item['avatar'] as String? ?? '');
        item['backgroundImage'] = fixPath(
          item['backgroundImage'] as String? ?? '',
        );
        final rawParticipants = item['participants'];
        if (rawParticipants is! List) continue;
        for (final participant
            in rawParticipants.whereType<Map<String, dynamic>>()) {
          participant['avatar'] = fixPath(
            participant['avatar'] as String? ?? '',
          );
        }
      }
    });
  }

  Future<String> saveMediaImage({
    required String folder,
    required String characterId,
    required Uint8List bytes,
  }) async {
    final directory = await _mediaDirectory(folder);
    final safeCharacterId = characterId.replaceAll(
      RegExp(r'[^a-zA-Z0-9_-]'),
      '_',
    );
    final file = File(
      '${directory.path}${Platform.pathSeparator}${safeCharacterId}_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<File> saveTemporaryImage(Uint8List bytes) async {
    final directory = await _mediaDirectory('temp');
    final file = File(
      '${directory.path}${Platform.pathSeparator}picked_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<File> _apiConfigFile() async {
    final directory = await appDataDirectory;
    return File('${directory.path}${Platform.pathSeparator}api_config.json');
  }

  Future<File> _aiUsageFile() async {
    final directory = await appDataDirectory;
    return File('${directory.path}${Platform.pathSeparator}ai_usage.json');
  }

  Future<File> _settingsFile() async {
    final directory = await appDataDirectory;
    return File('${directory.path}${Platform.pathSeparator}settings.json');
  }

  Future<File> _charactersFile() async {
    final directory = await appDataDirectory;
    return File('${directory.path}${Platform.pathSeparator}characters.json');
  }

  Future<File> _novelsFile() async {
    final directory = await appDataDirectory;
    return File('${directory.path}${Platform.pathSeparator}novels.json');
  }

  Future<File> _chatFile(String characterId) async {
    final directory = await appDataDirectory;
    return File(
      '${directory.path}${Platform.pathSeparator}chats${Platform.pathSeparator}$characterId.json',
    );
  }

  Future<File> _novelTextFile(String novelId) async {
    final directory = await appDataDirectory;
    return File(
      '${directory.path}${Platform.pathSeparator}novels${Platform.pathSeparator}$novelId.txt',
    );
  }

  Future<File> _novelChatFile(String novelId) async {
    final directory = await appDataDirectory;
    return File(
      '${directory.path}${Platform.pathSeparator}novel_chats${Platform.pathSeparator}$novelId.json',
    );
  }

  Future<File> _summaryFile(String characterId) async {
    final directory = await appDataDirectory;
    return File(
      '${directory.path}${Platform.pathSeparator}summaries${Platform.pathSeparator}$characterId.json',
    );
  }

  Future<File> _theaterSessionsFile() async {
    final directory = await appDataDirectory;
    return File(
      '${directory.path}${Platform.pathSeparator}theater_sessions.json',
    );
  }

  Future<File> _theaterMessagesFile(String sessionId) async {
    final directory = await appDataDirectory;
    return File(
      '${directory.path}${Platform.pathSeparator}theater_messages${Platform.pathSeparator}$sessionId.json',
    );
  }

  Future<Directory> _mediaDirectory(String folder) async {
    final directory = await appDataDirectory;
    final mediaDirectory = Directory(
      '${directory.path}${Platform.pathSeparator}media${Platform.pathSeparator}$folder',
    );
    if (!await mediaDirectory.exists()) {
      await mediaDirectory.create(recursive: true);
    }
    return mediaDirectory;
  }

  Future<void> _deleteAppMediaFile(String path) async {
    if (path.trim().isEmpty) {
      return;
    }

    final directory = await appDataDirectory;
    final mediaRoot =
        '${directory.path}${Platform.pathSeparator}media${Platform.pathSeparator}';
    if (!path.startsWith(mediaRoot)) {
      return;
    }

    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<void> _addMediaFile(
    Archive archive, {
    required String sourcePath,
    required String exportName,
    required Map<String, dynamic> json,
    required String jsonKey,
  }) async {
    final file = File(sourcePath);
    if (sourcePath.trim().isEmpty || !await file.exists()) {
      json[jsonKey] = '';
      return;
    }

    final bytes = await file.readAsBytes();
    archive.addFile(ArchiveFile(exportName, bytes.length, bytes));
    json[jsonKey] = exportName;
  }

  Future<String> _importPackagedMedia(
    Archive archive,
    String? name,
    String folder,
    String characterId,
  ) async {
    if (name == null || name.trim().isEmpty) {
      return '';
    }
    final file = archive.findFile(name.replaceAll('\\', '/'));
    if (file == null || !file.isFile) {
      return '';
    }
    return saveMediaImage(
      folder: folder,
      characterId: characterId,
      bytes: Uint8List.fromList(file.content as List<int>),
    );
  }

  Future<dynamic> _readJson(
    File file,
    dynamic fallback, {
    bool recoverOnInvalid = false,
  }) async {
    await jsonStore.waitFor(file);
    await jsonStore.recover(file);
    return _readJsonNow(file, fallback, recoverOnInvalid: recoverOnInvalid);
  }

  Future<dynamic> _readJsonNow(
    File file,
    dynamic fallback, {
    bool recoverOnInvalid = false,
  }) async {
    if (!await file.exists()) {
      await _writeJsonNow(file, fallback);
      return fallback;
    }

    try {
      final content = await file.readAsString();
      if (content.trim().isEmpty) {
        if (recoverOnInvalid) {
          final backupPath = await _backupInvalidJson(file);
          _recoveryMessages.add(_jsonRecoveryMessage(file, backupPath));
        }
        await _writeJsonNow(file, fallback);
        return fallback;
      }
      return jsonDecode(content);
    } on FormatException catch (_) {
      final backupPath = await _backupInvalidJson(file);
      await _writeJsonNow(file, fallback);
      final message = _jsonRecoveryMessage(file, backupPath);
      if (!recoverOnInvalid) {
        throw StorageException(message);
      }
      _recoveryMessages.add(message);
      return fallback;
    } on FileSystemException catch (error) {
      throw StorageException('读取本地文件失败：${error.message}');
    }
  }

  Future<void> _writeJson(File file, dynamic data) =>
      _enqueueWrite(file, () => _writeJsonNow(file, data));

  Future<T> _enqueueWrite<T>(File file, Future<T> Function() action) =>
      jsonStore.synchronized(file, action);

  Future<void> _writeJsonNow(File file, dynamic data) async {
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    final parentName = file.parent.uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .lastOrNull;
    final compact = const {
      'chats',
      'novel_chats',
      'theater_messages',
    }.contains(parentName);
    await jsonStore.writeNow(file, data, compact: compact);
  }

  Future<void> _updateCharacters(
    List<AppCharacter> Function(List<AppCharacter>) update,
  ) async {
    final file = await _charactersFile();
    await _enqueueWrite(file, () async {
      final decoded = await _readJsonNow(
        file,
        <dynamic>[],
        recoverOnInvalid: true,
      );
      if (decoded is! List) {
        throw StorageException('角色文件异常：${file.path}');
      }
      final characters = decoded
          .whereType<Map<String, dynamic>>()
          .map(AppCharacter.fromJson)
          .where((character) => character.id.isNotEmpty)
          .toList();
      final next = update(characters);
      await _writeJsonNow(
        file,
        next.map((character) => character.toJson()).toList(),
      );
    });
  }

  Future<void> _updateNovels(
    List<NovelBook> Function(List<NovelBook>) update,
  ) async {
    final file = await _novelsFile();
    await _enqueueWrite(file, () async {
      final decoded = await _readJsonNow(
        file,
        <dynamic>[],
        recoverOnInvalid: true,
      );
      if (decoded is! List) {
        throw StorageException('小说文件异常：${file.path}');
      }
      final books = decoded
          .whereType<Map<String, dynamic>>()
          .map(NovelBook.fromJson)
          .where((book) => book.id.isNotEmpty)
          .toList();
      final next = update(books);
      await _writeJsonNow(file, next.map((book) => book.toJson()).toList());
    });
  }

  Future<void> _updateTheaterSessions(
    List<TheaterSession> Function(List<TheaterSession>) update,
  ) async {
    final file = await _theaterSessionsFile();
    await _enqueueWrite(file, () async {
      final decoded = await _readJsonNow(
        file,
        <dynamic>[],
        recoverOnInvalid: true,
      );
      if (decoded is! List) {
        throw StorageException('群聊文件异常：${file.path}');
      }
      final sessions = decoded
          .whereType<Map<String, dynamic>>()
          .map(TheaterSession.fromJson)
          .where((session) => session.id.isNotEmpty)
          .toList();
      final next = update(sessions);
      await _writeJsonNow(
        file,
        next.map((session) => session.toJson()).toList(),
      );
    });
  }

  Future<void> _recoverMissingCharacters(List<AppCharacter> characters) async {
    final existingIds = characters.map((character) => character.id).toSet();
    final ids = <String>{};
    await _collectJsonFileIds('chats', ids);
    await _collectJsonFileIds('summaries', ids);
    await _collectMediaFileIds('avatars', ids);
    await _collectMediaFileIds('backgrounds', ids);
    ids.removeAll(existingIds);
    if (ids.isEmpty) {
      return;
    }

    for (final id in ids) {
      final avatar = await _latestMediaPath('avatars', id);
      final background = await _latestMediaPath('backgrounds', id);
      final lastUsedAt = await _latestKnownTime(id, [avatar, background]);
      characters.add(
        AppCharacter.fromJson({
          'id': id,
          'name': '恢复角色',
          'avatar': avatar,
          'backgroundImage': background,
          'description': '从本地聊天记录恢复，请重新补全角色设定。',
          'createdAt': lastUsedAt.toIso8601String(),
          'updatedAt': DateTime.now().toIso8601String(),
          'lastUsedAt': lastUsedAt.toIso8601String(),
        }),
      );
    }

    await _writeJson(
      await _charactersFile(),
      characters.map((character) => character.toJson()).toList(),
    );
  }

  Future<void> _collectJsonFileIds(String folder, Set<String> ids) async {
    final directory = Directory(
      '${(await appDataDirectory).path}${Platform.pathSeparator}$folder',
    );
    if (!await directory.exists()) {
      return;
    }
    await for (final entity in directory.list()) {
      if (entity is! File) {
        continue;
      }
      final name = entity.path.split(Platform.pathSeparator).last;
      if (name.endsWith('.json')) {
        ids.add(name.substring(0, name.length - 5));
      }
    }
  }

  Future<void> _collectMediaFileIds(String folder, Set<String> ids) async {
    final directory = await _mediaDirectory(folder);
    await for (final entity in directory.list()) {
      if (entity is! File) {
        continue;
      }
      final name = entity.path.split(Platform.pathSeparator).last;
      final match = RegExp(r'^(character_\d+)_').firstMatch(name);
      if (match != null) {
        ids.add(match.group(1)!);
      }
    }
  }

  Future<String> _latestMediaPath(String folder, String characterId) async {
    final directory = await _mediaDirectory(folder);
    File? latest;
    DateTime? latestTime;
    await for (final entity in directory.list()) {
      if (entity is! File) {
        continue;
      }
      final name = entity.path.split(Platform.pathSeparator).last;
      if (!name.startsWith('${characterId}_')) {
        continue;
      }
      final time = await entity.lastModified();
      if (latestTime == null || time.isAfter(latestTime)) {
        latest = entity;
        latestTime = time;
      }
    }
    return latest?.path ?? '';
  }

  Future<DateTime> _latestKnownTime(
    String characterId,
    List<String> media,
  ) async {
    var latest = DateTime.fromMillisecondsSinceEpoch(0);
    for (final file in [
      await _chatFile(characterId),
      await _summaryFile(characterId),
      ...media.where((path) => path.isNotEmpty).map(File.new),
    ]) {
      if (await file.exists()) {
        final modified = await file.lastModified();
        if (modified.isAfter(latest)) {
          latest = modified;
        }
      }
    }
    return latest.millisecondsSinceEpoch == 0 ? DateTime.now() : latest;
  }

  String _jsonRecoveryMessage(File file, String backupPath) {
    return '数据文件损坏：${file.path}\n已自动备份到：$backupPath\n已重建默认文件。';
  }

  Future<String> _backupInvalidJson(File file) async {
    if (!await file.exists()) {
      return '';
    }
    final backup = File(
      '${file.path}.broken_${DateTime.now().microsecondsSinceEpoch}',
    );
    await file.rename(backup.path);
    return backup.path;
  }
}
