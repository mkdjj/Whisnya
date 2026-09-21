import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/services/chat/reply_inspiration_service.dart';
import 'package:whisnya/widgets/chat/reply_inspiration_sheet.dart';
import 'package:whisnya/utils/app_i18n.dart';
import 'package:whisnya/services/ai_service.dart';

const choices = [
  ReplyInspiration('温柔', '我在这里'),
  ReplyInspiration('调侃', '舍不得？'),
  ReplyInspiration('推进', '出去走走'),
];

void main() {
  testWidgets(
    'switching mode cancels pending request and ignores stale options',
    (tester) async {
      AiCancelToken? token;
      var calls = 0;
      final pending = Completer<List<ReplyInspiration>>();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: appSupportedLocales,
          localizationsDelegates: appLocalizationsDelegates,
          home: Scaffold(
            body: ReplyInspirationSheet(
              generate: (mode, cancel) {
                calls++;
                token = cancel;
                return pending.future;
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('只给行动提示'));
      await tester.pump();
      expect(token!.isCancelled, isTrue);
      pending.complete(choices);
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('我在这里'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'explicit open generates once; mode selection alone never requests',
    (tester) async {
      var calls = 0;
      ReplyInspirationMode? lastMode;
      final pending = Completer<List<ReplyInspiration>>();
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: appSupportedLocales,
          localizationsDelegates: appLocalizationsDelegates,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  selected = await showModalBottomSheet<String>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => ReplyInspirationSheet(
                      generate: (mode, token) {
                        calls++;
                        lastMode = mode;
                        return calls == 1
                            ? pending.future
                            : Future.value(choices);
                      },
                    ),
                  );
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      expect(calls, 0);
      await tester.tap(find.text('打开'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(calls, 1);
      await tester.tap(find.text('生成三条建议'));
      await tester.pump();
      expect(calls, 1);
      pending.complete(choices);
      await tester.pumpAndSettle();
      await tester.tap(find.text('只给行动提示'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('我在这里'), findsNothing);
      await tester.tap(find.text('生成三条建议'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(lastMode, ReplyInspirationMode.actions);
      await tester.tap(find.text('我在这里'));
      await tester.pumpAndSettle();
      expect(selected, '我在这里');
    },
  );

  testWidgets(
    'errors retry only on click and dismissed late result is ignored',
    (tester) async {
      var calls = 0;
      AiCancelToken? activeToken;
      final pending = Completer<List<ReplyInspiration>>();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: appSupportedLocales,
          localizationsDelegates: appLocalizationsDelegates,
          home: Scaffold(
            body: ReplyInspirationSheet(
              generate: (mode, token) async {
                activeToken = token;
                calls++;
                if (calls == 1) throw const FormatException('invalid');
                return pending.future;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('建议生成失败，请重试。'), findsOneWidget);
      await tester.tap(find.text('生成三条建议'));
      await tester.pump();
      expect(calls, 2);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(activeToken!.isCancelled, isTrue);
      pending.complete(choices);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
