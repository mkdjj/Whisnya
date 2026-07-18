import 'package:flutter/material.dart';

import '../../utils/app_i18n.dart';

enum NovelTheaterIdentityChoice { defaultProfile, novelRole, temporary }

Future<NovelTheaterIdentityChoice?> showNovelTheaterIdentityPicker(
  BuildContext context,
) {
  return showDialog<NovelTheaterIdentityChoice>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(context.t('选择你在群聊中的身份')),
      children: [
        for (final choice in NovelTheaterIdentityChoice.values)
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(choice),
            child: ListTile(
              leading: Icon(switch (choice) {
                NovelTheaterIdentityChoice.defaultProfile =>
                  Icons.person_outline,
                NovelTheaterIdentityChoice.novelRole => Icons.auto_stories,
                NovelTheaterIdentityChoice.temporary => Icons.edit_outlined,
              }),
              title: Text(
                context.t(switch (choice) {
                  NovelTheaterIdentityChoice.defaultProfile => '使用默认用户设定',
                  NovelTheaterIdentityChoice.novelRole => '扮演小说角色',
                  NovelTheaterIdentityChoice.temporary => '自定义临时身份',
                }),
              ),
            ),
          ),
      ],
    ),
  );
}
