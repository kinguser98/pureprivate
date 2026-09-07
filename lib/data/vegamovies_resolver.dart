import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'domain_service.dart';
import '../widgets/special_search_dialog.dart';

class VegamoviesResolver {
  static const String _defaultDomain = 'https://vegamoviess.xyz';

  static Future<String> getBaseDomain() async {
    return _defaultDomain;
  }

  static Future<List<StreamSourceInfo>> resolveStreams({
    required String title,
    required int year,
    String? originalLanguage,
    String? imdbId,
    int? season,
    int? episode,
    bool isSeries = false,
  }) async {
    final sources = <StreamSourceInfo>[];

    // If imdbId is already provided, attempt direct player resolution first
    if (imdbId != null && imdbId.startsWith('tt')) {
      debugPrint('VegamoviesResolver: Trying direct embed player for IMDb ID $imdbId');
      final directStreams = await _resolveEmbedPlayer(imdbId, 'https://vegamoviess.xyz');
      if (directStreams.isNotEmpty) {
        return directStreams;
      }
    }

    final domain = await getBaseDomain();
    final cleanTitle = _cleanQuery(title);
    final searchUrl = '$domain/index.php?do=search&subaction=search&story=${Uri.encodeComponent(cleanTitle)}';

    debugPrint('VegamoviesResolver: Searching "$cleanTitle" on $searchUrl');

    try {
      final res = await http.get(
        Uri.parse(searchUrl),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
          'Referer': '$domain/',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        },
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) {
        debugPrint('VegamoviesResolver: Search HTTP status ${res.statusCode}');
        return [];
      }

      String searchHtml = res.body;
      var articleMatches = RegExp(r'<article[\s\S]*?<\/article>', caseSensitive: false).allMatches(searchHtml).toList();

      // Fallback search variant if initial search produced 0 articles
      if (articleMatches.isEmpty) {
        final words = cleanTitle.split(' ').where((w) => w.length > 2).toList();
        if (words.isNotEmpty) {
          final fallbackQuery = words.first;
          final fbUrl = '$domain/index.php?do=search&subaction=search&story=${Uri.encodeComponent(fallbackQuery)}';
          debugPrint('VegamoviesResolver: Trying fallback search "$fallbackQuery"');
          try {
            final fbRes = await http.get(
              Uri.parse(fbUrl),
              headers: {
                'User-Agent':
                    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
                'Referer': '$domain/',
              },
            ).timeout(const Duration(seconds: 6));
            if (fbRes.statusCode == 200) {
              articleMatches = RegExp(r'<article[\s\S]*?<\/article>', caseSensitive: false).allMatches(fbRes.body).toList();
            }
          } catch (_) {}
        }
      }

      if (articleMatches.isEmpty) {
        debugPrint('VegamoviesResolver: No articles found for "$cleanTitle"');
        return [];
      }

      final queryWords = cleanTitle.toLowerCase().split(' ').where((w) => w.length > 2).toList();
      final List<String> targetPostUrls = [];

      for (final a in articleMatches) {
        final aHtml = a.group(0) ?? '';
        final linkMatch = RegExp(r'href="([^"]+)"', caseSensitive: false).firstMatch(aHtml);
        final titleMatch = RegExp(r'(?:title|alt)="([^"]+)"', caseSensitive: false).firstMatch(aHtml);
        if (linkMatch == null) continue;

        final link = linkMatch.group(1)!;
        final postTitle = (titleMatch?.group(1) ?? '').toLowerCase();

        if (queryWords.isEmpty || queryWords.any((w) => postTitle.contains(w))) {
          final fullUrl = link.startsWith('http') ? link : '$domain$link';
          if (!targetPostUrls.contains(fullUrl)) {
            targetPostUrls.add(fullUrl);
          }
        }
        if (targetPostUrls.length >= 2) break;
      }

      // If no post matched keywords specifically, use the top article
      if (targetPostUrls.isEmpty && articleMatches.isNotEmpty) {
        final topMatch = RegExp(r'href="([^"]+)"', caseSensitive: false).firstMatch(articleMatches.first.group(0) ?? '');
        if (topMatch != null) {
          final l = topMatch.group(1)!;
          targetPostUrls.add(l.startsWith('http') ? l : '$domain$l');
        }
      }

      for (final postUrl in targetPostUrls) {
        debugPrint('VegamoviesResolver: Inspecting post $postUrl');

        final postRes = await http.get(
          Uri.parse(postUrl),
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
            'Referer': '$domain/',
          },
        ).timeout(const Duration(seconds: 8));

        if (postRes.statusCode == 200) {
          final postHtml = postRes.body;
          // Extract IMDb ID from IndStreamPlayerConfigs or HTML
          final playerConfigMatch = RegExp(r"""src:\s*['"](tt\d+)['"]""", caseSensitive: false).firstMatch(postHtml);
          String? foundImdbId = playerConfigMatch?.group(1);
          if (foundImdbId == null) {
            final directMatch = RegExp(r'tt\d{7,8}').firstMatch(postHtml);
            foundImdbId = directMatch?.group(0);
          }

          if (foundImdbId != null) {
            debugPrint('VegamoviesResolver: Found IMDb ID $foundImdbId in post');
            final streams = await _resolveEmbedPlayer(foundImdbId, domain);
            sources.addAll(streams);
            if (sources.isNotEmpty) break;
          }
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

    // Priority sorting: Malayalam first, then Tamil, Telugu, Hindi, etc.
    uniqueSources.sort((a, b) {
      int langRank(String name) {
        final n = name.toLowerCase();
        if (n.contains('malayalam')) return 0;
        if (n.contains('tamil')) return 1;
        if (n.contains('telugu')) return 2;
        if (n.contains('kannada')) return 3;
        if (n.contains('hindi')) return 4;
        return 5;
      }
      return langRank(a.name).compareTo(langRank(b.name));
    });

    debugPrint('VegamoviesResolver: Resolved ${uniqueSources.length} streams from embedded player');
    return uniqueSources;
  }

  /// Resolves direct HLS streams from Vegamovies embedded player (slast430did / hutro433fil)
  static Future<List<StreamSourceInfo>> _resolveEmbedPlayer(String imdbId, String domain) async {
    final results = <StreamSourceInfo>[];
    try {
      final slastUrl = 'https://slast430did.com/play/$imdbId';
      debugPrint('VegamoviesResolver: Fetching player page $slastUrl');

      final slastRes = await http.get(
        Uri.parse(slastUrl),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
          'Referer': '$domain/',
        },
      ).timeout(const Duration(seconds: 8));

      if (slastRes.statusCode != 200) {
        debugPrint('VegamoviesResolver: Slast returned status ${slastRes.statusCode}');
        return [];
      }

      final p3Match = RegExp(r'let\s+p3\s*=\s*(\{[\s\S]*?\});\s*var\s+ppl').firstMatch(slastRes.body);
      if (p3Match == null) {
        debugPrint('VegamoviesResolver: p3 config not found in player page');
        return [];
      }

      final p3Json = jsonDecode(p3Match.group(1)!);
      final fileUrl = p3Json['file'] as String?;
      final key = p3Json['key'] as String?;

      if (fileUrl == null || key == null) return [];

      // Step 1: POST to p3.file to get playlist items
      final post1Res = await http.post(
        Uri.parse(fileUrl),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'X-CSRF-TOKEN': key,
          'Referer': 'https://slast430did.com/',
          'Origin': 'https://slast430did.com',
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        },
      ).timeout(const Duration(seconds: 8));

      if (post1Res.statusCode != 200) {
        debugPrint('VegamoviesResolver: Post 1 failed with status ${post1Res.statusCode}');
        return [];
      }

      final dynamic playlistData = jsonDecode(post1Res.body);
      final playlistItems = playlistData is List ? playlistData : [];
      final basePath = fileUrl.substring(0, fileUrl.lastIndexOf('/') + 1);

      for (final item in playlistItems) {
        if (item is Map && item['file'] != null) {
          final trackTitle = item['title']?.toString() ?? 'Multi-Audio';
          String fileToken = item['file'].toString();
          if (fileToken.startsWith('~')) fileToken = fileToken.substring(1);
          final post2Url = '$basePath$fileToken.txt';

          try {
            final post2Res = await http.post(
              Uri.parse(post2Url),
              headers: {
                'Content-Type': 'application/x-www-form-urlencoded',
                'X-CSRF-TOKEN': key,
                'Referer': 'https://slast430did.com/',
                'Origin': 'https://slast430did.com',
                'User-Agent':
                    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
              },
            ).timeout(const Duration(seconds: 8));

            if (post2Res.statusCode == 200) {
              final m3u8Url = post2Res.body.trim();
              if (m3u8Url.startsWith('http') && m3u8Url.contains('.m3u8')) {
                results.add(
                  StreamSourceInfo(
                    name: 'Vegamovies • $trackTitle',
                    url: m3u8Url,
                    type: StreamSourceType.vegamovies,
                    quality: '1080p Multi-Quality',
                    languages: [trackTitle],
                    headers: {
                      'Referer': 'https://slast430did.com/',
                      'User-Agent':
                          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
                    },
                  ),
                );
              }
            }
          } catch (e) {
            debugPrint('VegamoviesResolver: Error resolving track $trackTitle: $e');
          }
        }
      }

      // Priority sorting: Malayalam first, then Tamil, Telugu, Hindi, etc.
      results.sort((a, b) {
        int langRank(String name) {
          final n = name.toLowerCase();
          if (n.contains('malayalam')) return 0;
          if (n.contains('tamil')) return 1;
          if (n.contains('telugu')) return 2;
          if (n.contains('kannada')) return 3;
          if (n.contains('hindi')) return 4;
          return 5;
        }
        return langRank(a.name).compareTo(langRank(b.name));
      });
    } catch (e) {
      debugPrint('VegamoviesResolver: _resolveEmbedPlayer error: $e');
    }
    return results;
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
}
