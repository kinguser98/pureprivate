import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../widgets/special_search_dialog.dart';

class StreamplayResolver {
  static const String _tmdbApiKey = '1865f43a0549ca50d341dd9ab8b29f49';
  static const Duration _timeout = Duration(seconds: 8);

  static const String _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36';

  /// Resolves streams across multiple fast API endpoints (VidLink, Videasy, MoviesApi, VidFast, VidZee).
  static Future<List<StreamSourceInfo>> resolveStreams({
    required String title,
    String? year,
    String? tmdbId,
    String? imdbId,
    bool isSeries = false,
    int? season,
    int? episode,
  }) async {
    final List<StreamSourceInfo> results = [];

    // 1. Resolve TMDB ID if missing
    String? effectiveTmdbId = tmdbId;
    String? effectiveImdbId = imdbId;

    if (effectiveTmdbId == null || effectiveTmdbId.isEmpty) {
      final (resolvedTmdb, resolvedImdb) =
          await _lookupTmdb(title: title, year: year, isSeries: isSeries);
      effectiveTmdbId = resolvedTmdb;
      effectiveImdbId ??= resolvedImdb;
    }

    if (effectiveTmdbId == null || effectiveTmdbId.isEmpty) {
      debugPrint('StreamplayResolver: Unable to resolve TMDB ID for "$title"');
      return [];
    }

    final s = isSeries ? (season ?? 1) : 1;
    final ep = isSeries ? (episode ?? 1) : 1;

    final playHeaders = {
      'User-Agent': 'Lavf/58.76.100',
    };

    // 2. Fire extractors in parallel with independent error handling
    final futures = <Future<List<StreamSourceInfo>>>[
      _resolveVidLink(effectiveTmdbId, isSeries, s, ep, playHeaders),
      _resolveMoviesApi(effectiveTmdbId, isSeries, s, ep),
      _resolveVideasy(effectiveTmdbId, isSeries, s, ep),
      _resolveVidFast(effectiveTmdbId, isSeries, s, ep),
      if (effectiveImdbId != null && effectiveImdbId.isNotEmpty)
        _resolveVidSrcSu(effectiveImdbId, isSeries, s, ep),
    ];

    final resolvedLists = await Future.wait(futures);
    for (final list in resolvedLists) {
      results.addAll(list);
    }

    debugPrint(
        'StreamplayResolver: Resolved ${results.length} streams for "$title" (TMDB: $effectiveTmdbId)');
    return results;
  }

