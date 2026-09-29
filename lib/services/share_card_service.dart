import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../models/memento.dart';

enum ShareCardTemplate { dialogue, note, dark }

class ShareCardOptions {
  const ShareCardOptions({
    this.template = ShareCardTemplate.dialogue,
    this.title,
    this.characterName,
    this.userName = '我',
    this.showAvatars = false,
    this.showTime = false,
    this.showInnerVoice = false,
    this.innerVoiceAllowed = false,
    this.hiddenEntries = const {},
    this.backgroundColor,
    this.backgroundPath,
    this.mediaDirectory,
  });
  final ShareCardTemplate template;
  final String? title, characterName, backgroundPath, mediaDirectory;
  final String userName;
  final bool showAvatars, showTime, showInnerVoice, innerVoiceAllowed;
  final Set<int> hiddenEntries;
  final Color? backgroundColor;
}

class ShareCardBlock {
  const ShareCardBlock({
    required this.entryIndex,
    required this.speaker,
    required this.text,
    required this.continued,
    this.time,
    this.avatarAssetId,
  });
  final int entryIndex;
  final String speaker, text;
  final bool continued;
  final DateTime? time;
  final String? avatarAssetId;
}

class ShareCardPage {
  ShareCardPage(List<ShareCardBlock> blocks)
    : blocks = List.unmodifiable(blocks);
  final List<ShareCardBlock> blocks;
}

const shareBodyStyle = TextStyle(
  fontSize: 16,
  height: 1.5,
  fontWeight: FontWeight.normal,
);
double _textHeight(String text, TextStyle style) {
  final p = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: TextScaler.noScaling,
  )..layout(maxWidth: 312);
  final h = p.height;
  p.dispose();
  return h;
}

class ShareCardPlan {
  ShareCardPlan._(
    this._snapshot,
    this.options,
    this.title,
    this.pages,
    this._hiddenEntries,
    this._includesInnerVoice,
  );
  final MementoSnapshot _snapshot;
  final ShareCardOptions options;
  final String title;
  final List<ShareCardPage> pages;
  final Set<int> _hiddenEntries;
  final bool _includesInnerVoice;

  /// Reuses the measured text chunks when only presentation metadata changes.
  ShareCardPlan withPresentation(
    MementoSnapshot snapshot,
    ShareCardOptions next,
  ) {
    final nextTitle = next.title ?? snapshot.title;
    final nextIncludesInnerVoice =
        next.showInnerVoice && next.innerVoiceAllowed;
    if (!identical(snapshot, _snapshot) ||
        nextTitle != title ||
        nextIncludesInnerVoice != _includesInnerVoice ||
        next.hiddenEntries.length != _hiddenEntries.length ||
        !_hiddenEntries.containsAll(next.hiddenEntries)) {
      return prepare(snapshot, next);
    }
    final blockMetadataChanged =
        next.userName != options.userName ||
        next.characterName != options.characterName ||
        next.showTime != options.showTime ||
        next.showAvatars != options.showAvatars;
    final nextPages = blockMetadataChanged
        ? List<ShareCardPage>.unmodifiable([
            for (final page in pages)
              ShareCardPage([
                for (final block in page.blocks)
                  ShareCardBlock(
                    entryIndex: block.entryIndex,
                    speaker: snapshot.entries[block.entryIndex].role == 'user'
                        ? next.userName
                        : (next.characterName ??
                              snapshot
                                  .entries[block.entryIndex]
                                  .speakerNameSnapshot),
                    text: block.text,
                    continued: block.continued,
                    time: next.showTime
                        ? snapshot.entries[block.entryIndex].time
                        : null,
                    avatarAssetId: next.showAvatars
                        ? snapshot.entries[block.entryIndex].avatarAssetId
                        : null,
                  ),
              ]),
          ])
        : pages;
    return ShareCardPlan._(
      snapshot,
      next,
      title,
      nextPages,
      _hiddenEntries,
      _includesInnerVoice,
    );
  }

