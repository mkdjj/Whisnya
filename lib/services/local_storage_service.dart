import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../models/api_config.dart';
import '../models/ai_usage.dart';
import '../models/app_character.dart';
import '../models/app_settings.dart';
import '../models/chat_message.dart';
import '../models/message_anchor.dart';
import '../models/chat_session.dart';
import '../models/chat_summary.dart';
import '../models/character_memory_entry.dart';
import '../models/novel_book.dart';
import '../models/qq_contact_binding.dart';
import '../models/qq_diagnostic_event.dart';
import '../models/qq_integration_settings.dart';
import '../models/theater.dart';
import '../models/world_book.dart';
import '../utils/password_lock.dart';
import '../utils/role_import_parser.dart';
import '../utils/safe_zip.dart';
import 'storage/json_file_store.dart';
import 'storage/backup_files.dart';
import 'storage/session_operation_coordinator.dart';
import 'storage/character_recovery_service.dart';
import 'chat/chat_session_service.dart';
import 'qq/qq_exceptions.dart';
import 'storage/media_store.dart' as media_store;
import 'storage/storage_paths.dart';
import 'story/story_checkpoint_service.dart';
import 'story/character_state_service.dart';
import 'memento_service.dart';
import 'story/story_backup_validation.dart';
import 'auto_story/auto_story_backup.dart';
import 'auto_story/auto_story_store.dart';

List<T> _upsert<T>(List<T> items, T value, String Function(T) id) {
  final index = items.indexWhere((item) => id(item) == id(value));
  index < 0 ? items.add(value) : items[index] = value;
  return items;
}

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
  dynamic redact(dynamic value) {
    if (value is List) return value.map(redact).toList();
    if (value is Map) {
      return <String, dynamic>{
        for (final entry in value.entries)
          entry.key as String:
              {
                'apikey',
                'apikeys',
                'bridgetoken',
                'localbridgetoken',
                'accesstoken',
                'authorization',
                'token',
                'secret',
              }.contains(
                entry.key
                    .toString()
                    .replaceAll(RegExp(r'[_\-]'), '')
                    .toLowerCase(),
              )
              ? ''
              : redact(entry.value),
      };
    }
    return value;
  }

  return redact(json) as Map<String, dynamic>;
}

bool isBackupExportPath(String path) {
  final normalized = path.replaceAll('\\', '/');
  final name = normalized.split('/').last;
  return !normalized.startsWith('media/temp/') &&
      normalized != 'story/transactions.json' &&
      normalized != 'story/checkpoint_transactions.json' &&
      !normalized.startsWith('transactions/') &&
      !name.endsWith('.tmp') &&
      !name.endsWith('.bak') &&
      !name.contains('.corrupt.') &&
      !name.contains('.broken_');
}

class StorageException implements Exception {
  StorageException(this.message);

  final String message;

  @override
  String toString() => message;
}

