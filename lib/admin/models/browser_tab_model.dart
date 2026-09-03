import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class BrowserTab {
  final String id;
  String url;
  String title;
  String? faviconUrl;
  bool isLoading;
  double progress;
  bool canGoBack;
  bool canGoForward;
  bool isDesktopMode;
  bool adBlockEnabled;
  InAppWebViewController? webViewController;
  List<SniffedMediaItem> sniffedMedia;

  BrowserTab({
    required this.id,
    this.url = 'https://www.google.com',
    this.title = 'New Tab',
    this.faviconUrl,
    this.isLoading = false,
    this.progress = 0.0,
    this.canGoBack = false,
    this.canGoForward = false,
    this.isDesktopMode = false,
    this.adBlockEnabled = true,
    this.webViewController,
    List<SniffedMediaItem>? sniffedMedia,
  }) : sniffedMedia = sniffedMedia ?? [];
}

enum SniffedMediaType {
  hlsStream, // .m3u8
  mpdStream, // .mpd / dash
  mp4Video,  // .mp4
  genericVideo, // .webm, .mkv, .ts, etc.
  audio,
  image,
}

class SniffedMediaItem {
  final String id;
  final String url;
  final SniffedMediaType type;
  final String title;
  final Map<String, String>? headers;
  final int? sizeBytes;
  final String? resolution;
  final DateTime detectedAt;

  SniffedMediaItem({
    required this.id,
    required this.url,
    required this.type,
    required this.title,
    this.headers,
    this.sizeBytes,
    this.resolution,
    required this.detectedAt,
  });

  String get typeLabel {
    switch (type) {
      case SniffedMediaType.hlsStream:
        return 'HLS Stream (.m3u8)';
      case SniffedMediaType.mpdStream:
        return 'DASH Stream (.mpd)';
      case SniffedMediaType.mp4Video:
        return 'MP4 Video';
      case SniffedMediaType.genericVideo:
        return 'Video Stream';
      case SniffedMediaType.audio:
        return 'Audio Track';
      case SniffedMediaType.image:
        return 'Image';
    }
  }

  String get typeBadge {
    switch (type) {
      case SniffedMediaType.hlsStream:
        return 'M3U8';
      case SniffedMediaType.mpdStream:
        return 'MPD';
      case SniffedMediaType.mp4Video:
        return 'MP4';
      case SniffedMediaType.genericVideo:
        return 'VIDEO';
      case SniffedMediaType.audio:
        return 'AUDIO';
      case SniffedMediaType.image:
        return 'IMG';
    }
  }
}
