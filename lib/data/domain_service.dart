import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class DomainService {
  static const String _primaryUrl =
      'https://raw.githubusercontent.com/phisher98/TVVVV/refs/heads/main/domains.json';
  static const String _fallbackUrl =
      'https://raw.githubusercontent.com/SaurabhKaperwan/Utils/refs/heads/main/urls.json';

  static const String _cacheKey = 'dynamic_domains_cache';
  static const String _lastFetchKey = 'dynamic_domains_last_fetch';
  static const Duration _cacheTtl = Duration(hours: 6);

  static final Map<String, String> _inMemoryDomains = {
    'hdhub4u': 'https://new5.hdhub4u.cl',
    '4khdhub': 'https://4khdhub.one',
    'moviesdrive': 'https://new3.moviesdrive.christmas',
    'vegamovies': 'https://vegamovies.catering',
    'bollyflix': 'https://bollyflix.af',
    'uhdmovies': 'https://uhdmovies.autos',
    'multimovies': 'https://multimovies.makeup',
    'moviesmod': 'https://moviesmod.army',
    'hdmovie2': 'https://hdmovie2a.cfd',
    'tamilblasters': 'https://www.1tamilblasters.sale',
    'dudefilms': 'https://dudefilms.garden',
    'nfmirror': 'https://tv.imgcdn.kim/newtv',
    'cinefreak': 'https://cinefreak.nl',
    'movies4u': 'https://new5.movies4u.clinic',
    'topmovies': 'https://moviesleech.bar',
    'toonstream': 'https://toon-stream.site',
  };

  static bool _hasInitialized = false;

  /// Initializes domain cache from SharedPreferences and triggers a background refresh if expired.
  static Future<void> init() async {
    if (_hasInitialized) return;
    _hasInitialized = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString(_cacheKey);
      if (cachedJson != null && cachedJson.isNotEmpty) {
        final Map<String, dynamic> decoded = jsonDecode(cachedJson);
        decoded.forEach((k, v) {
          if (v != null && v.toString().trim().isNotEmpty) {
            _inMemoryDomains[k.toLowerCase().trim()] =
                v.toString().trim().replaceAll(RegExp(r'/+$'), '');
          }
        });
      }

      final lastFetch = prefs.getInt(_lastFetchKey) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - lastFetch > _cacheTtl.inMilliseconds || _inMemoryDomains.isEmpty) {
        refreshDomains();
      }
    } catch (e) {
      debugPrint('DomainService.init error: $e');
    }
  }

  /// Refreshes domains from remote GitHub configs and updates cache.
  static Future<void> refreshDomains() async {
    try {
      Map<String, dynamic>? fetchedMap;

      // Try primary TVVVV repo
      try {
        final res = await http
            .get(Uri.parse(_primaryUrl), headers: {'User-Agent': 'Mozilla/5.0'})
            .timeout(const Duration(seconds: 6));
        if (res.statusCode == 200) {
          fetchedMap = jsonDecode(res.body) as Map<String, dynamic>?;
        }
      } catch (_) {}

      // Fallback repo if primary fails
      if (fetchedMap == null || fetchedMap.isEmpty) {
        try {
          final res = await http
              .get(Uri.parse(_fallbackUrl), headers: {'User-Agent': 'Mozilla/5.0'})
              .timeout(const Duration(seconds: 6));
          if (res.statusCode == 200) {
            fetchedMap = jsonDecode(res.body) as Map<String, dynamic>?;
          }
        } catch (_) {}
      }

      if (fetchedMap != null && fetchedMap.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        fetchedMap.forEach((k, v) {
          if (v != null && v.toString().trim().isNotEmpty) {
            final cleanUrl = v.toString().trim().replaceAll(RegExp(r'/+$'), '');
            _inMemoryDomains[k.toLowerCase().trim()] = cleanUrl;
          }
        });

        await prefs.setString(_cacheKey, jsonEncode(_inMemoryDomains));
        await prefs.setInt(_lastFetchKey, DateTime.now().millisecondsSinceEpoch);
        debugPrint('DomainService: successfully refreshed ${_inMemoryDomains.length} domains');
      }
    } catch (e) {
      debugPrint('DomainService.refreshDomains error: $e');
    }
  }

  /// Gets the latest active domain for a provider synchronously.
  static String getDomainSync(String key, {String? defaultFallback}) {
    final lowerKey = key.toLowerCase().trim();
    if (_inMemoryDomains.containsKey(lowerKey)) {
      return _inMemoryDomains[lowerKey]!;
    }
    return defaultFallback ?? '';
  }

  /// Gets the latest active domain for a provider asynchronously (ensures initialized).
  static Future<String> getDomain(String key, {String? defaultFallback}) async {
    await init();
    return getDomainSync(key, defaultFallback: defaultFallback);
  }
}
