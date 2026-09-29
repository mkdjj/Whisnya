import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/memento.dart';
import 'package:whisnya/services/share_card_service.dart';

MementoSnapshot sample(String text) => MementoSnapshot(
  id: 'x',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  idempotencyKey: 'x',
  title: 'Title',
  characterId: 'c',
  characterNameSnapshot: 'Role',
  sessionTitleSnapshot: 'Session',
  sourceSessionId: 's',
  entries: [
    MementoEntry(
      sourceMessageId: 'm',
      sourcePrefixDigest: 'd',
      role: 'user',
      speakerNameSnapshot: 'PRIVATE_NAME',
      time: DateTime.utc(2026),
      contentSnapshot: text,
      innerVoiceSnapshot: 'PRIVATE_INNER',
    ),
  ],
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('global inner voice off wins over stale share preference', () {
    final plan = ShareCardPlan.prepare(
      sample('Body'),
      const ShareCardOptions(showInnerVoice: true),
    );
    expect(plan.pages.single.blocks.single.text, 'Body');
    final allowed = ShareCardPlan.prepare(
      sample('Body'),
      const ShareCardOptions(showInnerVoice: true, innerVoiceAllowed: true),
    );
    expect(allowed.pages.single.blocks.single.text, 'Body\n\nPRIVATE_INNER');
  });
  test('default share omits sensitive display fields and keeps graphemes', () {
    final plan = ShareCardPlan.prepare(
      sample('Hello 👩‍👩‍👧‍👦 é'),
      const ShareCardOptions(),
    );
    expect(plan.pages.single.blocks.single.speaker, '我');
    expect(plan.pages.single.blocks.single.text, 'Hello 👩‍👩‍👧‍👦 é');
    expect(plan.pages.single.blocks.single.time, isNull);
    expect(plan.pages.single.blocks.single.avatarAssetId, isNull);
  });
  test(
    'presentation-only changes reuse pagination and update rendered metadata',
    () {
      final snapshot = sample(List.filled(200, '👩‍👩‍👧‍👦中é').join());
      final original = ShareCardPlan.prepare(
        snapshot,
        const ShareCardOptions(),
      );
      final themed = original.withPresentation(
        snapshot,
        const ShareCardOptions(
          template: ShareCardTemplate.dark,
          backgroundColor: Colors.black,
        ),
      );
      expect(identical(themed.pages, original.pages), true);
      expect(themed.options.template, ShareCardTemplate.dark);

      final renamed = themed.withPresentation(
        snapshot,
        const ShareCardOptions(userName: 'Anonymous', showTime: true),
      );
      expect(
        renamed.pages.expand((p) => p.blocks).map((b) => b.text).toList(),
        original.pages.expand((p) => p.blocks).map((b) => b.text).toList(),
      );
      expect(
        renamed.pages
            .expand((p) => p.blocks)
            .every((b) => b.speaker == 'Anonymous' && b.time != null),
        true,
      );
    },
  );
  test('title and text visibility changes repaginate from current values', () {
    final snapshot = sample('Body');
    final original = ShareCardPlan.prepare(snapshot, const ShareCardOptions());
    final retitled = original.withPresentation(
      snapshot,
      const ShareCardOptions(title: 'Latest title'),
    );
    expect(retitled.title, 'Latest title');
    expect(identical(retitled.pages, original.pages), false);
    final inner = retitled.withPresentation(
      snapshot,
      const ShareCardOptions(
        title: 'Latest title',
        showInnerVoice: true,
        innerVoiceAllowed: true,
      ),
    );
    expect(inner.pages.single.blocks.single.text, 'Body\n\nPRIVATE_INNER');
  });
  test('a different snapshot never reuses old text chunks', () {
    final original = ShareCardPlan.prepare(
      sample('Old body'),
      const ShareCardOptions(),
    );
    final changed = original.withPresentation(
      sample('New body'),
      const ShareCardOptions(template: ShareCardTemplate.dark),
    );
    expect(changed.pages.single.blocks.single.text, 'New body');
  });
  test(
    'long paragraph paginates without dropping text and rejects over twelve pages',
    () {
      final text = List.filled(400, '👩‍👩‍👧‍👦中é').join();
      final plan = ShareCardPlan.prepare(
        sample(text),
        const ShareCardOptions(),
      );
      expect(plan.pages.length, greaterThan(1));
      expect(
        plan.pages.expand((p) => p.blocks).map((b) => b.text).join(),
        text,
      );
      expect(
        () => ShareCardPlan.prepare(
          sample(List.filled(20000, '中').join()),
          const ShareCardOptions(),
        ),
        throwsStateError,
      );
    },
  );
  testWidgets('single preview page fits 360 wide and rasterizes to 1080', (
    tester,
  ) async {
    final plan = ShareCardPlan.prepare(
      sample('Hello'),
      const ShareCardOptions(),
    );
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: SingleChildScrollView(
          child: Center(
            child: SizedBox(
              width: 360,
              child: RepaintBoundary(
                key: key,
                child: ShareCardPageView(plan: plan, page: 0),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final bytes = (await tester.runAsync(() => renderShareCardPage(key)))!;
    expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    expect(
      (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19],
      1080,
    );
  });
}
