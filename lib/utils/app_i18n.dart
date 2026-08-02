import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

const appLanguageSystem = 'system';
const appLanguageZh = 'zh';
const appLanguageEn = 'en';
const appSupportedLocales = [Locale('zh'), Locale('en')];
const appLocalizationsDelegates = GlobalMaterialLocalizations.delegates;

final _parsedFieldsPattern = RegExp(r'^已识别 (\d+) 个字段$');
final _importedCharacterPattern = RegExp(r'^已导入角色：(.+)$');
final _importedCharactersPattern = RegExp(r'^已导入 (\d+) 个角色$');
final _importResultPattern = RegExp(r'^已导入 (\d+) 个，失败 (\d+) 个$');
final _downloadHttpErrorPattern = RegExp(r'^下载失败：HTTP (\d+)。$');
final _deletedCharacterPattern = RegExp(r'^已删除角色：(.+)$');
final _exportedCharactersPattern = RegExp(r'^已导出到角色：(.+)$');
final _generatedCharactersPattern = RegExp(r'^已生成 (\d+) 个角色$');
final _resultPositionPattern = RegExp(r'^第 (\d+) / (\d+) 个结果$');
final _chatCountPattern = RegExp(r'^聊天条数：(\d+) 条$');
final _chapterCountPattern = RegExp(r'^目录 (\d+) 条$');
final _summarizingPattern = RegExp(r'^正在总结 (\d+) / (\d+)$');
final _startChapterRangePattern = RegExp(r'^起始章节必须在 1-(\d+) 之间$');
final _validRangePattern = RegExp(r'^请输入 1-(\d+) 之间的有效范围$');
final _configSavedPattern = RegExp(r'^(.+) 配置已保存$');
final _connectedPattern = RegExp(r'^(.+) 连接成功：(.+)$');
final _incompleteConfigPattern = RegExp(r'^(.+) 配置不完整，请先到设置里配置 API。$');
final _apiErrorPattern = RegExp(r'^API 返回错误 (\d+)：(.+)$');
final _novelRoleCountPattern = RegExp(r'^共 (\d+) 个角色$');
final _memoryContextLimitPattern = RegExp(r'^每次最多注入 (\d+) 个字符$');
final _savedMemoriesPattern = RegExp(r'^已保存 (\d+) 条记忆$');

const _dynamicPrefixes = {
  '设置文件异常': 'Settings file is invalid',
  'API 配置文件异常': 'API config file is invalid',
  '角色文件异常': 'Character file is invalid',
  '聊天记录文件异常': 'Chat file is invalid',
  '小说文件异常': 'Novel file is invalid',
  '小说正文不存在': 'Novel text does not exist',
  '小说聊天记录异常': 'Novel chat file is invalid',
  '总结文件异常': 'Summary file is invalid',
  '数据文件异常，无法解析 JSON': 'Data file is invalid JSON',
  '读取本地文件失败': 'Failed to read local file',
};

extension AppI18n on BuildContext {
  bool get isEnglish => Localizations.localeOf(this).languageCode == 'en';

  String t(String text) {
    if (!isEnglish) return text;
    return _dynamicEn(text) ?? _en[text] ?? text;
  }
}

String? _dynamicEn(String text) {
  Match? match;

  match = _parsedFieldsPattern.firstMatch(text);
  if (match != null) return 'Parsed ${match[1]} fields';

  match = _importedCharacterPattern.firstMatch(text);
  if (match != null) return 'Imported character: ${match[1]}';

  match = _importedCharactersPattern.firstMatch(text);
  if (match != null) return 'Imported ${match[1]} characters';

  match = _importResultPattern.firstMatch(text);
  if (match != null) {
    return 'Imported ${match[1]}, failed ${match[2]}';
  }

  match = _downloadHttpErrorPattern.firstMatch(text);
  if (match != null) return 'Download failed: HTTP ${match[1]}.';

  match = _deletedCharacterPattern.firstMatch(text);
  if (match != null) return 'Deleted role: ${match[1]}';

  match = _exportedCharactersPattern.firstMatch(text);
  if (match != null) return 'Exported to characters: ${match[1]}';

  match = _generatedCharactersPattern.firstMatch(text);
  if (match != null) return '${match[1]} roles generated';

  match = _resultPositionPattern.firstMatch(text);
  if (match != null) return 'Result ${match[1]} / ${match[2]}';

  match = _chatCountPattern.firstMatch(text);
  if (match != null) return '${match[1]} chat messages';

  match = _chapterCountPattern.firstMatch(text);
  if (match != null) return '${match[1]} chapters';

  match = _summarizingPattern.firstMatch(text);
  if (match != null) return 'Summarizing ${match[1]} / ${match[2]}';

  match = _startChapterRangePattern.firstMatch(text);
  if (match != null) return 'Start chapter must be between 1 and ${match[1]}';

  match = _validRangePattern.firstMatch(text);
  if (match != null) return 'Enter a valid range between 1 and ${match[1]}';

  match = _configSavedPattern.firstMatch(text);
  if (match != null) return '${match[1]} config saved';

  match = _connectedPattern.firstMatch(text);
  if (match != null) return '${match[1]} connected: ${match[2]}';

  match = _incompleteConfigPattern.firstMatch(text);
  if (match != null) {
    return '${match[1]} config is incomplete. Configure API first.';
  }

  match = _apiErrorPattern.firstMatch(text);
  if (match != null) return 'API returned error ${match[1]}: ${match[2]}';

  match = _novelRoleCountPattern.firstMatch(text);
  if (match != null) return '${match[1]} novel roles';

  match = _memoryContextLimitPattern.firstMatch(text);
  if (match != null) return 'Inject at most ${match[1]} characters each time';

  match = _savedMemoriesPattern.firstMatch(text);
  if (match != null) return 'Saved ${match[1]} memories';

  for (final entry in _dynamicPrefixes.entries) {
    final prefix = '${entry.key}：';
    if (text.startsWith(prefix)) {
      return '${entry.value}: ${text.substring(prefix.length)}';
    }
  }

  return null;
}

