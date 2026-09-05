import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:private_cinema_mobile/widgets/stream_metadata_tile.dart';
import '../widgets/special_search_dialog.dart';

class MkvbaseResolver {
  static const String _defaultDomain = 'https://mkvbase.site';

  static Future<String> getBaseDomain() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('domain_mkvbase') ?? '';
    if (saved.isNotEmpty) return saved.endsWith('/') ? saved.substring(0, saved.length - 1) : saved;
    return _defaultDomain;
  }

  static Future<String?> _fetchHtml(String url) async {
    // 1. Try fast HTTP GET
    try {
      final res = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        },
      ).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200 && !res.body.contains('Just a moment...') && !res.body.contains('Cloudflare')) {
        return res.body;
      }
    } catch (_) {}

    // 2. Fallback to HeadlessInAppWebView to bypass Cloudflare Turnstile / Bot detection
    try {
      final completer = Completer<String?>();
      HeadlessInAppWebView? headless;
      Timer? timeoutTimer;

      headless = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(
          url: WebUri(url),
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
          },
        ),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          domStorageEnabled: true,
          userAgent:
              'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
        ),
        onLoadStop: (controller, uri) async {
          await Future.delayed(const Duration(milliseconds: 2000));
          try {
            final html = await controller.evaluateJavascript(source: 'document.documentElement.outerHTML');
            if (html is String && html.isNotEmpty && !completer.isCompleted) {
              timeoutTimer?.cancel();
              completer.complete(html);
            }
          } catch (_) {}
        },
      );

      timeoutTimer = Timer(const Duration(seconds: 14), () {
        if (!completer.isCompleted) completer.complete(null);
      });

      await headless.run();
      final result = await completer.future;
      try {
        await headless.dispose();
      } catch (_) {}
      return result;
    } catch (e) {
      debugPrint('Mkvbase headless fetch error: $e');
      return null;
    }
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
    final searchUrl = '$domain/?s=${Uri.encodeComponent(cleanTitle)}';

    debugPrint('MkvbaseResolver: Searching "$cleanTitle" on $searchUrl');
    final sources = <StreamSourceInfo>[];

    try {
      final html = await _fetchHtml(searchUrl);
      if (html != null && html.isNotEmpty) {
        final postUrls = _extractPostUrls(html, domain, cleanTitle);
        debugPrint('MkvbaseResolver: Found ${postUrls.length} posts for "$cleanTitle"');
        if (postUrls.isNotEmpty) {
          final postsToProcess = postUrls.take(3).toList();
          for (final targetPostUrl in postsToProcess) {
            debugPrint('MkvbaseResolver: Fetching post $targetPostUrl');
            final postHtml = await _fetchHtml(targetPostUrl);
            if (postHtml != null && postHtml.isNotEmpty) {
              final links = _extractStreamLinks(postHtml, targetPostUrl, title, originalLanguage);
              sources.addAll(links);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('MkvbaseResolver error: $e');
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

    debugPrint('MkvbaseResolver: Resolved ${sortedSources.length} sources for "$title"');
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
    final titleWords = cleanTitle.toLowerCase().split(' ').where((w) => w.length > 2).toList();

    final linkRegex = RegExp(r'<a[^>]+href="([^"]+)"[^>]*>(.*?)<\/a>', caseSensitive: false, dotAll: true);
    final matches = linkRegex.allMatches(html);

    for (final m in matches) {
      var href = m.group(1) ?? '';
      final anchorText = m.group(2) ?? '';

      if (href.startsWith('/')) {
        href = '$domain$href';
      }

      final lowerText = anchorText.toLowerCase();
      final lowerHref = href.toLowerCase();

      if (lowerHref.startsWith(domain.toLowerCase()) &&
          !lowerHref.contains('/category/') &&
          !lowerHref.contains('/tag/') &&
          !lowerHref.contains('/author/') &&
          !lowerHref.contains('/page/') &&
          !lowerHref.contains('wp-') &&
          !lowerHref.endsWith('/feed') &&
          !lowerHref.endsWith('/feed/') &&
          href != domain &&
          href != '$domain/') {
        
        bool match = false;
        if (titleWords.isNotEmpty) {
          int matchCount = 0;
          for (final word in titleWords) {
            if (lowerText.contains(word) || lowerHref.contains(word)) {
              matchCount++;
            }
          }
          if (matchCount >= 1) {
            match = true;
          }
        } else {
          match = true;
        }

        if (match && !postUrls.contains(href)) {
          postUrls.add(href);
        }
      }
    }

    return postUrls;
  }

  static List<StreamSourceInfo> _extractStreamLinks(
    String html,
    String postUrl,
    String title,
    String? originalLanguage,
  ) {
    final sources = <StreamSourceInfo>[];

    final hrefRegex = RegExp(r'<a[^>]+href="([^"]+)"[^>]*>(.*?)<\/a>', caseSensitive: false, dotAll: true);
    final matches = hrefRegex.allMatches(html);

    for (final m in matches) {
      final url = m.group(1)?.trim() ?? '';
      final text = m.group(2)?.replaceAll(RegExp(r'<[^>]*>'), '')?.trim() ?? '';
      final lowerUrl = url.toLowerCase();
      final lowerText = text.toLowerCase();

      // Skip fuckingfast
      if (lowerUrl.contains('fuckingfast.net')) continue;

      final isTargetProvider = lowerUrl.contains('hubcloud') ||
          lowerUrl.contains('gdflix') ||
          lowerUrl.contains('fastcloud') ||
          lowerUrl.contains('pixeldrain') ||
          lowerUrl.contains('gofile') ||
          lowerUrl.contains('drive') ||
          lowerText.contains('hubcloud') ||
          lowerText.contains('fast server') ||
          lowerText.contains('download') ||
          lowerText.contains('1080p') ||
          lowerText.contains('720p') ||
          lowerText.contains('480p') ||
          lowerText.contains('2160p') ||
          lowerText.contains('4k');

      if (isTargetProvider && url.startsWith('http') && !url.contains('mkvbase.site')) {
        String quality = '1080p Full HD';
        if (lowerUrl.contains('2160p') || lowerUrl.contains('4k') || lowerText.contains('2160p') || lowerText.contains('4k')) {
          quality = '4K (2160p)';
        } else if (lowerUrl.contains('1080p') || lowerText.contains('1080p')) {
          quality = '1080p Full HD';
        } else if (lowerUrl.contains('720p') || lowerText.contains('720p')) {
          quality = '720p HD';
        } else if (lowerUrl.contains('480p') || lowerText.contains('480p')) {
          quality = '480p SD';
        }

        String audio = 'Multi-Audio';
        if (lowerText.contains('hindi') || lowerUrl.contains('hindi')) {
          audio = 'Hindi';
        } else if (lowerText.contains('tamil') || lowerUrl.contains('tamil')) {
          audio = 'Tamil';
        } else if (lowerText.contains('telugu') || lowerUrl.contains('telugu')) {
          audio = 'Telugu';
        } else if (lowerText.contains('dual')) {
          audio = 'Dual-Audio';
        }

        String? size;
        final sizeMatch = RegExp(r'\[([0-9.]+\s*[GM]B)\]', caseSensitive: false).firstMatch(text);
        if (sizeMatch != null) {
          size = sizeMatch.group(1);
        }

        final serverName = lowerUrl.contains('hubcloud')
            ? 'HubCloud'
            : (lowerUrl.contains('gdflix') ? 'GDFlix' : 'FastCloud');

        final displayName = '$serverName • $quality [$audio]${size != null ? " [$size]" : ""}';

        sources.add(
          StreamSourceInfo(
            name: displayName,
            url: url,
            type: StreamSourceType.mkvbase,
            quality: quality,
            size: size,
            headers: {
              'Referer': postUrl,
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
            },
          ),
        );
      }
    }

    return sources;
  }
}
