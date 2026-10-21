import 'dart:io';

import 'package:flutter/material.dart';

import '../utils/app_i18n.dart';

Future<({String text, List<String> imagePaths})?> editChatMessage({
  required BuildContext context,
  required String text,
  required List<String> imagePaths,
  required bool hasFollowingMessages,
}) {
  var draft = text;
  final images = [...imagePaths];
  return showDialog<({String text, List<String> imagePaths})>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, update) => AlertDialog(
        title: Text(context.t('编辑并重发')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasFollowingMessages)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text('重发会删除这条消息之后的消息，并重新生成回复。'),
                ),
              ChatImages(
                paths: images,
                onRemove: (path) => update(() => images.remove(path)),
              ),
              TextFormField(
                initialValue: text,
                minLines: 3,
                maxLines: 8,
                autofocus: true,
                decoration: InputDecoration(labelText: context.t('输入消息')),
                onChanged: (value) => update(() => draft = value),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.t('取消')),
          ),
          FilledButton(
            onPressed: draft.trim().isEmpty && images.isEmpty
                ? null
                : () => Navigator.pop(context, (
                    text: draft.trim(),
                    imagePaths: images,
                  )),
            child: Text(context.t('编辑并重发')),
          ),
        ],
      ),
    ),
  );
}

class ChatImages extends StatelessWidget {
  const ChatImages({required this.paths, this.onRemove, super.key});

  final List<String> paths;
  final ValueChanged<String>? onRemove;

  @override
  Widget build(BuildContext context) {
    if (paths.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final path in paths)
            Stack(
              children: [
                InkWell(
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (context) => Dialog(
                      child: Stack(
                        children: [
                          InteractiveViewer(
                            child: Image.file(
                              File(path),
                              cacheWidth: 1600,
                              errorBuilder: (_, _, _) =>
                                  const Center(child: Icon(Icons.broken_image)),
                            ),
                          ),
                          Positioned(
                            top: 0,
                            right: 0,
                            child: IconButton.filledTonal(
                              tooltip: context.t('关闭'),
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(path),
                      width: onRemove == null ? 128 : 56,
                      height: onRemove == null ? 128 : 56,
                      cacheWidth: onRemove == null ? 384 : 168,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => SizedBox.square(
                        dimension: onRemove == null ? 128 : 56,
                        child: const Icon(Icons.broken_image_outlined),
                      ),
                    ),
                  ),
                ),
                if (onRemove != null)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: SizedBox.square(
                      dimension: 26,
                      child: IconButton.filledTonal(
                        tooltip: context.t('移除图片'),
                        padding: EdgeInsets.zero,
                        iconSize: 16,
                        onPressed: () => onRemove!(path),
                        icon: const Icon(Icons.close),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
