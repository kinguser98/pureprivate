class TelegramVideoItem {
  final String localId;
  final int messageId;
  final int chatId;
  final String? fileName;
  final String? caption;
  final int? sizeBytes;
  final int? durationSeconds;
  final DateTime date;
  final String? thumbnailUrl;
  final String? directUrl;
  final String source;

  const TelegramVideoItem({
    required this.localId,
    required this.messageId,
    required this.chatId,
    required this.date,
    this.fileName,
    this.caption,
    this.sizeBytes,
    this.durationSeconds,
    this.thumbnailUrl,
    this.directUrl,
    this.source = 'telegram',
  });

  String get title {
    if (caption != null && caption!.trim().isNotEmpty) {
      return caption!.trim();
    }
    if (fileName != null && fileName!.trim().isNotEmpty) {
      return _stripFileExt(fileName!);
    }
    return 'Telegram message $messageId';
  }

  String get queryKey {
    final base = (caption != null && caption!.trim().isNotEmpty)
        ? caption!
        : (fileName ?? title);
    return base.toLowerCase();
  }

  String? get sizeLabel {
    if (sizeBytes == null) return null;
    const kb = 1024;
    const mb = kb * 1024;
    const gb = mb * 1024;
    if (sizeBytes! >= gb) {
      return '${(sizeBytes! / gb).toStringAsFixed(2)} GB';
    }
    if (sizeBytes! >= mb) {
      return '${(sizeBytes! / mb).toStringAsFixed(1)} MB';
    }
    if (sizeBytes! >= kb) {
      return '${(sizeBytes! / kb).toStringAsFixed(0)} KB';
    }
    return '$sizeBytes B';
  }

  String? get durationLabel {
    if (durationSeconds == null || durationSeconds! <= 0) return null;
    final h = durationSeconds! ~/ 3600;
    final m = (durationSeconds! % 3600) ~/ 60;
    final s = durationSeconds! % 60;
    if (h > 0) {
      return '${h}h ${m}m';
    }
    if (m > 0) {
      return '${m}m ${s.toString().padLeft(2, '0')}s';
    }
    return '${s}s';
  }

  static String _stripFileExt(String name) {
    final dot = name.lastIndexOf('.');
    if (dot > 0 && dot < name.length - 1) {
      return name.substring(0, dot);
    }
    return name;
  }
}
