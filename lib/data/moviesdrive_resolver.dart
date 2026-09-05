import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:private_cinema_mobile/data/sync_service.dart';
import 'package:private_cinema_mobile/data/domain_service.dart';
import 'package:private_cinema_mobile/widgets/stream_metadata_tile.dart';
import '../widgets/special_search_dialog.dart';

class MoviesdriveResolver {
  static const List<String> _domains = [
    'https://new3.moviesdrive.christmas',
    'https://new.moviesdrive.christmas',
  ];

  static const Map<String, String> _requestHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml,application/json;q=0.9,*/*;q=0.8',
  };

  static Future<String> getBaseDomain() async {
    try {
      final dyn = await DomainService.getDomain('moviesdrive');
      if (dyn.isNotEmpty) return dyn;
    } catch (_) {}
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
    return _domains.first;
  }

  static Future<List<StreamSourceInfo>> resolveStreams({
    required String title,
    required int year,
    String? originalLanguage,
    int? season,
    int? episode,
    bool isSeries = false,
  }) async {
    final cleanTitle = _cleanQuery(title);
    final baseDomain = await getBaseDomain();
    final candidateDomains = [baseDomain, ..._domains.where((d) => d != baseDomain)];

    debugPrint('MoviesdriveResolver: Searching "$cleanTitle" ($year)...');
    final sources = <StreamSourceInfo>[];

    for (final domain in candidateDomains) {
      try {
        final postUrls = <String>[];

        // 1. Instant Typesense Search API (/search.php?q=...)
        try {
          final apiUrl = '$domain/search.php?q=${Uri.encodeComponent(cleanTitle)}&page=1';
          final apiRes = await http.get(Uri.parse(apiUrl), headers: _requestHeaders).timeout(const Duration(seconds: 6));
          if (apiRes.statusCode == 200) {
            final data = jsonDecode(apiRes.body);
            if (data is Map && data['hits'] is List) {
              for (final h in data['hits']) {
                if (h is Map && h['document'] is Map) {
                  var permalink = h['document']['permalink']?.toString() ?? '';
                  if (permalink.startsWith('/')) permalink = '$domain$permalink';
                  if (permalink.isNotEmpty && !postUrls.contains(permalink)) {
                    postUrls.add(permalink);
                  }
                }
              }
            }
          }
        } catch (_) {}

        // 2. Fallback to HTML Search (?s=...)
        if (postUrls.isEmpty) {
          try {
            final fbUrl = '$domain/?s=${Uri.encodeComponent(cleanTitle)}';
            final fbRes = await http.get(Uri.parse(fbUrl), headers: _requestHeaders).timeout(const Duration(seconds: 6));
            if (fbRes.statusCode == 200) {
              postUrls.addAll(_extractPostUrls(fbRes.body, domain, cleanTitle));
            }
          } catch (_) {}
        }

        // 3. Fallback to /search/ path
        if (postUrls.isEmpty) {
          try {
            final sUrl = '$domain/search/${Uri.encodeComponent(cleanTitle.toLowerCase())}';
            final sRes = await http.get(Uri.parse(sUrl), headers: _requestHeaders).timeout(const Duration(seconds: 6));
            if (sRes.statusCode == 200) {
              postUrls.addAll(_extractPostUrls(sRes.body, domain, cleanTitle));
            }
          } catch (_) {}
        }

        debugPrint('MoviesdriveResolver: Found ${postUrls.length} posts on $domain for "$cleanTitle"');

        if (postUrls.isNotEmpty) {
          for (final postUrl in postUrls.take(2)) {
            debugPrint('MoviesdriveResolver: Inspecting post $postUrl');
            final postRes = await http.get(
              Uri.parse(postUrl),
              headers: {
                ..._requestHeaders,
                'Referer': domain,
              },
            ).timeout(const Duration(seconds: 7));

            if (postRes.statusCode == 200) {
              final links = await _extractAndUnpackLinks(postRes.body, postUrl);
              sources.addAll(links);
            }
          }
        }

        if (sources.isNotEmpty) break;
      } catch (e) {
        debugPrint('MoviesdriveResolver error on $domain: $e');
      }
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

    // Quality sorting: 4K -> 1080p -> 720p -> 480p
    final sortedSources = sortStreamsByQuality<StreamSourceInfo>(
      uniqueSources,
      getName: (s) => s.name,
      getUrl: (s) => s.url,
      getQuality: (s) => s.quality,
      getSize: (s) => s.size,
    );

    debugPrint('MoviesdriveResolver: Resolved ${sortedSources.length} direct streams for "$title"');
    return sortedSources;
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
      final anchorText = m.group(2)?.replaceAll(RegExp(r'<[^>]*>'), '').trim() ?? '';

      if (href.startsWith('/')) href = '$domain$href';

      final lowerHref = href.toLowerCase();
      final lowerText = anchorText.toLowerCase();

      if (lowerHref.startsWith(domain.toLowerCase()) &&
          !lowerHref.contains('/category/') &&
          !lowerHref.contains('/tag/') &&
          !lowerHref.contains('/page/') &&
          !lowerHref.contains('/disclaimer') &&
          !lowerHref.contains('/how-to') &&
          !lowerHref.contains('/search.php') &&
          href != domain &&
          href != '$domain/') {
        bool match = words.isEmpty;
        for (final w in words) {
          if (lowerHref.contains(w) || lowerText.contains(w)) match = true;
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
      final text = m.group(2)?.replaceAll(RegExp(r'<[^>]*>'), '').trim() ?? '';
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
          lowerText.contains('fast server') ||
          lowerText.contains('fsl');

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
    String quality = '1080p Full HD';
    String? size;

    if (buttonText != null) {
      final lowerText = buttonText.toLowerCase();
      if (lowerText.contains('2160p') || lowerText.contains('4k') || lowerText.contains('uhd')) {
        quality = '4K (2160p)';
      } else if (lowerText.contains('1080p')) {
        quality = '1080p Full HD';
      } else if (lowerText.contains('720p')) {
        quality = '720p HD';
      } else if (lowerText.contains('480p')) {
        quality = '480p SD';
      }

      final sizeMatch = RegExp(r'\[([0-9.]+\s*[GM]B)\]', caseSensitive: false).firstMatch(buttonText) ??
                        RegExp(r'\b([0-9.]+\s*[GM]B)\b', caseSensitive: false).firstMatch(buttonText);
      if (sizeMatch != null) {
        size = sizeMatch.group(1);
      }
    }

    try {
      String currentUrl = initialUrl;

      // Hop 1: mdrive / hubdrive -> HubCloud
      if (currentUrl.contains('hubdrive.') || currentUrl.contains('drive.') || currentUrl.contains('mdrive.')) {
        final res1 = await http.get(Uri.parse(currentUrl), headers: _requestHeaders).timeout(const Duration(seconds: 5));
        final hubMatch = RegExp(r'href="([^"]*hubcloud[^"]*)"', caseSensitive: false).firstMatch(res1.body) ??
                         RegExp(r'action="([^"]*hubcloud[^"]*)"', caseSensitive: false).firstMatch(res1.body) ??
                         RegExp(r'''["'](https?://[^"']*hubcloud[^"']*)["']''', caseSensitive: false).firstMatch(res1.body);
        if (hubMatch != null) {
          currentUrl = hubMatch.group(1)!;
        }
      }

      // Hop 2: HubCloud -> Gateway (gamerxyt / etc.)
      if (currentUrl.contains('hubcloud.')) {
        final res2 = await http.get(Uri.parse(currentUrl), headers: {
          ..._requestHeaders,
          'Referer': referer ?? initialUrl,
        }).timeout(const Duration(seconds: 5));

        final targetMatch = RegExp(r"var\s+url\s*=\s*'([^']+)'", caseSensitive: false).firstMatch(res2.body) ??
                            RegExp(r'id="download"[^>]*href="([^"]+)"', caseSensitive: false).firstMatch(res2.body) ??
                            RegExp(r'href="([^"]*gamerxyt\.com[^"]*)"', caseSensitive: false).firstMatch(res2.body);
        if (targetMatch != null) {
          currentUrl = targetMatch.group(1)!;
        }
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
        final lowerLabel = label.toLowerCase();

        // Skip fuckingfast as requested
        if (lowerHref.contains('fuckingfast.net')) continue;

        if (lowerHref.contains('.r2.cloudflarestorage.com') ||
            lowerHref.contains('cdn.') ||
            lowerHref.endsWith('.mkv') ||
            lowerHref.endsWith('.mp4') ||
            lowerHref.contains('.mkv?') ||
            lowerHref.contains('.mp4?')) {
          String serverName = 'Fast Server';
          if (lowerLabel.contains('fslv2') || lowerHref.contains('lenin.buzz') || lowerHref.contains('pongala.life')) {
            serverName = 'FSLv2 CDN';
          } else if (lowerLabel.contains('fsl') || lowerHref.contains('.r2.')) {
            serverName = 'Cloudflare R2 Direct';
          } else if (lowerLabel.contains('10gbps')) {
            serverName = '10Gbps Dedicated';
          }

          final displayName = '$serverName • $quality${size != null ? " [$size]" : ""}';
          streams.add(StreamSourceInfo(
            name: displayName,
            url: href,
            type: StreamSourceType.moviesdrive,
            quality: quality,
            size: size,
          ));
        } else if (lowerHref.contains('pixeldrain.com/u/') || lowerHref.contains('pixeldrain.dev/u/')) {
          final fileIdMatch = RegExp(r'/u/([a-zA-Z0-9_-]+)').firstMatch(href);
          if (fileIdMatch != null) {
            final fileId = fileIdMatch.group(1)!;
            final streamUrl = 'https://pixeldrain.com/api/file/$fileId';
            final displayName = 'PixelDrain Direct • $quality${size != null ? " [$size]" : ""}';
            streams.add(StreamSourceInfo(
              name: displayName,
              url: streamUrl,
              type: StreamSourceType.moviesdrive,
              quality: quality,
              size: size,
            ));
          }
        }
      }
    } catch (e) {
      debugPrint('MoviesdriveResolver unpack error: $e');
    }

    return streams;
  }
}
