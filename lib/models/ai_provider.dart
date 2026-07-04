enum AiProvider { grok, deepseek, gpt }

extension AiProviderX on AiProvider {
  String get id {
    switch (this) {
      case AiProvider.grok:
        return 'grok';
      case AiProvider.deepseek:
        return 'deepseek';
      case AiProvider.gpt:
        return 'gpt';
    }
  }

  String get label {
    switch (this) {
      case AiProvider.grok:
        return 'Grok';
      case AiProvider.deepseek:
        return 'DeepSeek';
      case AiProvider.gpt:
        return 'GPT';
    }
  }

  static AiProvider fromId(String? id) {
    switch (id) {
      case 'grok':
        return AiProvider.grok;
      case 'gpt':
        return AiProvider.gpt;
      case 'deepseek':
      default:
        return AiProvider.deepseek;
    }
  }
}
