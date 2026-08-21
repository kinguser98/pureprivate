import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/special_search_dialog.dart';

class VegamoviesResolver {
  static const String _defaultDomain = 'https://vegamovies.se';

  static Future<String> getBaseDomain() async {
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
    final searchUrl = '$domain/?s=${Uri.encodeComponent(cleanTitle)}';

    debugPrint('VegamoviesResolver: Searching "$cleanTitle" on $searchUrl (OrigLang: $originalLanguage)');
    final sources = <StreamSourceInfo>[];

    try {
      final res = await http.get(
        Uri.parse(searchUrl),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        },
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode != 200) {
        debugPrint('VegamoviesResolver: Search HTTP status ${res.statusCode}');
        return [];
      }

      final html = res.body;
      final postUrls = _extractPostUrls(html, domain);
      if (postUrls.isEmpty) {
        debugPrint('VegamoviesResolver: No posts found for "$cleanTitle"');
        return [];
      }

      // Process top matching post
      final targetPostUrl = postUrls.first;
      debugPrint('VegamoviesResolver: Inspecting post $targetPostUrl');

      final postRes = await http.get(
        Uri.parse(targetPostUrl),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        },
      ).timeout(const Duration(seconds: 8));

      if (postRes.statusCode == 200) {
        final postHtml = postRes.body;
        final links = _extractStreamLinks(postHtml, title, originalLanguage);
        sources.addAll(links);
      }
    } catch (e) {
      debugPrint('VegamoviesResolver error: $e');
    }

    // Sort streams: prioritize original language over default Hindi
    if (originalLanguage != null && originalLanguage.isNotEmpty) {
      final langLower = originalLanguage.toLowerCase();
      sources.sort((a, b) {
        final aMatch = a.name.toLowerCase().contains(langLower);
        final bMatch = b.name.toLowerCase().contains(langLower);
        if (aMatch && !bMatch) return -1;
        if (!aMatch && bMatch) return 1;
        return 0;
      });
    }

    debugPrint('VegamoviesResolver: Resolved ${sources.length} sources');
    return sources;
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

  static List<String> _extractPostUrls(String html, String domain) {
    final matches = RegExp(r'href="(' + RegExp.escape(domain) + r'/[^"]+)"').allMatches(html);
    final urls = <String>[];
    for (final m in matches) {
      final u = m.group(1);
      if (u != null &&
          !u.contains('/category/') &&
          !u.contains('/page/') &&
          !u.contains('/tag/') &&
          !urls.contains(u)) {
        urls.add(u);
      }
    }
    return urls;
  }

  static List<StreamSourceInfo> _extractStreamLinks(String html, String movieTitle, String? origLang) {
    final sources = <StreamSourceInfo>[];
    
    final linkRegex = RegExp(r'href="(https?://[^"]+)"[^>]*>(.*?)</a>', caseSensitive: false, dotAll: true);
    final matches = linkRegex.allMatches(html);

    final langTag = (origLang != null && origLang.isNotEmpty) ? origLang : 'Original';

    for (final m in matches) {
      final url = m.group(1) ?? '';
      final labelText = m.group(2)?.replaceAll(RegExp(r'<[^>]*>'), '').trim() ?? '';

      if (url.isEmpty) continue;

      final u = url.toLowerCase();
      if (u.contains('vcloud') ||
          u.contains('fastcloud') ||
          u.contains('hubcloud') ||
          u.contains('drive') ||
          u.contains('download') ||
          u.contains('pixeldrain') ||
          u.contains('gdtot') ||
          u.contains('stream')) {
        
        String quality = 'HD';
        if (labelText.contains('1080p') || html.contains('1080p')) quality = '1080p';
        else if (labelText.contains('720p') || html.contains('720p')) quality = '720p';
        else if (labelText.contains('480p') || html.contains('480p')) quality = '480p';
        else if (labelText.contains('4K') || labelText.contains('2160p')) quality = '4K';

        final isMultiAudio = html.contains('Multi Audio') || html.contains('Dual Audio') || labelText.contains('Multi');
        final audioLabel = isMultiAudio ? 'Multi Audio ($langTag Default)' : langTag;
        final name = '$movieTitle • Vegamovies • $quality • $audioLabel';

        sources.add(
          StreamSourceInfo(
            name: name,
            url: url,
            type: StreamSourceType.vegamovies,
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
              'Referer': 'https://vegamovies.se/',
            },
            languages: isMultiAudio ? [langTag, 'Hindi'] : [langTag],
            quality: quality,
          ),
        );
      }
    }

    return sources;
  }
}
