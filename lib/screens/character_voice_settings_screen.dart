import 'dart:async';
import 'package:flutter/material.dart';
import '../models/character_voice_profile.dart';
import '../services/speech/role_speech_controller.dart';
import '../services/speech/speech_backend.dart';
import '../utils/app_i18n.dart';

/// Returns drafts to the character editor; never persists or mutates its input.
class CharacterVoiceSettingsScreen extends StatefulWidget {
  const CharacterVoiceSettingsScreen({
    super.key,
    required this.profiles,
    this.controller,
  });
  final Map<String, CharacterVoiceProfile> profiles;
  final RoleSpeechController? controller;
  @override
  State<CharacterVoiceSettingsScreen> createState() =>
      _CharacterVoiceSettingsScreenState();
}

class _CharacterVoiceSettingsScreenState
    extends State<CharacterVoiceSettingsScreen> {
  late final RoleSpeechController speech =
      widget.controller ?? RoleSpeechController.instance;
  late CharacterVoiceProfile draft =
      widget.profiles[speech.platformKey] ?? const CharacterVoiceProfile();
  final text = TextEditingController(text: '你好，今天想和我聊些什么？');
  List<AvailableVoice> voices = [];
  List<String> engines = [];
  bool loading = true;
  String? loadError;
  int _loadGeneration = 0;
  String tr(String zh, String en) => context.isEnglish ? en : zh;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
    speech.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    setState(() => loading = true);
    try {
      await speech.stop();
      final availability = await speech.backend.initialize().timeout(
        const Duration(seconds: 8),
      );
      final loadedEngines = await speech.backend.listEngines().timeout(
        const Duration(seconds: 8),
      );
      final loadedVoices = await speech.backend
          .listVoices(engineId: draft.engineId)
          .timeout(const Duration(seconds: 8));
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        engines = loadedEngines;
        voices = loadedVoices;
        loadError = availability.available && voices.isNotEmpty
            ? null
            : 'no_voices';
        loading = false;
      });
    } catch (_) {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          loading = false;
          loadError = 'engine_unavailable';
        });
      }
    }
  }

  @override
  void dispose() {
    _loadGeneration++;
    speech.removeListener(_changed);
    unawaited(speech.stop());
    text.dispose();
    super.dispose();
  }

  String networkLabel(AvailableVoice voice) => voice.networkRequired == false
      ? tr('离线', 'Offline')
      : voice.networkRequired == true
      ? tr('需要网络', 'Network required')
      : tr('网络需求未知', 'Network use unknown');
  @override
  Widget build(BuildContext context) {
    final selected = voices.indexWhere((v) => v.matches(draft));
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('角色声音', 'Character voice')),
        actions: [
          TextButton(
            onPressed: () async {
              await speech.stop();
              if (context.mounted) {
                Navigator.pop(context, {
                  ...widget.profiles,
                  speech.platformKey: draft,
                });
              }
            },
            child: Text(tr('保存', 'Save')),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            tr(
              '使用本机系统 TTS，不是声线克隆。音色取决于设备；引擎可能联网，与聊天 API 设置无关。',
              'Uses device system TTS, not voice cloning. Voices depend on this device; engine network use is separate from chat API settings.',
            ),
          ),
          SwitchListTile(
            title: Text(tr('使用角色声音', 'Use character voice')),
            value: draft.enabled,
            onChanged: (value) {
              setState(() => draft = draft.copyWith(enabled: value));
              if (!value) unawaited(speech.stop());
            },
          ),
          if (loading) const LinearProgressIndicator(),
          if (loadError != null)
            Text(
              tr(
                '没有可用语音服务或音色。请在 Android 系统设置的“文字转语音”中安装引擎/语言；Windows 请在设置→时间和语言→语音中安装语言包，然后刷新。',
                'No speech service or voices available. Install a TTS engine/language in Android text-to-speech settings, or Windows Settings → Time & language → Speech, then refresh.',
              ),
            ),
          if (speech.platformKey == 'android' && engines.isNotEmpty)
            DropdownButtonFormField<String>(
              initialValue: engines.contains(draft.engineId)
                  ? draft.engineId
                  : null,
              decoration: InputDecoration(
                labelText: tr('引擎（空白为系统默认）', 'Engine (blank = system default)'),
              ),
              items: [
                for (final engine in engines)
                  DropdownMenuItem(
                    value: engine,
                    child: Text(engine, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: loading
                  ? null
                  : (value) {
                      setState(
                        () => draft = draft.copyWith(
                          engineId: value,
                          voiceName: '',
                          locale: '',
                          identifier: '',
                        ),
                      );
                      unawaited(_load());
                    },
            ),
          if (!loading)
            DropdownButtonFormField<int>(
              key: ValueKey('$selected/${draft.engineId}'),
              initialValue: selected >= 0 ? selected : null,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: tr('音色', 'Voice'),
                hintText: tr(
                  '当前设备未配置声音',
                  'No voice configured for this device',
                ),
              ),
              items: [
                for (var i = 0; i < voices.length; i++)
                  DropdownMenuItem(
                    value: i,
                    child: Text(
                      '${voices[i].name} · ${voices[i].locale} · ${networkLabel(voices[i])}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (index) {
                if (index == null) return;
                final voice = voices[index];
                setState(
                  () => draft = draft.copyWith(
                    voiceName: voice.name,
                    locale: voice.locale,
                    identifier: voice.identifier ?? '',
                  ),
                );
              },
            ),
          if (selected < 0 && draft.voiceName.isNotEmpty)
            Text(
              tr(
                '已保存的音色在当前设备不可用，请重新选择。',
                'The saved voice is unavailable on this device. Please select another.',
              ),
            ),
          _slider(
            tr(
              '语速：慢 / 标准 / 快（不是精确倍速）',
              'Rate: slow / normal / fast (not exact multipliers)',
            ),
            draft.rate,
            0,
            1,
            (v) => draft = draft.copyWith(rate: v),
          ),
          _slider(
            tr('音量', 'Volume'),
            draft.volume,
            0,
            1,
            (v) => draft = draft.copyWith(volume: v),
          ),
          _slider(
            tr('音调（效果取决于引擎）', 'Pitch (effect depends on engine)'),
            draft.pitch,
            .5,
            2,
            (v) => draft = draft.copyWith(pitch: v),
          ),
          TextField(
            controller: text,
            maxLength: 300,
            maxLines: 3,
            decoration: InputDecoration(labelText: tr('试听文本', 'Preview text')),
          ),
          Wrap(
            spacing: 12,
            children: [
              FilledButton.icon(
                key: const ValueKey('speech-preview'),
                onPressed: loading || selected < 0 || !draft.enabled
                    ? null
                    : () => unawaited(
                        speech.preview(text: text.text, profile: draft),
                      ),
                icon: const Icon(Icons.volume_up),
                label: Text(tr('试听', 'Preview')),
              ),
              OutlinedButton(
                key: const ValueKey('speech-stop'),
                onPressed: () => unawaited(speech.stop()),
                child: Text(tr('停止', 'Stop')),
              ),
              TextButton(
                onPressed: loading ? null : _load,
                child: Text(tr('刷新音色', 'Refresh voices')),
              ),
            ],
          ),
          if (speech.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                speechErrorText(speech.error!, english: context.isEnglish),
              ),
            ),
        ],
      ),
    );
  }

  Widget _slider(
    String title,
    double value,
    double min,
    double max,
    void Function(double) update,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title),
      Slider(
        value: value,
        min: min,
        max: max,
        onChanged: (v) => setState(() => update(v)),
      ),
    ],
  );
}

