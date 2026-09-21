import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/api_config.dart';
import 'package:whisnya/models/app_character.dart';
import 'package:whisnya/models/user_profile.dart';
import 'package:whisnya/services/auto_story/auto_story_creation.dart';

void main() {
  test('creation freezes actors and permits the same endpoint for both', () {
    final character = AppCharacter.fromJson({
      'id': 'source',
      'name': 'Same',
      'description': 'private A',
      'isLocked': true,
    });
    const user = UserProfile(name: 'Same', description: 'private B');
    final endpoint = AiEndpointConfig(
      id: 'api',
      name: 'API',
      apiKey: 'SECRET KEY',
      baseUrl: 'https://example.invalid/v1',
      model: 'model',
      enabled: true,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    final story = buildAutoStoryDraft(
      id: 'story',
      character: character,
      user: user,
      publicA: 'public A',
      publicB: 'public B',
      opening: 'Rain',
      targetEnding: 'Friends',
      endpointA: endpoint,
      endpointB: endpoint,
      plannedRounds: 30,
    );
    expect(story.actors.map((a) => a.actorId), ['A', 'B']);
    expect(story.actors.map((a) => a.endpointId), ['api', 'api']);
    expect(story.config.title, 'Same · Same · 故事演绎');
    expect(story.config.maxRequests, 82);
    expect(story.privacyRequired, isTrue);
    expect(story.actors[1].persona, contains('private B'));
    expect(user.description, 'private B');
    expect(story.toJson().toString(), isNot(contains('SECRET KEY')));
    expect(story.turns, isEmpty);
    expect(story.plan, isEmpty);
  });
}
