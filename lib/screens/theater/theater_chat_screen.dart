part of 'theater_screens.dart';

class TheaterChatScreen extends StatefulWidget {
  const TheaterChatScreen({
    required this.storage,
    required this.aiService,
    required this.settings,
    required this.session,
    super.key,
  });

  final LocalStorageService storage;
  final AiService aiService;
  final AppSettings settings;
  final TheaterSession session;

  @override
  State<TheaterChatScreen> createState() => _TheaterChatScreenState();
}

class _TheaterChatScreenState extends State<TheaterChatScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  late TheaterSession _session;
  var _messages = <TheaterMessage>[];
  var _apiConfig = ApiConfig.defaults();
  var _novelSummary = '';
  var _isLoading = true;
  var _isGenerating = false;
  var _isSummarizing = false;
  var _generationId = 0;
  AiCancelToken? _cancelToken;
  final _streamFlushers = <void Function()>{};

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    _load();
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final apiConfig = await widget.storage.loadApiConfig();
    final messages = await widget.storage.loadTheaterMessages(_session.id);
    var novelSummary = '';
    if (_session.boundNovelId.isNotEmpty) {
      final novels = await widget.storage.loadNovels();
      for (final novel in novels) {
        if (novel.id == _session.boundNovelId) {
          novelSummary = novel.summary;
          break;
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _apiConfig = apiConfig;
      _messages = messages;
      _novelSummary = novelSummary;
      _isLoading = false;
    });
  }

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isGenerating) return;
    final now = DateTime.now();
    final userRole = _session.userParticipant;
    final round = _messages.isEmpty ? 1 : _messages.last.round + 1;
    final message = TheaterMessage(
      id: 'theater_msg_${now.microsecondsSinceEpoch}',
      sessionId: _session.id,
      round: round,
      speakerType: TheaterSpeakerType.user,
      speakerId: userRole?.id ?? '',
      speakerName: userRole?.name ?? context.t('我'),
      content: text,
      time: now,
    );
    setState(() {
      _messages = [..._messages, message];
      _isGenerating = true;
    });
    _inputController.clear();
    await _saveMessages();
    await _saveSession(_session.copyWith(updatedAt: now));
    await _generateReplies(round, TheaterGenerationIntent.userReply);
  }

  Future<void> _regenerateRound() =>
      _beginContinuation(TheaterGenerationIntent.continueConversation);

  Future<void> _continueTheater() =>
      _beginContinuation(TheaterGenerationIntent.continueTheater);

  Future<void> _beginContinuation(TheaterGenerationIntent intent) async {
    if (_isGenerating) return;
    if (_messages.isEmpty) {
      context.showSnack('请先输入第一句话');
      return;
    }
    if (_session.aiParticipants.isEmpty) {
      context.showSnack('没有可自动回复的角色');
      return;
    }
    final round = _messages.last.round + 1;
    setState(() => _isGenerating = true);
    await _generateReplies(round, intent);
  }

  Future<void> _generateReplies(
    int round,
    TheaterGenerationIntent intent,
  ) async {
    final generationId = ++_generationId;
    final cancelToken = AiCancelToken();
    _cancelToken = cancelToken;
    try {
      final summaryUpdated = await _updateRollingSummary(
        generationId,
        cancelToken,
      );
      if (!mounted || generationId != _generationId) return;
      final available = _session.activeAiParticipants;
      if (available.isEmpty) {
        await _appendSystemError('没有可自动回复的角色', round);
        return;
      }

      if (_session.apiMode == TheaterApiMode.multiApi &&
          _session.multiApiReplyMode == TheaterMultiApiReplyMode.turnBased) {
        final selected = intent == TheaterGenerationIntent.continueTheater
            ? selectParticipants(
                participants: available,
                count: resolveContinueTheaterCount(
                  availableCount: available.length,
                ),
              )
            : null;
        await _generateTurnBased(
          round,
          generationId,
          cancelToken,
          oneParticipant:
              intent == TheaterGenerationIntent.continueConversation,
          selectedParticipants: selected,
          generationIntent: intent,
          summaryUpdated: summaryUpdated,
        );
        return;
      }

      final mainCount = intent == TheaterGenerationIntent.continueTheater
          ? resolveContinueTheaterCount(availableCount: available.length)
          : _session.mainReplyCount;
      final mainParticipants = selectParticipants(
        participants: available,
        count: mainCount,
      );
      await _generateParticipantSet(
        mainParticipants,
        round,
        generationId,
        cancelToken,
        generationIntent: intent,
        phase: TheaterReplyPhase.main,
        summaryUpdated: summaryUpdated,
      );
      if (intent == TheaterGenerationIntent.continueTheater ||
          !mounted ||
          generationId != _generationId) {
        return;
      }

      final extraCount = resolveExtraReplyCount(
        mode: _session.extraReplyMode,
        availableCount: available.length,
      );
      if (extraCount == 0) return;
      final extraParticipants = selectParticipants(
        participants: available,
        count: extraCount,
      );
      await _generateParticipantSet(
        extraParticipants,
        round,
        generationId,
        cancelToken,
        generationIntent: TheaterGenerationIntent.continueConversation,
        phase: TheaterReplyPhase.extra,
        summaryUpdated: summaryUpdated,
        forceSequential: true,
      );
    } finally {
      if (identical(_cancelToken, cancelToken)) _cancelToken = null;
      if (mounted && generationId == _generationId) {
        setState(() => _isGenerating = false);
      }
    }
  }

  Future<void> _generateParticipantSet(
    List<TheaterParticipant> participants,
    int round,
    int generationId,
    AiCancelToken cancelToken, {
    required TheaterGenerationIntent generationIntent,
    required TheaterReplyPhase phase,
    required bool summaryUpdated,
    bool forceSequential = false,
  }) async {
    if (_session.apiMode == TheaterApiMode.singleApi) {
      await _generateSingleApi(
        participants,
        round,
        generationId,
        cancelToken,
        generationIntent: generationIntent,
        phase: phase,
        summaryUpdated: summaryUpdated,
      );
      return;
    }
    if (!forceSequential &&
        _session.multiApiReplyMode == TheaterMultiApiReplyMode.parallel) {
      await _generateParallel(
        participants,
        round,
        generationId,
        cancelToken,
        generationIntent: generationIntent,
        phase: phase,
        summaryUpdated: summaryUpdated,
      );
      return;
    }
    await _generateSequential(
      participants,
      round,
      generationId,
      cancelToken,
      generationIntent: generationIntent,
      phase: phase,
      summaryUpdated: summaryUpdated,
    );
  }

  Future<void> _generateSingleApi(
    List<TheaterParticipant> allowedParticipants,
    int round,
    int generationId,
    AiCancelToken cancelToken, {
    required TheaterGenerationIntent generationIntent,
    required TheaterReplyPhase phase,
    required bool summaryUpdated,
  }) async {
    final endpoint = _apiConfig.effectiveEndpoint(_session.singleEndpointId);
    final error = _validateEndpoint(endpoint);
    if (error != null) {
      await _appendSystemError(error, round);
      return;
    }
    if (allowedParticipants.isEmpty) {
      await _appendSystemError('没有可自动回复的角色', round);
      return;
    }
    final parser = TheaterStreamingParser();
    final rawBackup = StringBuffer();
    final pending = <String, String>{};
    final streamResponses = widget.settings.streamResponses;
    TheaterMessage? currentMessage;
    Timer? refreshTimer;
    var validMessages = 0;

    void flushPending() {
      refreshTimer?.cancel();
      refreshTimer = null;
      if (pending.isEmpty || !mounted || generationId != _generationId) {
        pending.clear();
        return;
      }
      final updates = Map<String, String>.from(pending);
      pending.clear();
      setState(() {
        for (final entry in updates.entries) {
          final index = _messages.indexWhere((item) => item.id == entry.key);
          if (index < 0) continue;
          final message = _messages[index];
          _replaceMessage(
            entry.key,
            message.copyWith(content: message.content + entry.value),
          );
        }
      });
    }

    final flushStream = flushPending;
    _streamFlushers.add(flushStream);

    void handleEvents(List<TheaterStreamEvent> events) {
      for (final event in events) {
        switch (event) {
          case TheaterSpeakerStarted(:final speaker):
            flushPending();
            final participant = _matchParticipant(speaker, allowedParticipants);
            currentMessage = participant == null
                ? null
                : _roleMessage(participant, '', round, endpoint: endpoint!);
            if (streamResponses && currentMessage != null) {
              setState(() => _messages = [..._messages, currentMessage!]);
            }
          case TheaterContentDelta(:final delta):
            final message = currentMessage;
            if (!streamResponses || message == null || delta.isEmpty) continue;
            pending.update(
              message.id,
              (value) => value + delta,
              ifAbsent: () => delta,
            );
            refreshTimer ??= Timer(
              const Duration(milliseconds: 30),
              flushPending,
            );
          case TheaterMessageCompleted(:final content):
            flushPending();
            final message = currentMessage;
            currentMessage = null;
            if (message == null) continue;
            final finalContent = content.trim();
            if (finalContent.isEmpty) {
              if (streamResponses) setState(() => _removeMessage(message.id));
              continue;
            }
            final completed = message.copyWith(content: finalContent);
            setState(() {
              if (streamResponses) {
                _replaceMessage(message.id, completed);
              } else {
                _messages = [..._messages, completed];
              }
            });
            validMessages++;
        }
      }
    }

    try {
      final requestMessages = PromptBuilder.buildTheaterSingleApiRequest(
        session: _session,
        novelSummary: _novelSummary,
        messages: _recentMessages(),
        allowedParticipants: allowedParticipants,
        generationIntent: generationIntent,
        phase: phase,
      );
      await for (final chunk in widget.aiService.streamMessage(
        apiKey: endpoint!.apiKey,
        baseUrl: endpoint.baseUrl,
        model: endpoint.model,
        messages: requestMessages,
        cancelToken: cancelToken,
        includeReasoning: widget.settings.showReasoningContent,
        maxTokens: 1200,
        onUsage: (usage) => unawaited(
          widget.storage.recordAiUsage(
            requestType: 'theater',
            model: endpoint.model,
            usage: usage,
            messages: requestMessages,
            summaryUpdated: summaryUpdated,
          ),
        ),
      )) {
        if (!mounted || generationId != _generationId) return;
        rawBackup.write(chunk);
        handleEvents(parser.addChunk(chunk));
      }
      handleEvents(parser.finish());
      if (!mounted || generationId != _generationId) return;

      if (validMessages == 0) {
        final fallback = <TheaterMessage>[];
        for (final draft in resolveSingleApiFallback(
          rawBackup.toString(),
          allowedParticipants,
        )) {
          final participant = _matchParticipant(
            draft.speaker,
            allowedParticipants,
          );
          if (participant != null) {
            fallback.add(
              _roleMessage(
                participant,
                draft.content,
                round,
                endpoint: endpoint,
              ),
            );
          }
        }
        if (fallback.isEmpty) {
          await _appendSystemError('模型没有按群聊格式输出，可重试', round);
          return;
        }
        setState(() => _messages = [..._messages, ...fallback]);
      }
      await _saveMessages();
    } catch (error) {
      if (!mounted || generationId != _generationId) return;
      await _appendSystemError(error.toString(), round);
    } finally {
      _streamFlushers.remove(flushStream);
      refreshTimer?.cancel();
      if (mounted && generationId == _generationId) {
        flushPending();
        setState(() {
          _messages = _messages
              .where(
                (message) =>
                    message.speakerType != TheaterSpeakerType.role ||
                    message.content.trim().isNotEmpty,
              )
              .toList();
        });
        await _saveMessages();
      }
    }
  }

  Future<void> _generateSequential(
    List<TheaterParticipant> participants,
    int round,
    int generationId,
    AiCancelToken cancelToken, {
    required TheaterGenerationIntent generationIntent,
    required TheaterReplyPhase phase,
    required bool summaryUpdated,
  }) async {
    for (final participant in participants) {
      if (!mounted || generationId != _generationId) return;
      await _generateForParticipant(
        participant,
        round,
        generationId,
        cancelToken,
        generationIntent: generationIntent,
        phase: phase,
        summaryUpdated: summaryUpdated,
      );
    }
  }

  Future<void> _generateParallel(
    List<TheaterParticipant> participants,
    int round,
    int generationId,
    AiCancelToken cancelToken, {
    required TheaterGenerationIntent generationIntent,
    required TheaterReplyPhase phase,
    required bool summaryUpdated,
  }) async {
    final contextSnapshot = _recentMessages();
    await Future.wait([
      for (final participant in participants)
        _generateForParticipant(
          participant,
          round,
          generationId,
          cancelToken,
          contextMessages: contextSnapshot,
          generationIntent: generationIntent,
          phase: phase,
          summaryUpdated: summaryUpdated,
          saveOnComplete: false,
        ),
    ]);
    if (mounted && generationId == _generationId) await _saveMessages();
  }

  Future<void> _generateForParticipant(
    TheaterParticipant participant,
    int round,
    int generationId,
    AiCancelToken cancelToken, {
    List<TheaterMessage>? contextMessages,
    TheaterGenerationIntent generationIntent =
        TheaterGenerationIntent.userReply,
    TheaterReplyPhase phase = TheaterReplyPhase.main,
    bool summaryUpdated = false,
    int maxTokens = 800,
    bool saveOnComplete = true,
  }) async {
    if (participant.isMuted) return;
    final endpoint = _apiConfig.effectiveEndpoint(participant.endpointId);
    final error = _validateEndpoint(endpoint);
    if (error != null) {
      await _appendRoleError(participant, error, round);
      return;
    }
    final activeEndpoint = endpoint!;
    final requestContext = contextMessages ?? _recentMessages();
    final streamResponses = widget.settings.streamResponses;
    final placeholder = _roleMessage(
      participant,
      '',
      round,
      endpoint: activeEndpoint,
    );
    try {
      if (!mounted || generationId != _generationId) return;
      if (streamResponses) {
        setState(() => _messages = [..._messages, placeholder]);
      }
      final reply = await requestSanitizedParticipantReply(
        request: (isRetry) async {
          if (!mounted || generationId != _generationId) return '';
          var displayedReply = '';
          if (isRetry && streamResponses) {
            setState(() => _replaceMessage(placeholder.id, placeholder));
          }
          final requestMessages = PromptBuilder.buildTheaterParticipantRequest(
            session: _session,
            participant: participant,
            novelSummary: _novelSummary,
            messages: requestContext,
            generationIntent: generationIntent,
            phase: phase,
            previousOutputInvalid: isRetry,
          );
          final rawReply = StringBuffer();
          final streamBuffer = StreamTextBuffer(
            onFlush: (delta) {
              displayedReply += delta;
              if (!streamResponses ||
                  !mounted ||
                  generationId != _generationId) {
                return;
              }
              setState(
                () => _replaceMessage(
                  placeholder.id,
                  placeholder.copyWith(content: displayedReply),
                ),
              );
            },
          );
          void flushStream() => streamBuffer.flush();
          _streamFlushers.add(flushStream);
          try {
            await for (final chunk in widget.aiService.streamMessage(
              apiKey: activeEndpoint.apiKey,
              baseUrl: activeEndpoint.baseUrl,
              model: activeEndpoint.model,
              messages: requestMessages,
              cancelToken: cancelToken,
              includeReasoning: widget.settings.showReasoningContent,
              maxTokens: maxTokens,
              onUsage: (usage) => unawaited(
                widget.storage.recordAiUsage(
                  requestType: 'theater',
                  model: activeEndpoint.model,
                  usage: usage,
                  messages: requestMessages,
                  summaryUpdated: summaryUpdated,
                ),
              ),
            )) {
              rawReply.write(chunk);
              if (streamResponses) streamBuffer.add(chunk);
            }
          } finally {
            streamBuffer.flush();
            streamBuffer.dispose();
            _streamFlushers.remove(flushStream);
          }
          return rawReply.toString();
        },
        targetName: participant.name,
        allParticipantNames: _session.participants
            .map((item) => item.name)
            .toList(),
      );
      if (reply == null) {
        throw AiException(theaterMultipleRoleErrorText);
      }
      if (!mounted || generationId != _generationId) return;
      setState(() {
        final message = placeholder.copyWith(content: reply);
        if (streamResponses) {
          _replaceMessage(placeholder.id, message);
        } else {
          _messages = [..._messages, message];
        }
      });
      if (saveOnComplete) await _saveMessages();
    } catch (error) {
      if (!mounted || generationId != _generationId) return;
      if (streamResponses) setState(() => _removeMessage(placeholder.id));
      final errorText = error.toString();
      await _appendRoleError(
        participant,
        errorText,
        round,
        content: errorText == theaterMultipleRoleErrorText
            ? context.t(theaterMultipleRoleErrorText)
            : null,
        save: saveOnComplete,
      );
    }
  }

  TheaterMessage _roleMessage(
    TheaterParticipant participant,
    String content,
    int round, {
    required AiEndpointConfig endpoint,
  }) {
    final now = DateTime.now();
    return TheaterMessage(
      id: 'theater_msg_${now.microsecondsSinceEpoch}_${participant.id}',
      sessionId: _session.id,
      round: round,
      speakerType: TheaterSpeakerType.role,
      speakerId: participant.id,
      speakerName: participant.name,
      content: content.trim(),
      endpointId: endpoint.id,
      endpointName: endpoint.name,
      model: endpoint.model,
      time: now,
    );
  }

  void _replaceMessage(String id, TheaterMessage message) {
    final index = _messages.indexWhere((item) => item.id == id);
    if (index < 0) return;
    final next = [..._messages];
    next[index] = message;
    _messages = next;
  }

  void _removeMessage(String id) {
    _messages = _messages.where((item) => item.id != id).toList();
  }

  Future<void> _generateTurnBased(
    int round,
    int generationId,
    AiCancelToken cancelToken, {
    required bool oneParticipant,
    required TheaterGenerationIntent generationIntent,
    List<TheaterParticipant>? selectedParticipants,
    required bool summaryUpdated,
  }) async {
    final participants = _session.aiParticipants;
    if (participants.isEmpty) {
      await _appendSystemError('没有可自动回复的角色', round);
      return;
    }
    final start = _session.nextSpeakerIndex % participants.length;
    final ordered = [
      for (var offset = 0; offset < participants.length; offset++)
        participants[(start + offset) % participants.length],
    ];
    final selectedIds = selectedParticipants?.map((item) => item.id).toSet();
    final targets = selectedIds == null
        ? ordered.take(oneParticipant ? 1 : ordered.length)
        : ordered.where((participant) => selectedIds.contains(participant.id));
    for (final participant in targets) {
      if (!mounted || generationId != _generationId) return;
      final index = participants.indexWhere(
        (item) => item.id == participant.id,
      );
      await _generateForParticipant(
        participant,
        round,
        generationId,
        cancelToken,
        generationIntent: generationIntent,
        summaryUpdated: summaryUpdated,
      );
      if (!mounted || generationId != _generationId) return;
      await _saveSession(
        _session.copyWith(
          nextSpeakerIndex: (index + 1) % participants.length,
          updatedAt: DateTime.now(),
        ),
      );
    }
  }

  Future<void> _deleteTheaterMessage(String id) async {
    setState(() => _removeMessage(id));
    await _saveMessages();
  }

  Future<void> _toggleParticipantMuted(TheaterParticipant participant) async {
    if (_isGenerating) return;
    final current = _session.participants.firstWhere(
      (item) => item.id == participant.id,
      orElse: () => participant,
    );
    await _saveSession(
      _session.copyWith(
        participants: [
          for (final item in _session.participants)
            item.id == current.id
                ? item.copyWith(isMuted: !current.isMuted)
                : item,
        ],
        nextSpeakerIndex: 0,
        updatedAt: DateTime.now(),
      ),
    );
  }

  TheaterParticipant? _matchParticipant(
    String name, [
    Iterable<TheaterParticipant>? allowedParticipants,
  ]) {
    final normalized = name.trim().replaceAll(
      RegExp(r'''^["'“”‘’]+|["'“”‘’]+$'''),
      '',
    );
    for (final participant
        in allowedParticipants ?? _session.activeAiParticipants) {
      if (participant.name.trim() == normalized) return participant;
    }
    return null;
  }

  Future<void> _appendSystemError(String error, int round) async {
    final now = DateTime.now();
    setState(() {
      _messages = [
        ..._messages,
        TheaterMessage(
          id: 'theater_msg_${now.microsecondsSinceEpoch}_error',
          sessionId: _session.id,
          round: round,
          speakerType: TheaterSpeakerType.system,
          speakerId: '',
          speakerName: context.t('系统'),
          content: error,
          isError: true,
          errorMessage: error,
          time: now,
        ),
      ];
    });
    await _saveMessages();
  }

  Future<void> _appendRoleError(
    TheaterParticipant participant,
    String error,
    int round, {
    String? content,
    bool save = true,
  }) async {
    final now = DateTime.now();
    setState(() {
      _messages = [
        ..._messages,
        TheaterMessage(
          id: 'theater_msg_${now.microsecondsSinceEpoch}_error_${participant.id}',
          sessionId: _session.id,
          round: round,
          speakerType: TheaterSpeakerType.role,
          speakerId: participant.id,
          speakerName: participant.name,
          content: content ?? context.t('生成失败，点击重试'),
          isError: true,
          errorMessage: error,
          time: now,
        ),
      ];
    });
    if (save) await _saveMessages();
  }

  Future<void> _retry(TheaterMessage message) async {
    if (_isGenerating) return;
    final singleApiRetry = prepareSingleApiRetry(_messages, message);
    if (_session.apiMode == TheaterApiMode.singleApi &&
        singleApiRetry != null) {
      await _retrySingleApiRound(singleApiRetry);
      return;
    }
    final participant = _session.participants.firstWhere(
      (item) => item.id == message.speakerId,
      orElse: () => const TheaterParticipant(
        id: '',
        source: TheaterRoleSource.appCharacter,
        name: '',
        avatar: '',
        description: '',
        personality: '',
        background: '',
        speakingStyle: '',
      ),
    );
    if (participant.id.isEmpty) return;
    if (participant.isMuted) {
      context.showSnack('该角色已被禁言，请前往群聊设置取消禁言。');
      return;
    }
    final generationId = ++_generationId;
    final cancelToken = AiCancelToken();
    _cancelToken = cancelToken;
    setState(() {
      _isGenerating = true;
      _messages = _messages.where((item) => item.id != message.id).toList();
    });
    await _saveMessages();
    try {
      await _generateForParticipant(
        participant,
        message.round,
        generationId,
        cancelToken,
      );
    } finally {
      if (identical(_cancelToken, cancelToken)) _cancelToken = null;
      if (mounted && generationId == _generationId) {
        setState(() => _isGenerating = false);
      }
    }
  }

  Future<void> _retrySingleApiRound(TheaterRetryState retry) async {
    final generationId = ++_generationId;
    final cancelToken = AiCancelToken();
    _cancelToken = cancelToken;
    final intent =
        retry.messages.any(
          (message) =>
              message.round == retry.round &&
              message.speakerType == TheaterSpeakerType.user,
        )
        ? TheaterGenerationIntent.userReply
        : TheaterGenerationIntent.continueConversation;
    final participants = selectParticipants(
      participants: _session.activeAiParticipants,
      count: _session.mainReplyCount,
    );
    setState(() {
      _isGenerating = true;
      _messages = retry.messages;
    });
    await _saveMessages();
    try {
      await _generateSingleApi(
        participants,
        retry.round,
        generationId,
        cancelToken,
        generationIntent: intent,
        phase: TheaterReplyPhase.main,
        summaryUpdated: false,
      );
    } finally {
      if (identical(_cancelToken, cancelToken)) _cancelToken = null;
      if (mounted && generationId == _generationId) {
        setState(() => _isGenerating = false);
      }
    }
  }

  Future<bool> _updateRollingSummary(
    int generationId,
    AiCancelToken cancelToken,
  ) async {
    final summarizeUntil = PromptBuilder.theaterSummaryEndIndex(
      messages: _messages,
      summarizedMessageCount: _session.summarizedMessageCount,
      messageBatchSize: _session.recentMessageLimit,
      roundBatchSize: _session.keepRoundCount,
    );
    final summarizedCount = _session.summarizedMessageCount
        .clamp(0, summarizeUntil)
        .toInt();
    if (summarizedCount >= summarizeUntil) return false;
    final aiParticipants = _session.aiParticipants;
    final endpointId = _session.apiMode == TheaterApiMode.singleApi
        ? _session.singleEndpointId
        : aiParticipants.isEmpty
        ? ''
        : aiParticipants.first.endpointId;
    final endpoint = _apiConfig.effectiveEndpoint(endpointId);
    if (_validateEndpoint(endpoint) != null) return false;
    final chunk = _messages
        .sublist(summarizedCount, summarizeUntil)
        .where(isValidTheaterContextMessage)
        .toList();
    if (chunk.isEmpty) return false;
    setState(() => _isSummarizing = true);
    try {
      final summaryMessages = [
        {'role': 'system', 'content': '你负责总结群聊记录，并只输出总结内容。'},
        {
          'role': 'user',
          'content': PromptBuilder.buildTheaterSummaryPrompt(
            previousSummary: _session.theaterSummary,
            messages: chunk,
            useCustomItems: widget.settings.useCustomTheaterSummaryItems,
            customItems: widget.settings.customTheaterSummaryItems,
          ),
        },
      ];
      final summary = await widget.aiService.sendMessage(
        apiKey: endpoint!.apiKey,
        baseUrl: endpoint.baseUrl,
        model: endpoint.model,
        messages: summaryMessages,
        cancelToken: cancelToken,
        maxTokens: 800,
        onUsage: (usage) => unawaited(
          widget.storage.recordAiUsage(
            requestType: 'theaterSummary',
            model: endpoint.model,
            usage: usage,
            messages: summaryMessages,
            summaryUpdated: true,
          ),
        ),
      );
      if (!mounted || generationId != _generationId) return false;
      await _saveSession(
        _session.copyWith(
          theaterSummary: PromptBuilder.limitSummary(summary, 1500),
          summarizedMessageCount: summarizeUntil,
          updatedAt: DateTime.now(),
        ),
      );
      return true;
    } catch (_) {
      return false;
    } finally {
      if (mounted) setState(() => _isSummarizing = false);
    }
  }

  List<TheaterMessage> _recentMessages() {
    return recentTheaterMessages(
      _messages,
      summarizedMessageCount: _session.summarizedMessageCount,
    );
  }

  String? _validateEndpoint(AiEndpointConfig? endpoint) {
    if (endpoint == null) return '请先到 API 设置添加配置。';
    if (!endpoint.enabled) return '当前 API 配置已禁用。';
    if (endpoint.apiKey.trim().isEmpty) return 'API Key 为空，请先配置。';
    if (endpoint.baseUrl.trim().isEmpty) return 'Base URL 为空，请先配置。';
    if (endpoint.model.trim().isEmpty) return 'Model 为空，请先配置。';
    return null;
  }

  Future<void> _saveMessages() {
    return widget.storage.saveTheaterMessages(_session.id, _messages);
  }

  Future<void> _saveSession(TheaterSession session) async {
    await widget.storage.saveTheaterSession(session);
    if (!mounted) return;
    setState(() => _session = session);
  }

  void _stopGeneration() {
    if (!_isGenerating) return;
    for (final flush in [..._streamFlushers]) {
      flush();
    }
    _cancelToken?.cancel();
    _cancelToken = null;
    _generationId++;
    setState(() {
      _messages = _messages
          .where(
            (message) =>
                message.speakerType != TheaterSpeakerType.role ||
                message.content.trim().isNotEmpty,
          )
          .toList();
      _isGenerating = false;
    });
    unawaited(_saveMessages());
  }

  Future<void> _clearMessages() async {
    final ok = await showConfirmDialog(
      context: context,
      title: '清空群聊消息',
      content: context.t('确定清空当前群聊消息吗？群聊总结也会清空。'),
      confirmLabel: '清空',
    );
    if (!ok) return;
    await widget.storage.clearTheaterMessages(_session.id);
    await _saveSession(
      _session.copyWith(
        theaterSummary: '',
        summarizedMessageCount: 0,
        updatedAt: DateTime.now(),
      ),
    );
    if (mounted) setState(() => _messages = []);
  }

  Future<void> _showSummaryDialog() async {
    final controller = TextEditingController(text: _session.theaterSummary);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t('群聊总结')),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: TextField(
            controller: controller,
            minLines: 8,
            maxLines: 14,
            decoration: InputDecoration(hintText: context.t('可以直接填写历史总结')),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.t('取消')),
          ),
          FilledButton(
            onPressed: () async {
              await _saveSession(
                _session.copyWith(
                  theaterSummary: controller.text.trim(),
                  summarizedMessageCount: controller.text.trim().isEmpty
                      ? 0
                      : theaterPreserveStartIndex(_messages),
                  updatedAt: DateTime.now(),
                ),
              );
              if (context.mounted) Navigator.of(context).pop();
            },
            child: Text(context.t('保存')),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  Future<void> _openSettings() async {
    var draft = _session;
    var openEditor = false;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          void preview(TheaterSession next) {
            setSheetState(() => draft = next);
            setState(() => _session = next);
          }

          void apply(TheaterSession next) {
            final saved = next.copyWith(updatedAt: DateTime.now());
            preview(saved);
            unawaited(widget.storage.saveTheaterSession(saved));
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: ListView(
                shrinkWrap: true,
                children: [
                  Text(
                    context.t('群聊设置'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 18),
                  _TheaterSettingsInfo(
                    icon: Icons.chat_bubble_outline,
                    title: _chatCountLabel(),
                    subtitle: _theaterSpeedHint(),
                  ),
                  _TheaterSettingsInfo(
                    icon: Icons.memory_outlined,
                    title: context.t('当前模型'),
                    subtitle: _currentModelLabel(),
                    onTap: draft.apiMode == TheaterApiMode.singleApi
                        ? () async {
                            final endpointId = await showEndpointPicker(
                              context: context,
                              endpoints: _apiConfig.enabledEndpoints,
                              selectedId: draft.singleEndpointId,
                            );
                            if (endpointId != null) {
                              apply(
                                draft.copyWith(singleEndpointId: endpointId),
                              );
                            }
                          }
                        : () {
                            openEditor = true;
                            Navigator.of(context).pop();
                          },
                  ),
                  if (draft.apiMode == TheaterApiMode.singleApi ||
                      draft.multiApiReplyMode !=
                          TheaterMultiApiReplyMode.turnBased) ...[
                    const SizedBox(height: 8),
                    TheaterReplySettings(
                      mainReplyCount: draft.mainReplyCount,
                      extraReplyMode: draft.extraReplyMode,
                      onMainReplyCountChanged: (value) =>
                          apply(draft.copyWith(mainReplyCount: value)),
                      onExtraReplyModeChanged: (value) =>
                          apply(draft.copyWith(extraReplyMode: value)),
                    ),
                  ],
                  _TheaterSettingsInfo(
                    icon: Icons.history_toggle_off,
                    title: _keepRoundCountLabel(draft.keepRoundCount),
                    subtitle: null,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: Text(_roundSheetLabel('短', 15)),
                        selected: draft.keepRoundCount == 15,
                        onSelected: (_) =>
                            apply(draft.copyWith(keepRoundCount: 15)),
                      ),
                      ChoiceChip(
                        label: Text(_roundSheetLabel('标准', 30)),
                        selected: draft.keepRoundCount == 30,
                        onSelected: (_) =>
                            apply(draft.copyWith(keepRoundCount: 30)),
                      ),
                      ChoiceChip(
                        label: Text(_roundSheetLabel('长', 50)),
                        selected: draft.keepRoundCount == 50,
                        onSelected: (_) =>
                            apply(draft.copyWith(keepRoundCount: 50)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SettingSlider(
                    label: '背景图透明度',
                    value: draft.backgroundImageOpacity,
                    min: 0,
                    max: 1,
                    divisions: 100,
                    display: '${(draft.backgroundImageOpacity * 100).round()}%',
                    onChanged: (value) =>
                        preview(draft.copyWith(backgroundImageOpacity: value)),
                    onChangeEnd: (value) =>
                        apply(draft.copyWith(backgroundImageOpacity: value)),
                    height: 26,
                    displayWidth: 52,
                  ),
                  SettingSlider(
                    label: '背景图模糊度',
                    value: draft.backgroundBlur,
                    min: 0,
                    max: 12,
                    divisions: 12,
                    display: draft.backgroundBlur.toStringAsFixed(0),
                    onChanged: (value) =>
                        preview(draft.copyWith(backgroundBlur: value)),
                    onChangeEnd: (value) =>
                        apply(draft.copyWith(backgroundBlur: value)),
                    height: 26,
                    displayWidth: 52,
                  ),
                  SettingSlider(
                    label: '文本框透明度',
                    value: draft.bubbleOpacity,
                    min: 0,
                    max: 1,
                    divisions: 100,
                    display: '${(draft.bubbleOpacity * 100).round()}%',
                    onChanged: (value) =>
                        preview(draft.copyWith(bubbleOpacity: value)),
                    onChangeEnd: (value) =>
                        apply(draft.copyWith(bubbleOpacity: value)),
                    height: 26,
                    displayWidth: 52,
                  ),
                  SettingSlider(
                    label: '输入框透明度',
                    value: draft.inputOpacity,
                    min: 0,
                    max: 1,
                    divisions: 100,
                    display: '${(draft.inputOpacity * 100).round()}%',
                    onChanged: (value) =>
                        preview(draft.copyWith(inputOpacity: value)),
                    onChangeEnd: (value) =>
                        apply(draft.copyWith(inputOpacity: value)),
                    height: 26,
                    displayWidth: 52,
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () {
                      openEditor = true;
                      Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.tune),
                    label: Text(context.t('编辑群聊')),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (!mounted) return;
    if (openEditor) {
      await _openFullSettings();
    }
  }

  Future<void> _openFullSettings() async {
    final session = await Navigator.of(context).push<TheaterSession>(
      MaterialPageRoute(
        builder: (_) => TheaterEditScreen(
          storage: widget.storage,
          aiService: widget.aiService,
          session: _session,
        ),
      ),
    );
    if (session == null || !mounted) return;
    setState(() => _session = session);
  }

  String _currentModelLabel() {
    if (_session.apiMode == TheaterApiMode.multiApi) {
      return context.t('多 API');
    }
    return _apiConfig.effectiveEndpoint(_session.singleEndpointId)?.name ??
        context.t('未配置 API');
  }

  String _chatCountLabel() {
    return context.isEnglish
        ? '${context.t('聊天条数')}: ${_messages.length}'
        : '${context.t('聊天条数')}：${_messages.length} 条';
  }

  String _keepRoundCountLabel(int count) {
    return context.isEnglish
        ? '${context.t('上下文保留轮数')}: $count'
        : '${context.t('上下文保留轮数')}：$count轮';
  }

  String _theaterSpeedHint() {
    if (_messages.length < 80) return context.t('速度判断：正常');
    if (_messages.length < 180) {
      return context.t('速度判断：聊天变长，模型可能会慢一点');
    }
    return context.t('速度判断：聊天很多，模型读取上下文可能明显变慢');
  }

  String _roundSheetLabel(String label, int count) {
    return context.isEnglish
        ? '${context.t(label)} $count'
        : '${context.t(label)} $count轮';
  }

  Future<void> _copy(TheaterMessage message) async {
    await Clipboard.setData(ClipboardData(text: message.content));
    if (!mounted) return;
    _showSnack('已复制消息');
  }

  void _showSnack(String text) {
    context.showSnack(text);
  }

  SystemUiOverlayStyle _overlayStyle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final hasBackground = _session.backgroundImage.trim().isNotEmpty;
    return _TheaterBackground(
      imagePath: _session.backgroundImage,
      region: _session.backgroundImageRegion,
      opacity: _session.backgroundImageOpacity,
      blur: _session.backgroundBlur,
      child: Scaffold(
        backgroundColor: hasBackground ? Colors.transparent : null,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          systemOverlayStyle: _overlayStyle(context),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_session.title),
              Text(
                _session.boundNovelTitle.isEmpty
                    ? '${context.t('我的身份')}：${_session.userParticipant?.name ?? context.t('我自己')}'
                    : '${_session.boundNovelTitle} · ${context.t('我的身份')}：${_session.userParticipant?.name ?? context.t('我自己')}',
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: context.t('群聊总结'),
              onPressed: _showSummaryDialog,
              icon: const Icon(Icons.summarize_outlined),
            ),
            IconButton(
              tooltip: context.t('清空群聊消息'),
              onPressed: _clearMessages,
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
            IconButton(
              tooltip: context.t('群聊设置'),
              onPressed: _openSettings,
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
        ),
        body: Column(
          children: [
            if (_isSummarizing) const LinearProgressIndicator(minHeight: 2),
            Expanded(child: _buildMessages()),
            _TheaterInputComposer(
              controller: _inputController,
              isGenerating: _isGenerating,
              hasBackground: hasBackground,
              inputOpacity: _session.inputOpacity,
              onRegenerate: _regenerateRound,
              onSend: _send,
              onStop: _stopGeneration,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessages() {
    if (_messages.isEmpty) {
      return Center(child: Text(context.t('当前还没有群聊消息。')));
    }
    final participants = {
      for (final item in _session.participants) item.id: item,
    };
    final showTyping =
        _isGenerating &&
        (_messages.isEmpty ||
            _messages.last.speakerType != TheaterSpeakerType.role);
    return AdaptivePage(
      child: ListView.builder(
        controller: _scrollController,
        reverse: true,
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 16),
        itemCount: _messages.length + (showTyping ? 1 : 0),
        itemBuilder: (context, index) {
          if (showTyping && index == 0) {
            return const _TheaterTypingBubble();
          }
          final messageIndex =
              _messages.length - 1 - (index - (showTyping ? 1 : 0));
          final message = _messages[messageIndex];
          final participant = participants[message.speakerId];
          final canControlRole =
              message.speakerType == TheaterSpeakerType.role &&
              participant != null &&
              !_isGenerating;
          final onMute = canControlRole
              ? () => _toggleParticipantMuted(participant)
              : null;
          final onSpeakAgain = canControlRole ? _continueTheater : null;
          return RepaintBoundary(
            child: _TheaterMessageBubble(
              message: message,
              participant: participant,
              bubbleOpacity: _session.bubbleOpacity,
              chatTextColor: widget.settings.chatTextColor,
              onCopy: () => _copy(message),
              onDelete: _isGenerating
                  ? null
                  : () => _deleteTheaterMessage(message.id),
              onMute: onMute,
              onSpeakAgain: onSpeakAgain,
              onRetry: message.isError ? () => _retry(message) : null,
            ),
          );
        },
      ),
    );
  }
}