  /// Looks up TMDB ID and IMDb ID by title and year.
  static Future<(String?, String?)> _lookupTmdb({
    required String title,
    String? year,
    required bool isSeries,
  }) async {
    try {
      final cleanTitle =
          Uri.encodeComponent(title.replaceAll(RegExp(r'\(.*?\)'), '').trim());
      final type = isSeries ? 'tv' : 'movie';
      final yrParam = year != null && year.isNotEmpty
          ? (isSeries ? '&first_air_date_year=$year' : '&year=$year')
          : '';
      final url =
          'https://api.themoviedb.org/3/search/$type?api_key=$_tmdbApiKey&query=$cleanTitle$yrParam';

      final res =
          await http.get(Uri.parse(url), headers: {'User-Agent': _ua}).timeout(_timeout);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final results = data['results'] as List? ?? [];
        if (results.isNotEmpty) {
          final first = results.first as Map;
          final id = first['id']?.toString();
          return (id, null);
        }
      }
    } catch (e) {
      debugPrint('StreamplayResolver TMDB lookup error: $e');
    }
    return (null, null);
  }

  /// VidLink Extractor with Encrypted Token Gateway
  static Future<List<StreamSourceInfo>> _resolveVidLink(
    String tmdbId,
    bool isSeries,
    int season,
    int episode,
    Map<String, String> playHeaders,
  ) async {
    final sources = <StreamSourceInfo>[];
    try {
      // 1. Get encrypted token from gateway
      String effectiveKey = tmdbId;
      try {
        final encRes = await http
            .get(
              Uri.parse('https://enc-dec.app/api/enc-vidlink?text=$tmdbId'),
              headers: {'User-Agent': _ua},
            )
            .timeout(const Duration(seconds: 4));
        if (encRes.statusCode == 200) {
          final encData = jsonDecode(encRes.body);
          if (encData['result'] != null && encData['result'].toString().isNotEmpty) {
            effectiveKey = encData['result'].toString();
          }
        }
      } catch (_) {}

      final url = isSeries
          ? 'https://vidlink.pro/api/b/tv/$effectiveKey/$season/$episode'
          : 'https://vidlink.pro/api/b/movie/$effectiveKey';

      final res = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': _ua,
          'Referer': 'https://vidlink.pro/',
          'Origin': 'https://vidlink.pro',
          'Accept': 'application/json, text/plain, */*',
        },
      ).timeout(_timeout);

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is Map) {
          // Direct stream url
          final streamObj = data['stream'];
          if (streamObj is Map) {
            final qualities = streamObj['qualities'];
            if (qualities is Map) {
              qualities.forEach((k, v) {
                if (v is Map && v['url'] != null) {
                  final u = v['url'].toString();
                  final codec = v['codecName']?.toString() ?? '';
                  final label =
                      'VidLink • ${k}p${codec.isNotEmpty ? " ($codec)" : ""}';
                  sources.add(StreamSourceInfo(
                    name: label,
                    url: u,
                    type: StreamSourceType.streamplay,
                    quality: '${k}p',
                    headers: playHeaders,
                  ));
                }
              });
            }

            final directUrl = streamObj['url']?.toString() ??
                streamObj['file']?.toString() ??
                '';
            if (directUrl.isNotEmpty && !sources.any((s) => s.url == directUrl)) {
              sources.add(StreamSourceInfo(
                name: 'VidLink • Auto 1080p (HLS)',
                url: directUrl,
                type: StreamSourceType.streamplay,
                quality: '1080p',
                headers: null,
              ));
            }
          }

          // Fallback root url
          final rootUrl = data['url']?.toString() ?? data['file']?.toString() ?? '';
          if (rootUrl.isNotEmpty && !sources.any((s) => s.url == rootUrl)) {
            sources.add(StreamSourceInfo(
              name: 'StreamPlay • VidLink Server • HD (Direct)',
              url: rootUrl,
              type: StreamSourceType.streamplay,
              quality: '1080p',
              headers: null,
            ));
          }
        }
      }
    } catch (e) {
      debugPrint('StreamplayResolver VidLink error: $e');
    }
    return sources;
  }

  /// MoviesApi.club Extractor
  static Future<List<StreamSourceInfo>> _resolveMoviesApi(
    String tmdbId,
    bool isSeries,
    int season,
    int episode,
  ) async {
    final sources = <StreamSourceInfo>[];
    try {
      final url = isSeries
          ? 'https://moviesapi.club/tv/$tmdbId-$season-$episode'
          : 'https://moviesapi.club/movie/$tmdbId';

      final res = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': _ua,
          'Referer': 'https://moviesapi.club/',
        },
      ).timeout(_timeout);

      if (res.statusCode == 200) {
        final body = res.body;
        final m3u8Regex =
            RegExp(r'''(https?://[^\s"'<>]+\.m3u8[^\s"'<>]*)''');
        final matches = m3u8Regex.allMatches(body);
        for (final m in matches) {
          final u = m.group(1);
          if (u != null && u.isNotEmpty && !sources.any((s) => s.url == u)) {
            sources.add(StreamSourceInfo(
              name: 'MoviesClub • 1080p (HLS)',
              url: u,
              type: StreamSourceType.streamplay,
              quality: '1080p',
              headers: {
                'Referer': 'https://moviesapi.club/',
                'User-Agent': _ua,
              },
            ));
          }
        }
      }
    } catch (e) {
      debugPrint('StreamplayResolver MoviesApi error: $e');
    }
    return sources;
  }

  /// Videasy Extractor
  static Future<List<StreamSourceInfo>> _resolveVideasy(
    String tmdbId,
    bool isSeries,
    int season,
    int episode,
  ) async {
    final sources = <StreamSourceInfo>[];
    try {
      final url = isSeries
          ? 'https://player.videasy.to/tv/$tmdbId/$season/$episode'
          : 'https://player.videasy.to/movie/$tmdbId';

      final res = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': _ua,
          'Referer': 'https://player.videasy.to/',
        },
      ).timeout(_timeout);

      if (res.statusCode == 200) {
        final body = res.body;
        final fileRegex = RegExp(
            r'''(?:file|source|url)\s*:\s*["'](https?://[^"']+\.m3u8[^"']*)["']''');
        final match = fileRegex.firstMatch(body);
        if (match != null && match.group(1) != null) {
          final streamUrl = match.group(1)!;
          sources.add(StreamSourceInfo(
            name: 'Videasy • 1080p (HLS)',
            url: streamUrl,
            type: StreamSourceType.streamplay,
            quality: '1080p',
            headers: {
              'Referer': 'https://player.videasy.to/',
              'User-Agent': _ua,
            },
          ));
        }
      }
    } catch (e) {
      debugPrint('StreamplayResolver Videasy error: $e');
    }
    return sources;
  }

  /// VidFast Extractor
  static Future<List<StreamSourceInfo>> _resolveVidFast(
    String tmdbId,
    bool isSeries,
    int season,
    int episode,
  ) async {
    final sources = <StreamSourceInfo>[];
    try {
      final url = isSeries
          ? 'https://vidfast.vc/tv/$tmdbId/$season/$episode'
          : 'https://vidfast.vc/movie/$tmdbId';

      final res = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': _ua,
          'Referer': 'https://vidfast.vc/',
        },
      ).timeout(_timeout);

      if (res.statusCode == 200) {
        final body = res.body;
        final m3u8Regex =
            RegExp(r'''(https?://[^\s"'<>]+\.m3u8[^\s"'<>]*)''');
        final match = m3u8Regex.firstMatch(body);
        if (match != null && match.group(1) != null) {
          sources.add(StreamSourceInfo(
            name: 'VidFast • Auto HD (HLS)',
            url: match.group(1)!,
            type: StreamSourceType.streamplay,
            quality: '1080p',
            headers: {
              'Referer': 'https://vidfast.vc/',
              'User-Agent': _ua,
            },
          ));
        }
      }
    } catch (e) {
      debugPrint('StreamplayResolver VidFast error: $e');
    }
    return sources;
  }

  /// VidSrc.su Extractor
  static Future<List<StreamSourceInfo>> _resolveVidSrcSu(
    String imdbId,
    bool isSeries,
    int season,
    int episode,
  ) async {
    final sources = <StreamSourceInfo>[];
    try {
      final url = isSeries
          ? 'https://vidsrc-embed.su/embed/tv?imdb=$imdbId&season=$season&episode=$episode'
          : 'https://vidsrc-embed.su/embed/movie?imdb=$imdbId';

      final res = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': _ua,
          'Referer': 'https://vidsrc-embed.su/',
        },
      ).timeout(_timeout);

      if (res.statusCode == 200) {
        final body = res.body;
        final m3u8Regex =
            RegExp(r'''(https?://[^\s"'<>]+\.m3u8[^\s"'<>]*)''');
        final match = m3u8Regex.firstMatch(body);
        if (match != null && match.group(1) != null) {
          sources.add(StreamSourceInfo(
            name: 'VidSrc Global • Auto HD (HLS)',
            url: match.group(1)!,
            type: StreamSourceType.streamplay,
            quality: '1080p',
            headers: {
              'Referer': 'https://vidsrc-embed.su/',
              'User-Agent': _ua,
            },
          ));
        }
      }
    } catch (e) {
      debugPrint('StreamplayResolver VidSrcSu error: $e');
    }
    return sources;
  }
}
