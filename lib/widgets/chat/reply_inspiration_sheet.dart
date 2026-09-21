import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/ai_service.dart';
import '../../services/chat/reply_inspiration_service.dart';
import '../../utils/app_i18n.dart';

class ReplyInspirationSheet extends StatefulWidget {
  const ReplyInspirationSheet({required this.generate, super.key});

  final Future<List<ReplyInspiration>> Function(
    ReplyInspirationMode mode,
    AiCancelToken cancelToken,
  )
  generate;

  @override
  State<ReplyInspirationSheet> createState() => _ReplyInspirationSheetState();
}

class _ReplyInspirationSheetState extends State<ReplyInspirationSheet> {
  var _mode = ReplyInspirationMode.reply;
  var _busy = false;
  String? _error;
  List<ReplyInspiration> _suggestions = const [];
  AiCancelToken? _token;

  @override
  void initState() {
    super.initState();
    // The sheet exists only after the user explicitly taps the lightbulb.
    unawaited(_generate());
  }

  @override
  void dispose() {
    _token?.cancel();
    super.dispose();
  }

  Future<void> _generate() async {
    if (_busy) return;
    final token = AiCancelToken();
    _token = token;
    setState(() {
      _busy = true;
      _error = null;
      _suggestions = const [];
    });
    try {
      final suggestions = await widget.generate(_mode, token);
      if (mounted && identical(_token, token)) {
        setState(() => _suggestions = suggestions);
      }
    } catch (error) {
      if (mounted && identical(_token, token)) {
        setState(
          () => _error = error is AiException ? error.message : '建议生成失败，请重试。',
        );
      }
    } finally {
      if (mounted && identical(_token, token)) {
        setState(() {
          _busy = false;
          _token = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope<String>(
    onPopInvokedWithResult: (didPop, result) {
      if (didPop) {
        _token?.cancel();
        _token = null;
      }
    },
    child: SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.t('回复灵感'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: context.t('关闭'),
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Text(context.t('选择后填入输入框，可编辑，不会自动发送。')),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final mode in ReplyInspirationMode.values)
                  ChoiceChip(
                    label: Text(
                      context.t(
                        mode == ReplyInspirationMode.reply ? '回复建议' : '只给行动提示',
                      ),
                    ),
                    selected: _mode == mode,
                    onSelected: (_) {
                      if (_mode == mode) return;
                      _token?.cancel();
                      setState(() {
                        _token = null;
                        _busy = false;
                        _mode = mode;
                        _suggestions = const [];
                        _error = null;
                      });
                    },
                  ),
              ],
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(context.t(_error!)),
              ),
            for (final suggestion in _suggestions)
              Card(
                child: ListTile(
                  title: Text(suggestion.label),
                  subtitle: Text(suggestion.text),
                  trailing: const Icon(Icons.add_comment_outlined),
                  onTap: () => Navigator.of(context).pop(suggestion.text),
                ),
              ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: _busy ? null : _generate,
              icon: const Icon(Icons.lightbulb_outline),
              label: Text(context.t('生成三条建议')),
            ),
            Text(
              context.t('每次生成会使用当前 API；切换模式后请点击生成。'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
  );
}
