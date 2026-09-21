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
  File get autoStoryIndex => _file('auto_story_index.json');
  File autoStory(String id) => _file('auto_stories', '$id.json');
  File get chatSessions => _file('chat_sessions.json');
  File get checkpointsIndex => _file('story/checkpoints/index.json');
  File checkpoint(String id) => _file('story/checkpoints/$id.json');
  File characterState(String sessionId) =>
      _file('story/states/$sessionId.json');
  File get collectionIndex => _file('collection/index.json');
  File memento(String id) => _file('collection/items/$id.json');
  File get storyTransactions => _file('story/transactions.json');
  File get checkpointTransactions =>
      _file('story/checkpoint_transactions.json');
  File get qqIntegration => _file('config', 'qq_integration.json');
  File get qqContactBindings => _file('config', 'qq_contact_bindings.json');
  File get qqDiagnostics => _file('logs', 'qq_diagnostics.json');
  File chat(String id) => _file('chats', '$id.json');
  File summary(String id) => _file('summaries', '$id.json');
  File chatBySession(String sessionId) => chat(sessionId);
  File summaryBySession(String sessionId) => summary(sessionId);
  File characterMemories(String characterId) =>
      _file('memories', '$characterId.json');
  File get worldBooks => _file('worldbooks.json');
  File worldBookEntries(String worldBookId) =>
      _file('worldbook_entries', '$worldBookId.json');
  File novelText(String id) => _file('novels', '$id.txt');
  File novelSummaryCache(String id) => _file('novel_summary_cache', '$id.json');
  File theaterMessages(String id) => _file('theater_messages', '$id.json');
  Directory media(String folder) => _directory('media', folder);

  File _file(String first, [String? second]) =>
      File([root.path, first, ?second].join(Platform.pathSeparator));

  Directory _directory(String first, String second) =>
      Directory([root.path, first, second].join(Platform.pathSeparator));
}
