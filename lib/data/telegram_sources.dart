import 'package:freebuff_core/services/telegram/telegram_video_item.dart';
import '../models/movie.dart';

class TelegramSources {
  static const String urlScheme = 'tg://';

  static String buildUrl(String localId) => '$urlScheme$localId';

  static List<StreamSource> toStreamSources(List<TelegramVideoItem> items) {
    return items
        .map(
          (i) => StreamSource(
            name: 'TG • ${i.title}',
            url: buildUrl(i.localId),
            quality: i.sizeLabel,
            qualityBadgeText: 'TG',
          ),
        )
        .toList();
  }

  static bool isTelegramUrl(String url) => url.startsWith(urlScheme);

  static String extractLocalId(String url) {
    if (!isTelegramUrl(url)) return '';
    return url.substring(urlScheme.length);
  }
}