String languageName(BuildContext context, String code) {
  final en = context.isEnglish;
  return switch (code) {
    appLanguageEn => en ? 'English' : 'English',
    appLanguageZh => en ? 'Chinese' : '中文',
    _ => en ? 'Follow system' : '跟随系统',
  };
}

Locale? appLocaleFromCode(String code) {
  return switch (code) {
    appLanguageEn => const Locale('en'),
    appLanguageZh => const Locale('zh'),
    _ => null,
  };
}

const _en = {
  'Whisnya': 'Whisnya',
  '小说': 'Novels',
  '设置': 'Settings',
  '角色': 'Characters',
  '群聊': 'Theater',
  '网格': 'Grid',
  '列表': 'List',
  '导入 txt': 'Import txt',
  '还没有导入小说': 'No novels imported yet',
  '选择 TXT 编码': 'Choose TXT encoding',
  'TXT 编码识别失败，请手动选择编码重新导入。':
      'TXT encoding detection failed. Choose an encoding and import again.',
  '已取消导入。': 'Import canceled.',
  '阅读模式': 'Reading mode',
  '删除小说': 'Delete novel',
  '打开小说': 'Open novel',
  '隐藏书名': 'Hide title',
  '显示书名': 'Show title',
  '新建': 'New',
  '新建角色': 'New character',
  '导入': 'Import',
  '选择导入方式': 'Choose import method',
  '从文件导入角色卡': 'Import character card from file',
  '支持 JSON / ZIP / TXT / MD': 'Supports JSON / ZIP / TXT / MD',
  '导入 PNG 角色卡': 'Import PNG character card',
  '支持带内嵌角色数据的 PNG 图片': 'Supports PNG images with embedded character data',
  '从 URL 导入角色卡': 'Import character card from URL',
  '粘贴 JSON / PNG / ZIP / TXT / MD 文件直链':
      'Paste a direct JSON / PNG / ZIP / TXT / MD file link',
  '支持 Whisnya 角色包、酒馆 JSON/PNG 角色卡、TXT/MD 设定文本和文件直链。':
      'Supports Whisnya packages, Tavern JSON/PNG cards, TXT/MD character text, and direct file links.',
  '文件直链': 'File URL',
  '查看失败原因': 'View failure reasons',
  '批量导入角色卡': 'Batch import character cards',
  '支持 Whisnya 角色包和常见角色卡文件':
      'Supports Whisnya packages and common character card files',
  '还没有角色': 'No characters yet',
  '创建第一个角色': 'Create first character',
  '重新加载': 'Reload',
  '未填写简介': 'No description',
  '编辑角色': 'Edit character',
  '置顶角色': 'Pin',
  '取消置顶': 'Unpin',
  '隐藏设定': 'Hide details',
  '显示设定': 'Show details',
  '上锁': 'Lock',
  '解除上锁': 'Unlock',
  '删除角色': 'Delete character',
  '进入聊天': 'Open chat',
  '隐私密码': 'Privacy password',
  '取消': 'Cancel',
  '确认': 'OK',
  '删除': 'Delete',
  '保存': 'Save',
  '清空': 'Clear',
  '默认': 'Default',
  '应用': 'Apply',
  '继续': 'Continue',
  '关闭': 'Close',
  '完成': 'Done',
  '条': 'items',
  '轮': 'rounds',
  '密码不正确': 'Wrong password',
  '请先到设置里设置隐私密码': 'Set a privacy password in Settings first',
  '已置顶角色': 'Character pinned',
  '已取消置顶': 'Character unpinned',
  '已隐藏设定': 'Details hidden',
  '已显示设定': 'Details shown',
  '已上锁': 'Locked',
  '已解除上锁': 'Unlocked',
  '已删除角色': 'Character deleted',
  'API 设置': 'API settings',
  'API 配置': 'API configurations',
  '模型配置': 'Model configuration',
  '添加配置': 'Add configuration',
  '编辑配置': 'Edit configuration',
  '复制配置': 'Duplicate configuration',
  '删除 API 配置': 'Delete API configuration',
  '确定删除这个 API 配置吗？': 'Delete this API configuration?',
  '设为默认': 'Set as default',
  '启用配置': 'Enable configuration',
  '禁用配置': 'Disable configuration',
  '当前 API 配置已禁用。': 'This API configuration is disabled.',
  '请先添加 API 配置': 'Add an API configuration first',
  '请先到 API 设置添加配置。': 'Add an API configuration in API settings first.',
  '请先到 API 设置添加完整配置。':
      'Add a complete API configuration in API settings first.',
  '还没有 API 配置': 'No API configurations yet',
  '未配置 API': 'No API configured',
  '未填写模型': 'No model',
  '未填写 Base URL': 'No Base URL',
  '自动选择': 'Automatic',
  '手动填写': 'Enter manually',
  '正在获取模型…': 'Loading models…',
  '填写 URL 和 API Key 后自动获取模型':
      'Models load automatically after entering the URL and API key',
  '已启用': 'Enabled',
  '已禁用': 'Disabled',
  '配置已保存': 'Configuration saved',
  '配置已复制': 'Configuration duplicated',
  '配置已删除': 'Configuration deleted',
  '配置已启用': 'Configuration enabled',
  '配置已禁用': 'Configuration disabled',
  '已设为默认模型': 'Default model set',
  '模型、Base URL、API Key': 'Model, Base URL, API Key',
  'API 使用统计': 'API usage',
  '暂无使用统计': 'No usage records yet',
  '使用明细': 'Usage details',
  '请求次数': 'Requests',
  '总 Tokens': 'Total tokens',
  '提示 Tokens': 'Prompt tokens',
  '回复 Tokens': 'Completion tokens',
  '平均缓存命中率': 'Average cache hit rate',
  '不支持缓存统计': 'Cache statistics are not supported',
  '本轮更新总结': 'Summary updated this turn',
  '是': 'Yes',
  '否': 'No',
  '角色聊天': 'Character chat',
  '小说聊天': 'Novel chat',
  '小说聊天总结': 'Novel chat summary',
  '小说总结': 'Novel summary',
  '总结': 'Summary',
  '语言': 'Language',
  '主题': 'Theme',
  '主题设置': 'Theme settings',
  '与界面和颜色相关的一些设置': 'Interface and color settings',
  '主题模式': 'Theme',
  '跟随系统': 'Follow system',
  '白天': 'Light',
  '黑夜': 'Dark',
  '全局字体大小': 'Global font size',
  '颜色': 'Colors',
  '主界面字体颜色': 'Main text color',
  '聊天字体颜色': 'Chat text color',
  '背景': 'Background',
  '主页和设置背景': 'Home and settings background',
  '未设置': 'Not set',
  '已设置': 'Set',
  '界面背景透明度': 'Background transparency',
  '界面背景模糊度': 'Background blur',
  '底部导航栏透明度': 'Navigation bar transparency',
  '清空界面背景': 'Clear background',
  '只删除背景引用，不影响图片文件': 'Only clears the reference, not the image file',
  '隐私': 'Privacy',
  '数据': 'Data',
  '导入角色包': 'Import character package',
  '导出全部数据': 'Export all data',
  '导入全部数据': 'Import all data',
  '包含 API Key': 'Includes API Key',
  '默认不包含 API Key': 'API Key excluded by default',
  '会覆盖当前本地数据': 'Overwrites current local data',
  '导出角色包': 'Export character package',
  '导入角色设定': 'Import character card',
  '复制角色设定': 'Copy character card',
  '保存角色': 'Save character',
  '头像': 'Avatar',
  '聊天背景图': 'Chat background',
  '名称': 'Name',
  '简介': 'Description',
  '性格': 'Personality',
  '背景故事': 'Backstory',
  '说话风格': 'Speaking style',
  '开场白': 'Opening message',
  '补充设定': 'Extra prompt',
  '默认模型': 'Default model',
  '选择图片': 'Choose image',
  '裁剪': 'Crop',
  '裁剪头像': 'Crop avatar',
  '裁剪聊天背景': 'Crop chat background',
  '请输入角色名称': 'Enter a character name',
  '自动识别': 'Auto parse',
  '测试连接': 'Test connection',
  '测试': 'Test',
  '显示 API Key': 'Show API Key',
  '隐藏 API Key': 'Hide API Key',
  '保存文件': 'Save file',
  '保存角色包': 'Save character package',
  '搜索聊天': 'Search chat',
  '查看历史总结': 'View summary',
  '聊天设置': 'Chat settings',
  '当前还没有聊天记录。': 'No chat messages yet.',
  '结束并总结': 'End and summarize',
  '输入消息': 'Type a message',
  '发送': 'Send',
  '复制消息': 'Copy message',
  '生成中': 'Generating',
  '粘贴包含名称、简介、性格、说话风格等内容的角色卡':
      'Paste a character card with name, description, personality, speaking style, etc.',
  '未识别到明确字段': 'No clear fields found',
  '角色设定已复制': 'Character card copied',
  '角色包已导出': 'Character package exported',
  '没有拿到可读取的图片路径。': 'No readable image path was found.',
  '当前没有可裁剪的图片。': 'No image to crop.',
  '裁剪界面背景': 'Crop interface background',
  '这会覆盖当前 App 本地数据。建议先导出一份备份。':
      'This will overwrite current local data. Export a backup first.',
  '备份可能包含角色、聊天记录、小说原文、图片、设置和 API 配置，请不要公开上传。':
      'Backups may contain characters, chats, novel texts, images, settings, and API config. Do not upload them publicly.',
  '会包含角色、小说原文、小说聊天、聊天记录、总结、图片、设置和 API 配置。API Key 也会在备份里。':
      'Includes characters, novel texts, novel chats, chat history, summaries, images, settings, and API config. API keys are included.',
  '修改密码': 'Change password',
  '忘记密码': 'Forgot password',
  '删除密码': 'Delete password',
  '设置隐私密码': 'Set privacy password',
  '修改隐私密码': 'Change privacy password',
  '删除隐私密码': 'Delete privacy password',
  '当前密码': 'Current password',
  '新密码': 'New password',
  '确认新密码': 'Confirm new password',
  '恢复问题': 'Recovery question',
  '恢复答案': 'Recovery answer',
  '找回隐私密码': 'Recover privacy password',
  '重置密码': 'Reset password',
  '密码至少 4 位': 'Password must be at least 4 characters',
  '两次输入的密码不一致': 'Passwords do not match',
  '请填写恢复问题和答案': 'Fill in a recovery question and answer',
  '当前密码不正确': 'Current password is wrong',
  '恢复答案不正确': 'Recovery answer is wrong',
  '隐私密码已保存': 'Privacy password saved',
  '隐私密码已重置': 'Privacy password reset',
  '隐私密码已删除': 'Privacy password deleted',
  '没有设置恢复问题，无法找回密码。':
      'No recovery question is set, so the password cannot be recovered.',
  '已导入角色': 'Character imported',
  '设置文件异常': 'Settings file is invalid',
  'API 配置文件异常': 'API config file is invalid',
  '角色文件异常': 'Character file is invalid',
  '聊天记录文件异常': 'Chat file is invalid',
  '小说文件异常': 'Novel file is invalid',
  '未命名小说': 'Untitled novel',
  '小说正文不存在': 'Novel text does not exist',
  '小说聊天记录异常': 'Novel chat file is invalid',
  '总结文件异常': 'Summary file is invalid',
  '角色包缺少 character.json': 'Character package is missing character.json',
  '角色包 character.json 异常': 'Character package character.json is invalid',
  '未识别到有效角色卡字段。': 'No valid character card fields found.',
  '该 PNG 未检测到内嵌角色卡数据。':
      'No embedded character card data was found in this PNG.',
  'JPG 图片不能作为角色卡导入，请使用 JSON 或带内嵌角色数据的 PNG 角色卡。':
      'JPG images cannot be imported as character cards. Use JSON or a PNG card with embedded character data.',
  'ZIP 中未找到可识别的角色卡 JSON。':
      'No recognizable character card JSON was found in the ZIP.',
  '未识别到名称、简介、性格等角色字段。':
      'No character fields such as name, description, or personality were found.',
  'JSON 格式错误。': 'Invalid JSON.',
  '角色卡 JSON 过大。': 'Character card JSON is too large.',
  '文件过大，暂不支持导入。': 'The file is too large to import.',
  '当前仅支持角色卡文件直链，请复制 JSON/PNG/ZIP/TXT/MD 文件下载链接。':
      'Only direct character card file links are supported. Copy a JSON/PNG/ZIP/TXT/MD download link.',
  '该网页未找到可导入的角色卡或提示词内容。':
      'No importable character card or prompt content was found on this page.',
  '请输入有效 URL。': 'Enter a valid URL.',
  '当前仅支持 HTTP/HTTPS 文件直链。': 'Only HTTP/HTTPS direct file links are supported.',
  '下载超时，请稍后重试。': 'Download timed out. Try again later.',
  '无法读取文件。': 'Could not read the file.',
  '数据文件异常，无法解析 JSON': 'Data file is invalid JSON',
  '读取本地文件失败': 'Failed to read local file',
  'API 返回格式异常。': 'API response format is invalid.',
  'API 返回内容不是有效 JSON。': 'API response was not valid JSON.',
  'API 没有返回可用回复。': 'API returned no usable reply.',
  'Base URL 为空，请先配置。': 'Base URL is empty. Configure it first.',
  'Base URL 格式不正确。': 'Base URL format is invalid.',
  'API Key 为空，请先配置。': 'API Key is empty. Configure it first.',
  'Model 为空，请先配置。': 'Model is empty. Configure it first.',
  '无法读取图片文件。': 'Could not read the image file.',
  '重置': 'Reset',
  '完成裁剪': 'Finish crop',
  '使用图片': 'Use image',
  '当前没有可总结的聊天记录。': 'No chat messages to summarize.',
  '清空聊天': 'Clear chat',
  '确定清空当前角色的聊天记录吗？历史总结不会被删除。':
      'Clear this character\'s chat history? The saved summary will not be deleted.',
  '聊天记录已清空': 'Chat history cleared',
  '当前没有可搜索的聊天记录': 'No chat messages to search',
  '输入关键词开始搜索': 'Enter a keyword to search',
  '没有找到结果': 'No results found',
  '搜索聊天记录': 'Search chat history',
  '输入关键词': 'Enter keyword',
  '上一个': 'Previous',
  '下一个': 'Next',
  '搜索': 'Search',
  '历史总结': 'Chat summary',
  '暂无历史总结，请先生成历史总结。': 'No summary yet. Generate a chat summary first.',
  '可以直接填写历史总结': 'You can enter a summary directly',
  '删除历史总结': 'Delete summary',
  '确定删除当前角色的历史总结吗？': 'Delete this character\'s saved summary?',
  '历史总结已删除': 'Summary deleted',
  '总结内容不能为空，想删除请点删除历史总结':
      'Summary cannot be empty. Use Delete summary to remove it.',
  '保存历史总结': 'Save summary',
  '确定保存对历史总结的改动吗？': 'Save changes to the summary?',
  '历史总结已保存': 'Summary saved',
  '当前模型': 'Current model',
  '选择模型': 'Choose model',
  '删除消息': 'Delete message',
  '确定删除这条消息吗？': 'Delete this message?',
  '上下文模式': 'Context mode',
  '全部上下文': 'Full context',
  '总结 + 最近消息': 'Summary + recent',
  '自动总结阈值': 'Auto summary threshold',
  '暂无历史总结': 'No saved summary',
  '已有历史总结': 'Saved summary available',
  '建议先生成历史总结': 'Consider generating a chat summary first',
  '背景图透明度': 'Background image transparency',
  '背景图模糊度': 'Background image blur',
  '聊天气泡透明度': 'Chat bubble transparency',
  '输入框透明度': 'Input box transparency',
  '清空聊天记录': 'Clear chat history',
  '历史总结不会被删除': 'The saved summary will not be deleted',
  '速度判断：正常': 'Speed: normal',
  '速度判断：聊天变长，模型可能会慢一点':
      'Speed: the chat is getting long, so the model may slow down a little',
  '速度判断：聊天很多，模型读取上下文可能明显变慢':
      'Speed: lots of chat history, context reading may become noticeably slower',
  '已复制消息': 'Message copied',
  '重试上一条': 'Retry last message',
  '重试': 'Retry',
  '编辑并重发': 'Edit and resend',
  '停止生成': 'Stop generation',
  '已停止生成': 'Generation stopped',
  '没有可编辑的用户消息。': 'No user message to edit.',
  '已删除小说': 'Novel deleted',
  '准备总结小说': 'Preparing novel summary',
  '正在合并总结并生成角色': 'Merging summaries and generating roles',
  '小说总结完成': 'Novel summary complete',
  '低成本总结': 'Low-cost summary',
  '前 10 章 + 自选多个十章范围': 'First 10 chapters + custom ten-chapter ranges',
  '自选章节范围总结': 'Custom chapter range summary',
  '只总结一个连续章节范围': 'Summarize one continuous chapter range only',
  '全文总结': 'Full-text summary',
  '最完整，费用最高': 'Most complete, highest cost',
  '删除范围': 'Remove range',
  '添加范围': 'Add range',
  '开始总结': 'Start summary',
  '起始章节': 'Start chapter',
  '结束章节': 'End chapter',
  '请输入起始章节': 'Enter a start chapter',
  '还没有角色，请先总结小说。': 'No roles yet. Summarize the novel first.',
  '导出到角色': 'Export to characters',
  '导出': 'Export',
  '小说设置': 'Novel settings',
  '按章节阅读': 'Read by chapter',
  '小说正文为空': 'Novel text is empty',
  '目录': 'Table of contents',
  '阅读字体大小': 'Reading font size',
  '阅读行距': 'Reading line height',
  '总结小说并生成角色': 'Summarize novel and generate roles',
  '首次生成': 'First generation',
  '对话管理': 'Chat sessions',
  '新建对话': 'New chat',
  '对话标题': 'Chat title',
  '重命名对话': 'Rename chat',
  '进行中的对话': 'Active chats',
  '已归档': 'Archived',
  '消息数': 'Messages',
  '复制对话': 'Duplicate chat',
  '归档对话': 'Archive chat',
  '取消归档': 'Unarchive chat',
  '删除对话': 'Delete chat',
  '确定删除这个对话及其聊天记录吗？': 'Delete this chat and its history?',
  '确定清空当前对话的聊天记录吗？历史总结不会被删除。':
      'Clear this chat history? Its saved summary will not be deleted.',
  '切换候选回复': 'Switch reply variant',
  '切换此候选将删除它之后的消息，并可能清空历史总结，是否继续？':
      'Switching this variant will remove all following messages and may clear the summary. Continue?',
  '删除候选回复': 'Delete reply variant',
  '确定删除当前候选回复吗？': 'Delete the current reply variant?',
  '记忆与世界书': 'Memory and world book',
  '加入记忆': 'Add to memory',
  '记忆已保存': 'Memory saved',
  '新建记忆': 'New memory',
  '编辑记忆': 'Edit memory',
  '标题': 'Title',
  '内容': 'Content',
  '范围': 'Scope',
  '长期记忆': 'Long-term memory',
  '当前对话记忆': 'Current chat memory',
  '关键词': 'Keywords',
  '用逗号或换行分隔；留空则始终生效':
      'Separate with commas or new lines; leave empty to always apply',
  '使用逗号或换行分隔关键词': 'Separate keywords with commas or new lines',
  '优先级': 'Priority',
  '启用记忆': 'Enable memory',
  '禁用记忆': 'Disable memory',
  '请填写标题和内容': 'Enter a title and content',
  '关键词世界书': 'Keyword world book',
  '管理全局世界书和关键词词条': 'Manage global world books and keyword entries',
  '添加长期记忆': 'Add long-term memory',
  '添加当前对话记忆': 'Add current chat memory',
  '添加世界书': 'Add world book',
  '引用已有世界书': 'Reference existing world book',
  '新建世界书': 'Create world book',
  '取消引用': 'Remove reference',
  '添加词条': 'Add entry',
  '编辑世界书': 'Edit world book',
  '删除世界书': 'Delete world book',
  '确定删除这本世界书吗？': 'Delete this world book?',
  '角色引用数量': 'Roles referencing this book',
  '世界书名称': 'World book name',
  '启用世界书': 'Enable world book',
  '禁用世界书': 'Disable world book',
  '启用世界书词条': 'Enable world book entry',
  '禁用世界书词条': 'Disable world book entry',
  '这本世界书还没有关键词词条': 'This world book has no keyword entries yet',
  '至少填写一个关键词': 'Enter at least one keyword',
  '当前角色还没有长期记忆': 'This character has no long-term memories yet',
  '当前对话还没有记忆': 'This chat has no memories yet',
  '当前角色还没有引用世界书': 'This character does not reference any world books yet',
  '保存引用': 'Save references',
  '还没有世界书': 'No world books yet',
  '有效词条': 'active entries',
  '筛选': 'Filter',
  '还没有记忆': 'No memories yet',
  '始终生效': 'Always active',
  '删除记忆': 'Delete memory',
  '确定删除这条记忆吗？': 'Delete this memory?',
  'AI 提取记忆': 'Extract memories with AI',
  '审核提取记忆': 'Review extracted memories',
  '保存选中项': 'Save selected',
  '重新开始': 'Start over',
  '继续上次总结': 'Continue previous summary',
  '清理总结缓存': 'Clear summary cache',
  '未选择': 'Not selected',
  '查看小说设定档': 'View novel profile',
  '清除聊天背景': 'Clear chat background',
  '小说设定档': 'Novel profile',
  '上一章': 'Previous chapter',
  '下一章': 'Next chapter',
  '编辑目录': 'Edit catalog',
  '每行一个章节标题': 'One chapter title per line',
  '目录行数必须和当前章节数一致': 'Catalog line count must match the current chapter count',
  '阅读背景': 'Reading background',
  '纸白': 'Paper',
  '护眼': 'Green',
  '夜间': 'Night',
  '搜索正文': 'Search text',
  '清除': 'Clear',
  '没有找到匹配内容': 'No matching content',
  '书签': 'Bookmark',
  '阅读进度': 'Reading progress',
  '还没有群聊': 'No theater chats yet',
  '新建群聊': 'New theater chat',
  '群聊外观': 'Theater appearance',
  '群聊头像': 'Theater avatar',
  '群聊背景': 'Theater background',
  '裁剪群聊头像': 'Crop theater avatar',
  '裁剪群聊背景': 'Crop theater background',
  '群聊名称': 'Theater chat name',
  '绑定小说': 'Bound novel',
  '不绑定小说': 'No novel',
  '无': 'None',
  '参与角色': 'Participants',
  '生成模式': 'Generation mode',
  '最后消息': 'Last message',
  '重命名': 'Rename',
  '重命名群聊': 'Rename theater chat',
  '删除群聊': 'Delete theater chat',
  '编辑群聊': 'Edit theater chat',
  '群聊设置': 'Theater settings',
  '聊天条数': 'Chat messages',
  '添加参与角色': 'Add participants',
  '从角色库添加': 'From characters',
  '从绑定小说添加': 'From bound novel',
  '我的身份': 'My identity',
  '我自己': 'Myself',
  '我': 'Me',
  '导出聊天记录': 'Export chat history',
  '导出为 UTF-8 TXT': 'Export as UTF-8 TXT',
  '聊天记录已导出': 'Chat history exported',
  '当前没有可导出的聊天记录': 'No chat history to export',
  '保存聊天记录': 'Save chat history',
  'API 模式': 'API mode',
  '单 API': 'Single API',
  '多 API': 'Multi API',
  '随机顺序': 'Random order',
  '并行回复': 'Parallel replies',
  '轮流发言': 'Turn-taking',
  '主要回复人数': 'Main reply count',
  '1 人': '1 role',
  '2 人': '2 roles',
  '全部角色': 'All roles',
  '追加发言': 'Extra replies',
  '不追加': 'None',
  '随机追加 0～1 个角色': 'Randomly add 0-1 roles',
  '随机追加 0～2 个角色': 'Randomly add 0-2 roles',
  '禁言': 'Mute',
  '解除禁言': 'Unmute',
  '已禁言': 'Muted',
  '未禁言': 'Active',
  '允许发言': 'Allow speaking',
  '再说一句': 'Speak again',
  '让TA回复': 'Reply once',
  '只让当前角色回复一次': 'Only let this character reply once',
  '拖动调整发言顺序': 'Drag to change speaking order',
  '角色不存在或已被移除': 'The character no longer exists or was removed',
  '该角色已禁用': 'This character is disabled',
  '该角色已被禁言': 'This character is muted',
  '该角色已被禁言，请前往群聊设置取消禁言。':
      'This role is muted. Unmute it in theater settings first.',
  '角色按照顺序逐个回复，后一个角色可以看到前一个角色刚生成的内容。':
      'Characters reply in order, and each character can see the previous reply.',
  '多个角色同时生成，速度快，但无法读取本轮其他角色刚生成的内容。':
      'Characters generate in parallel for speed, but cannot see other replies from this round.',
  '角色按随机顺序逐个回复。': 'Characters reply one at a time in random order.',
  '多 API · 并行': 'Multi API · parallel',
  '多 API · 随机': 'Multi API · random',
  '上下文保留轮数': 'Context rounds',
  '短': 'Short',
  '标准': 'Standard',
  '长': 'Long',
  '自定义': 'Custom',
  '自定义轮数': 'Custom rounds',
  '自定义轮数必须在 5-100 之间': 'Custom rounds must be between 5 and 100',
  '文本框透明度': 'Message bubble transparency',
  '顶部状态栏透明度': 'Top bar transparency',
  '流式对话': 'Streaming replies',
  '边返回边显示': 'Show text as it arrives',
  '显示思考过程': 'Show thinking process',
  '把 reasoning_content 显示在回复里': 'Show reasoning_content in replies',
  '记忆上下文上限': 'Memory context limit',
  '连续气泡输出': 'Continuous bubble output',
  '上一个候选': 'Previous variant',
  '下一个候选': 'Next variant',
  '重新生成': 'Regenerate',
  '按非空行拆分角色回复': 'Split role replies by non-empty lines',
  '角色聊天总结': 'Character chat summary',
  '聊天总结': 'Chat summary',
  '配置角色聊天和群聊总结项目': 'Configure character and theater summary items',
  '使用自定义总结项目': 'Use custom summary items',
  '使用自定义总结项目，最多 20 个': 'Use custom summary items, up to 20',
  '使用默认总结结构': 'Use the default summary structure',
  '可编辑 1-20 个总结项目': 'Edit 1-20 summary items',
  '添加项目': 'Add item',
  '编辑项目': 'Edit item',
  '恢复默认': 'Restore defaults',
  '总结项目': 'Summary item',
  '最多 20 个总结项目': 'Up to 20 summary items',
  '至少保留一个总结项目': 'Keep at least one summary item',
  '创建群聊': 'Create theater chat',
  '请输入群聊名称': 'Enter a theater chat name',
  '至少选择 2 个参与角色': 'Choose at least 2 participants',
  '请先选择完整的 API 配置': 'Choose a complete API configuration',
  '请为每个 AI 角色选择 API 配置': 'Choose an API configuration for every AI role',
  '群聊文件异常': 'Theater chat file is invalid',
  '群聊消息文件异常': 'Theater message file is invalid',
  '群聊总结': 'Theater summary',
  '系统': 'System',
  '没有可自动回复的角色': 'No AI-controlled role can reply',
  '继续一轮': 'Continue one round',
  '模型仍然输出了多个角色，请重试或更换模型':
      'The model still returned multiple characters. Retry or change the model.',
  '请先输入第一句话': 'Enter the first message first',
  '模型没有按群聊格式输出，可重试':
      'The model did not follow the theater format. Please retry.',
  '生成失败，可重试': 'Generation failed. Retry available.',
  '生成失败，点击重试': 'Generation failed. Tap retry.',
  '清空群聊消息': 'Clear theater messages',
  '确定清空当前群聊消息吗？群聊总结也会清空。':
      'Clear this theater chat? The theater summary will also be cleared.',
  '当前还没有群聊消息。': 'No theater messages yet.',
  '批量导入': 'Batch import',
  '搜索角色': 'Search characters',
  '没有匹配的角色': 'No matching characters',
  '聊天气泡样式': 'Chat bubble style',
  '角色气泡': 'Character bubble',
  '我的气泡': 'My bubble',
  '气泡颜色': 'Bubble color',
  '文字颜色': 'Text color',
  '气泡透明度': 'Bubble transparency',
  '恢复当前默认': 'Restore this default',
  '恢复全部默认': 'Restore all defaults',
  '默认圆润': 'Rounded',
  '极简方角': 'Square',
  '胶囊气泡': 'Capsule',
  '玻璃磨砂': 'Glass',
  '纸张便签': 'Note',
  '漫画对白框': 'Comic',
  '像素复古': 'Pixel',
  '软糖气泡': 'Candy',
  '描边透明': 'Outline',
  '无气泡纯文字': 'Text only',
  '角色甲：我们继续吧。': 'Role A: Let us continue.',
  '角色乙：我也准备好了。': 'Role B: I am ready too.',
  '很高兴见到你。': 'Nice to meet you.',
  '好的，开始吧。': 'Okay, let us begin.',
  '列表卡片透明度': 'List card transparency',
  '小说角色': 'Novel roles',
  '管理小说角色': 'Manage novel roles',
  '创建小说群聊': 'Create novel theater chat',
  '导入全部小说角色并配置群聊': 'Import all novel roles and configure the theater chat',
  '小说群聊已创建': 'Novel theater chat created',
  '用户设定': 'User profile',
  '用户昵称': 'Nickname',
  '身份简介': 'Identity description',
  '说话方式': 'Speaking style',
  '更换头像': 'Change avatar',
  '清除头像': 'Clear avatar',
  '编辑我的身份': 'Edit my identity',
  '选择你在群聊中的身份': 'Choose who you are in this chat',
  '使用默认用户设定': 'Use default user profile',
  '扮演小说角色': 'Play a novel character',
  '自定义临时身份': 'Use a temporary identity',
  '至少添加一个 AI 角色': 'Add at least one AI role',
  '编辑': 'Edit',
  '聊天外观': 'Chat appearance',
  '请先到 API 设置添加配置': 'Add an API configuration in API settings first.',
  '预览': 'Preview',
  'QQ 私聊自动回复': 'QQ private chat auto-reply',
  'NapCat / OneBot 或通知监听': 'NapCat / OneBot or notification listener',
  '当前仅 Android 支持手机后台 QQ 接入':
      'Background QQ integration is currently available on Android only',
  '非官方接入风险': 'Unofficial integration risk',
  'NapCat 可能掉线、失效或触发账号风险；通知和无障碍依赖 QQ 当前格式。只使用不重要的 QQ 小号。':
      'NapCat may disconnect, stop working, or put the account at risk. Notification and accessibility modes depend on the current QQ layout. Use only a non-critical QQ account.',
  '总开关': 'Master switch',
  '仍需手动点击“启动”才会运行': 'You must still tap Start to run it',
  '通知监听': 'Notification listener',
  '状态': 'Status',
  '运行中': 'Running',
  '已停止': 'Stopped',
  '启动': 'Start',
  '暂停': 'Pause',
  '停止': 'Stop',
  '联系人绑定': 'Contact bindings',
  '强制白名单；每位联系人绑定一个角色和独立会话':
      'Strict allowlist; every contact uses one character and a dedicated session',
  '权限和隐私': 'Permissions and privacy',
  '电池优化设置': 'Battery optimization settings',
  'Termux 与 Whisnya 都建议关闭电池优化':
      'Disable battery optimization for both Termux and Whisnya',
  '诊断日志': 'Diagnostic log',
  '最多 200 条，不记录消息原文、回复原文、API Key 或 token':
      'Up to 200 entries; message text, reply text, API keys, and tokens are never logged',
  'NapCat / OneBot 配置': 'NapCat / OneBot settings',
  'Token（仅安全存储）': 'Token (secure storage only)',
  '自动重连': 'Auto reconnect',
  '保存配置': 'Save settings',
  'Termux 帮助': 'Termux help',
  'OneBot 配置已保存': 'OneBot settings saved',
  '远程明文连接风险': 'Remote plaintext connection risk',
  '远程 ws 会暴露 QQ 消息和 token。确认仍要允许吗？':
      'A remote ws connection exposes QQ messages and the token. Allow it anyway?',
  '我已了解并允许': 'I understand and allow it',
  '通知监听配置': 'Notification listener settings',
  '通知读取权限': 'Notification access',
  '应用通知权限': 'App notification permission',
  '已开启': 'Enabled',
  '未开启': 'Disabled',
  '捕获下一条 QQ 私聊通知': 'Capture the next QQ private notification',
  '进入联系人绑定后开始 60 秒捕获': 'Open contact bindings to start a 60-second capture',
  '快捷回复': 'Quick reply',
  '优先使用通知 RemoteInput，不打开 QQ':
      'Prefer notification RemoteInput without opening QQ',
  '无障碍兜底': 'Accessibility fallback',
  '只在快捷回复不存在或失败时使用': 'Used only when quick reply is unavailable or fails',
  '发送后返回 Whisnya': 'Return to Whisnya after sending',
  '仅无障碍兜底发送成功后生效':
      'Applies only after a successful accessibility fallback send',
  '发送失败时显示提示': 'Show a notice when sending fails',
  '无障碍服务': 'Accessibility service',
  'QQ 包名': 'QQ package name',
  'QQ 包名不能为空。': 'The QQ package name cannot be empty.',
  '发送按钮 ViewId（可选）': 'Send button ViewId (optional)',
  '仅在标题严格匹配后用于无障碍兜底':
      'Used by accessibility fallback only after an exact title match',
  '保存通知配置': 'Save notification settings',
  '通知配置已保存': 'Notification settings saved',
  '使用说明': 'Instructions',
  '回复设置': 'Reply settings',
  '连续消息合并窗口': 'Consecutive-message merge window',
  '回复延迟': 'Reply delay',
  '最大回复字符（100–8000）': 'Maximum reply characters (100–8000)',
  'OneBot 分片字符': 'OneBot chunk size',
  'AI 超时秒数（15–300）': 'AI timeout in seconds (15–300)',
  '保存回复设置': 'Save reply settings',
  '静默时段': 'Quiet hours',
  '支持跨午夜；命令仍可使用': 'May cross midnight; commands remain available',
  '静默开始': 'Quiet hours start',
  '静默结束': 'Quiet hours end',
  '开始与结束相同表示全天静默': 'Matching start and end times mean quiet all day',
  '无障碍权限披露': 'Accessibility permission disclosure',
  '通知权限披露': 'Notification access disclosure',
  '我已了解': 'I understand',
  '仅在 QQ 通知没有快捷回复时使用。Whisnya 会打开触发通知的 QQ 会话、核对标题、填写回复并点击一次发送。无法确认目标时不会发送。':
      'Used only when a QQ notification has no quick reply. Whisnya opens the originating QQ chat, verifies its title, fills the reply, and taps Send once. It never sends when the target cannot be verified.',
  'Whisnya 将读取 QQ 发出的消息通知，只处理你明确绑定的联系人。通知内容会保存到本地聊天记录，并发送给你配置的 AI API。':
      'Whisnya reads message notifications from QQ and processes only contacts you explicitly bind. Notification content is saved to local chat history and sent to your configured AI API.',
  'QQ 诊断日志': 'QQ diagnostic log',
  '已复制脱敏诊断': 'Redacted diagnostics copied',
  '暂无诊断记录': 'No diagnostic entries',
  '60 秒内没有捕获到有效 QQ 私聊通知。':
      'No valid QQ private notification was captured within 60 seconds.',
  '删除联系人绑定': 'Delete contact binding',
  '默认只删除绑定；QQ 对话和聊天记录可以保留。':
      'Only the binding is deleted by default; the QQ session and chat history can be kept.',
  '仅删除绑定': 'Delete binding only',
  '删除绑定和 QQ 会话': 'Delete binding and QQ session',
  '有效 60 秒；捕获到的通知不会触发回复':
      'Valid for 60 seconds; the captured notification will not trigger a reply',
  '还没有联系人绑定。陌生联系人会被静默忽略。':
      'No contact bindings yet. Unknown contacts are silently ignored.',
  '添加联系人绑定': 'Add contact binding',
  '编辑联系人绑定': 'Edit contact binding',
  '请先创建一个角色。': 'Create a character first.',
  '这个联系人已经绑定。': 'This contact is already bound.',
  '通知联系人 Key': 'Notification contact key',
  'QQ 号': 'QQ ID',
  '只能通过捕获 QQ 私聊通知生成':
      'Can only be created by capturing a QQ private notification',
  '始终按字符串保存': 'Always stored as a string',
  '显示名': 'Display name',
  '绑定角色': 'Bound character',
  '联系人标题别名': 'Contact title aliases',
  '每行一个；无障碍发送时只做精确匹配':
      'One per line; accessibility sending uses exact matches only',
  '启用这个联系人': 'Enable this contact',
  'QQ 通知监听说明': 'QQ notification listener guide',
  'Whisnya 只处理你通过通知捕获并明确绑定的 QQ 私聊联系人。':
      'Whisnya processes only QQ private contacts you explicitly bind through notification capture.',
  '回复优先使用通知自带的快捷回复，成功时不会打开 QQ。':
      'Replies prefer the notification quick-reply action and do not open QQ when successful.',
  '只有快捷回复不存在或失败，并且你明确开启无障碍兜底后，才会通过原通知打开对应会话。':
      'The originating chat is opened only when quick reply is unavailable or fails and you explicitly enable accessibility fallback.',
  '无障碍会精确核对联系人标题，使用 ACTION_SET_TEXT 填写并只点击一次发送；锁屏、标题不符或无法确认目标时绝不发送。':
      'Accessibility verifies the exact contact title, fills text with ACTION_SET_TEXT, and taps Send only once. It never sends while locked, on a title mismatch, or when the target is uncertain.',
  '通知内容会保存到本地聊天记录，并发送给你配置的 AI API。诊断日志不保存消息原文。':
      'Notification content is saved to local chat history and sent to your configured AI API. Diagnostic logs do not store message text.',
  'NapCat / Termux 帮助': 'NapCat / Termux guide',
  'NapCat 是非官方 QQ 接入，可能掉线、失效或触发账号风险。':
      'NapCat is an unofficial QQ integration and may disconnect, stop working, or put the account at risk.',
  '复制安装命令': 'Copy install command',
  '安装 Termux。': 'Install Termux.',
  '用下方命令安装 NapCat。': 'Install NapCat with the command below.',
  '登录一个不重要的 QQ 小号。': 'Sign in with a non-critical QQ account.',
  '在 WebUI 启用 OneBot 11 正向 WebSocket。':
      'Enable the OneBot 11 forward WebSocket in the WebUI.',
  '绑定 127.0.0.1，设置端口和随机 token；不要监听 0.0.0.0。':
      'Bind to 127.0.0.1, set a port and random token, and do not listen on 0.0.0.0.',
  '回到 Whisnya 测试连接。': 'Return to Whisnya and test the connection.',
  '添加白名单联系人并绑定角色。': 'Add allowlisted contacts and bind their characters.',
  '启动 QQ 自动回复。': 'Start QQ auto-reply.',
  '为 Termux 和 Whisnya 关闭电池优化。':
      'Disable battery optimization for Termux and Whisnya.',
  '手机重启后手动重新启动 Termux 和 Whisnya。':
      'After a phone restart, manually restart Termux and Whisnya.',
};
