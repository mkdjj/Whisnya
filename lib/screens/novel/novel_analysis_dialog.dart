part of 'novel_screens.dart';

class _NovelAiResult {
  const _NovelAiResult({required this.summary, required this.roles});

  final String summary;
  final List<NovelRoleCandidate> roles;
}
