import 'dart:async';
import 'dart:convert';
import '../../models/ai_usage.dart';
import '../../models/api_config.dart';
import '../../models/auto_story.dart';
import '../ai/ai_conversation_runner.dart';
import '../ai/ai_gateway.dart';

/// Single-call director transport and strict, side-effect-free parsers.
class AutoStoryDirectorService {
  const AutoStoryDirectorService(
    this.gateway, {
    this.timeout = const Duration(seconds: 90),
  });
  final AiGateway gateway;
  final Duration timeout;

  Future<String> request({
    required AiEndpointConfig endpoint,
    required List<Map<String, String>> messages,
    AiCancelToken? cancelToken,
    void Function(AiUsage)? onUsage,
  }) async {
    if (endpoint.validationError case final String error) {
      throw AiException(error);
    }
    final token = cancelToken ?? AiCancelToken();
    if (token.isCancelled) throw AiException('请求已取消。');
    Future<String> perform() async {
      if (gateway is StructuredAiGateway) {
        final response = await (gateway as StructuredAiGateway).sendResponse(
          AiRequest(
            apiKey: endpoint.apiKey,
            baseUrl: endpoint.baseUrl,
            model: endpoint.model,
            messages: messages,
            temperature: 0.3,
          ),
          cancelToken: token,
        );
        // Existing structured adapters encode unavailable usage as all zeroes.
        if (response.usage.totalTokens > 0) onUsage?.call(response.usage);
        return response.content;
      }
      return gateway.sendMessage(
        apiKey: endpoint.apiKey,
        baseUrl: endpoint.baseUrl,
        model: endpoint.model,
        messages: messages,
        temperature: 0.3,
        cancelToken: token,
        onUsage: onUsage,
      );
    }

    final text = await perform().timeout(
      timeout,
      onTimeout: () {
        token.cancel();
        throw TimeoutException('导演请求超时。', timeout);
      },
    );
    if (token.isCancelled) throw AiException('请求已取消。');
    return text;
  }

  static List<StoryStage> parsePlan(
    String raw, {
    required int plannedRounds,
    String idPrefix = 'plan',
  }) {
    final json = _object(raw);
    final stages = _list(json['stages'], 3, 8, 'stages');
    final maps = stages.map((e) => _map(e, 'stage')).toList();
    final minimum = maps
        .map((e) => _positive(e['minRounds'], 'minRounds'))
        .toList();
    final weights = maps
        .map((e) => _positive(e['targetRounds'], 'targetRounds'))
        .toList();
    final minSum = minimum.fold<int>(0, (a, b) => a + b);
    if (plannedRounds < minSum || plannedRounds > 300) {
      throw const FormatException('阶段最少轮数超过预算。');
    }
    final total = weights.fold<int>(0, (a, b) => a + b);
    final allocations = List<int>.of(weights);
    if (total != plannedRounds ||
        List.generate(
          maps.length,
          (i) => weights[i] < minimum[i],
        ).any((e) => e)) {
      final remaining = plannedRounds - minSum;
      final fractions = List.generate(
        maps.length,
        (i) => remaining * weights[i] / total,
      );
      for (var i = 0; i < maps.length; i++) {
        allocations[i] = minimum[i] + fractions[i].floor();
      }
      var extra = plannedRounds - allocations.fold<int>(0, (a, b) => a + b);
      final order = List.generate(maps.length, (i) => i)
        ..sort((a, b) {
          final difference = (fractions[b] - fractions[b].floor()).compareTo(
            fractions[a] - fractions[a].floor(),
          );
          return difference == 0 ? a.compareTo(b) : difference;
        });
      for (final index in order) {
        if (extra-- <= 0) break;
        allocations[index]++;
      }
    }
    return List.generate(maps.length, (i) {
      final value = maps[i];
      return StoryStage(
        id: '${idPrefix}_stage_$i',
        title: _text(value['title'], 200, 'title'),
        objective: _text(value['objective'], 2000, 'objective'),
        minRounds: minimum[i],
        targetRounds: allocations[i],
        acceptanceCriteria: _strings(
          value['acceptanceCriteria'],
          1,
          3,
          'acceptanceCriteria',
        ),
        permittedDevelopments: _strings(
          value['permittedDevelopments'],
          0,
          10,
          'permittedDevelopments',
        ),
        prematureDevelopments: _strings(
          value['prematureDevelopments'],
          0,
          10,
          'prematureDevelopments',
        ),
      );
    });
  }