Future<void> validateBackupDirectory(Directory directory) async {
  try {
    await validateBackupFiles(directory);
    await validateMementoBackup(directory);
    await validateStoryBackup(directory);
    await validateAutoStoryBackup(directory);
  } on FormatException catch (error) {
    throw StorageException('备份校验失败：${error.message}');
  }
  final separator = Platform.pathSeparator;
  final manifest = File('${directory.path}${separator}backup_manifest.json');
  if (!await manifest.exists()) {
    throw StorageException('备份文件缺少 backup_manifest.json');
  }
  final manifestJson = await _readBackupJson(manifest);
  if (manifestJson is! Map<String, dynamic> || manifestJson['format'] != 1) {
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
  await optionalJson('chat_sessions.json', (value) => value is List);
  await optionalJson('novels.json', (value) => value is List);
  await optionalJson('theater_sessions.json', (value) => value is List);
  await optionalJson(
    'config${separator}qq_integration.json',
    (value) => value is Map<String, dynamic>,
  );
  await optionalJson(
    'config${separator}qq_contact_bindings.json',
    (value) => value is List,
  );
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
  static const _secureLocalBridgeTokenKey = 'whisnya.qq.local_bridge_token';

  final FlutterSecureStorage _secureStorage;
  final JsonFileStore jsonStore;
  late final AutoStoryStore autoStories = AutoStoryStore(this);
  int get datasetEpoch => jsonStore.datasetEpoch;
  ValueListenable<int> get datasetEpochListenable =>
      jsonStore.datasetEpochNotifier;
  final ValueNotifier<String> backupStage = ValueNotifier('');
  final List<String> backupWarnings = [];
  @visibleForTesting
  Future<void> Function(String stage)? backupFailureHook;
  Directory? _appDataDirectory;
  Future<Directory>? _appDataDirectoryFuture;
  Future<ChatSessionService>? _chatSessionServiceFuture;
  final _recoveryMessages = <String>[];
  bool _characterRecoveryAttempted = false;
  Future<void> _characterLifecycleTail = Future<void>.value();

  // Test and embedder subclasses from pre-session releases can continue to
  // provide loadChat/saveChat without being forced to implement session files.
  bool get usesSessionStorage => runtimeType == LocalStorageService;

  List<String> takeRecoveryMessages() {
    final messages = List<String>.from(_recoveryMessages);
    _recoveryMessages.clear();
    return messages;
  }

  Future<Directory> get appDataDirectory =>
      _appDataDirectoryFuture ??= _prepareAppDataDirectory();

  Future<StoragePaths> get _paths async => StoragePaths(await appDataDirectory);

  Future<ChatSessionService> get _chatSessions =>
      _chatSessionServiceFuture ??= appDataDirectory.then(
        (root) => ChatSessionService(root: root, jsonStore: jsonStore),
      );

  Future<Directory> _prepareAppDataDirectory() async {
    final directory =
        _appDataDirectory ??
        Directory(
          '${(await getApplicationDocumentsDirectory()).path}'
          '${Platform.pathSeparator}app_data',
        );
    _appDataDirectory = directory;
    await _recoverBackupTransaction(directory);
    await _ensureAppDataDirectories(directory);
    return directory;
  }

  Future<void> ensureReady() async {
    final directory = await appDataDirectory;
    await (await _chatSessions).recoverPendingClears(pruneOrphanState: true);
    await StoryCheckpointService.recover(this);
    await autoStories.recoverInterruptedStories();
    await media_store.cleanupTemporaryMedia(directory);
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
      'novel_summary_cache',
      'theater_messages',
      'memories',
      'worldbook_entries',
      'config',
      'logs',
    ]) {
      await Directory(
        '${directory.path}${Platform.pathSeparator}$name',
      ).create(recursive: true);
    }
  }

  Future<AppSettings> loadSettings() async {
    final file = (await _paths).settings;
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
    await _writeJson((await _paths).settings, settings.toJson());
  }

  Future<QqIntegrationSettings> loadQqIntegrationSettings() async {
    final file = (await _paths).qqIntegration;
    final decoded = await _readJson(
      file,
      const QqIntegrationSettings().toJson(),
      recoverOnInvalid: true,
    );
    if (decoded is! Map<String, dynamic>) {
      throw StorageException('QQ 接入设置文件异常');
    }
    return QqIntegrationSettings.fromJson(decoded);
  }

  Future<void> saveQqIntegrationSettings(QqIntegrationSettings value) async {
    await _writeJson((await _paths).qqIntegration, value.toJson());
  }

  Future<List<QqContactBinding>> loadQqContactBindings() async {
    final file = (await _paths).qqContactBindings;
    final decoded = await _readJson(file, <dynamic>[], recoverOnInvalid: true);
    return _parseQqContactBindings(decoded);
  }

  Future<void> saveQqContactBinding(QqContactBinding value) async {
    final file = (await _paths).qqContactBindings;
    await _enqueueWrite(file, () async {
      final decoded = await _readJsonNow(
        file,
        <dynamic>[],
        recoverOnInvalid: true,
      );
      final bindings = _parseQqContactBindings(decoded);
      if (bindings.any(
        (binding) =>
            binding.id != value.id && binding.sessionId == value.sessionId,
      )) {
        throw const QqBindingException('每位 QQ 联系人必须使用独立对话。');
      }
      _upsert(bindings, value, (binding) => binding.id);
      await _writeJsonNow(
        file,
        bindings.map((binding) => binding.toJson()).toList(),
      );
    });
  }

  Future<void> deleteQqContactBinding(String id) async {
    final file = (await _paths).qqContactBindings;
    await _enqueueWrite(file, () async {
      final decoded = await _readJsonNow(
        file,
        <dynamic>[],
        recoverOnInvalid: true,
      );
      final bindings = _parseQqContactBindings(decoded)
        ..removeWhere((binding) => binding.id == id);
      await _writeJsonNow(
        file,
        bindings.map((binding) => binding.toJson()).toList(),
      );
    });
  }

  Future<String> loadOrCreateLocalBridgeToken() async {
    final existing =
        (await _secureStorage.read(key: _secureLocalBridgeTokenKey))?.trim() ??
        '';
    if (existing.isNotEmpty) return existing;
    final random = Random.secure();
    final token = base64UrlEncode(
      Uint8List.fromList(List<int>.generate(32, (_) => random.nextInt(256))),
    ).replaceAll('=', '');
    await _secureStorage.write(key: _secureLocalBridgeTokenKey, value: token);
    return token;
  }

  Future<List<QqDiagnosticEvent>> loadQqDiagnostics() async {
    final file = (await _paths).qqDiagnostics;
    final decoded = await _readJson(file, <dynamic>[], recoverOnInvalid: true);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(QqDiagnosticEvent.fromJson)
        .toList();
  }

  Future<void> appendQqDiagnosticEvent(QqDiagnosticEvent event) async {
    final file = (await _paths).qqDiagnostics;
    await _enqueueWrite(file, () async {
      final decoded = await _readJsonNow(
        file,
        <dynamic>[],
        recoverOnInvalid: true,
      );
      final events = decoded is List
          ? decoded
                .whereType<Map<String, dynamic>>()
                .map(QqDiagnosticEvent.fromJson)
                .toList()
          : <QqDiagnosticEvent>[];
      events.add(event);
      final kept = events.length <= 200
          ? events
          : events.sublist(events.length - 200);
      await _writeJsonNow(file, kept.map((item) => item.toJson()).toList());
    });
  }

  Future<void> clearQqDiagnostics() async {
    await _writeJson((await _paths).qqDiagnostics, <dynamic>[]);
  }

  List<QqContactBinding> _parseQqContactBindings(dynamic decoded) {
    if (decoded is! List) throw StorageException('QQ 联系人绑定文件异常');
    final result = <QqContactBinding>[];
    for (final value in decoded.whereType<Map<String, dynamic>>()) {
      try {
        result.add(QqContactBinding.fromJson(value));
      } on Object {
        // A single corrupt binding must not erase the other bindings.
      }
    }
    return result;
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

  Future<ApiConfig> loadApiConfig() => jsonStore.runOperation(() async {
    final file = (await _paths).apiConfig;
    final decoded = await _readJson(file, ApiConfig().toJson());
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
  });

  Future<void> saveApiConfig(ApiConfig config) =>
      jsonStore.runOperation(() async {
        await _writeSecureApiKeys(config);
        await _writeJson(
          (await _paths).apiConfig,
          _configWithoutApiKeys(config).toJson(),
        );
      });

  Future<List<AiUsageRecord>> loadAiUsageRecords() async {
    final decoded = await _readJson((await _paths).aiUsage, <dynamic>[]);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(AiUsageRecord.fromJson)
        .toList();
  }

  Future<void> recordAiUsage({
    required String requestType,
    required String model,
    required AiUsage usage,
    required List<Map<String, String>> messages,
    required bool summaryUpdated,
  }) async {
    final record = AiUsageRecord.fromRequest(
      requestType: requestType,
      model: model,
      usage: usage,
      messages: messages,
      summaryUpdated: summaryUpdated,
    );
    final file = (await _paths).aiUsage;
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
    final apiKeys = await Future.wait([
      for (final endpoint in config.endpoints)
        _secureStorage.read(key: _secureApiKeyKey(endpoint.id)),
    ]);
    return config.copyWith(
      endpoints: [
        for (var index = 0; index < config.endpoints.length; index++)
          apiKeys[index] == null
              ? config.endpoints[index]
              : config.endpoints[index].copyWith(apiKey: apiKeys[index]),
      ],
    );
  }

  Future<void> _writeSecureApiKeys(ApiConfig config) async {
    final previousIds = await _readSecureApiKeyIds();
    final nextIds = <String>{};
    final currentIds = config.endpoints.map((endpoint) => endpoint.id).toSet();
    final operations = <Future<void>>[];
    for (final endpoint in config.endpoints) {
      final apiKey = endpoint.apiKey.trim();
      final key = _secureApiKeyKey(endpoint.id);
      if (apiKey.isEmpty) {
        operations.add(_secureStorage.delete(key: key));
      } else {
        operations.add(_secureStorage.write(key: key, value: apiKey));
        nextIds.add(endpoint.id);
      }
    }
    for (final id in previousIds.difference(currentIds)) {
      operations.add(_secureStorage.delete(key: _secureApiKeyKey(id)));
    }
    await Future.wait(operations);
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

  Future<T> _withCharacterLifecycle<T>(Future<T> Function() action) {
    final result = _characterLifecycleTail.then(
      (_) => jsonStore.maintain(action),
    );
    _characterLifecycleTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<List<AppCharacter>> loadCharacters() => _withCharacterLifecycle(
    () async {
      final file = (await _paths).characters;
      await jsonStore.waitFor(file);
      if (await jsonStore.recoveryNeeded(file)) await jsonStore.recover(file);
      final hadCharacterFile = await file.exists();
      var invalidCharacterFile = false;
      if (!_characterRecoveryAttempted && hadCharacterFile) {
        try {
          invalidCharacterFile = jsonDecode(await file.readAsString()) is! List;
        } on FormatException {
          invalidCharacterFile = true;
        }
        if (invalidCharacterFile) {
          final backupPath = await _backupInvalidJson(file);
          _recoveryMessages.add(_jsonRecoveryMessage(file, backupPath));
        }
      }
      final characters = await _loadCharactersFile();
      if (!_characterRecoveryAttempted) {
        _characterRecoveryAttempted = true;
        if (characters.isEmpty && (!hadCharacterFile || invalidCharacterFile)) {
          await _recoverMissingCharacters(characters);
        }
      }
      return characters..sort((a, b) {
        if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
        return b.lastUsedAt.compareTo(a.lastUsedAt);
      });
    },
  );

  Future<void> saveCharacter(AppCharacter character) async {
    if (character.isLocked) {
      await jsonStore.maintain(() async {
        await _protectStorySnapshots(character.id);
        await _updateCharacters(
          (characters) => _upsert(characters, character, (item) => item.id),
        );
      });
      return;
    }
    await _updateCharacters(
      (characters) => _upsert(characters, character, (item) => item.id),
    );
  }

  Future<void> _protectStorySnapshots(String characterId) async {
    final root = await appDataDirectory;
    await jsonStore.maintain(() async {
      await protectAutoStorySource(root, jsonStore, characterId);
      await autoStories.repairIndex();
      for (final folder in ['story/checkpoints', 'collection/items']) {
        final directory = Directory('${root.path}/$folder');
        if (!await directory.exists()) continue;
        await for (final file in directory.list(followLinks: false)) {
          if (file is! File ||
              !file.path.endsWith('.json') ||
              file.path.endsWith('index.json')) {
            continue;
          }
          final raw = await jsonStore.read(file, null);
          if (raw is Map<String, dynamic> &&
              raw['characterId'] == characterId &&
              raw['requiresUnlock'] != true) {
            await jsonStore.write(file, {...raw, 'requiresUnlock': true});
          }
        }
      }
      for (final name in [
        'story/checkpoints/index.json',
        'collection/index.json',
      ]) {
        final file = File('${root.path}/$name');
        final rows = await jsonStore.read(file, null);
        if (rows is List) {
          await jsonStore.write(
            file,
            rows
                .map(
                  (r) =>
                      r is Map<String, dynamic> &&
                          r['characterId'] == characterId
                      ? {...r, 'requiresUnlock': true}
                      : r,
                )
                .toList(),
          );
        }
      }
    });
  }

  Future<void> deleteCharacter(String characterId) => _withCharacterLifecycle(
    () async {
      _characterRecoveryAttempted = true;
      final paths = await _paths;
      final rawCharacters = await jsonStore.read(paths.characters, <dynamic>[]);
      if ((rawCharacters as List).whereType<Map<String, dynamic>>().any(
        (c) => c['id'] == characterId && c['isLocked'] == true,
      )) {
        await _protectStorySnapshots(characterId);
      }
      final rows = await jsonStore.read(paths.chatSessions, <dynamic>[]);
      for (final row in (rows as List).whereType<Map<String, dynamic>>().where(
        (s) => s['characterId'] == characterId,
      )) {
        await CharacterStateService(this).clearState(row['id'] as String);
      }
      await _updateCharacters((characters) {
        characters.removeWhere((character) => character.id == characterId);
        return characters;
      });
      await (await _chatSessions).deleteCharacterSessions(characterId);
      await cleanupUnusedMedia();
    },
  );

  Future<void> deleteCharacterStorySnapshots(String characterId) async {
    final root = await appDataDirectory;
    await jsonStore.maintain(() async {
      for (final kind in [
        ('story/checkpoints/index.json', 'story/checkpoints'),
        ('collection/index.json', 'collection/items'),
      ]) {
        final index = File('${root.path}/${kind.$1}');
        final rows = await jsonStore.read(index, <dynamic>[]);
        final removed = (rows as List)
            .whereType<Map<String, dynamic>>()
            .where((r) => r['characterId'] == characterId)
            .toList();
        await jsonStore.write(
          index,
          rows
              .where((r) => r is! Map || r['characterId'] != characterId)
              .toList(),
        );
        for (final row in removed) {
          final id = row['id'];
          if (id is! String || !RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id)) {
            continue;
          }
          final file = File('${root.path}/${kind.$2}/$id.json');
          if (await file.exists()) await file.delete();
        }
      }
    });
  }

  Future<List<ChatSession>> loadChatSessions(String characterId) async =>
      (await _chatSessions).loadChatSessions(characterId);

  Future<void> restoreRecoveredChatSessions(
    List<ChatSession> recovered,
  ) async => (await _chatSessions).restoreRecoveredChatSessions(recovered);

  Future<ChatSession> getOrCreateRecentChatSession(String characterId) async =>
      (await _chatSessions).getOrCreateRecentChatSession(characterId);

  Future<ChatSession> createChatSession(
    String characterId, {
    String? title,
  }) async =>
      (await _chatSessions).createChatSession(characterId, title: title);

  Future<void> saveChatSession(ChatSession session) async =>
      (await _chatSessions).saveChatSession(session);

  Future<ChatSession> markOpeningMessageInitialized({
    required String sessionId,
    required String characterId,
  }) async => (await _chatSessions).markOpeningMessageInitialized(
    sessionId: sessionId,
    characterId: characterId,
  );

  Future<ChatSession> duplicateChatSession(ChatSession source) async =>
      (await _chatSessions).duplicateChatSession(source);

  Future<void> deleteChatSession(ChatSession session) async {
    await (await _chatSessions).deleteChatSession(session);
  }

  Future<void> archiveChatSession(ChatSession session) async =>
      (await _chatSessions).archiveChatSession(session);

  Future<void> unarchiveChatSession(ChatSession session) async =>
      (await _chatSessions).unarchiveChatSession(session);

  Future<List<ChatMessage>> loadChatBySession(ChatSession session) async =>
      (await _chatSessions).loadChatBySession(session);

  Future<void> saveChatBySession(
    ChatSession session,
    List<ChatMessage> messages,
  ) async => (await _chatSessions).saveChatBySession(session, messages);

  Future<bool> saveChatBySessionIfExists(
    ChatSession session,
    List<ChatMessage> messages, {
    SessionOperationToken? token,
  }) async => (await _chatSessions).saveChatBySessionIfExists(
    session,
    messages,
    token: token,
  );

  Future<SessionOperationToken> captureSessionToken(
    ChatSession session,
  ) async => (await _chatSessions).captureToken(session);

  Future<ChatSummary> clearChatPreservingSummary(ChatSession session) async {
    final summary = await (await _chatSessions).clearChatPreservingSummary(
      session,
    );
    return summary;
  }

  Future<void> backfillMessageCounts(
    List<ChatSession> sessions, {
    void Function(ChatSession)? onUpdated,
    void Function(String, Object)? onError,
  }) async => (await _chatSessions).backfillMessageCounts(
    sessions,
    onUpdated: onUpdated,
    onError: onError,
  );

  Future<ChatSummary> loadSummaryBySession(ChatSession session) async =>
      (await _chatSessions).loadSummaryBySession(session);

  Future<void> saveSummaryBySession(
    ChatSummary summary, {
    SessionOperationToken? token,
  }) async => (await _chatSessions).saveSummaryBySession(summary, token: token);

  Future<List<CharacterMemoryEntry>> loadCharacterMemories(
    String characterId,
  ) async {
    final service = await _chatSessions;
    final memories = await service.loadCharacterMemories(characterId);
    final legacy = memories
        .where((memory) => memory.keywords.isNotEmpty)
        .toList();
    if (legacy.isEmpty) return memories;

    final character = (await loadCharacters())
        .where((item) => item.id == characterId)
        .firstOrNull;
    if (character == null) return memories;

    final worldBookId = 'legacy_worldbook_${_safeWorldBookPart(characterId)}';
    final books = await service.loadWorldBooks();
    var worldBook = books.where((book) => book.id == worldBookId).firstOrNull;
    final now = DateTime.now();
    if (worldBook == null) {
      worldBook = WorldBook(
        id: worldBookId,
        name:
            '${character.name.trim().isEmpty ? characterId : character.name.trim()} - 旧关键词世界书',
        description: '从旧版关键词记忆迁移',
        createdAt: now,
        updatedAt: now,
      );
      await service.saveWorldBook(worldBook);
    }

    final existing = await service.loadWorldBookEntries(worldBookId);
    final existingIds = existing.map((entry) => entry.id).toSet();
    for (final memory in legacy) {
      final entryId = 'legacy_worldbook_entry_${_safeWorldBookPart(memory.id)}';
      if (existingIds.contains(entryId)) continue;
      await service.saveWorldBookEntry(
        WorldBookEntry(
          id: entryId,
          worldBookId: worldBookId,
          title: memory.title,
          content: memory.content,
          keywords: memory.keywords,
          priority: memory.priority,
          enabled: memory.enabled,
          createdAt: memory.createdAt,
          updatedAt: memory.updatedAt,
        ),
      );
    }

    if (!character.worldBookIds.contains(worldBookId)) {
      await updateCharacterWorldBookReferences(characterId, [
        ...character.worldBookIds,
        worldBookId,
      ]);
    }
    for (final memory in legacy) {
      await service.deleteCharacterMemory(characterId, memory.id);
    }
    return service.loadCharacterMemories(characterId);
  }

  static String _safeWorldBookPart(String value) {
    final cleaned = value.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return cleaned.isEmpty ? 'legacy' : cleaned;
  }

  Future<List<WorldBook>> loadWorldBooks() async =>
      (await _chatSessions).loadWorldBooks();

  Future<void> saveWorldBook(WorldBook worldBook) async =>
      (await _chatSessions).saveWorldBook(worldBook);

  Future<void> deleteWorldBook(String worldBookId) async {
    await (await _chatSessions).deleteWorldBook(worldBookId);
    await _updateCharacters((characters) {
      for (var index = 0; index < characters.length; index++) {
        final character = characters[index];
        if (character.worldBookIds.contains(worldBookId)) {
          characters[index] = character.copyWith(
            worldBookIds: character.worldBookIds
                .where((id) => id != worldBookId)
                .toList(),
          );
        }
      }
      return characters;
    });
  }

  Future<List<WorldBookEntry>> loadWorldBookEntries(String worldBookId) async =>
      (await _chatSessions).loadWorldBookEntries(worldBookId);

  Future<void> saveWorldBookEntry(WorldBookEntry entry) async =>
      (await _chatSessions).saveWorldBookEntry(entry);

  Future<void> deleteWorldBookEntry(String worldBookId, String entryId) async =>
      (await _chatSessions).deleteWorldBookEntry(worldBookId, entryId);

  Future<void> updateCharacterWorldBookReferences(
    String characterId,
    List<String> worldBookIds,
  ) async {
    await _updateCharacters((characters) {
      final index = characters.indexWhere(
        (character) => character.id == characterId,
      );
      if (index >= 0) {
        characters[index] = characters[index].copyWith(
          worldBookIds: worldBookIds,
        );
      }
      return characters;
    });
  }

  Future<void> saveCharacterMemory(CharacterMemoryEntry entry) async =>
      (await _chatSessions).saveCharacterMemory(entry);

  Future<void> deleteCharacterMemory(
    String characterId,
    String memoryId,
  ) async => (await _chatSessions).deleteCharacterMemory(characterId, memoryId);

  Future<void> deleteSessionMemories(
    String characterId,
    String sessionId,
  ) async =>
      (await _chatSessions).deleteSessionMemories(characterId, sessionId);

  Future<List<CharacterMemoryEntry>> duplicateSessionMemories(
    String characterId,
    String sourceSessionId,
    String targetSessionId,
  ) async => (await _chatSessions).duplicateSessionMemories(
    characterId,
    sourceSessionId,
    targetSessionId,
  );

  Future<List<ChatMessage>> loadChat(String characterId) async {
    final file = (await _paths).chat(characterId);
    final decoded = await _readJson(file, const {'messages': <dynamic>[]});
    if (decoded is! Map<String, dynamic>) {
      throw StorageException('聊天记录文件异常：${file.path}');
    }
    final messages = decoded['messages'];
    return messages is List
        ? messages
              .whereType<Map<String, dynamic>>()
              .map(ChatMessage.fromJson)
              .toList()
        : const [];
  }

  Future<void> saveChat(String characterId, List<ChatMessage> messages) async {
    messages = assignMessageIds(messages);
    await _writeJson((await _paths).chat(characterId), {
      'characterId': characterId,
      'messages': messages.map((message) => message.toJson()).toList(),
    });
  }

  Future<void> clearChat(String characterId) => saveChat(characterId, const []);

  Future<List<NovelBook>> loadNovels() async {
    final file = (await _paths).novels;
    return await _loadJsonList(
        file,
        error: '小说文件异常：${file.path}',
        fromJson: NovelBook.fromJson,
        isValid: (book) => book.id.isNotEmpty && book.textPath.isNotEmpty,
      )
      ..sort((a, b) => b.lastOpenedSortTime.compareTo(a.lastOpenedSortTime));
  }

  Future<NovelBook> importNovelText({
    required String title,
    required String content,
  }) => jsonStore.runOperation(() async {
    final now = DateTime.now();
    final id = 'novel_${now.microsecondsSinceEpoch}';
    final file = (await _paths).novelText(id);
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
  });

  Future<String> loadNovelText(NovelBook book) async {
    final file = File(book.textPath);
    if (!await file.exists()) {
      throw StorageException('小说正文不存在：${book.textPath}');
    }
    return file.readAsString();
  }

  Future<void> saveNovel(NovelBook book) async {
    await _updateNovels((books) => _upsert(books, book, (item) => item.id));
  }

  Future<void> deleteNovel(NovelBook book) => jsonStore.runOperation(() async {
    await _updateNovels((books) {
      books.removeWhere((item) => item.id == book.id);
      return books;
    });
    final textFile = File(book.textPath);
    if (await textFile.exists()) {
      await textFile.delete();
    }
    final cache = (await _paths).novelSummaryCache(book.id);
    if (await cache.exists()) {
      await cache.delete();
    }
  });

  Future<ChatSummary> loadSummary(String characterId) async {
    final file = (await _paths).summary(characterId);
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
    await _writeJson(
      (await _paths).summary(summary.characterId),
      summary.toJson(),
    );
  }

  Future<List<TheaterSession>> loadTheaterSessions() async {
    final file = (await _paths).theaterSessions;
    return await _loadJsonList(
        file,
        error: '群聊文件异常：${file.path}',
        fromJson: TheaterSession.fromJson,
        isValid: (session) => session.id.isNotEmpty,
      )
      ..sort((a, b) => b.lastOpenedSortTime.compareTo(a.lastOpenedSortTime));
  }

  Future<void> saveTheaterSession(TheaterSession session) async {
    await _updateTheaterSessions(
      (sessions) => _upsert(sessions, session, (item) => item.id),
    );
  }

  Future<void> deleteTheaterSession(String sessionId) =>
      jsonStore.runOperation(() async {
        await _updateTheaterSessions((sessions) {
          sessions.removeWhere((session) => session.id == sessionId);
          return sessions;
        });
        final messages = (await _paths).theaterMessages(sessionId);
        if (await messages.exists()) {
          await messages.delete();
        }
        await cleanupUnusedMedia();
      });

  Future<int> cleanupUnusedMedia() => jsonStore.runOperation(() async {
    final referenced = <String>{};
    void add(String path) {
      if (path.trim().isNotEmpty) referenced.add(path);
    }

    final settings = await loadSettings();
    add(settings.globalBackgroundImage);
    add(settings.userProfile.avatar);
    for (final character in await _loadCharactersFile()) {
      add(character.avatar);
      add(character.backgroundImage);
    }
    for (final session in await loadTheaterSessions()) {
      add(session.avatar);
      add(session.backgroundImage);
      for (final participant in session.participants) {
        add(participant.avatar);
      }
    }
    referenced.addAll(await autoStoryReferencedMedia(await appDataDirectory));
    return media_store.cleanupUnusedMedia(await appDataDirectory, referenced);
  });

  Future<List<TheaterMessage>> loadTheaterMessages(String sessionId) async {
    final file = (await _paths).theaterMessages(sessionId);
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
      (await _paths).theaterMessages(sessionId),
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
    late final Archive archive;
    try {
      archive = decodeSafeZip(bytes);
    } on SafeZipException catch (error) {
      throw StorageException(error.message);
    }
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
    final file = await exportAllDataToFile(includeApiKeys: includeApiKeys);
    try {
      return await file.readAsBytes();
    } finally {
      await file.parent.delete(recursive: true);
    }
  }

  Future<File> exportAllDataToFile({bool includeApiKeys = false}) async {
    final root = await appDataDirectory;
    final exports = await Directory(
      '${root.parent.path}/backup_exports',
    ).create(recursive: true);
    final work = await exports.createTemp('export_');
    final snapshot = Directory('${work.path}/snapshot');
    final output = File('${work.path}/backup.zip');
    try {
      backupStage.value = '准备一致性快照';
      await _characterLifecycleTail;
      await jsonStore.maintain(() async {
        await (await _chatSessions).recoverPendingClears();
        await snapshot.create();
        final files = <Map<String, dynamic>>[];
        await for (final entity in root.list(
          recursive: true,
          followLinks: false,
        )) {
          if (entity is! File) continue;
          final name = entity.path
              .substring(root.path.length + 1)
              .replaceAll('\\', '/');
          if (!isBackupExportPath(name) || name == 'backup_manifest.json') {
            continue;
          }
          final destination = File('${snapshot.path}/$name');
          await destination.parent.create(recursive: true);
          if (name == 'api_config.json' ||
              name == 'config/qq_integration.json') {
            final decoded = jsonDecode(await entity.readAsString());
            if (decoded is! Map<String, dynamic>) {
              throw StorageException('配置损坏，无法安全脱敏');
            }
            if (name == 'api_config.json') {
              final endpoints = decoded['endpoints'];
              if (endpoints != null &&
                  (endpoints is! List ||
                      endpoints.any((e) => e is! Map<String, dynamic>))) {
                throw StorageException('API 配置损坏，无法安全脱敏');
              }
              ApiConfig.fromJson(decoded);
            }
            final data = includeApiKeys && name == 'api_config.json'
                ? (await _withSecureApiKeys(
                    ApiConfig.fromJson(decoded),
                  )).toJson()
                : redactApiKeysForExport(decoded);
            await destination.writeAsString(jsonEncode(data), flush: true);
          } else {
            await entity.openRead().pipe(destination.openWrite());
          }
          files.add({
            'path': name,
            'bytes': await destination.length(),
            'sha256': await backupHash(destination),
          });
        }
        await File('${snapshot.path}/backup_manifest.json').writeAsString(
          jsonEncode({
            'format': 1,
            'schemaVersion': 3,
            'features': {
              'storyCheckpoints': 1,
              'characterState': 1,
              'mementoCollection': 1,
              'characterSpeech': 1,
              'autoStories': 1,
            },
            'includesApiKeys': includeApiKeys,
            'snapshotAt': DateTime.now().toUtc().toIso8601String(),
            'files': files,
          }),
          flush: true,
        );
      }, advanceEpoch: true);
      backupStage.value = '压缩备份';
      await zipBackupDirectory(snapshot, output);
      await snapshot.delete(recursive: true);
      return output;
    } catch (_) {
      if (await work.exists()) await work.delete(recursive: true);
      rethrow;
    } finally {
      backupStage.value = '';
    }
  }

  Future<void> importAllData(Uint8List bytes) async {
    final root = await appDataDirectory;
    final work = await root.parent.createTemp('backup_input_');
    try {
      final file = File('${work.path}/input.zip');
      await file.writeAsBytes(bytes, flush: true);
      await importAllDataFromFile(file);
    } finally {
      await work.delete(recursive: true);
    }
  }

  Future<void> importAllDataFromFile(
    File sourceZip, {
    bool allowApiKeys = false,
  }) async {
    final root = await appDataDirectory;
    final stagingParent = await Directory(
      '${root.parent.path}/backup_staging',
    ).create(recursive: true);
    final staging = await stagingParent.createTemp('stage_');
    try {
      backupStage.value = '解压与校验';
      await extractBackupFile(sourceZip, staging);
      await validateBackupDirectory(staging);
      backupWarnings.clear();
      backupWarnings.addAll(await backupAssetWarnings(staging));
      backupWarnings.addAll(await validateStoryBackup(staging));
      backupWarnings.addAll(await validateAutoStoryBackup(staging));
      final manifest =
          await readBackupJson(File('${staging.path}/backup_manifest.json'))
              as Map<String, dynamic>;
      final configFile = File('${staging.path}/api_config.json');
      final incoming = await configFile.exists()
          ? await readBackupJson(configFile) as Map<String, dynamic>
          : <String, dynamic>{};
      final containsKeys = _hasApiKeys(ApiConfig.fromJson(incoming));
      if (containsKeys && !allowApiKeys) {
        throw StorageException('备份包含 API Key，请明确确认后恢复');
      }
      await _activateBackup(
        root,
        staging,
        containsKeys: manifest['includesApiKeys'] == true || containsKeys,
      );
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
      backupStage.value = '';
    }
  }

  File _backupJournal(Directory root) =>
      File('${root.parent.path}/backup_transaction.json');
  File _rollbackPointer(Directory root) =>
      File('${root.parent.path}/backup_rollback.json');
  String _credentialSnapshotKey(String name) =>
      'whisnya_backup_credentials_$name';

  Future<Map<String, String>> _credentialSnapshot() async {
    final keys = {
      _secureApiKeyIndexKey,
      _secureLocalBridgeTokenKey,
      for (final id in await _readSecureApiKeyIds()) _secureApiKeyKey(id),
    };
    final snapshot = <String, String>{};
    for (final key in keys) {
      final value = await _secureStorage.read(key: key);
      if (value != null) snapshot[key] = value;
    }
    return snapshot;
  }

  Future<void> _restoreCredentialSnapshot(
    String rollbackName, {
    List<String> touchedIds = const [],
  }) async {
    final raw = await _secureStorage.read(
      key: _credentialSnapshotKey(rollbackName),
    );
    if (raw == null) return;
    final snapshot = Map<String, String>.from(jsonDecode(raw) as Map);
    final current = await _credentialSnapshot();
    for (final id in touchedIds) {
      final key = _secureApiKeyKey(id);
      if (!snapshot.containsKey(key)) await _secureStorage.delete(key: key);
    }
    for (final key in current.keys) {
      if (!snapshot.containsKey(key)) await _secureStorage.delete(key: key);
    }
    for (final entry in snapshot.entries) {
      await _secureStorage.write(key: entry.key, value: entry.value);
    }
  }

  Future<void> _recoverBackupTransaction(Directory root) async {
    final journal = _backupJournal(root);
    if (!await journal.exists() &&
        !await File('${journal.path}.tmp').exists() &&
        !await File('${journal.path}.bak').exists()) {
      return;
    }
    await jsonStore.recover(journal);
    if (!await journal.exists()) return;
    final transaction = await readBackupJson(journal) as Map;
    final name = transaction['rollback'] as String;
    if (!RegExp(r'^backup_rollback_[0-9]+$').hasMatch(name)) {
      throw StorageException('恢复事务路径异常');
    }
    final rollback = Directory('${root.parent.path}/$name');
    if (transaction['phase'] == 'complete') {
      await jsonStore.writeNow(_rollbackPointer(root), {'directory': name});
    } else {
      if (await rollback.exists()) {
        await jsonStore.writeNow(journal, {
          ...transaction,
          'phase': 'restoring',
        });
        if (await root.exists()) {
          await root.rename(
            '${root.parent.path}/backup_failed_${DateTime.now().microsecondsSinceEpoch}',
          );
        }
        await rollback.rename(root.path);
      } else if (!await root.exists() ||
          !['prepared', 'restoring'].contains(transaction['phase'])) {
        throw StorageException('恢复事务缺少回滚目录，请保留数据并手动修复');
      }
      await _restoreCredentialSnapshot(
        name,
        touchedIds:
            (transaction['touchedIds'] as List?)?.cast<String>() ?? const [],
      );
    }
    await journal.delete();
  }

  Future<void> _activateBackup(
    Directory root,
    Directory staging, {
    required bool containsKeys,
    String? restoreCredentialsFrom,
  }) async {
    await _characterLifecycleTail;
    await jsonStore.maintain(() async {
      backupStage.value = '恢复数据（保留回滚点）';
      await pauseRestoredAutoStories(staging, jsonStore);
      final name = 'backup_rollback_${DateTime.now().microsecondsSinceEpoch}';
      final rollback = Directory('${root.parent.path}/$name');
      final journal = _backupJournal(root);
      final previousConfig = await loadApiConfig();
      final oldRawFile = File('${root.path}/api_config.json');
      final oldRaw = await oldRawFile.exists()
          ? await readBackupJson(oldRawFile) as Map
          : <String, dynamic>{};
      final newConfigFile = File('${staging.path}/api_config.json');
      final touchedIds = await newConfigFile.exists()
          ? ApiConfig.fromJson(
              await readBackupJson(newConfigFile) as Map<String, dynamic>,
            ).endpoints.map((e) => e.id).toList()
          : <String>[];
      await _secureStorage.write(
        key: _credentialSnapshotKey(name),
        value: jsonEncode(await _credentialSnapshot()),
      );
      await jsonStore.writeNow(journal, {
        'phase': 'prepared',
        'rollback': name,
        'touchedIds': touchedIds,
      });
      try {
        await backupFailureHook?.call('prepared');
        await root.rename(rollback.path);
        await jsonStore.writeNow(journal, {
          'phase': 'oldMoved',
          'rollback': name,
          'touchedIds': touchedIds,
        });
        await backupFailureHook?.call('oldMoved');
        await staging.rename(root.path);
        await jsonStore.writeNow(journal, {
          'phase': 'newActive',
          'rollback': name,
          'touchedIds': touchedIds,
        });
        await backupFailureHook?.call('newActive');
        await _ensureAppDataDirectories(root);
        await _repairRestoredAppDataPaths(root);
        await autoStories.recoverInterruptedStories();
        final configFile = File('${root.path}/api_config.json');
        await backupFailureHook?.call('credentials');
        if (restoreCredentialsFrom != null) {
          await _restoreCredentialSnapshot(restoreCredentialsFrom);
        } else if (await configFile.exists()) {
          final decoded =
              await readBackupJson(configFile) as Map<String, dynamic>;
          final config = ApiConfig.fromJson(decoded);
          if (containsKeys) {
            await _writeSecureApiKeys(config);
          } else {
            final oldEndpoints = oldRaw['endpoints'] is List
                ? oldRaw['endpoints'] as List
                : <dynamic>[];
            final newEndpoints = decoded['endpoints'] is List
                ? decoded['endpoints'] as List
                : <dynamic>[];
            for (final endpoint in config.endpoints) {
              final old = previousConfig.endpointById(endpoint.id);
              final before = oldEndpoints
                  .whereType<Map<String, dynamic>>()
                  .where((e) => e['id'] == endpoint.id)
                  .firstOrNull;
              final after = newEndpoints
                  .whereType<Map<String, dynamic>>()
                  .where((e) => e['id'] == endpoint.id)
                  .firstOrNull;
              final same =
                  old != null &&
                  _endpointAddress(old.baseUrl) ==
                      _endpointAddress(endpoint.baseUrl) &&
                  before?['provider'] == after?['provider'];
              final key = _secureApiKeyKey(endpoint.id);
              if (same && old.apiKey.isNotEmpty) {
                await _secureStorage.write(key: key, value: old.apiKey);
              } else {
                await _secureStorage.delete(key: key);
              }
            }
          }
          await jsonStore.writeNow(configFile, redactApiKeysForExport(decoded));
        }
        await backupFailureHook?.call('afterCredentials');
        _chatSessionServiceFuture = null;
        _characterRecoveryAttempted = false;
        await jsonStore.writeNow(journal, {
          'phase': 'complete',
          'rollback': name,
        });
        await jsonStore.writeNow(_rollbackPointer(root), {'directory': name});
        await journal.delete();
      } catch (_) {
        await _recoverBackupTransaction(root);
        await pauseRestoredAutoStories(root, jsonStore);
        await autoStories.repairIndex();
        _chatSessionServiceFuture = null;
        _characterRecoveryAttempted = false;
        rethrow;
      }
    }, advanceEpoch: true);
  }

  String _endpointAddress(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null) return value.trim();
    return uri
        .replace(
          scheme: uri.scheme.toLowerCase(),
          host: uri.host.toLowerCase(),
          path: uri.path.replaceFirst(RegExp(r'/+$'), ''),
        )
        .toString();
  }

  Future<bool> hasBackupRollback() async =>
      await _rollbackPointer(await appDataDirectory).exists();

  Future<void> restorePreviousBackup() async {
    final root = await appDataDirectory;
    final pointer = await readBackupJson(_rollbackPointer(root)) as Map;
    final name = pointer['directory'] as String;
    if (!RegExp(r'^backup_rollback_[0-9]+$').hasMatch(name)) {
      throw StorageException('回滚目录异常');
    }
    final previous = Directory('${root.parent.path}/$name');
    if (!await previous.exists()) throw StorageException('回滚点不存在');
    final stagingParent = await Directory(
      '${root.parent.path}/backup_staging',
    ).create(recursive: true);
    final staging = await stagingParent.createTemp('stage_');
    try {
      await for (final entity in previous.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final file = File(
          '${staging.path}/${entity.path.substring(previous.path.length + 1)}',
        );
        await file.parent.create(recursive: true);
        await entity.openRead().pipe(file.openWrite());
      }
      await _activateBackup(
        root,
        staging,
        containsKeys: false,
        restoreCredentialsFrom: name,
      );
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  Future<void> _repairRestoredAppDataPaths(Directory directory) async {
    String fixPath(String path) => restoreAppDataPath(path, directory.path);
    // Legacy schema backups may contain bare message arrays. Validate first,
    // then add only the envelope; retain every original message/unknown field.
    if (!await File('${directory.path}/chat_sessions.json').exists()) {
      final chats = Directory('${directory.path}/chats');
      if (await chats.exists()) {
        await for (final file in chats.list(followLinks: false)) {
          if (file is! File || !file.path.endsWith('.json')) continue;
          final decoded = await readBackupJson(file);
          if (decoded is List) {
            final id = file.uri.pathSegments.last.replaceFirst(
              RegExp(r'\.json$'),
              '',
            );
            await _writeJsonNow(file, {'characterId': id, 'messages': decoded});
          }
        }
      }
    }

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
        final userProfile = decoded['userProfile'];
        if (userProfile is Map<String, dynamic>) {
          userProfile['avatar'] = fixPath(
            userProfile['avatar'] as String? ?? '',
          );
        }
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
  }) => jsonStore.runOperation(() async {
    final directory = await _mediaDirectory(folder);
    final safeCharacterId = characterId.replaceAll(
      RegExp(r'[^a-zA-Z0-9_-]'),
      '_',
    );
    final extension = media_store.imageFileExtension(bytes);
    final file = File(
      '${directory.path}${Platform.pathSeparator}${safeCharacterId}_${DateTime.now().microsecondsSinceEpoch}$extension',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  });

  Future<File> saveTemporaryImage(
    Uint8List bytes,
  ) => jsonStore.runOperation(() async {
    final directory = await _mediaDirectory('temp');
    final file = File(
      '${directory.path}${Platform.pathSeparator}picked_${DateTime.now().microsecondsSinceEpoch}${media_store.imageFileExtension(bytes)}',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file;
  });

  Future<Directory> _mediaDirectory(String folder) async {
    final mediaDirectory = (await _paths).media(folder);
    if (!await mediaDirectory.exists()) {
      await mediaDirectory.create(recursive: true);
    }
    return mediaDirectory;
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
    if (await jsonStore.recoveryNeeded(file)) await jsonStore.recover(file);
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
    final parentName = file.parent.uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .lastOrNull;
    final compact = const {'chats', 'theater_messages'}.contains(parentName);
    await jsonStore.writeNow(file, data, compact: compact);
  }

  Future<void> _updateCharacters(
    List<AppCharacter> Function(List<AppCharacter>) update,
  ) async {
    final file = (await _paths).characters;
    await _updateJsonList(
      file,
      error: '角色文件异常：${file.path}',
      fromJson: AppCharacter.fromJson,
      isValid: (character) => character.id.isNotEmpty,
      toJson: (character) => character.toJson(),
      update: update,
    );
  }

  Future<List<AppCharacter>> _loadCharactersFile() async {
    final file = (await _paths).characters;
    final decoded = await _readJson(file, <dynamic>[], recoverOnInvalid: true);
    if (decoded is! List) throw StorageException('角色文件异常：${file.path}');
    final characters = <AppCharacter>[];
    final seen = <String>{};
    for (var index = 0; index < decoded.length; index++) {
      try {
        final row = decoded[index];
        if (row is! Map<String, dynamic>) throw const FormatException();
        final character = AppCharacter.fromJson(row);
        if (character.id.isEmpty || !seen.add(character.id)) {
          throw const FormatException();
        }
        characters.add(character);
      } on Object catch (error) {
        if (error is! FormatException && error is! TypeError) rethrow;
        _recoveryMessages.add('characters.json 第 $index 项损坏或重复；原始文件已保留');
      }
    }
    return characters;
  }

  Future<void> _updateNovels(
    List<NovelBook> Function(List<NovelBook>) update,
  ) async {
    final file = (await _paths).novels;
    await _updateJsonList(
      file,
      error: '小说文件异常：${file.path}',
      fromJson: NovelBook.fromJson,
      isValid: (book) => book.id.isNotEmpty,
      toJson: (book) => book.toJson(),
      update: update,
    );
  }

  Future<void> _updateTheaterSessions(
    List<TheaterSession> Function(List<TheaterSession>) update,
  ) async {
    final file = (await _paths).theaterSessions;
    await _updateJsonList(
      file,
      error: '群聊文件异常：${file.path}',
      fromJson: TheaterSession.fromJson,
      isValid: (session) => session.id.isNotEmpty,
      toJson: (session) => session.toJson(),
      update: update,
    );
  }

  Future<List<T>> _loadJsonList<T>(
    File file, {
    required String error,
    required T Function(Map<String, dynamic>) fromJson,
    required bool Function(T) isValid,
  }) async {
    final decoded = await _readJson(file, <dynamic>[], recoverOnInvalid: true);
    return _parseJsonList(decoded, error, fromJson, isValid);
  }

  List<T> _parseJsonList<T>(
    dynamic decoded,
    String error,
    T Function(Map<String, dynamic>) fromJson,
    bool Function(T) isValid,
  ) {
    if (decoded is! List) throw StorageException(error);
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(fromJson)
        .where(isValid)
        .toList();
  }

  Future<void> _updateJsonList<T>(
    File file, {
    required String error,
    required T Function(Map<String, dynamic>) fromJson,
    required bool Function(T) isValid,
    required Map<String, dynamic> Function(T) toJson,
    required List<T> Function(List<T>) update,
  }) async {
    await _enqueueWrite(file, () async {
      final decoded = await _readJsonNow(
        file,
        <dynamic>[],
        recoverOnInvalid: true,
      );
      final next = update(_parseJsonList(decoded, error, fromJson, isValid));
      await _writeJsonNow(file, next.map(toJson).toList());
    });
  }

  Future<void> _recoverMissingCharacters(List<AppCharacter> characters) async {
    final existingIds = characters.map((character) => character.id).toSet();
    final resolution = await CharacterRecoveryService()
        .resolveRecoveryCandidates(await appDataDirectory);
    _recoveryMessages.addAll(resolution.warnings);
    await restoreRecoveredChatSessions(resolution.sessions);
    final ids = resolution.characterIds;
    ids.removeAll(existingIds);
    if (ids.isEmpty) {
      return;
    }

    for (final id in ids) {
      final avatar = await _latestMediaPath('avatars', id);
      final background = await _latestMediaPath('backgrounds', id);
      if (avatar.isEmpty || background.isEmpty) {
        _recoveryMessages.add('角色 $id 的头像或背景缺失，将使用默认显示；聊天文本不受影响');
      }
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
      (await _paths).characters,
      characters.map((character) => character.toJson()).toList(),
    );
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
    final paths = await _paths;
    for (final file in [
      paths.chat(characterId),
      paths.summary(characterId),
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
