import 'dart:async';

import '../../models/ai_usage.dart';
import '../../models/ai_response.dart';
import '../../models/api_config.dart';
import '../../models/theater.dart';
import '../../prompts/prompt_builder.dart';
import '../../utils/theater_participant_reply_sanitizer.dart';
import '../../utils/theater_streaming_parser.dart';
import '../ai/ai_conversation_runner.dart';
import '../ai/ai_gateway.dart';
import 'theater_generation_event.dart';
import 'theater_reply_engine.dart';

class TheaterGenerationService {
  const TheaterGenerationService(this._gateway);

  final AiGateway _gateway;

  Stream<AiResponseDelta> _stream({
    required AiEndpointConfig endpoint,
    required List<Map<String, String>> messages,
    AiCancelToken? cancelToken,
    void Function(AiUsage)? onUsage,
  }) async* {
    final gateway = _gateway;
    if (gateway is StructuredAiGateway) {
      await for (final event in (gateway as StructuredAiGateway).streamResponse(
        AiRequest(
          apiKey: endpoint.apiKey,
          baseUrl: endpoint.baseUrl,
          model: endpoint.model,
          messages: messages,
          stream: true,
        ),
        cancelToken: cancelToken,
      )) {
        if (event.usage != null) onUsage?.call(event.usage!);
        yield event;
      }
    } else {
      await for (final text in gateway.streamMessage(
        apiKey: endpoint.apiKey,
        baseUrl: endpoint.baseUrl,
        model: endpoint.model,
        messages: messages,
        cancelToken: cancelToken,
        onUsage: onUsage,
      )) {
        yield AiResponseDelta(contentDelta: text);
      }
    }
  }

  Stream<TheaterGenerationEvent> generate({
    required TheaterSession session,
    required ApiConfig apiConfig,
    required List<TheaterParticipant> participants,
    required List<TheaterMessage> messages,
    required String novelSummary,
    required int round,
    TheaterGenerationIntent generationIntent =
        TheaterGenerationIntent.userReply,
    TheaterReplyPhase phase = TheaterReplyPhase.main,
    AiCancelToken? cancelToken,
    bool includeReasoning = false,
    void Function(
      AiUsage usage,
      AiEndpointConfig endpoint,
      List<Map<String, String>> request,
    )?
    onUsage,
  }) async* {
    if (session.apiMode == TheaterApiMode.singleApi) {
      final endpoint = apiConfig.effectiveEndpoint(session.singleEndpointId);
      if (endpoint == null || !endpoint.isComplete) {
        yield TheaterGenerationFailed(_error(session, round, 'API 配置不可用。'));
        return;
      }
      yield* _singleApi(
        session: session,
        participants: participants,
        messages: messages,
        novelSummary: novelSummary,
        endpoint: endpoint,
        round: round,
        generationIntent: generationIntent,
        phase: phase,
        cancelToken: cancelToken,
        includeReasoning: includeReasoning,
        onUsage: onUsage,
      );
      return;
    }

    final snapshot = List<TheaterMessage>.of(messages);
    if (session.multiApiReplyMode == TheaterMultiApiReplyMode.parallel) {
      final controller = StreamController<TheaterGenerationEvent>();
      var remaining = participants.length;
      if (remaining == 0) {
        await controller.close();
      } else {
        for (final participant in participants) {
          _participant(
            session: session,
            participant: participant,
            apiConfig: apiConfig,
            messages: snapshot,
            novelSummary: novelSummary,
            round: round,
            generationIntent: generationIntent,
            phase: phase,
            cancelToken: cancelToken,
            includeReasoning: includeReasoning,
            onUsage: onUsage,
          ).listen(
            controller.add,
            onError: (Object error) => controller.add(
              TheaterGenerationFailed(
                _roleError(
                  session,
                  participant,
                  round,
                  _exceptionMessage(error),
                ),
              ),
            ),
            onDone: () {
              if (--remaining == 0) unawaited(controller.close());
            },
          );
        }
      }
      yield* controller.stream;
      return;
    }

    final context = List<TheaterMessage>.of(messages);
    for (final participant in participants) {
      await for (final event in _participant(
        session: session,
        participant: participant,
        apiConfig: apiConfig,
        messages: context,
        novelSummary: novelSummary,
        round: round,
        generationIntent: generationIntent,
        phase: phase,
        cancelToken: cancelToken,
        includeReasoning: includeReasoning,
        onUsage: onUsage,
      )) {
        if (event case TheaterMessageFinished(:final message)) {
          context.add(message);
        }
        yield event;
      }
    }
  }

