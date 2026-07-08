import '../models/app_character.dart';

class ParsedRoleFields {
  const ParsedRoleFields({
    this.name = '',
    this.description = '',
    this.personality = '',
    this.background = '',
    this.speakingStyle = '',
    this.openingMessage = '',
    this.extraPrompt = '',
  });

  final String name;
  final String description;
  final String personality;
  final String background;
  final String speakingStyle;
  final String openingMessage;
  final String extraPrompt;

  int get filledCount {
    return [
      name,
      description,
      personality,
      background,
      speakingStyle,
      openingMessage,
      extraPrompt,
    ].where((value) => value.trim().isNotEmpty).length;
  }
}

class RoleImportParser {
  const RoleImportParser._();

  static ParsedRoleFields parse(String source) {
    final buckets = <String, List<String>>{
      for (final field in _fieldOrder) field: <String>[],
      _ignoredField: <String>[],
    };
    String? currentField;
    for (final rawLine in source.replaceAll('\r\n', '\n').split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        continue;
      }

      final parsed = _parseHeadingLine(line);
      if (parsed != null) {
        currentField = parsed.field;
        if (parsed.value.isNotEmpty) {
          buckets[currentField]!.add(parsed.value);
        }
        continue;
      }

      if (currentField != null) {
        buckets[currentField]!.add(line);
      }
    }

    return ParsedRoleFields(
      name: _join(buckets['name']!),
      description: _join(buckets['description']!),
      personality: _join(buckets['personality']!),
      background: _join(buckets['background']!),
      speakingStyle: _join(buckets['speakingStyle']!),
      openingMessage: _join(buckets['openingMessage']!),
      extraPrompt: _join(buckets['extraPrompt']!),
    );
  }

  static ParsedRoleFields parseJson(Map<String, dynamic> json) {
    final data = _stringKeyMap(json['data']);

    String read(List<String> keys) {
      for (final source in [data, json]) {
        for (final key in keys) {
          final value = _stringValue(source[key]);
          if (value.isNotEmpty) return value;
        }
      }
      return '';
    }

    final extraParts = [
      read(['mes_example', 'example_dialogue']),
      read(['system_prompt', 'creator_notes', 'post_history_instructions']),
      _tagsValue(data['tags'] ?? json['tags']),
    ].where((value) => value.isNotEmpty);

    return ParsedRoleFields(
      name: read(['name', 'char_name', 'character_name']),
      description: read(['description', 'desc']),
      personality: read(['personality']),
      background: read(['scenario', 'background', 'world_scenario']),
      openingMessage: read(['first_mes', 'greeting', 'opening_message']),
      extraPrompt: extraParts.join('\n\n'),
    );
  }

  static String formatCharacter(AppCharacter character) {
    return '''
名称：${character.name}

简介：${character.description}

性格：${character.personality}

背景故事：${character.background}

说话风格：${character.speakingStyle}

开场白：${character.openingMessage}

补充设定：${character.extraPrompt}
'''
        .trim();
  }

  static _ParsedHeading? _parseHeadingLine(String line) {
    final normalized = line
        .replaceFirst(RegExp(r'^[#>\-\*\s]+'), '')
        .replaceAll(RegExp(r'^[【\[\(（]'), '')
        .trim();

    final match = RegExp(
      r'^([^】\]\)）：:]{1,20})[】\]\)）\s]*[：:]\s*(.*)$',
    ).firstMatch(normalized);
    if (match != null) {
      final field = _fieldForLabel(match.group(1)!);
      if (field != null) {
        return _ParsedHeading(field, match.group(2)?.trim() ?? '');
      }
    }

    final heading = RegExp(
      r'^([^】\]\)）]{1,20})[】\]\)）]$',
    ).firstMatch(normalized);
    if (heading != null) {
      final field = _fieldForLabel(heading.group(1)!);
      if (field != null) {
        return _ParsedHeading(field, '');
      }
    }

    final directField = _fieldForLabel(normalized);
    if (directField != null) {
      return _ParsedHeading(directField, '');
    }

    return null;
  }

  static String? _fieldForLabel(String label) {
    final key = label
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll('：', '')
        .replaceAll(':', '');

    for (final entry in _labels.entries) {
      if (entry.value.any((candidate) => candidate == key)) {
        return entry.key;
      }
    }
    return null;
  }

  static String _join(List<String> lines) {
    return lines
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .join('\n');
  }

  static Map<String, dynamic> _stringKeyMap(Object? value) {
    if (value is Map) {
      return {
        for (final entry in value.entries)
          if (entry.key != null) entry.key.toString(): entry.value,
      };
    }
    return const {};
  }

  static String _stringValue(Object? value) {
    if (value == null) return '';
    if (value is String) return value.trim();
    if (value is List) {
      return value
          .map(_stringValue)
          .where((item) => item.isNotEmpty)
          .join('\n');
    }
    return value.toString().trim();
  }

  static String _tagsValue(Object? value) {
    final text = _stringValue(value);
    return text.isEmpty ? '' : '标签：$text';
  }

  static const _fieldOrder = [
    'name',
    'description',
    'personality',
    'background',
    'speakingStyle',
    'openingMessage',
    'extraPrompt',
  ];

  static const _ignoredField = '_ignored';

  static const _labels = <String, List<String>>{
    'name': ['名称', '名字', '角色名', '角色名称', 'name', 'charname'],
    'description': ['简介', '角色简介', '描述', '介绍', 'description', 'desc'],
    'personality': ['性格', '性格设定', '人设', '人格', 'personality'],
    'background': ['背景', '背景故事', '经历', '世界观', 'background', 'scenario'],
    'speakingStyle': [
      '说话风格',
      '说话方式',
      '语言风格',
      '语气',
      '口吻',
      '口癖',
      'speakingstyle',
    ],
    _ignoredField: ['关系', '与用户的关系', '用户关系', 'relationship'],
    'openingMessage': [
      '开场白',
      '开场',
      '初始消息',
      '第一句话',
      'openingmessage',
      'firstmes',
      'greeting',
    ],
    'extraPrompt': [
      '补充设定',
      '额外设定',
      '其他设定',
      '注意事项',
      'extraprompt',
      'systemprompt',
      'creatornotes',
    ],
  };
}

class _ParsedHeading {
  const _ParsedHeading(this.field, this.value);

  final String field;
  final String value;
}
