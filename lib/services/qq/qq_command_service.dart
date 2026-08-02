import '../../models/app_character.dart';
import '../../models/qq_contact_binding.dart';
import '../../models/unified_qq_reply.dart';
import '../local_storage_service.dart';

class QqCommandService {
  const QqCommandService(this.storage);

  static const commands = <String>{'/帮助', '/当前角色', '/新对话', '/暂停', '/继续'};

  final LocalStorageService storage;

  static bool isCommand(String text) => commands.contains(text.trim());

  Future<UnifiedQqReply?> handle(String text, QqContactBinding binding) async {
    final command = text.trim();
    if (!isCommand(command)) return null;
    var liveBinding = binding;
    var reply = '';
    switch (command) {
      case '/帮助':
        reply = '可用命令：/帮助、/当前角色、/新对话、/暂停、/继续';
        break;
      case '/当前角色':
        final character = await _character(binding.characterId);
        reply = '当前角色：${character.name}';
        break;
      case '/新对话':
        var session = await storage.createChatSession(
          binding.characterId,
          title: 'QQ · ${binding.displayName}',
        );
        session = await storage.markOpeningMessageInitialized(
          sessionId: session.id,
          characterId: binding.characterId,
        );
        liveBinding = binding.copyWith(
          sessionId: session.id,
          updatedAt: DateTime.now(),
        );
        await storage.saveQqContactBinding(liveBinding);
        reply = '已创建新对话，旧对话仍保留。';
        break;
      case '/暂停':
        liveBinding = binding.copyWith(
          enabled: false,
          updatedAt: DateTime.now(),
        );
        await storage.saveQqContactBinding(liveBinding);
        reply = '已暂停这个联系人的自动回复。发送 /继续 可恢复。';
        break;
      case '/继续':
        liveBinding = binding.copyWith(
          enabled: true,
          updatedAt: DateTime.now(),
        );
        await storage.saveQqContactBinding(liveBinding);
        reply = '已继续这个联系人的自动回复。';
        break;
    }
    return UnifiedQqReply(
      externalUserId: liveBinding.externalUserId,
      bindingId: liveBinding.id,
      sessionId: liveBinding.sessionId,
      text: reply,
      createdAt: DateTime.now(),
    );
  }

  Future<AppCharacter> _character(String id) async {
    for (final character in await storage.loadCharacters()) {
      if (character.id == id) return character;
    }
    throw StateError('绑定角色不存在');
  }
}
