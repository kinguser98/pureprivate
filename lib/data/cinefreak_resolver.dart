import '../widgets/special_search_dialog.dart';
import '../widgets/stream_metadata_tile.dart';
import 'package:private_cinema_mobile/widgets/stream_metadata_tile.dart';
import 'package:private_cinema_mobile/widgets/special_search_dialog.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:private_cinema_mobile/data/sync_service.dart';
import 'package:private_cinema_mobile/data/modular_source_service.dart';

class CinefreakResolver {
  static const String _defaultDomain = 'https://cinefreak.ch';

  static Future<String> getBaseDomain() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final custom = prefs.getString('domain_cinefreak');
      if (custom != null && custom.trim().isNotEmpty) {
        return custom.trim().replaceAll(RegExp(r'/+$'), '');
      }
      final cloud = await SyncService.fetchAppSettings();
      if (cloud.containsKey('domain_cinefreak') &&
          cloud['domain_cinefreak']!.trim().isNotEmpty) {
        return cloud['domain_cinefreak']!.trim().replaceAll(RegExp(r'/+$'), '');
      }
    } catch (_) {}
    return _defaultDomain;
  }

  static String _cleanName(String raw) {
    var s = raw
        .replaceAll(RegExp(r'CINEFREAK(\.NET|\.ch)?', caseSensitive: false), '')
        .replaceAll(RegExp(r'\b(Full Movie Download|Watch Online|GDrive|ESub)\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*[-•|:]\s*'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (s.startsWith('-') || s.startsWith('|') || s.startsWith('•')) {
      s = s.substring(1).trim();
    }
    return s;
  }

  static String _buildCleanLabel(String postTitle, String mediaUrl, String? sizeStr) {
    String lang = 'Dual Audio';
    final lowerTitle = postTitle.toLowerCase();
    if (lowerTitle.contains('hindi') && lowerTitle.contains('english')) {
      lang = 'Dual Audio (Hindi - English)';
    } else if (lowerTitle.contains('hindi')) {
      lang = 'Hindi Dubbed';
    } else if (lowerTitle.contains('english')) {
      lang = 'English';
    } else if (lowerTitle.contains('bangla')) {
      lang = 'Bangla';
    } else if (lowerTitle.contains('korean') || lowerTitle.contains('k-drama')) {
      lang = 'Korean';
    } else if (lowerTitle.contains('tamil')) {
      lang = 'Tamil';
    } else if (lowerTitle.contains('telugu')) {
      lang = 'Telugu';
    }

    String quality = 'HD';
    final lowerUrl = mediaUrl.toLowerCase();
    if (lowerTitle.contains('2160p') || lowerTitle.contains('4k') || lowerUrl.contains('2160p') || lowerUrl.contains('4k')) {
      quality = '4K 2160p';
    } else if (lowerTitle.contains('1080p') || lowerUrl.contains('1080p')) {
      quality = '1080p Full HD';
    } else if (lowerTitle.contains('720p') || lowerUrl.contains('720p')) {
      quality = '720p HD';
    } else if (lowerTitle.contains('480p') || lowerUrl.contains('480p')) {
      quality = '480p SD';
    }

    String fmt = 'MKV';
    if (lowerUrl.contains('.mp4')) fmt = 'MP4';
    if (lowerUrl.contains('hevc') || lowerTitle.contains('hevc') || lowerTitle.contains('10bit')) {
      fmt += ' (HEVC)';
    }

    var label = '$lang • $quality • $fmt';
    if (sizeStr != null && sizeStr.isNotEmpty) {
      label += ' ($sizeStr)';
    }
    return label;
  }

  static Future<List<StreamSourceInfo>> resolveStreams({
    required String title,
    int? year,
    String? tmdbId,
    int? season,
    int? episode,
    bool isSeries = false,
  }) async {
    final domain = await getBaseDomain();
    final sources = <StreamSourceInfo>[];
    final seenUrls = <String>{};

    try {
      final apiUrl = '$domain/wp-json/wp/v2/posts?search=${Uri.encodeComponent(title.trim())}';
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
      final req = await client.getUrl(Uri.parse(apiUrl));
      req.headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36');
      final res = await req.close();
      if (res.statusCode != 200) {
        client.close(force: true);
        return [];
      }

      final body = await res.transform(utf8.decoder).join();
      client.close();

      final posts = jsonDecode(body);
      if (posts is! List || posts.isEmpty) {
        return [];
      }

      final targetPosts = <Map<String, String>>[];
      for (final p in posts) {
        if (p is! Map) continue;
        final pTitle = p['title']?['rendered']?.toString() ?? '';
        final pLink = p['link']?.toString() ?? '';
        if (pLink.isNotEmpty) {
          targetPosts.add({'title': pTitle, 'link': pLink});
        }
      }

      final futures = targetPosts.take(3).map((postItem) async {
        final pTitle = postItem['title']!;
        final pLink = postItem['link']!;
        final localSources = <StreamSourceInfo>[];

        try {
          final pClient = HttpClient()..connectionTimeout = const Duration(seconds: 6);
          final pReq = await pClient.getUrl(Uri.parse(pLink));
          pReq.headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36');
          final pRes = await pReq.close();
          if (pRes.statusCode != 200) {
            pClient.close(force: true);
            return localSources;
          }

          final pHtml = await pRes.transform(utf8.decoder).join();
          pClient.close();

          final b64Matches = RegExp(r'generate\.php\?id=([a-zA-Z0-9+/=]+)').allMatches(pHtml);
          final seenIds = <String>{};

          for (final m in b64Matches) {
            final b64 = m.group(1);
            if (b64 == null || b64.isEmpty) continue;

            try {
              var padB64 = b64;
              while (padB64.length % 4 != 0) {
                padB64 += '=';
              }
              final decodedUrl = utf8.decode(base64.decode(padB64.replaceAll('-', '+').replaceAll('_', '/')));

              final idMatch = RegExp(r'/[xf]/([a-fA-F0-9]{8})').firstMatch(decodedUrl);
              if (idMatch == null) continue;
              final streamId = idMatch.group(1)!;
              if (!seenIds.add(streamId)) continue;

              final cinecloudUrl = 'https://new5.cinecloud.site/f/$streamId';
              final cClient = HttpClient()..connectionTimeout = const Duration(seconds: 6);
              final cReq = await cClient.getUrl(Uri.parse(cinecloudUrl));
              cReq.headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36');
              cReq.headers.set(HttpHeaders.refererHeader, '$domain/');
              final cRes = await cReq.close();
              if (cRes.statusCode != 200) {
                cClient.close(force: true);
                continue;
              }

              final cBody = await cRes.transform(utf8.decoder).join();
              cClient.close();

              final mediaMatches = RegExp(r'https?://[^\s\x22\x27<>\\]+\.(?:m3u8|mp4|mkv)[^\s\x22\x27<>\\]*').allMatches(cBody);
              if (mediaMatches.isNotEmpty) {
                final mediaUrl = mediaMatches.first.group(0)!;
                if (seenUrls.add(mediaUrl)) {
                  final label = _buildCleanLabel(pTitle, mediaUrl, null);
                  localSources.add(
                    StreamSourceInfo(
                      name: label,
                      url: mediaUrl,
                      type: StreamSourceType.cinefreak,
                      quality: label.contains('2160p') ? '4K 2160p' : (label.contains('1080p') ? '1080p Full HD' : '720p HD'),
                      headers: const {
                        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
                        'Referer': 'https://cinefreak.ch/',
                      },
                    ),
                  );
                }
              }
            } catch (_) {}
          }
        } catch (_) {}

        return localSources;
      });

      final results = await Future.wait(futures);
      for (final list in results) {
        sources.addAll(list);
      }
    } catch (_) {}

    final sorted = sortStreamsByQuality<StreamSourceInfo>(
      sources,
      getName: (s) => s.name,
      getUrl: (s) => s.url,
      getQuality: (s) => s.quality,
      getSize: (s) => s.size,
    );

    return sorted;
  }
}
