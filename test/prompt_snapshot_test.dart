import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/app_character.dart';
import 'package:whisnya/models/chat_message.dart';
import 'package:whisnya/models/theater.dart';
import 'package:whisnya/prompts.dart';

void main() {
  final character = AppCharacter.fromJson({'id': 'c', 'name': '角色'});
  final chat = [ChatMessage(role: 'user', content: '你好', time: DateTime(2026))];
  final theater = [
    TheaterMessage(
      id: 'm',
      sessionId: 's',
      round: 1,
      speakerType: TheaterSpeakerType.user,
      speakerId: 'user',
      speakerName: '用户',
      content: '你好',
      time: DateTime(2026),
    ),
  ];

  test('character system prompt snapshot remains routed unchanged', () {
    expect(
      CharacterPromptBuilder.system(character),
      PromptBuilder.buildSystemPrompt(character),
    );
  });
  test('full chat request snapshot remains routed unchanged', () {
    expect(
      CharacterPromptBuilder.request(
        character: character,
        historySummary: '',
        summarizedMessageCount: 0,
        messages: chat,
        useFullContext: true,
      ),
      PromptBuilder.buildChatRequestMessages(
        character: character,
        historySummary: '',
        summarizedMessageCount: 0,
        messages: chat,
        useFullContext: true,
      ),
    );
  });
  test('summary plus recent messages snapshot remains stable', () {
    final request = CharacterPromptBuilder.request(
      character: character,
      historySummary: '摘要',
      summarizedMessageCount: 1,
      messages: chat,
      useFullContext: false,
    );
    expect(request[1]['content'], contains('摘要'));
  });
  test('rolling summary snapshot remains routed unchanged', () {
    expect(
      SummaryPromptBuilder.rolling(previousSummary: '旧摘要', newMessages: chat),
      PromptBuilder.buildRollingSummaryPrompt(
        previousSummary: '旧摘要',
        newMessages: chat,
      ),
    );
  });
  test('novel chunk snapshot remains routed unchanged', () {
    expect(
      NovelPromptBuilder.chunk('正文', 1, 2),
      PromptBuilder.buildNovelChunkPrompt('正文', 1, 2),
    );
  });
  test('novel merge snapshot remains routed unchanged', () {
    expect(
      NovelPromptBuilder.merge(const ['一', '二']),
      PromptBuilder.buildNovelMergePrompt(const ['一', '二']),
    );
  });
  test('single API theater reply parser remains routed unchanged', () {
    const raw = '[{"speaker":"角色","content":"回复"}]';
    expect(
      TheaterPromptBuilder.parseReplies(
        raw,
      ).map((item) => [item.speaker, item.content]),
      PromptBuilder.parseTheaterReplies(
        raw,
      ).map((item) => [item.speaker, item.content]),
    );
  });
  test('theater summary snapshot remains routed unchanged', () {
    expect(
      TheaterPromptBuilder.summary(previousSummary: '', messages: theater),
      PromptBuilder.buildTheaterSummaryPrompt(
        previousSummary: '',
        messages: theater,
      ),
    );
  });
  test('recent context boundary remains stable', () {
    expect(
      PromptBuilder.recentContextStartIndex(messageCount: 70, summaryLimit: 50),
      49,
    );
  });
  test('theater preservation boundary remains stable', () {
    expect(
      PromptBuilder.theaterSummaryEndIndex(
        messages: theater,
        summarizedMessageCount: 0,
      ),
      0,
    );
  });
  test('summary length limit remains stable', () {
    expect(PromptBuilder.limitSummary('abcdef', 3), 'abc');
  });
}
