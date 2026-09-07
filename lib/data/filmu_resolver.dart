import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../widgets/special_search_dialog.dart';

class FilmuResolver {
  static const String _defaultApiHost = 'rive.filmu.in';
  static const String _apiKey = 'filmu_moviebox_key_v1';

  static const Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'Accept': 'application/json, text/plain, */*',
  };

  /// Resolves streaming sources from FilmU / RiveStream API.
  static Future<List<StreamSourceInfo>> resolveStreams({
    required String tmdbId,
    String? imdbId,
    required String title,
    String? year,
    int? season,
    int? episode,
    bool isSeries = false,
  }) async {
    final sources = <StreamSourceInfo>[];
    final mediaType = isSeries ? 'tv' : 'movie';
    final targetId = (imdbId != null && imdbId.isNotEmpty && imdbId.startsWith('tt'))
        ? imdbId
        : tmdbId;

    if (targetId.isEmpty && title.isEmpty) return [];

    debugPrint('[FilmuResolver] Resolving $mediaType targetId=$targetId tmdbId=$tmdbId title="$title"');

    // 1. Try /scrape/rivestream/$mediaType/$targetId or tmdbId
    try {
      final queryParams = <String, String>{
        'apikey': _apiKey,
        if (title.isNotEmpty) 'title': title,
        if (isSeries && season != null) 'season': season.toString(),
        if (isSeries && episode != null) 'episode': episode.toString(),
        if (tmdbId.isNotEmpty) 'tmdbId': tmdbId,
        if (year != null && year.isNotEmpty) 'year': year,
      };

      final idToScrape = tmdbId.isNotEmpty ? tmdbId : targetId;
      final uri = Uri.https(_defaultApiHost, '/scrape/rivestream/$mediaType/$idToScrape', queryParams);
      debugPrint('[FilmuResolver] Requesting: $uri');

      final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(utf8.decode(res.bodyBytes));
        final rawSources = data['sources'] as List<dynamic>? ?? data['streams'] as List<dynamic>? ?? [];

        for (final src in rawSources) {
          if (src is! Map) continue;
          final name = src['name']?.toString() ?? 'FilmU Server';
          final url = src['workerProxyUrl']?.toString() ?? src['url']?.toString() ?? '';
          final quality = src['quality']?.toString() ?? '1080p';
          final rawHeaders = src['headers'];
          final Map<String, String> resolvedHeaders = {};
          if (rawHeaders is Map) {
            rawHeaders.forEach((k, v) => resolvedHeaders[k.toString()] = v.toString());
          }

          if (url.isNotEmpty && url.startsWith('http')) {
            sources.add(StreamSourceInfo(
              name: 'FilmU: $name',
              url: url,
              type: StreamSourceType.filmu,
              quality: quality,
              headers: resolvedHeaders,
            ));
          }
        }
      }
    } catch (e) {
      debugPrint('[FilmuResolver] /scrape/rivestream attempt failed: $e');
    }

    // 2. If no sources yet, try /stream/$mediaType/$targetId?tmdbId=$tmdbId
    if (sources.isEmpty) {
      try {
        final queryParams = <String, String>{
          if (tmdbId.isNotEmpty) 'tmdbId': tmdbId,
          if (isSeries && season != null) 'season': season.toString(),
          if (isSeries && episode != null) 'episode': episode.toString(),
        };

        final uri = Uri.https(_defaultApiHost, '/stream/$mediaType/$targetId', queryParams);
        debugPrint('[FilmuResolver] Fallback requesting: $uri');

        final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 6));
        if (res.statusCode == 200) {
          final Map<String, dynamic> data = jsonDecode(utf8.decode(res.bodyBytes));
          final rawStreams = data['streams'] as List<dynamic>? ??
              data['sources'] as List<dynamic>? ??
              data['artplayer_sources'] as List<dynamic>? ??
              [];

          for (final item in rawStreams) {
            if (item is! Map) continue;
            final name = item['title']?.toString() ?? item['name']?.toString() ?? 'FilmU Fast';
            final url = item['url']?.toString() ?? '';
            final quality = item['quality']?.toString() ?? '1080p';
            final rawHeaders = item['headers'];
            final Map<String, String> resolvedHeaders = {};
            if (rawHeaders is Map) {
              rawHeaders.forEach((k, v) => resolvedHeaders[k.toString()] = v.toString());
            }

            if (url.isNotEmpty && url.startsWith('http')) {
              sources.add(StreamSourceInfo(
                name: 'FilmU: $name',
                url: url,
                type: StreamSourceType.filmu,
                quality: quality,
                headers: resolvedHeaders,
              ));
            }
          }
        }
      } catch (e) {
        debugPrint('[FilmuResolver] /stream fallback failed: $e');
      }
    }

    // Deduplicate sources
    final uniqueSources = <StreamSourceInfo>[];
    final seenUrls = <String>{};
    for (final s in sources) {
      if (!seenUrls.contains(s.url)) {
        seenUrls.add(s.url);
        uniqueSources.add(s);
      }
    }

    debugPrint('[FilmuResolver] Resolved ${uniqueSources.length} FilmU sources');
    return uniqueSources;
  }
}