  static ShareCardPlan prepare(
    MementoSnapshot snapshot,
    ShareCardOptions options,
  ) {
    final title = options.title ?? snapshot.title;
    if (title.characters.length > 80) throw ArgumentError('Title is too long');
    final header =
        _textHeight(
          title,
          const TextStyle(
            fontSize: 22,
            height: 1.3,
            fontWeight: FontWeight.bold,
          ),
        ) +
        76;
    final capacity = 1280 - header - 32;
    final pages = <ShareCardPage>[];
    var blocks = <ShareCardBlock>[];
    var used = 0.0;
    void finish() {
      if (blocks.isNotEmpty) {
        pages.add(ShareCardPage(blocks));
        blocks = [];
        used = 0;
      }
      if (pages.length >= 12) throw StateError('超过 12 页，请减少选择内容');
    }

    for (var i = 0; i < snapshot.entries.length; i++) {
      if (options.hiddenEntries.contains(i)) continue;
      final e = snapshot.entries[i];
      final text =
          e.contentSnapshot +
          (options.showInnerVoice &&
                  options.innerVoiceAllowed &&
                  e.innerVoiceSnapshot.isNotEmpty
              ? '\n\n${e.innerVoiceSnapshot}'
              : '');
      final chars = text.characters.toList();
      var offset = 0;
      var continuation = false;
      while (offset < chars.length) {
        final available = capacity - used - 84;
        if (available < 28) {
          finish();
          continue;
        }
        var low = 1, high = chars.length - offset, best = 0;
        while (low <= high) {
          final mid = (low + high) ~/ 2;
          final h = _textHeight(
            chars.sublist(offset, offset + mid).join(),
            shareBodyStyle,
          );
          if (h <= available) {
            best = mid;
            low = mid + 1;
          } else {
            high = mid - 1;
          }
        }
        if (best == 0) {
          finish();
          continue;
        }
        final chunk = chars.sublist(offset, offset + best).join();
        blocks.add(
          ShareCardBlock(
            entryIndex: i,
            speaker: e.role == 'user'
                ? options.userName
                : (options.characterName ?? e.speakerNameSnapshot),
            text: chunk,
            continued: continuation,
            time: options.showTime ? e.time : null,
            avatarAssetId: options.showAvatars ? e.avatarAssetId : null,
          ),
        );
        used += _textHeight(chunk, shareBodyStyle) + 84;
        offset += best;
        continuation = true;
        if (offset < chars.length) finish();
      }
    }
    if (blocks.isNotEmpty) pages.add(ShareCardPage(blocks));
    if (pages.isEmpty) throw StateError('请选择至少一条非空消息');
    if (pages.length > 12) throw StateError('超过 12 页，请减少选择内容');
    return ShareCardPlan._(
      snapshot,
      options,
      title,
      List.unmodifiable(pages),
      Set.unmodifiable(options.hiddenEntries),
      options.showInnerVoice && options.innerVoiceAllowed,
    );
  }
}

class ShareCardPageView extends StatelessWidget {
  const ShareCardPageView({super.key, required this.plan, required this.page});
  final ShareCardPlan plan;
  final int page;
  @override
  Widget build(BuildContext context) {
    final o = plan.options;
    final dark = o.template == ShareCardTemplate.dark;
    final color = dark ? Colors.white : const Color(0xff242424);
    return Center(
      child: SizedBox(
        width: 360,
        child: MediaQuery.withNoTextScaling(
          child: DefaultTextStyle(
            style: shareBodyStyle.copyWith(color: color),
            child: Container(
              decoration: BoxDecoration(
                color:
                    o.backgroundColor ??
                    (dark
                        ? const Color(0xff20232a)
                        : o.template == ShareCardTemplate.note
                        ? const Color(0xfffff5d6)
                        : Colors.white),
                image: o.backgroundPath == null
                    ? null
                    : DecorationImage(
                        image: ResizeImage(
                          FileImage(File(o.backgroundPath!)),
                          width: 1080,
                        ),
                        fit: BoxFit.cover,
                        opacity: 0.22,
                      ),
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    plan.title,
                    style: TextStyle(
                      fontSize: 22,
                      height: 1.3,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 20),
                  for (final b in plan.pages[page].blocks) ...[
                    Row(
                      children: [
                        if (b.avatarAssetId != null &&
                            o.mediaDirectory != null) ...[
                          Image.file(
                            File('${o.mediaDirectory}/${b.avatarAssetId}'),
                            width: 24,
                            height: 24,
                            cacheWidth: 72,
                            errorBuilder: (_, _, _) =>
                                const Icon(Icons.person, size: 24),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(
                            '${b.speaker}${b.continued ? ' · 续' : ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              height: 1.3,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (b.time != null)
                      Text(
                        b.time!.toLocal().toString(),
                        style: const TextStyle(fontSize: 10, height: 1.3),
                      ),
                    const SizedBox(height: 8),
                    Text(b.text, style: shareBodyStyle.copyWith(color: color)),
                    const SizedBox(height: 24),
                  ],
                  Text(
                    '${page + 1} / ${plan.pages.length}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 10),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<Uint8List> renderShareCardPage(GlobalKey key) async {
  final boundary =
      key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  if (boundary == null || boundary.debugNeedsPaint) {
    throw StateError('Preview not ready');
  }
  final image = await boundary.toImage(pixelRatio: 3);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) throw StateError('PNG encoding failed');
    return bytes.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

enum ShareExportStatus { saved, partiallySaved, cancelled, failed }

class ShareExportResult {
  ShareExportResult(this.status, List<String> paths, {this.error})
    : paths = List.unmodifiable(paths);
  final ShareExportStatus status;
  final List<String> paths;
  final Object? error;
}

Future<ShareExportResult> saveSharePages({
  required int pageCount,
  required Future<Uint8List> Function(int page) render,
  required Future<String?> Function(int page, Uint8List bytes) save,
}) async {
  final paths = <String>[];
  try {
    for (var i = 0; i < pageCount; i++) {
      final bytes = await render(i);
      final path = await save(i, bytes);
      if (path == null) {
        return ShareExportResult(
          paths.isEmpty
              ? ShareExportStatus.cancelled
              : ShareExportStatus.partiallySaved,
          paths,
        );
      }
      paths.add(path);
    }
    return ShareExportResult(ShareExportStatus.saved, paths);
  } catch (e) {
    return ShareExportResult(
      paths.isEmpty
          ? ShareExportStatus.failed
          : ShareExportStatus.partiallySaved,
      paths,
      error: e,
    );
  }
}
