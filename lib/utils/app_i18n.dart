import 'package:flutter/material.dart';

const appLanguageSystem = 'system';
const appLanguageZh = 'zh';
const appLanguageEn = 'en';

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
  '界面背景透明度': 'Background opacity',
  '界面背景模糊度': 'Background blur',
  '底部导航栏透明度': 'Navigation bar opacity',
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
  '上下文模式': 'Context mode',
  '全部上下文': 'Full context',
  '总结 + 最近消息': 'Summary + recent',
  '自动总结阈值': 'Auto summary threshold',
  '暂无历史总结': 'No saved summary',
  '已有历史总结': 'Saved summary available',
  '建议先生成历史总结': 'Consider generating a chat summary first',
  '背景图透明度': 'Background image opacity',
  '背景图模糊度': 'Background image blur',
  '聊天气泡透明度': 'Chat bubble opacity',
  '输入框透明度': 'Input box opacity',
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
  '选择 AI 扮演的角色': 'Choose the AI role',
  '选择你扮演的角色': 'Choose your role',
  '不选择固定角色': 'No fixed role',
  '聊天时自由扮演自己或临时角色': 'Chat as yourself or any temporary role',
  '导出到角色': 'Export to characters',
  '导出': 'Export',
  '小说设置': 'Novel settings',
  '总结和聊天模型': 'Summary and chat model',
  '按章节阅读': 'Read by chapter',
  '小说正文为空': 'Novel text is empty',
  '目录': 'Table of contents',
  '阅读字体大小': 'Reading font size',
  '阅读行距': 'Reading line height',
  '聊天模式': 'Chat mode',
  '需要先总结小说并选择角色': 'Summarize the novel and choose a role first',
  '在小说内聊天': 'Chat inside the novel',
  '总结小说并生成角色': 'Summarize novel and generate roles',
  '首次生成': 'First generation',
  '重新生成': 'Regenerate',
  '重新开始': 'Start over',
  '继续上次总结': 'Continue previous summary',
  '清理总结缓存': 'Clear summary cache',
  '选择 AI 角色': 'Choose AI role',
  '未选择': 'Not selected',
  '选择用户角色': 'Choose user role',
  '查看小说设定档': 'View novel profile',
  '小说聊天背景': 'Novel chat background',
  '聊天背景透明度': 'Chat background opacity',
  '聊天背景模糊度': 'Chat background blur',
  '清除聊天背景': 'Clear chat background',
  '清空小说聊天': 'Clear novel chat',
  '小说设定档': 'Novel profile',
  '确定清空这本小说里的聊天记录吗？小说正文和总结不会被删除。':
      'Clear this novel\'s chat history? The novel text and summary will not be deleted.',
  '小说聊天已清空': 'Novel chat cleared',
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
  '开始小说内聊天吧。': 'Start chatting inside the novel.',
  '小说聊天背景已设置': 'Novel chat background set',
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
  '文本框透明度': 'Message bubble opacity',
  '顶部状态栏透明度': 'Top bar opacity',
  '流式对话': 'Streaming replies',
  '边返回边显示': 'Show text as it arrives',
  '显示思考过程': 'Show thinking process',
  '把 reasoning_content 显示在回复里': 'Show reasoning_content in replies',
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
};
