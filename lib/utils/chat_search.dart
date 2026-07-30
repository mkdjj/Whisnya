import 'package:flutter/material.dart';

import 'app_i18n.dart';

typedef ChatSearchUpdate = ({String query, List<int> results, int activeIndex});

List<int> findChatSearchResults(Iterable<String> contents, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return const [];
  final results = <int>[];
  var index = 0;
  for (final content in contents) {
    if (content.toLowerCase().contains(needle)) results.add(index);
    index++;
  }
  return results;
}

Future<void> showChatSearchDialog({
  required BuildContext context,
  required List<String> contents,
  required String initialQuery,
  required int initialActiveIndex,
  required ValueChanged<ChatSearchUpdate> onChanged,
}) async {
  final controller = TextEditingController(text: initialQuery);
  var query = initialQuery;
  var results = findChatSearchResults(contents, query);
  var active = results.isEmpty
      ? 0
      : initialActiveIndex.clamp(0, results.length - 1).toInt();

  void apply(String nextQuery, List<int> nextResults, int nextActive) {
    final safeActive = nextResults.isEmpty
        ? 0
        : nextActive.clamp(0, nextResults.length - 1).toInt();
    onChanged((
      query: nextQuery,
      results: nextResults,
      activeIndex: safeActive,
    ));
  }

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) {
        void runSearch() {
          final nextQuery = controller.text;
          final nextResults = findChatSearchResults(contents, nextQuery);
          setDialogState(() {
            query = nextQuery;
            results = nextResults;
            active = 0;
          });
          apply(nextQuery, nextResults, 0);
        }

        void move(int delta) {
          if (results.isEmpty) return;
          final nextActive = (active + delta + results.length) % results.length;
          setDialogState(() => active = nextActive);
          apply(query, results, nextActive);
        }

        final status = query.trim().isEmpty
            ? context.t('输入关键词开始搜索')
            : results.isEmpty
            ? context.t('没有找到结果')
            : context.t('第 ${active + 1} / ${results.length} 个结果');

        return AlertDialog(
          title: Text(context.t('搜索聊天记录')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: context.t('输入关键词'),
                  prefixIcon: const Icon(Icons.search),
                ),
                onSubmitted: (_) => runSearch(),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  IconButton(
                    tooltip: context.t('上一个'),
                    onPressed: results.isEmpty ? null : () => move(-1),
                    icon: const Icon(Icons.keyboard_arrow_up),
                  ),
                  Expanded(child: Text(status, textAlign: TextAlign.center)),
                  IconButton(
                    tooltip: context.t('下一个'),
                    onPressed: results.isEmpty ? null : () => move(1),
                    icon: const Icon(Icons.keyboard_arrow_down),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                apply('', const [], 0);
                Navigator.of(dialogContext).pop();
              },
              child: Text(context.t('关闭')),
            ),
            FilledButton(onPressed: runSearch, child: Text(context.t('搜索'))),
          ],
        );
      },
    ),
  );
  controller.dispose();
}
