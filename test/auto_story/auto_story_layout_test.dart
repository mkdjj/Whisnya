import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/auto_story.dart';
import 'package:whisnya/widgets/auto_story/auto_story_turn_card.dart';

void main() {
  for (final reasoning in [false, true]) {
    testWidgets(
      'drag over ${reasoning ? 'reasoning' : 'body'} scrolls the story timeline',
      (tester) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        final text = List.filled(60, '这是一段足够长的剧情正文，用于模拟手机里的长气泡。').join('\n');
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: TargetPlatform.android),
            home: Scaffold(
              body: ListView(
                controller: scroll,
                children: [
                  AutoStoryTurnCard(
                    turn: StoryTurn(
                      turnId: 'turn',
                      ordinal: 0,
                      speakerId: 'A',
                      content: reasoning ? '短正文' : text,
                      reasoningContent: reasoning ? text : '',
                    ),
                    actor: StoryActorSnapshot(actorId: 'A', name: '演员'),
                    english: false,
                    split: false,
                    showReasoning: reasoning,
                    onCollect: () {},
                  ),
                  const SizedBox(height: 800),
                ],
              ),
            ),
          ),
        );
        if (reasoning) {
          await tester.tap(find.byType(ExpansionTile));
          await tester.pumpAndSettle();
        }
        await tester.tapAt(const Offset(150, 280));
        await tester.pump();
        await tester.dragFrom(const Offset(150, 280), const Offset(0, -180));
        await tester.pumpAndSettle();
        expect(scroll.offset, greaterThan(100));
        await tester.dragFrom(const Offset(150, 280), const Offset(0, 110));
        await tester.pumpAndSettle();
        expect(scroll.offset, lessThan(180));
      },
    );
  }
}
