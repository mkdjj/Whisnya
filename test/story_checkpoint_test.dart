import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/app_character.dart';
import 'package:whisnya/models/chat_message.dart';
import 'package:whisnya/models/chat_summary.dart';
import 'package:whisnya/models/message_anchor.dart';
import 'package:whisnya/services/local_storage_service.dart';
import 'package:whisnya/services/story/story_checkpoint_service.dart';

void main() {
  test('branch copies only anchored prefix, never future or summary', () async {
    final directory = await Directory.systemTemp.createTemp(
      'story_checkpoint_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final storage = LocalStorageService(appDataDirectory: directory);
    final character = AppCharacter.fromJson({'id': 'c', 'name': 'Role'});
    await storage.saveCharacter(character);
    final source = await storage.createChatSession('c');
    final messages = List.generate(
      20,
      (i) => ChatMessage(
        id: 'm$i',
        role: i.isEven ? 'user' : 'assistant',
        content: i < 8 ? 'past$i' : 'FUTURE SECRET',
        time: DateTime(2026),
      ),
    );
    await storage.saveChatBySession(source, messages);
    await storage.saveSummaryBySession(
      ChatSummary(
        characterId: 'c',
        sessionId: source.id,
        summary: 'FUTURE SECRET',
        updatedAt: DateTime(2026),
        summarizedMessageCount: 20,
      ),
    );
    final service = StoryCheckpointService(storage);
    final checkpoint = await service.create(
      source: source,
      character: character,
      anchor: MessageAnchor.capture(source.id, messages, 7),
      title: 'route',
    );
    final branch = await service.fork(checkpoint.id, title: 'new route');
    expect(branch.isStoryBranch, true);
    expect(branch.allowSharedCharacterMemories, false);
    expect((await storage.loadChatBySession(branch)).length, 8);
    expect((await storage.loadSummaryBySession(branch)).summary, '');
    await storage.saveChatBySession(source, [
      messages.first.copyWith(content: 'changed'),
    ]);
    expect(
      (await service.load(checkpoint.id)).contentHash,
      checkpoint.contentHash,
    );
    expect((await storage.loadChatBySession(branch)).last.content, 'past7');
  });
}
