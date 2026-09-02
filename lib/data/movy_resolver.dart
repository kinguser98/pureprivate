import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:private_cinema_mobile/widgets/special_search_dialog.dart';
import 'package:private_cinema_mobile/data/embed_resolver.dart';

class MovyResolver {
  static const String baseUrl = 'https://www.movy.bz';

  /// Build direct streaming web URL for a movie or TV episode
  static String buildMovieUrl(String tmdbId) {
    return '$baseUrl/movie/$tmdbId?play=true';
  }

  static String buildSeriesUrl(String tmdbId, int season, int episode) {
    return '$baseUrl/tv/$tmdbId?s=$season&e=$episode&play=true';
  }

  /// Resolves direct stream sources for a given movie using TMDB ID
  static Future<List<StreamSourceInfo>> resolveMovieStreams({
    required String tmdbId,
    String? title,
    String? year,
  }) async {
    if (tmdbId.isEmpty || tmdbId == '0' || tmdbId == 'null') return [];

    final targetUrl = buildMovieUrl(tmdbId);
    final sources = <StreamSourceInfo>[];

    try {
      // 1. Primary Movy.bz Multi-Source Link (Master Stream with 4K/1080p/720p/480p and Multi-Audio)
      sources.add(
        StreamSourceInfo(
          name: 'Movy.bz Multi-Source (4K/1080p/720p/480p Multi-Audio)',
          url: targetUrl,
          type: StreamSourceType.movy,
          addonName: 'Movy.bz',
          originalTitle: title ?? 'Movy Stream',
          quality: '4K/1080p/720p/480p Multi-Audio',
          languages: ['Multi-Audio', 'English', 'Tamil', 'Hindi', 'Telugu'],
          headers: {
            'Referer': '$baseUrl/',
            'Origin': baseUrl,
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
          },
        ),
      );
    } catch (e) {
      debugPrint('MovyResolver error: $e');
    }

    return sources;
  }

  /// Resolves direct stream sources for a given TV show episode
  static Future<List<StreamSourceInfo>> resolveSeriesStreams({
    required String tmdbId,
    required int season,
    required int episode,
    String? title,
  }) async {
    if (tmdbId.isEmpty || tmdbId == '0' || tmdbId == 'null') return [];

    final targetUrl = buildSeriesUrl(tmdbId, season, episode);
    final sources = <StreamSourceInfo>[];

    try {
      sources.add(
        StreamSourceInfo(
          name: 'Movy.bz S${season}E$episode (Multi-Audio)',
          url: targetUrl,
          type: StreamSourceType.movy,
          addonName: 'Movy.bz',
          originalTitle: '${title ?? 'TV Show'} S${season}E$episode',
          quality: '1080p HD',
          languages: ['Multi-Audio', 'English'],
          headers: {
            'Referer': '$baseUrl/',
            'Origin': baseUrl,
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
          },
        ),
      );
    } catch (e) {
      debugPrint('MovyResolver series error: $e');
    }

    return sources;
  }
}
