import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:private_cinema_mobile/data/domain_service.dart';
import '../widgets/special_search_dialog.dart';

class VegamoviesResolver {
  static const String _defaultDomain = 'https://vegamovies.catering';

  static Future<String> getBaseDomain() async {
    try {
      final dyn = await DomainService.getDomain('vegamovies');
      if (dyn.isNotEmpty) return dyn;
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('domain_vegamovies') ?? '';
    if (saved.isNotEmpty) return saved.endsWith('/') ? saved.substring(0, saved.length - 1) : saved;
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
    final searchUrl = '$domain/index.php?do=search&subaction=search&story=${Uri.encodeComponent(cleanTitle)}';

    debugPrint('VegamoviesResolver: Searching "$cleanTitle" on $searchUrl (OrigLang: $originalLanguage)');
    final sources = <StreamSourceInfo>[];

    try {
      var res = await http.get(
        Uri.parse(searchUrl),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        },
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode != 200 || !res.body.contains('.html')) {
        final fallbackUrl = '$domain/?s=${Uri.encodeComponent(cleanTitle)}';
        debugPrint('VegamoviesResolver: Fallback GET search $fallbackUrl');
        res = await http.get(
          Uri.parse(fallbackUrl),
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
          },
        ).timeout(const Duration(seconds: 10));
      }

      if (res.statusCode != 200) {
        debugPrint('VegamoviesResolver: Search HTTP status ${res.statusCode}');
        return [];
      }

      final html = res.body;
      final postUrls = _extractPostUrls(html, domain, cleanTitle);
      if (postUrls.isEmpty) {
        debugPrint('VegamoviesResolver: No posts found for "$cleanTitle"');
        return [];
      }

      // Process top matching posts (up to 3)
      final postsToProcess = postUrls.take(3).toList();
      for (final targetPostUrl in postsToProcess) {
        debugPrint('VegamoviesResolver: Inspecting post $targetPostUrl');

        final postRes = await http.get(
          Uri.parse(targetPostUrl),
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
          },
        ).timeout(const Duration(seconds: 10));

        if (postRes.statusCode == 200) {
          final postHtml = postRes.body;
          final links = _extractStreamLinks(postHtml, targetPostUrl, title, originalLanguage, domain);
          sources.addAll(links);
        }
      }
    } catch (e) {
      debugPrint('VegamoviesResolver error: $e');
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

    // Sort streams: prioritize original language & Slast native player
    if (originalLanguage != null && originalLanguage.isNotEmpty) {
      final langLower = originalLanguage.toLowerCase();
      uniqueSources.sort((a, b) {
        final aMatch = a.name.toLowerCase().contains(langLower);
        final bMatch = b.name.toLowerCase().contains(langLower);
        if (aMatch && !bMatch) return -1;
        if (!aMatch && bMatch) return 1;
        return 0;
      });
    }

    debugPrint('VegamoviesResolver: Resolved ${uniqueSources.length} sources');
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

  static List<String> _extractPostUrls(String html, String domain, String cleanQuery) {
    final urls = <String>[];
    final words = cleanQuery.toLowerCase().split(' ').where((w) => w.length > 2).toList();
    
    // Pattern 1: Links ending with .html
    final htmlRegex = RegExp(r'href="([^"]+\.html)"', caseSensitive: false);
    for (final m in htmlRegex.allMatches(html)) {
      var u = m.group(1);
      if (u != null) {
        if (u.startsWith('/')) u = '$domain$u';
        final lower = u.toLowerCase();
        if (!lower.contains('/category/') &&
            !lower.contains('/page/') &&
            !lower.contains('/tag/') &&
            !lower.contains('request') &&
            !lower.contains('dmca') &&
            !urls.contains(u)) {
          if (words.isEmpty || words.any((w) => lower.contains(w))) {
            urls.add(u);
          }
        }
      }
    }

    // Pattern 2: Rel bookmark links
    final bookmarkRegex = RegExp(r'<a\s+[^>]*href="([^"]+)"[^>]*rel="bookmark"[^>]*>', caseSensitive: false);
    for (final m in bookmarkRegex.allMatches(html)) {
      var u = m.group(1);
      if (u != null) {
        if (u.startsWith('/')) u = '$domain$u';
        if (!urls.contains(u)) urls.add(u);
      }
    }

    return urls;
  }

  static List<StreamSourceInfo> _extractStreamLinks(
    String html,
    String postUrl,
    String movieTitle,
    String? origLang,
    String domain,
  ) {
    final sources = <StreamSourceInfo>[];
    final langTag = (origLang != null && origLang.isNotEmpty) ? origLang : 'Original';

    // Extract post title for quality / audio info if available
    final titleMatch = RegExp(r'<h1[^>]*>([\s\S]*?)<\/h1>', caseSensitive: false).firstMatch(html);
    final postTitle = titleMatch != null ? titleMatch.group(1)!.replaceAll(RegExp(r'<[^>]+>'), '').trim() : '';

    String quality = 'HD';
    if (postTitle.contains('2160p') || postTitle.contains('4K')) {
      quality = '2160p 4K';
    } else if (postTitle.contains('1080p')) {
      quality = '1080p';
    } else if (postTitle.contains('720p')) {
      quality = '720p';
    } else if (postTitle.contains('480p')) {
      quality = '480p';
    } else if (postTitle.toLowerCase().contains('hdtc') || postTitle.toLowerCase().contains('cam')) {
      quality = 'HDTC / CAM';
    }

    final isMultiAudio = html.contains('Multi Audio') || html.contains('Dual Audio') || postTitle.contains('Dual');
    final audioTag = isMultiAudio ? 'Dual Audio' : langTag;

    // 1. Check for IndStreamPlayerConfigs (Slast Native Embedded Player)
    final configMatch = RegExp(r'IndStreamPlayerConfigs\s*=\s*\{[\s\S]*?src\s*:\s*["\x27]([^"\x27]+)["\x27]', caseSensitive: false).firstMatch(html);
    if (configMatch != null) {
      final srcId = configMatch.group(1)!;

      final translators = [
        {'tr': '8', 'label': 'Malayalam (HD)', 'quality': '1080p / 720p HD'},
        {'tr': '4', 'label': 'Hindi (LiNE / Dual Audio)', 'quality': quality},
        {'tr': '3', 'label': 'Tamil (HDTC / CAM)', 'quality': 'HDTC / CAM'},
        {'tr': '2', 'label': 'Telugu (HD)', 'quality': '1080p / 720p HD'},
        {'tr': '5', 'label': 'Kannada (HD)', 'quality': '1080p / 720p HD'},
      ];

      for (final item in translators) {
        final tr = item['tr']!;
        final label = item['label']!;
        final q = item['quality']!;
        final slastUrl = 'https://slast430did.com/play/$srcId?tr=$tr';

        sources.add(
          StreamSourceInfo(
            name: label,
            url: slastUrl,
            type: StreamSourceType.vegamovies,
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
              'Referer': '$domain/',
            },
            quality: q,
          ),
        );
      }
    } else {
      // Fallback: use post URL to resolve embed stream
      sources.add(
        StreamSourceInfo(
          name: '$movieTitle • Vegamovies Web Stream ($quality • $audioTag)',
          url: postUrl,
          type: StreamSourceType.vegamovies,
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
            'Referer': '$domain/',
          },
          quality: quality,
        ),
      );
    }

    return sources;
  }
}