  static DirectorResult parseReview(
    String raw, {
    required AutoStoryDocument story,
    required int coveredThroughOrdinal,
    String? checkpointId,
    String? checkKey,
    DateTime? now,
  }) {
    final json = _object(raw);
    final previous = story.currentCheckpoint;
    if (story.plan.isEmpty ||
        json['coveredThroughOrdinal'] is! int ||
        story.turns.length.isOdd ||
        coveredThroughOrdinal < 0 ||
        coveredThroughOrdinal.isEven ||
        coveredThroughOrdinal >= story.turns.length ||
        coveredThroughOrdinal < (previous?.coveredThroughOrdinal ?? -1) ||
        json['coveredThroughOrdinal'] != coveredThroughOrdinal) {
      throw const FormatException('导演覆盖范围不符合本次完整正文批次。');
    }
    final covered = story.turns.take(coveredThroughOrdinal + 1).toList();
    final byId = {for (final turn in covered) turn.turnId: turn};
    List<StoryEvidence> evidence(Object? raw, {bool actual = false}) =>
        _list(raw, 0, 60, 'evidence').map((value) {
          final item = _map(value, 'evidence');
          final id = _text(item['turnId'], 200, 'turnId');
          final quote = _text(item['quote'], 4000, 'quote');
          final turn = byId[id];
          if (turn == null || !turn.content.contains(quote)) {
            throw const FormatException('导演证据引用不存在或摘录与正文不符。');
          }
          if (actual &&
              (item['eventType'] != 'actual' ||
                  !_actualExcerpt(turn.content, quote))) {
            throw const FormatException('愿望、梦境、计划不能作为实际达成证据。');
          }
          return StoryEvidence(turnId: id, quote: quote);
        }).toList();
    final summary = _text(json['summary'], 4000, 'summary', empty: true);
    final facts = _list(json['facts'], 0, 20, 'facts').map((value) {
      final map = _map(value, 'fact');
      final sources = evidence(map['evidence']);
      if (sources.isEmpty) throw const FormatException('事实必须有正文摘录证据。');
      return StoryFact(
        text: _text(map['text'], 2000, 'fact.text'),
        evidenceTurnIds: sources.map((e) => e.turnId).toSet().toList(),
        evidence: sources,
      );
    }).toList();
    if (json['stageSatisfied'] is! bool || json['goalReached'] is! bool) {
      throw const FormatException('导演判断必须为布尔值。');
    }
    final criteria = evidence(json['criteriaEvidence'], actual: true);
    final goal = evidence(json['goalEvidence'], actual: true);
    final current = story.stageIndex;
    final currentStage = story.plan[current];
    var satisfied = json['stageSatisfied'] == true;
    if (satisfied) {
      final indices = _list(
        json['criteriaEvidence'],
        1,
        60,
        'criteriaEvidence',
      ).map((e) => _map(e, 'criteriaEvidence')['criterionIndex']).toSet();
      if (indices.any(
        (i) =>
            i is! int || i < 0 || i >= currentStage.acceptanceCriteria.length,
      )) {
        throw const FormatException('阶段条件编号无效。');
      }
      if (!List.generate(
        currentStage.acceptanceCriteria.length,
        (i) => i,
      ).every(indices.contains)) {
        throw const FormatException('阶段证据未覆盖全部达成条件。');
      }
    }
    // Retain already established conditions until their minimum duration elapses.
    if (previous?.stageSatisfied == true) satisfied = true;
    final completeCoverage = coveredThroughOrdinal == story.turns.length - 1;
    final startRound =
        previous?.stageStartedRound ??
        (story.toJson()['replanStartRound'] as int? ?? 0);
    final minimumMet =
        story.completedRounds - startRound >= currentStage.minRounds;
    final reached = json['goalReached'] == true;
    if (reached &&
        (!completeCoverage ||
            current != story.plan.length - 1 ||
            !satisfied ||
            !minimumMet ||
            goal.isEmpty)) {
      throw const FormatException('结局必须在最终阶段、完整轮次及有效证据成立后确认。');
    }
    final advance =
        completeCoverage &&
        satisfied &&
        minimumMet &&
        current < story.plan.length - 1;
    final pacing = _text(json['pacing'], 20, 'pacing');
    if (!['normal', 'wrapUp'].contains(pacing)) {
      throw const FormatException('未知节奏。');
    }
    final created = now ?? DateTime.now();
    final id =
        checkpointId ??
        'checkpoint_${story.config.planVersion}_${coveredThroughOrdinal}_${created.microsecondsSinceEpoch}';
    final hash = storyTurnsHash(covered);
    final events = <StoryEvent>[];
    if (json['sceneConflict'] == true) {
      throw StateError('场景建议与已发生事实冲突，请暂停后由用户决定。');
    }
    if (json['sceneTransition'] != null) {
      final transition = _text(json['sceneTransition'], 120, 'sceneTransition');
      if (RegExp(
        r'结婚|恋爱|爱上|同意|答应|死亡|杀死|married|fell in love|agreed|died',
        caseSensitive: false,
      ).hasMatch(transition)) {
        throw const FormatException('场景过渡不能替角色做重大决定。');
      }
      events.add(
        StoryEvent(
          eventId: '${id}_scene',
          kind: 'sceneTransition',
          content: transition,
          effectiveAfterOrdinal: coveredThroughOrdinal,
          sourceCheckpointId: id,
          status: 'applied',
          createdAt: created,
        ),
      );
    }
    return DirectorResult(
      checkpoint: DirectorCheckpoint(
        checkpointId: id,
        coveredThroughOrdinal: coveredThroughOrdinal,
        coveredTurnIdsHash: hash,
        planVersion: story.config.planVersion,
        summary: summary,
        confirmedFacts: facts,
        stageIndex: advance ? current + 1 : current,
        criterionEvidence: advance
            ? const []
            : criteria.isEmpty
            ? (previous?.criterionEvidence ?? const [])
            : criteria,
        stageSatisfied: advance ? false : satisfied,
        stageStartedRound: advance ? story.completedRounds : startRound,
        nextBeat: _text(json['nextBeat'], 2000, 'nextBeat', empty: true),
        pacing: pacing,
        createdAt: created,
        goalEvidence: goal,
        checkKey:
            checkKey ??
            '${story.config.planVersion}:${story.completedRounds}:$hash',
      ),
      events: events,
      goalReached: reached,
    );
  }
}

