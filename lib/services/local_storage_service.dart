import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';

import '../models/api_config.dart';
import '../models/app_character.dart';
import '../models/app_settings.dart';
import '../models/chat_message.dart';
import '../models/chat_session.dart';
import '../models/chat_summary.dart';
import '../models/novel_book.dart';
import '../utils/role_import_parser.dart';

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

class StorageException implements Exception {
  StorageException(this.message);

  final String message;

  @override
  String toString() => message;
}

class LocalStorageService {
  Directory? _appDataDirectory;
  Future<void> _writeQueue = Future.value();

  Future<Directory> get appDataDirectory async {
    if (_appDataDirectory != null) {
      return _appDataDirectory!;
    }

    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(
      '${documents.path}${Platform.pathSeparator}app_data',
    );
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    await Directory(
      '${directory.path}${Platform.pathSeparator}chats',
    ).create(recursive: true);
    await Directory(
      '${directory.path}${Platform.pathSeparator}summaries',
    ).create(recursive: true);
    await Directory(
      '${directory.path}${Platform.pathSeparator}media',
    ).create(recursive: true);
    await Directory(
      '${directory.path}${Platform.pathSeparator}novels',
    ).create(recursive: true);
    await Directory(
      '${directory.path}${Platform.pathSeparator}novel_chats',
    ).create(recursive: true);
    _appDataDirectory = directory;
    return directory;
  }

  Future<void> ensureReady() async {
    await appDataDirectory;
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

  Future<ApiConfig> loadApiConfig() async {
    final file = await _apiConfigFile();
    final decoded = await _readJson(file, ApiConfig.defaults().toJson());
    if (decoded is! Map<String, dynamic>) {
      throw StorageException('API 配置文件异常：${file.path}');
    }
    return ApiConfig.fromJson(decoded);
  }

  Future<void> saveApiConfig(ApiConfig config) async {
    await _writeJson(await _apiConfigFile(), config.toJson());
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

  Future<void> clearChat(String characterId) async {
    await saveChat(characterId, const []);
  }

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
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
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
    return ChatSummary.fromJson(decoded).characterId.isEmpty
        ? ChatSummary.empty(characterId)
        : ChatSummary.fromJson(decoded);
  }

  Future<void> saveSummary(ChatSummary summary) async {
    await _writeJson(await _summaryFile(summary.characterId), summary.toJson());
  }

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

  Future<Uint8List> exportAllData() async {
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
      final bytes = await entity.readAsBytes();
      final name = entity.path
          .substring(directory.path.length + 1)
          .replaceAll(Platform.pathSeparator, '/');
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  Future<void> importAllData(Uint8List bytes) async {
    final directory = await appDataDirectory;
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
    await directory.create(recursive: true);
    _appDataDirectory = directory;

    final archive = ZipDecoder().decodeBytes(bytes);
    for (final file in archive.files) {
      if (!file.isFile) {
        continue;
      }
      final safeName = file.name.replaceAll('\\', '/');
      if (safeName.startsWith('/') || safeName.contains('..')) {
        continue;
      }
      final outPath =
          '${directory.path}${Platform.pathSeparator}${safeName.replaceAll('/', Platform.pathSeparator)}';
      final outFile = File(outPath);
      await outFile.parent.create(recursive: true);
      await outFile.writeAsBytes(file.content as List<int>, flush: true);
    }
    await _repairRestoredAppDataPaths(directory);
    await ensureReady();
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
    await _writeQueue;
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
        await _writeJsonNow(file, fallback);
        return fallback;
      }
      return jsonDecode(content);
    } on FormatException catch (_) {
      if (recoverOnInvalid) {
        await _backupInvalidJson(file);
        await _writeJsonNow(file, fallback);
        return fallback;
      }
      throw StorageException('数据文件异常，无法解析 JSON：${file.path}');
    } on FileSystemException catch (error) {
      throw StorageException('读取本地文件失败：${error.message}');
    }
  }

  Future<void> _writeJson(File file, dynamic data) async {
    await _enqueueWrite(() => _writeJsonNow(file, data));
  }

  Future<T> _enqueueWrite<T>(Future<T> Function() action) async {
    final write = _writeQueue.then((_) => action());
    _writeQueue = write.then<void>((_) {}, onError: (_, _) {});
    return write;
  }

  Future<void> _writeJsonNow(File file, dynamic data) async {
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    const encoder = JsonEncoder.withIndent('  ');
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(encoder.convert(data), flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await temp.rename(file.path);
  }

  Future<void> _updateCharacters(
    List<AppCharacter> Function(List<AppCharacter>) update,
  ) async {
    final file = await _charactersFile();
    await _enqueueWrite(() async {
      final decoded = await _readJsonNow(file, <dynamic>[]);
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
    await _enqueueWrite(() async {
      final decoded = await _readJsonNow(file, <dynamic>[]);
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

  Future<void> _backupInvalidJson(File file) async {
    if (!await file.exists()) {
      return;
    }
    final backup = File(
      '${file.path}.broken_${DateTime.now().microsecondsSinceEpoch}',
    );
    await file.rename(backup.path);
  }
}
