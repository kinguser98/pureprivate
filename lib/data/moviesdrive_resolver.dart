import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:private_cinema_mobile/data/sync_service.dart';
import 'package:private_cinema_mobile/data/domain_service.dart';
import '../widgets/special_search_dialog.dart';

class MoviesdriveResolver {
  static const String _defaultDomain = 'https://new3.moviesdrive.christmas';
  static const Map<String, String> _requestHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36',
    'Accept': 'application/json, text/html, application/xhtml+xml, */*',
    'Accept-Language': 'en-US,en;q=0.9',
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
    final sources = <StreamSourceInfo>[];

    try {
      List<String> postUrls = [];

      // Method 1: Instant Typesense JSON search API (/search.php?q=...)
      final apiSearchUrl = '$domain/search.php?q=${Uri.encodeComponent(cleanTitle)}&page=1';
      debugPrint('MoviesdriveResolver: Searching "$cleanTitle" ($year) on $apiSearchUrl');

      try {
        final apiRes = await http.get(
          Uri.parse(apiSearchUrl),
          headers: _requestHeaders,
        ).timeout(const Duration(seconds: 7));

        if (apiRes.statusCode == 200) {
          final data = jsonDecode(apiRes.body);
          if (data is Map && data['hits'] is List) {
            for (final hit in data['hits']) {
              if (hit is Map && hit['document'] is Map) {
                final doc = hit['document'];
                final permalink = doc['permalink']?.toString() ?? '';
                final postTitle = doc['post_title']?.toString() ?? '';
                if (permalink.isNotEmpty && _isTitleMatch(postTitle, cleanTitle, year)) {
                  postUrls.add(permalink);
                }
              }
            }
          }
        }
      } catch (e) {
        debugPrint('MoviesdriveResolver: /search.php error: $e');
      }

      // Method 2: Fallback to standard HTML search (?s=...) if API returned no matching posts
      if (postUrls.isEmpty) {
        try {
          final fbUrl = '$domain/?s=${Uri.encodeComponent(cleanTitle)}';
          debugPrint('MoviesdriveResolver: Trying HTML search fallback $fbUrl');
          final fbRes = await http.get(Uri.parse(fbUrl), headers: _requestHeaders).timeout(const Duration(seconds: 7));
          if (fbRes.statusCode == 200) {
            postUrls = _extractPostUrls(fbRes.body, domain, cleanTitle, year);
          }
        } catch (e) {
          debugPrint('MoviesdriveResolver: HTML search error: $e');
        }
      }

      debugPrint('MoviesdriveResolver: Found ${postUrls.length} posts for "$cleanTitle"');

      if (postUrls.isNotEmpty) {
        // Inspect top 2 matching post pages
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
            final links = await _extractAndUnpackLinks(postRes.body, targetPostUrl, season: season, episode: episode, isSeries: isSeries);
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
        .replaceAll(RegExp(r'\b(dub|dubbed|hd|4k|hindi|tamil|telugu|malayalam|kannada|multi|dual audio)\b', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static bool _isTitleMatch(String postTitle, String cleanTitle, int year) {
    final lowerPost = postTitle.toLowerCase();
    final lowerClean = cleanTitle.toLowerCase();
    final words = lowerClean.split(' ').where((w) => w.length > 2).toList();
    
    // Check if main words are contained in post title
    if (words.isNotEmpty) {
      int matchCount = 0;
      for (final w in words) {
        if (lowerPost.contains(w)) matchCount++;
      }
      if (matchCount < (words.length > 1 ? 2 : 1)) {
        return false;
      }
    }

    // Check year if present and title has multiple words
    if (year > 1900 && lowerPost.contains(year.toString())) {
      return true;
    }
    
    return true;
  }

  static List<String> _extractPostUrls(String html, String domain, String cleanTitle, int year) {
    final postUrls = <String>[];
    final words = cleanTitle.toLowerCase().split(' ').where((w) => w.length > 2).toList();
    final linkRegex = RegExp(r'<a[^>]+href="([^"]+)"[^>]*>(.*?)<\/a>', caseSensitive: false, dotAll: true);
    final matches = linkRegex.allMatches(html);

    for (final m in matches) {
      var href = m.group(1) ?? '';
      final text = m.group(2)?.replaceAll(RegExp(r'<[^>]*>'), '').trim() ?? '';
      if (href.startsWith('/')) href = '$domain$href';

      final lowerHref = href.toLowerCase();
      final lowerText = text.toLowerCase();

      if (lowerHref.startsWith(domain.toLowerCase()) &&
          !lowerHref.contains('/category/') &&
          !lowerHref.contains('/tag/') &&
          !lowerHref.contains('/page/') &&
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

  static Future<List<StreamSourceInfo>> _extractAndUnpackLinks(
    String html,
    String postUrl, {
    int? season,
    int? episode,
    bool isSeries = false,
  }) async {
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
          lowerUrl.contains('gamerxyt') ||
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
    String quality = '1080p';
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
        final res1 = await http.get(Uri.parse(currentUrl), headers: _requestHeaders).timeout(const Duration(seconds: 6));
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
        }).timeout(const Duration(seconds: 6));

        final targetMatch = RegExp(r"var\s+url\s*=\s*'([^']+)'", caseSensitive: false).firstMatch(res2.body) ??
                            RegExp(r'id="download"[^>]*href="([^"]+)"', caseSensitive: false).firstMatch(res2.body) ??
                            RegExp(r'href="([^"]*gamerxyt\.com[^"]*)"', caseSensitive: false).firstMatch(res2.body);
        if (targetMatch != null) {
          currentUrl = targetMatch.group(1)!;
        }
      }

      // Hop 3: Gateway -> Direct video streams
      if (currentUrl.contains('gamerxyt.com') || currentUrl.contains('hubcloud.php')) {
        final res3 = await http.get(Uri.parse(currentUrl), headers: {
          ..._requestHeaders,
          'Referer': 'https://hubcloud.cx/',
        }).timeout(const Duration(seconds: 6));

        final btnRegex = RegExp(r'<a[^>]+href="([^"]+)"[^>]*>(.*?)<\/a>', caseSensitive: false, dotAll: true);
        for (final m in btnRegex.allMatches(res3.body)) {
          final href = m.group(1) ?? '';
          final label = m.group(2)?.replaceAll(RegExp(r'<[^>]*>'), '').trim() ?? '';
          final lowerHref = href.toLowerCase();
          final lowerLabel = label.toLowerCase();

          // 1. Cloudflare R2 Direct / CDN Fast Server / Direct MKV / MP4
          if (lowerHref.contains('.r2.cloudflarestorage.com') ||
              lowerHref.contains('cdn.') ||
              lowerHref.endsWith('.mkv') ||
              lowerHref.endsWith('.mp4') ||
              lowerHref.contains('.mkv?') ||
              lowerHref.contains('.mp4?')) {
            String serverName = 'MoviesDrive Fast Server';
            if (lowerLabel.contains('fslv2') || lowerHref.contains('lenin.buzz') || lowerHref.contains('pongala.life')) {
              serverName = 'MoviesDrive FSLv2 CDN';
            } else if (lowerLabel.contains('fsl') || lowerHref.contains('.r2.')) {
              serverName = 'MoviesDrive Cloudflare R2';
            } else if (lowerLabel.contains('10gbps')) {
              serverName = 'MoviesDrive 10Gbps';
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
          // 2. PixelDrain direct stream
          else if (lowerHref.contains('pixeldrain.com/u/') || lowerHref.contains('pixeldrain.dev/u/')) {
            final fileIdMatch = RegExp(r'/u/([a-zA-Z0-9_-]+)').firstMatch(href);
            if (fileIdMatch != null) {
              final fileId = fileIdMatch.group(1)!;
              final streamUrl = 'https://pixeldrain.com/api/file/$fileId';
              streams.add(StreamSourceInfo(
                name: 'MoviesDrive PixelDrain Direct • $quality',
                url: streamUrl,
                type: StreamSourceType.moviesdrive,
                quality: quality,
                size: size,
              ));
            }
          }
          // 3. Buzz / FuckingFast direct stream
          else if (lowerHref.contains('fuckingfast.net/')) {
            streams.add(StreamSourceInfo(
              name: 'MoviesDrive Buzz High-Speed • $quality',
              url: href,
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
