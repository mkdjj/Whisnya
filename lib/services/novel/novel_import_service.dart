import '../novel_parser.dart';

class NovelImportResult {
  const NovelImportResult({required this.text, required this.encoding});

  final String text;
  final String encoding;
}

class NovelImportService {
  const NovelImportService();

  NovelImportResult decode(List<int> bytes, {String? encoding}) {
    final candidates = encoding == null
        ? supportedNovelEncodings
        : [encoding.toLowerCase()];
    for (final candidate in candidates) {
      try {
        return NovelImportResult(
          text: decodeNovelBytes(bytes, encoding: candidate),
          encoding: candidate,
        );
      } on NovelDecodeException {
        continue;
      }
    }
    throw const NovelDecodeException('TXT 编码识别失败，请手动选择编码重新导入。');
  }
}
