import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:private_cinema_mobile/models/movie.dart';
import 'package:private_cinema_mobile/utils/logo_cache_manager.dart';

class LogoService {
  static final Map<String, String> _memCache = {};
  static final Map<String, DateTime> _temporaryFailures = {};
  static SharedPreferences? _prefs;

  static const String _tmdbApiKey = '8baba8ab6b8bbe247645bcae7df63d0d';

  static String getCacheKey(Movie movie) {
    return 'logo_cache_${movie.tmdbId ?? movie.id}_${movie.title.hashCode}';
  }

  static Future<void> init() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
    } catch (_) {}
  }

  /// Synchronous instant check for 0ms frame rendering
  static String? getCachedLogoSync(Movie movie) {
    if (movie.logoUrl != null && movie.logoUrl!.isNotEmpty) {
      return movie.logoUrl;
    }
    final key = getCacheKey(movie);
    if (_memCache.containsKey(key)) {
      final val = _memCache[key];
      return (val != null && val.isNotEmpty) ? val : null;
    }
    if (_prefs != null) {
      final val = _prefs!.getString(key);
      if (val != null && val.isNotEmpty) {
        _memCache[key] = val;
        return val;
      }
    }
    return null;
  }

  /// Resolves the movie ClearLogo with multi-tier permanent local caching.
  /// Positive results are saved permanently to disk.
  /// Temporary network failures are NOT permanently cached so future retries succeed.
  static Future<String?> resolveLogo(Movie movie, {bool forceRefresh = false}) async {
    // 0. Explicit model property
    if (!forceRefresh && movie.logoUrl != null && movie.logoUrl!.isNotEmpty) {
      return movie.logoUrl;
    }

    final key = getCacheKey(movie);

    // 1. Memory cache check (0ms)
    if (!forceRefresh && _memCache.containsKey(key)) {
      final val = _memCache[key];
      if (val != null && val.isNotEmpty) return val;
    }

    // 2. SharedPreferences permanent disk cache check
    _prefs ??= await SharedPreferences.getInstance();
    if (!forceRefresh) {
      final diskCached = _prefs!.getString(key);
      if (diskCached != null && diskCached.isNotEmpty) {
        _memCache[key] = diskCached;
        return diskCached;
      }
    }

    // Avoid aggressive retry spamming within 30 seconds if failed
    if (!forceRefresh && _temporaryFailures.containsKey(key)) {
      final failedAt = _temporaryFailures[key]!;
      if (DateTime.now().difference(failedAt).inSeconds < 30) {
        return null;
      }
    }

    String? logoUrl;
    final rawId = movie.tmdbId?.toString() ?? movie.id;

    // 3. Hosted backend server check
    if (rawId.isNotEmpty && rawId != '0' && rawId != 'null') {
      final serverLogoUrl = 'https://ot.goprivate.fun/uploads/logos/$rawId.png';
      try {
        final res = await http.head(Uri.parse(serverLogoUrl)).timeout(const Duration(seconds: 5));
        if (res.statusCode == 200) {
          logoUrl = serverLogoUrl;
        }
      } catch (_) {}
    }

    // 4. Direct TMDB images endpoint query (No language filter to catch all regional / global logos)
    if (logoUrl == null && rawId.isNotEmpty && int.tryParse(rawId) != null) {
      final isTv = movie.genre.toLowerCase().contains('tv') || movie.genre.toLowerCase().contains('series');
      final firstType = isTv ? 'tv' : 'movie';
      final secondType = isTv ? 'movie' : 'tv';

      logoUrl = await _fetchTmdbLogo(firstType, rawId);
      logoUrl ??= await _fetchTmdbLogo(secondType, rawId);
    }

    // 5. Fallback TMDB title search (Supports subtitle cleanup, multi-language, and year matching)
    if (logoUrl == null) {
      logoUrl = await _searchTmdbLogo(movie.title, yearHint: movie.year);
    }

    if (logoUrl != null && logoUrl.isNotEmpty) {
      _memCache[key] = logoUrl;
      _temporaryFailures.remove(key);
      await _prefs!.setString(key, logoUrl);

      // Download image bytes into permanent disk cache in background
      unawaited(_cacheImageBytes(logoUrl));
      return logoUrl;
    } else {
      _temporaryFailures[key] = DateTime.now();
      return null;
    }
  }

  static Future<void> _cacheImageBytes(String url) async {
    try {
      await LogoCacheManager.instance.downloadFile(url);
    } catch (_) {}
  }

  /// Pre-caches logos for a list of movies in parallel
  static Future<void> precacheLogos(List<Movie> movies) async {
    if (movies.isEmpty) return;
    try {
      _prefs ??= await SharedPreferences.getInstance();
      final futures = <Future>[];
      for (final m in movies) {
        final key = getCacheKey(m);
        if (!_memCache.containsKey(key)) {
          futures.add(resolveLogo(m));
        }
      }
      if (futures.isNotEmpty) {
        await Future.wait(futures.take(20));
      }
    } catch (e) {
      debugPrint('Error precaching logos: $e');
    }
  }

  static Future<String?> _fetchTmdbLogo(String type, String id) async {
    try {
      final url = Uri.parse(
        'https://api.themoviedb.org/3/$type/$id/images?api_key=$_tmdbApiKey',
      );
      final res = await http.get(url).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        final logos = data['logos'] as List?;
        if (logos != null && logos.isNotEmpty) {
          final sorted = List<Map<String, dynamic>>.from(logos)
            ..sort((a, b) {
              final aLang = a['iso_639_1']?.toString() ?? '';
              final bLang = b['iso_639_1']?.toString() ?? '';
              if (aLang == 'en' && bLang != 'en') return -1;
              if (bLang == 'en' && aLang != 'en') return 1;
              final aVote = (a['vote_average'] as num?)?.toDouble() ?? 0;
              final bVote = (b['vote_average'] as num?)?.toDouble() ?? 0;
              return bVote.compareTo(aVote);
            });
          final filePath = sorted.first['file_path']?.toString();
          if (filePath != null && filePath.isNotEmpty) {
            return 'https://image.tmdb.org/t/p/w300$filePath';
          }
        }
      }
    } catch (_) {}
    return null;
  }

  static String _cleanTitle(String rawTitle) {
    String t = rawTitle;
    t = t.replaceAll(RegExp(r'\[.*?\]'), '');
    t = t.replaceAll(RegExp(r'\(\d{4}\)'), '');
    t = t.replaceAll(
      RegExp(r'\b(MAL|MALAYALAM|TAM|TAMIL|HIN|HINDI|TEL|TELUGU|KAN|KANNADA|ENG|ENGLISH|MAR|MARATHI|BEN|BENGALI|PUN|PUNJABI|GUJ|GUJARATI|ORI|ORIYA|KOR|KOREAN|JAP|JAPANESE)\b', caseSensitive: false),
      '',
    );
    t = t.replaceAll(
      RegExp(r'\b(4K|8K|2160P|1080P|720P|480P|360P|FHD|UHD|HD|SD|HDR|HDR10|HEVC|H264|H265|X264|X265|WEB-?DL|WEBRIP|BLURAY|DV|PROPER|REPACK|HQ|REMUX|ESUB|MSUB|SUB|DUB|DUBBED|DUAL|MULTI|AAC|DTS|DD5\.1|5\.1|AUDIO)\b', caseSensitive: false),
      '',
    );
    t = t.replaceAll(RegExp(r'[\-\|\:_]+'), ' ');
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static Future<String?> _searchTmdbLogo(String rawTitle, {int? yearHint}) async {
    try {
      final clean = _cleanTitle(rawTitle);
      if (clean.isEmpty) return null;

      int? year = yearHint;
      if (year == null) {
        final yearMatch = RegExp(r'\((\d{4})\)').firstMatch(rawTitle) ?? RegExp(r'\b(19\d\d|20\d\d)\b').firstMatch(rawTitle);
        if (yearMatch != null) {
          year = int.tryParse(yearMatch.group(1) ?? '');
        }
      }

      final encoded = Uri.encodeComponent(clean);

      // Search movie with year if available
      if (year != null && year > 1950) {
        final urlWithYear = Uri.parse(
          'https://api.themoviedb.org/3/search/movie?api_key=$_tmdbApiKey&query=$encoded&year=$year',
        );
        final res = await http.get(urlWithYear).timeout(const Duration(seconds: 6));
        if (res.statusCode == 200) {
          final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
          final results = data['results'] as List?;
          if (results != null && results.isNotEmpty) {
            final id = results.first['id']?.toString();
            if (id != null) {
              final logo = await _fetchTmdbLogo('movie', id);
              if (logo != null) return logo;
            }
          }
        }
      }

      // Search multi without year restriction
      final multiUrl = Uri.parse(
        'https://api.themoviedb.org/3/search/multi?api_key=$_tmdbApiKey&query=$encoded',
      );
      final res = await http.get(multiUrl).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        final results = data['results'] as List?;
        if (results != null && results.isNotEmpty) {
          final first = results.first;
          final id = first['id']?.toString();
          final type = first['media_type']?.toString() ?? 'movie';
          if (id != null) {
            return await _fetchTmdbLogo(type, id);
          }
        }
      }
    } catch (_) {}
    return null;
  }
}