  Stream<TheaterGenerationEvent> _participant({
    required TheaterSession session,
    required TheaterParticipant participant,
    required ApiConfig apiConfig,
    required List<TheaterMessage> messages,
    required String novelSummary,
    required int round,
    required TheaterGenerationIntent generationIntent,
    required TheaterReplyPhase phase,
    required AiCancelToken? cancelToken,
    required bool includeReasoning,
    required void Function(
      AiUsage usage,
      AiEndpointConfig endpoint,
      List<Map<String, String>> request,
    )?
    onUsage,
  }) async* {
    final endpoint = apiConfig.effectiveEndpoint(participant.endpointId);
    if (endpoint == null || !endpoint.isComplete) {
      yield TheaterGenerationFailed(
        _roleError(session, participant, round, 'API 配置不可用。'),
      );
      return;
    }
    final placeholder = _roleMessage(session, participant, endpoint, round, '');
    var placeholderVisible = false;
    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        if (placeholderVisible) {
          yield TheaterMessageRemoved(placeholder.id);
        }
        yield TheaterMessageStarted(placeholder);
        placeholderVisible = true;
        final request = PromptBuilder.buildTheaterParticipantRequest(
          session: session,
          participant: participant,
          novelSummary: novelSummary,
          messages: messages,
          generationIntent: generationIntent,
          phase: phase,
          previousOutputInvalid: attempt == 1,
        );
        final raw = StringBuffer();
        final reasoning = StringBuffer();
        await for (final event in _stream(
          endpoint: endpoint,
          messages: request,
          cancelToken: cancelToken,
          onUsage: (usage) => onUsage?.call(usage, endpoint, request),
        )) {
          raw.write(event.contentDelta);
          reasoning.write(event.reasoningDelta);
          if (event.contentDelta.isNotEmpty) {
            yield TheaterMessageDelta(placeholder.id, event.contentDelta);
          }
        }
        final reply = sanitizeParticipantReply(
          rawReply: raw.toString(),
          targetName: participant.name,
          allParticipantNames: session.participants
              .map((item) => item.name)
              .toList(),
        );
        if (reply != null) {
          yield TheaterMessageFinished(
            placeholder.copyWith(
              content: reply,
              reasoningContent: reasoning.toString(),
            ),
          );
          return;
        }
      }
      yield TheaterMessageRemoved(placeholder.id);
      yield TheaterGenerationFailed(
        _roleError(session, participant, round, theaterMultipleRoleErrorText),
      );
    } on AiException catch (error) {
      if (placeholderVisible) yield TheaterMessageRemoved(placeholder.id);
      yield TheaterGenerationFailed(
        _roleError(session, participant, round, error.message),
      );
    } on TimeoutException catch (error) {
      if (placeholderVisible) yield TheaterMessageRemoved(placeholder.id);
      yield TheaterGenerationFailed(
        _roleError(session, participant, round, _exceptionMessage(error)),
      );
    } on Exception catch (error) {
      if (placeholderVisible) yield TheaterMessageRemoved(placeholder.id);
      yield TheaterGenerationFailed(
        _roleError(session, participant, round, _exceptionMessage(error)),
      );
    }
  }

  Stream<TheaterGenerationEvent> _singleApi({
    required TheaterSession session,
    required List<TheaterParticipant> participants,
    required List<TheaterMessage> messages,
    required String novelSummary,
    required AiEndpointConfig endpoint,
    required int round,
    required TheaterGenerationIntent generationIntent,
    required TheaterReplyPhase phase,
    required AiCancelToken? cancelToken,
    required bool includeReasoning,
    required void Function(
      AiUsage usage,
      AiEndpointConfig endpoint,
      List<Map<String, String>> request,
    )?
    onUsage,
  }) async* {
    final request = PromptBuilder.buildTheaterSingleApiRequest(
      session: session,
      novelSummary: novelSummary,
      messages: messages,
      allowedParticipants: participants,
      generationIntent: generationIntent,
      phase: phase,
    );
    final parser = TheaterStreamingParser();
    final raw = StringBuffer();
    final reasoning = StringBuffer();
    final completed = <TheaterMessage>[];
    TheaterMessage? current;
    var finished = 0;
    void usageCallback(AiUsage usage) =>
        onUsage?.call(usage, endpoint, request);
    try {
      await for (final response in _stream(
        endpoint: endpoint,
        messages: request,
        cancelToken: cancelToken,
        onUsage: usageCallback,
      )) {
        final chunk = response.contentDelta;
        reasoning.write(response.reasoningDelta);
        raw.write(chunk);
        for (final event in parser.addChunk(chunk)) {
          switch (event) {
            case TheaterSpeakerStarted(:final speaker):
              final participant = _participantByName(participants, speaker);
              current = participant == null
                  ? null
                  : _roleMessage(session, participant, endpoint, round, '');
              if (current != null) yield TheaterMessageStarted(current);
            case TheaterContentDelta(:final delta):
              if (current != null) yield TheaterMessageDelta(current.id, delta);
            case TheaterMessageCompleted(:final content):
              if (current != null && content.trim().isNotEmpty) {
                finished++;
                completed.add(current.copyWith(content: content.trim()));
              }
              current = null;
          }
        }
      }
      for (final event in parser.finish()) {
        if (event case TheaterMessageCompleted(:final content)) {
          if (current != null && content.trim().isNotEmpty) {
            finished++;
            completed.add(current.copyWith(content: content.trim()));
          }
        }
      }
    } finally {
      // Single-API reasoning belongs to the whole response, not each actor.
      // Retain it exactly once on the first finished reply.
      for (var i = 0; i < completed.length; i++) {
        yield TheaterMessageFinished(
          completed[i].copyWith(
            reasoningContent: i == 0 ? reasoning.toString() : '',
          ),
        );
      }
    }
    if (finished > 0) return;
    final fallback = resolveSingleApiFallback(raw.toString(), participants);
    if (fallback.isEmpty) {
      yield TheaterGenerationFailed(
        _error(session, round, theaterFormatErrorText),
      );
      return;
    }
    for (final draft in fallback) {
      final participant = _participantByName(participants, draft.speaker);
      if (participant != null) {
        yield TheaterMessageFinished(
          _roleMessage(
            session,
            participant,
            endpoint,
            round,
            draft.content,
          ).copyWith(reasoningContent: reasoning.toString()),
        );
        reasoning.clear();
      }
    }
  }

  TheaterParticipant? _participantByName(
    List<TheaterParticipant> participants,
    String name,
  ) {
    for (final participant in participants) {
      if (participant.name.trim() == name.trim()) return participant;
    }
    return null;
  }

  TheaterMessage _roleMessage(
    TheaterSession session,
    TheaterParticipant participant,
    AiEndpointConfig endpoint,
    int round,
    String content,
  ) {
    final now = DateTime.now();
    return TheaterMessage(
      id: 'theater_msg_${now.microsecondsSinceEpoch}_${participant.id}',
      sessionId: session.id,
      round: round,
      speakerType: TheaterSpeakerType.role,
      speakerId: participant.id,
      speakerName: participant.name,
      content: content,
      endpointId: endpoint.id,
      endpointName: endpoint.name,
      model: endpoint.model,
      time: now,
    );
  }

  TheaterMessage _roleError(
    TheaterSession session,
    TheaterParticipant participant,
    int round,
    String message,
  ) => TheaterMessage(
    id: 'theater_msg_${DateTime.now().microsecondsSinceEpoch}_error',
    sessionId: session.id,
    round: round,
    speakerType: TheaterSpeakerType.role,
    speakerId: participant.id,
    speakerName: participant.name,
    content: message,
    isError: true,
    errorMessage: message,
    time: DateTime.now(),
  );

  TheaterMessage _error(TheaterSession session, int round, String message) =>
      TheaterMessage(
        id: 'theater_msg_${DateTime.now().microsecondsSinceEpoch}_error',
        sessionId: session.id,
        round: round,
        speakerType: TheaterSpeakerType.system,
        speakerId: '',
        speakerName: '系统',
        content: message,
        isError: true,
        errorMessage: message,
        time: DateTime.now(),
      );

  String _exceptionMessage(Object error) => switch (error) {
    AiException(:final message) => message,
    TimeoutException(:final message) => message ?? '请求超时。',
    _ => error.toString(),
  };
}
