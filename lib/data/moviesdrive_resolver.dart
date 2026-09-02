import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:private_cinema_mobile/data/sync_service.dart';
import '../widgets/special_search_dialog.dart';

class MoviesdriveResolver {
  static const String _defaultDomain = 'https://new3.moviesdrive.christmas';
  static const Map<String, String> _requestHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36',
    'Accept': 'application/json, text/html, */*',
  };

  static Future<String> getBaseDomain() async {
    try {
      final cloud = await SyncService.fetchAppSettings();
      if (cloud.containsKey('domain_moviesdrive') && cloud['domain_moviesdrive']!.isNotEmpty) {
        final d = cloud['domain_moviesdrive']!;
        return d.endsWith('/') ? d.substring(0, d.length - 1) : d;
      }
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('domain_moviesdrive') ?? '';
      if (saved.isNotEmpty) {
        return saved.endsWith('/') ? saved.substring(0, saved.length - 1) : saved;
      }
    } catch (_) {}
    return _defaultDomain;
  }

  static Future<List<StreamSourceInfo>> resolveStreams({
    required String title,
    required int year,
    String? originalLanguage,
    int? season,
    int? episode,
    bool isSeries = false,
  }) async {
    final domain = await getBaseDomain();
    final cleanTitle = _cleanQuery(title);
    final wpSearchUrl = '$domain/wp-json/wp/v2/posts?search=${Uri.encodeComponent(cleanTitle)}';

    debugPrint('MoviesdriveResolver: Searching "$cleanTitle" ($year) on $wpSearchUrl');
    final sources = <StreamSourceInfo>[];

    try {
      final res = await http.get(
        Uri.parse(wpSearchUrl),
        headers: _requestHeaders,
      ).timeout(const Duration(seconds: 8));

      List<String> postUrls = [];
      if (res.statusCode == 200) {
        try {
          final data = jsonDecode(res.body);
          if (data is List) {
            for (final p in data) {
              if (p is Map && p['link'] != null) {
                postUrls.add(p['link'].toString());
              }
            }
          }
        } catch (_) {}
      }

      // Fallback to HTML search if wp-json failed
      if (postUrls.isEmpty) {
        final fbUrl = '$domain/?s=${Uri.encodeComponent(cleanTitle)}';
        final fbRes = await http.get(Uri.parse(fbUrl), headers: _requestHeaders).timeout(const Duration(seconds: 8));
        if (fbRes.statusCode == 200) {
          postUrls = _extractPostUrls(fbRes.body, domain, cleanTitle);
        }
      }

      debugPrint('MoviesdriveResolver: Found ${postUrls.length} posts for "$cleanTitle"');

      if (postUrls.isNotEmpty) {
        for (final targetPostUrl in postUrls.take(2)) {
          debugPrint('MoviesdriveResolver: Inspecting post $targetPostUrl');
          final postRes = await http.get(
            Uri.parse(targetPostUrl),
            headers: {
              ..._requestHeaders,
              'Referer': domain,
            },
          ).timeout(const Duration(seconds: 8));

          if (postRes.statusCode == 200) {
            final links = await _extractAndUnpackLinks(postRes.body, targetPostUrl);
            sources.addAll(links);
          }
        }
      }
    } catch (e) {
      debugPrint('MoviesdriveResolver error: $e');
    }

    // Deduplicate by URL
    final uniqueSources = <StreamSourceInfo>[];
    final seenUrls = <String>{};
    for (final s in sources) {
      if (!seenUrls.contains(s.url)) {
        seenUrls.add(s.url);
        uniqueSources.add(s);
      }
    }

    debugPrint('MoviesdriveResolver: Resolved ${uniqueSources.length} direct streams for "$title"');
    return uniqueSources;
  }

  static String _cleanQuery(String query) {
    return query
        .replaceAll(RegExp(r'\[.*?\]'), ' ')
        .replaceAll(RegExp(r'\(.*?\)'), ' ')
        .replaceAll(RegExp(r'\b(dub|dubbed|hd|4k|hindi|tamil|telugu|multi|dual audio)\b', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static List<String> _extractPostUrls(String html, String domain, String cleanTitle) {
    final postUrls = <String>[];
    final words = cleanTitle.toLowerCase().split(' ').where((w) => w.length > 2).toList();
    final linkRegex = RegExp(r'<a[^>]+href="([^"]+)"[^>]*>(.*?)<\/a>', caseSensitive: false, dotAll: true);
    final matches = linkRegex.allMatches(html);

    for (final m in matches) {
      var href = m.group(1) ?? '';
      if (href.startsWith('/')) href = '$domain$href';

      final lowerHref = href.toLowerCase();
      if (lowerHref.startsWith(domain.toLowerCase()) &&
          !lowerHref.contains('/category/') &&
          !lowerHref.contains('/tag/') &&
          !lowerHref.contains('/page/') &&
          href != domain &&
          href != '$domain/') {
        bool match = words.isEmpty;
        for (final w in words) {
          if (lowerHref.contains(w)) match = true;
        }
        if (match && !postUrls.contains(href)) {
          postUrls.add(href);
        }
      }
    }
    return postUrls;
  }

  static Future<List<StreamSourceInfo>> _extractAndUnpackLinks(String html, String postUrl) async {
    final linkRegex = RegExp(r'<a[^>]+href="([^"]+)"[^>]*>(.*?)<\/a>', caseSensitive: false, dotAll: true);
    final matches = linkRegex.allMatches(html);
    final unpackFutures = <Future<List<StreamSourceInfo>>>[];

    for (final m in matches) {
      final url = m.group(1)?.trim() ?? '';
      final text = m.group(2)?.replaceAll(RegExp(r'<[^>]*>'), '')?.trim() ?? '';
      final lowerUrl = url.toLowerCase();
      final lowerText = text.toLowerCase();

      final isDownloadButton = lowerUrl.contains('hubdrive') ||
          lowerUrl.contains('hubcloud') ||
          lowerUrl.contains('mdrive.') ||
          lowerUrl.contains('drive.') ||
          lowerText.contains('720p') ||
          lowerText.contains('1080p') ||
          lowerText.contains('2160p') ||
          lowerText.contains('4k') ||
          lowerText.contains('hevc') ||
          lowerText.contains('download') ||
          lowerText.contains('fast server');

      if (isDownloadButton && url.startsWith('http') && !url.contains('moviesdrive')) {
        unpackFutures.add(_unpackDirectStreams(url, buttonText: text, referer: postUrl));
      }
    }

    final results = await Future.wait(unpackFutures);
    final flatList = <StreamSourceInfo>[];
    for (final r in results) {
      flatList.addAll(r);
    }
    return flatList;
  }

  static Future<List<StreamSourceInfo>> _unpackDirectStreams(
    String initialUrl, {
    String? buttonText,
    String? referer,
  }) async {
    final streams = <StreamSourceInfo>[];
    String quality = '1080p';
    String? size;

    if (buttonText != null) {
      final lowerText = buttonText.toLowerCase();
      if (lowerText.contains('2160p') || lowerText.contains('4k')) {
        quality = '4K (2160p)';
      } else if (lowerText.contains('1080p')) {
        quality = '1080p Full HD';
      } else if (lowerText.contains('720p')) {
        quality = '720p HD';
      } else if (lowerText.contains('480p')) {
        quality = '480p SD';
      }

      final sizeMatch = RegExp(r'\[([0-9.]+\s*[GM]B)\]', caseSensitive: false).firstMatch(buttonText);
      if (sizeMatch != null) {
        size = sizeMatch.group(1);
      }
    }

    try {
      String currentUrl = initialUrl;

      // Hop 1: mdrive / hubdrive -> HubCloud
      if (currentUrl.contains('hubdrive.') || currentUrl.contains('drive.') || currentUrl.contains('mdrive.')) {
        final res1 = await http.get(Uri.parse(currentUrl), headers: _requestHeaders).timeout(const Duration(seconds: 5));
        final hubMatch = RegExp(r'href="(https?://[^"]*hubcloud[^"]*)"').firstMatch(res1.body);
        if (hubMatch != null) currentUrl = hubMatch.group(1)!;
      }

      // Hop 2: HubCloud -> Gateway (gamerxyt / etc.)
      if (currentUrl.contains('hubcloud.')) {
        final res2 = await http.get(Uri.parse(currentUrl), headers: {
          ..._requestHeaders,
          'Referer': referer ?? initialUrl,
        }).timeout(const Duration(seconds: 5));

        final targetMatch = RegExp(r"var\s+url\s*=\s*'([^']+)'").firstMatch(res2.body) ??
                            RegExp(r'id="download"[^>]*href="([^"]+)"').firstMatch(res2.body);
        if (targetMatch != null) currentUrl = targetMatch.group(1)!;
      }

      // Hop 3: Gateway -> Direct video streams
      final res3 = await http.get(Uri.parse(currentUrl), headers: {
        ..._requestHeaders,
        'Referer': 'https://hubcloud.cx/',
      }).timeout(const Duration(seconds: 5));

      final btnRegex = RegExp(r'<a[^>]+href="([^"]+)"[^>]*>(.*?)<\/a>', caseSensitive: false, dotAll: true);
      for (final m in btnRegex.allMatches(res3.body)) {
        final href = m.group(1) ?? '';
        final label = m.group(2)?.replaceAll(RegExp(r'<[^>]*>'), '').trim() ?? '';
        final lowerHref = href.toLowerCase();

        if (lowerHref.contains('.r2.cloudflarestorage.com') ||
            lowerHref.contains('cdn.') ||
            lowerHref.endsWith('.mkv') ||
            lowerHref.endsWith('.mp4') ||
            lowerHref.contains('.mkv?') ||
            lowerHref.contains('.mp4?')) {
          String serverName = 'Fast Server';
          if (label.contains('FSLv2') || lowerHref.contains('lenin.buzz') || lowerHref.contains('pongala.life')) {
            serverName = 'FSLv2 CDN';
          } else if (label.contains('FSL Server') || lowerHref.contains('.r2.')) {
            serverName = 'Cloudflare R2 Direct';
          } else if (label.contains('10Gbps')) {
            serverName = '10Gbps Dedicated';
          }

          final displayName = '$serverName • $quality';
          streams.add(StreamSourceInfo(
            name: displayName,
            url: href,
            type: StreamSourceType.moviesdrive,
            quality: quality,
            size: size,
          ));
        }
      }
    } catch (e) {
      debugPrint('MoviesdriveResolver unpack error: $e');
    }

    return streams;
  }
}
