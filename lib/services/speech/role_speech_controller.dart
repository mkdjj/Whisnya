import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show StringCharacters;
import '../../models/chat_message.dart';
import '../../models/character_voice_profile.dart';
import 'speech_backend.dart';
import 'flutter_tts_backend.dart';
import 'speech_text_formatter.dart';

enum SpeechState { unavailable, idle, preparing, speaking, stopping, error }

class RoleSpeechController extends ChangeNotifier {
  RoleSpeechController({required this.backend});
  static final instance = RoleSpeechController(backend: FlutterTtsBackend());
  final SpeechBackend backend;
  SpeechState state = SpeechState.idle;
  String? error, messageId, variantId, sessionId, playbackId, contentDigest;
  int? datasetEpoch;
  CharacterVoiceProfile? voiceProfileSnapshot;
  bool _enabled = false, _allowNetwork = false, _disposed = false;
  bool _nativePlaybackMayBeActive = false;
  bool _backendUsed = false;
  int _generation = 0;
  Future<void> _transition = Future.value();
  final Set<String> _consumed = {};
  String get platformKey => backend.platformKey;
  bool get isPlaying =>
      state == SpeechState.preparing ||
      state == SpeechState.speaking ||
      state == SpeechState.stopping;
  void configure({required bool enabled, required bool allowNetworkVoices}) {
    final revokedNetwork = _allowNetwork && !allowNetworkVoices;
    _enabled = enabled;
    _allowNetwork = allowNetworkVoices;
    if ((!enabled || revokedNetwork) && isPlaying) unawaited(stop());
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _serial(Future<void> Function() action) {
    final result = _transition.then((_) => action());
    _transition = result.catchError((Object _) {});
    return result;
  }

  Future<void> stop() {
    ++_generation;
    // Lifecycle hooks may call stop repeatedly even when speech was never used.
    // Still invalidate pending generations, but do not wake a native engine or
    // allocate timeout timers unless preparation/playback actually needs it.
    if (!isPlaying && !_nativePlaybackMayBeActive) return Future.value();
    state = SpeechState.stopping;
    _notify();
    return _serial(() async {
      try {
        await backend.stop().timeout(const Duration(seconds: 6));
        _nativePlaybackMayBeActive = false;
        state = SpeechState.idle;
        error = null;
      } catch (_) {
        state = SpeechState.error;
        error = 'stop_failed';
      }
      messageId = null;
      variantId = null;
      playbackId = null;
      _notify();
    });
  }

  Future<void> playMessage({
    required ChatMessage message,
    required String sessionId,
    required String messageId,
    required String variantId,
    required int datasetEpoch,
    required CharacterVoiceProfile? profile,
  }) {
    if (!message.isAssistant) return Future.value();
    return _play(
      message.effectiveContent,
      sessionId: sessionId,
      messageId: messageId,
      variantId: variantId,
      datasetEpoch: datasetEpoch,
      profile: profile,
    );
  }

  Future<void> preview({
    required String text,
    required CharacterVoiceProfile profile,
  }) => _play(
    text.characters.take(300).toString(),
    sessionId: 'preview',
    messageId: 'preview',
    variantId: 'preview',
    datasetEpoch: -1,
    profile: profile,
    preview: true,
  );
  Future<void> autoReadSavedReply({
    required ChatMessage message,
    required String sessionId,
    required String messageId,
    required String variantId,
    required int datasetEpoch,
    required CharacterVoiceProfile? profile,
    required bool persisted,
    required bool selected,
    required bool enabled,
  }) async {
    if (!persisted ||
        !selected ||
        !enabled ||
        !_enabled ||
        message.effectiveReplyState != 'completed') {
      return;
    }
    final key = '$datasetEpoch/$sessionId/$messageId/$variantId';
    if (!_consumed.add(key) || isPlaying) return;
    await playMessage(
      message: message,
      sessionId: sessionId,
      messageId: messageId,
      variantId: variantId,
      datasetEpoch: datasetEpoch,
      profile: profile,
    );
  }

  Future<void> _play(
    String text, {
    required String sessionId,
    required String messageId,
    required String variantId,
    required int datasetEpoch,
    required CharacterVoiceProfile? profile,
    bool preview = false,
  }) async {
    if ((!_enabled && !preview) || _disposed) return;
    final generation = ++_generation;
    state = SpeechState.preparing;
    error = null;
    _notify();
    List<String> chunks = [];
    await _serial(() async {
      if (generation != _generation) return;
      try {
        _backendUsed = true;
        await backend.stop().timeout(const Duration(seconds: 6));
        _nativePlaybackMayBeActive = false;
        if (generation != _generation) return;
        state = SpeechState.preparing;
        error = null;
        _notify();
        if (profile == null || !profile.enabled || profile.voiceName.isEmpty) {
          throw StateError('voice_not_configured');
        }
        final availability = await backend.initialize().timeout(
          const Duration(seconds: 8),
        );
        if (!availability.available) {
          throw StateError(availability.reason ?? 'engine_unavailable');
        }
        final voices = await backend
            .listVoices(engineId: profile.engineId)
            .timeout(const Duration(seconds: 8));
        final matches = voices.where((v) => v.matches(profile));
        if (matches.isEmpty) throw StateError('voice_unavailable');
        if (matches.first.networkRequired != false && !_allowNetwork) {
          throw StateError(
            matches.first.networkRequired == true
                ? 'network_voice_blocked'
                : 'network_unknown',
          );
        }
        chunks = const SpeechTextFormatter().chunks(
          text,
          maxCodeUnits: availability.maxCodeUnits,
        );
        if (chunks.isEmpty) throw StateError('no_readable_text');
        if (generation != _generation) return;
        this.sessionId = sessionId;
        this.messageId = messageId;
        this.variantId = variantId;
        this.datasetEpoch = datasetEpoch;
        playbackId = '$generation';
        contentDigest = sha256.convert(utf8.encode(text)).toString();
        voiceProfileSnapshot = profile;
        state = SpeechState.speaking;
        _notify();
      } catch (e) {
        if (generation == _generation) {
          state = SpeechState.error;
          error = e is StateError ? e.message.toString() : 'speech_failed';
          _notify();
        }
        chunks = [];
      }
    });
    for (final chunk in chunks) {
      if (generation != _generation || _disposed) return;
      try {
        _nativePlaybackMayBeActive = true;
        await backend
            .speak(
              SpeechRequest(
                playbackId: '$generation',
                text: chunk,
                profile: profile!,
              ),
            )
            .timeout(Duration(seconds: 30 + chunk.length));
      } catch (_) {
        if (generation == _generation) {
          await stop();
          state = SpeechState.error;
          error = 'speech_failed';
          _notify();
        }
        return;
      }
    }
    if (generation == _generation && chunks.isNotEmpty) {
      _nativePlaybackMayBeActive = false;
      state = SpeechState.idle;
      this.messageId = null;
      playbackId = null;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    if (_backendUsed) unawaited(backend.dispose().catchError((Object _) {}));
    super.dispose();
  }
}