String speechErrorText(String error, {required bool english}) {
  final messages = <String, List<String>>{
    'voice_not_configured': [
      '当前设备未配置声音。',
      'No voice configured for this device.',
    ],
    'voice_unavailable': [
      '当前音色不存在，请重新选择。',
      'This voice is unavailable. Please select another.',
    ],
    'network_voice_blocked': [
      '音色需要网络。请先在角色语音设置中明确允许。',
      'This voice requires network access. Allow it explicitly in speech settings first.',
    ],
    'network_unknown': [
      '音色网络需求未知，尚未播放。允许网络音色也表示接受未知网络需求。',
      'Network use is unknown; playback was blocked. Allowing network voices also accepts unknown network use.',
    ],
    'no_readable_text': ['没有可朗读文本。', 'No readable text.'],
    'no_voices': [
      '没有可用音色，请安装系统语音资源。',
      'No voices available. Install system speech resources.',
    ],
    'engine_unavailable': [
      '语音引擎不可用，请检查系统语音设置。',
      'Speech engine unavailable. Check system speech settings.',
    ],
    'stop_failed': [
      '语音引擎未确认停止，未开始新的朗读。',
      'The engine did not confirm stopping; no new speech started.',
    ],
  };
  return (messages[error] ??
      [
        '朗读失败，聊天正文不受影响。',
        'Speech failed; the saved chat is unaffected.',
      ])[english ? 1 : 0];
}
