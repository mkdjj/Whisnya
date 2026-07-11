import 'dart:io';

class StoragePaths {
  const StoragePaths(this.root);

  final Directory root;

  File get settings => _file('settings.json');
  File get apiConfig => _file('api_config.json');
  File get aiUsage => _file('ai_usage.json');
  File get characters => _file('characters.json');
  File get novels => _file('novels.json');
  File get theaterSessions => _file('theater_sessions.json');
  File chat(String id) => _file('chats', '$id.json');
  File summary(String id) => _file('summaries', '$id.json');
  File novelText(String id) => _file('novels', '$id.txt');
  File novelChat(String id) => _file('novel_chats', '$id.json');
  File novelSummaryCache(String id) => _file('novel_summary_cache', '$id.json');
  File theaterMessages(String id) => _file('theater_messages', '$id.json');
  Directory media(String folder) => _directory('media', folder);

  File _file(String first, [String? second]) =>
      File([root.path, first, ?second].join(Platform.pathSeparator));

  Directory _directory(String first, String second) =>
      Directory([root.path, first, second].join(Platform.pathSeparator));
}
