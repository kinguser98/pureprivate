import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/special_search_dialog.dart';

class CinejoyResolver {
  static const String _defaultDomain = 'https://cinejoy.to';

  static Future<String> getBaseDomain() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('domain_cinejoy') ?? '';
    if (saved.isNotEmpty) return saved.endsWith('/') ? saved.substring(0, saved.length - 1) : saved;
    return _defaultDomain;
  }

  static Future<List<StreamSourceInfo>> resolveStreams({
    required String title,
    required int year,
    String? tmdbId,
    int? season,
    int? episode,
    bool isSeries = false,
  }) async {
    final domain = await getBaseDomain();
    final sources = <StreamSourceInfo>[];

    debugPrint('CinejoyResolver: Resolving for "$title" (TMDB: $tmdbId) on $domain');

    if (tmdbId != null && tmdbId.isNotEmpty && tmdbId != 'null' && tmdbId != '0') {
      final playerPath = isSeries
          ? '/watch/tv/$tmdbId/${season ?? 1}/${episode ?? 1}'
          : '/watch/movie/$tmdbId';
      final streamUrl = '$domain$playerPath';

      sources.add(
        StreamSourceInfo(
          name: 'Cinejoy HD Server (1080p)',
          url: streamUrl,
          type: StreamSourceType.cinejoy,
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
            'Referer': '$domain/',
          },
          quality: '1080p',
        ),
      );

      // VidSrc auto-fallback player
      final vidsrcUrl = isSeries
          ? 'https://vidsrc.me/embed/tv?tmdb=$tmdbId&season=${season ?? 1}&episode=${episode ?? 1}'
          : 'https://vidsrc.me/embed/movie?tmdb=$tmdbId';

      sources.add(
        StreamSourceInfo(
          name: 'Cinejoy VidSrc Mirror (1080p)',
          url: vidsrcUrl,
          type: StreamSourceType.cinejoy,
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
            'Referer': '$domain/',
          },
          quality: '1080p',
        ),
      );
    }

    debugPrint('CinejoyResolver: Resolved ${sources.length} sources');
    return sources;
  }
}
