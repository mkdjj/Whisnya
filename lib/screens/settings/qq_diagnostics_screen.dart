import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/qq_diagnostic_event.dart';
import '../../services/local_storage_service.dart';
import '../../utils/app_i18n.dart';

class QqDiagnosticsScreen extends StatefulWidget {
  const QqDiagnosticsScreen({required this.storage, super.key});

  final LocalStorageService storage;

  @override
  State<QqDiagnosticsScreen> createState() => _QqDiagnosticsScreenState();
}

class _QqDiagnosticsScreenState extends State<QqDiagnosticsScreen> {
  List<QqDiagnosticEvent> _events = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final events = await widget.storage.loadQqDiagnostics();
    if (mounted) setState(() => _events = events.reversed.toList());
  }

  String _exportText() => _events
      .map((event) {
        final value = event.toJson();
        return value.entries
            .map((entry) => '${entry.key}=${entry.value}')
            .join(' | ');
      })
      .join('\n');

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _exportText()));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.t('已复制脱敏诊断'))));
    }
  }

  Future<void> _clear() async {
    await widget.storage.clearQqDiagnostics();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.t('QQ 诊断日志')),
        actions: [
          IconButton(
            onPressed: _events.isEmpty ? null : _copy,
            icon: const Icon(Icons.copy),
          ),
          IconButton(
            onPressed: _events.isEmpty ? null : _clear,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: _events.isEmpty
          ? Center(child: Text(context.t('暂无诊断记录')))
          : ListView.builder(
              itemCount: _events.length,
              itemBuilder: (context, index) {
                final event = _events[index];
                return ListTile(
                  leading: Icon(
                    event.success
                        ? Icons.check_circle_outline
                        : Icons.error_outline,
                    color: event.success ? Colors.green : Colors.red,
                  ),
                  title: Text(event.eventType.name),
                  subtitle: Text(
                    '${event.time.toLocal()} · ${event.contactDisplayName}\n'
                    '${event.transport} ${event.errorCode} ${event.errorSummary}',
                  ),
                  isThreeLine: true,
                );
              },
            ),
    );
  }
}