bool _actualExcerpt(String content, String quote) {
  // Check the entire containing sentence so cropped quotes cannot hide modality.
  final start = content.indexOf(quote);
  var left = start;
  var right = start + quote.length;
  while (left > 0 && !'。！？!?\n'.contains(content[left - 1])) {
    left--;
  }
  while (right < content.length && !'。！？!?\n'.contains(content[right])) {
    right++;
  }
  return !RegExp(
    r'梦见|梦到|梦里|梦中|梦境|计划|将来|以后|未来|假如|如果|希望|想象|幻想|打算|dream|imagin|\b(?:will|would|wish|hope|plan|if)\b',
    caseSensitive: false,
  ).hasMatch(content.substring(left, right));
}

Map<String, dynamic> _object(String raw) {
  if (raw.length > 100000) throw const FormatException('导演回复超出长度限制。');
  return _map(jsonDecode(raw), 'response');
}

Map<String, dynamic> _map(Object? value, String field) {
  if (value is! Map<String, dynamic>) {
    throw FormatException('$field must be object');
  }
  return value;
}

List<dynamic> _list(Object? value, int min, int max, String field) {
  if (value is! List || value.length < min || value.length > max) {
    throw FormatException('$field invalid length');
  }
  return value;
}

String _text(Object? value, int max, String field, {bool empty = false}) {
  if (value is! String ||
      (!empty && value.trim().isEmpty) ||
      value.runes.length > max) {
    throw FormatException('$field invalid text');
  }
  return value.trim();
}

int _positive(Object? value, String field) {
  if (value is! int || value < 1 || value > 300) {
    throw FormatException('$field invalid integer');
  }
  return value;
}

List<String> _strings(Object? value, int min, int max, String field) =>
    _list(value, min, max, field).map((e) => _text(e, 2000, field)).toList();
