import '../models/browser_tab_model.dart';

class MediaSnifferService {
  static SniffedMediaType? classifyUrl(String rawUrl) {
    final lower = rawUrl.toLowerCase().split('?').first;

    if (lower.endsWith('.m3u8') || lower.contains('/hls/') || lower.contains('.m3u8')) {
      return SniffedMediaType.hlsStream;
    }
    if (lower.endsWith('.mpd') || lower.contains('/dash/')) {
      return SniffedMediaType.mpdStream;
    }
    if (lower.endsWith('.mp4')) {
      return SniffedMediaType.mp4Video;
    }
    if (lower.endsWith('.webm') || lower.endsWith('.mkv') || lower.endsWith('.ts') || lower.endsWith('.mov') || lower.endsWith('.avi')) {
      return SniffedMediaType.genericVideo;
    }
    if (lower.endsWith('.mp3') || lower.endsWith('.aac') || lower.endsWith('.m4a') || lower.endsWith('.wav')) {
      return SniffedMediaType.audio;
    }
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.png') || lower.endsWith('.webp') || lower.endsWith('.gif')) {
      return SniffedMediaType.image;
    }
    return null;
  }

  static SniffedMediaItem? createItemFromDetection({
    required String url,
    required String pageTitle,
    Map<String, String>? headers,
    String? explicitType,
  }) {
    // Ignore small thumbnails, ads, trackers, and favicons
    final lower = url.toLowerCase();
    if (lower.contains('favicon') || lower.contains('analytics') || lower.contains('tracker') || lower.contains('pixel')) {
      return null;
    }

    SniffedMediaType? type = classifyUrl(url);
    if (type == null && explicitType != null) {
      if (explicitType == 'video') {
        type = lower.contains('.m3u8') ? SniffedMediaType.hlsStream : SniffedMediaType.mp4Video;
      } else if (explicitType == 'image') {
        type = SniffedMediaType.image;
      }
    }

    if (type == null) return null;

    // Generate readable title
    String title = pageTitle;
    try {
      final uri = Uri.parse(url);
      final seg = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
      if (seg.isNotEmpty && seg.length < 50 && (seg.contains('.') || seg.length > 5)) {
        title = seg;
      }
    } catch (_) {}

    return SniffedMediaItem(
      id: '${url.hashCode}_${DateTime.now().millisecondsSinceEpoch}',
      url: url,
      type: type,
      title: title,
      headers: headers,
      detectedAt: DateTime.now(),
    );
  }
}
