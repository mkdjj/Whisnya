import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/chat_bubble_preset.dart';
import 'package:whisnya/models/chat_bubble_theme.dart';
import 'package:whisnya/services/local_storage_service.dart';

void main() {
  test('stores presets in their own json file', () async {
    final directory = await Directory.systemTemp.createTemp('bubble-presets-');
    addTearDown(() => directory.delete(recursive: true));
    final storage = LocalStorageService(appDataDirectory: directory);
    final preset = ChatBubblePreset(
      id: 'p',
      name: '预设',
      appearance: const ChatBubbleAppearance(opacity: 0.4),
    );

    await storage.saveChatBubblePresets(
      ChatBubblePresetSettings(presets: [preset]),
    );

    expect((await storage.loadChatBubblePresets()).presets.single.id, 'p');
    expect(
      await File(
        '${directory.path}${Platform.pathSeparator}chat_bubble_presets.json',
      ).exists(),
      isTrue,
    );
  });

  test('legacy bubble migration is stable and idempotent', () async {
    final directory = await Directory.systemTemp.createTemp('bubble-legacy-');
    addTearDown(() => directory.delete(recursive: true));
    await directory.create(recursive: true);
    await File(
      '${directory.path}${Platform.pathSeparator}characters.json',
    ).writeAsString(
      jsonEncode([
        {
          'id': 'c',
          'name': '角色',
          'bubbleTheme': {
            'role': {'opacity': 0.3},
            'user': {'opacity': 0.6},
          },
        },
      ]),
    );
    await File(
      '${directory.path}${Platform.pathSeparator}theater_sessions.json',
    ).writeAsString(
      jsonEncode([
        {
          'id': 't',
          'title': '群聊',
          'bubbleTheme': {
            'role': {'opacity': 0.4},
            'user': {'opacity': 0.7},
          },
        },
      ]),
    );
    final storage = LocalStorageService(appDataDirectory: directory);

    await storage.ensureReady();
    await storage.ensureReady();

    final settings = await storage.loadChatBubblePresets();
    expect(settings.presets.map((preset) => preset.id).toSet(), {
      'character_legacy_bubble_c_role',
      'character_legacy_bubble_c_user',
      'theater_legacy_bubble_t_role',
      'theater_legacy_bubble_t_user',
    });
    final characters =
        jsonDecode(
              await File(
                '${directory.path}${Platform.pathSeparator}characters.json',
              ).readAsString(),
            )
            as List<dynamic>;
    final theaters =
        jsonDecode(
              await File(
                '${directory.path}${Platform.pathSeparator}theater_sessions.json',
              ).readAsString(),
            )
            as List<dynamic>;
    expect(
      (characters.single as Map<String, dynamic>)['roleBubblePresetId'],
      'character_legacy_bubble_c_role',
    );
    expect(
      (theaters.single as Map<String, dynamic>)['userBubblePresetId'],
      'theater_legacy_bubble_t_user',
    );
  });

  test('restore path repairs windows and android app data roots', () {
    expect(
      restoreAppDataPath(
        r'C:\Users\me\Documents\app_data\media\bubble_skins\skin.png',
        '/data/user/0/app/app_flutter/app_data',
      ),
      '/data/user/0/app/app_flutter/app_data${Platform.pathSeparator}media'
      '${Platform.pathSeparator}bubble_skins${Platform.pathSeparator}skin.png',
    );
    expect(restoreAppDataPath('', r'C:\new\app_data'), '');
  });
}
