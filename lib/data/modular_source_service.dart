import 'package:private_cinema_mobile/data/cinefreak_resolver.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:private_cinema_mobile/data/sync_service.dart';
import 'package:private_cinema_mobile/data/domain_service.dart';
import 'package:private_cinema_mobile/widgets/stream_metadata_tile.dart';
import '../widgets/special_search_dialog.dart';

/// Stremio-Style Remote Source Module Service
/// Fetches streams from modular microservices hosted on shared hosting or remote backends,
/// enabling zero-rebuild source additions and domain updates across all devices.
class ModularSourceService {
  static final Map<String, String> _defaultModules = {
    'movieshunt': 'https://ot.goprivate.fun/sources/movieshunt.php',
    'hdhub4u': 'https://ot.goprivate.fun/sources/hdhub4u.php',
    'moviesdrive': 'https://ot.goprivate.fun/sources/moviesdrive.php',
    'vegamovies': 'https://ot.goprivate.fun/sources/vegamovies.php',
    'cinejoy': 'https://ot.goprivate.fun/sources/cinejoy.php',
    'filmu': 'https://ot.goprivate.fun/sources/filmu.php',
    'istreamflare': 'https://ot.goprivate.fun/sources/istreamflare.php',
  };

  /// Fetches installed modules list from cloud settings with local fallbacks
  static Future<List<Map<String, dynamic>>> fetchActiveModules({bool forceRefresh = false}) async {
    try {
      final cloud = await SyncService.fetchAppSettings();
      if (cloud.containsKey('source_modules_json') && cloud['source_modules_json']!.isNotEmpty) {
        final decoded = jsonDecode(cloud['source_modules_json']!);
        if (decoded is Map && decoded['modules'] is List) {
          return List<Map<String, dynamic>>.from(decoded['modules']);
        }
      }
    } catch (_) {}
    return _defaultModules.entries.map((e) => {
      'id': e.key,
      'name': getModuleName(e.key),
      'endpoint': e.value,
      'enabled': true,
    }).toList();
  }

  /// Returns friendly human-readable label for a module
  static String getModuleName(String id, {String? defaultName}) {
    if (defaultName != null && defaultName.isNotEmpty) return defaultName;
    switch (id) {
      case 'movieshunt': return 'MoviesHunt Server';
      case 'hdhub4u': return 'HDHub4u 4K & Dolby';
      case 'moviesdrive': return 'MoviesDrive Fast Streams';
      case 'vegamovies': return 'VegaMovies Server';
      case 'cinejoy': return 'Cinejoy Server';
      case 'filmu': return 'FilmU Premium Server';
      case 'istreamflare': return 'iStream Server';
      default: return id.substring(0, 1).toUpperCase() + id.substring(1);
    }
  }

  /// Resolves streams from a named remote module
  static Future<List<StreamSourceInfo>> resolveModuleStreams({
    required String moduleKey,
    required String title,
    required int year,
    bool isSeries = false,
    int? season,
    int? episode,
    String? tmdbId,
    String? imdbId,
  }) async {
    String? moduleUrl = _defaultModules[moduleKey];

    // Check Cloud App Settings for dynamic override / new modules
    try {
      final cloud = await SyncService.fetchAppSettings();
      final cloudKey = 'module_$moduleKey';
      if (cloud.containsKey(cloudKey) && cloud[cloudKey]!.isNotEmpty) {
        moduleUrl = cloud[cloudKey]!;
      } else if (cloud.containsKey('source_modules_json') && cloud['source_modules_json']!.isNotEmpty) {
        final decoded = jsonDecode(cloud['source_modules_json']!);
        if (decoded is Map && decoded['modules'] is List) {
          for (final m in decoded['modules']) {
            if (m is Map && m['id'] == moduleKey && m['endpoint'] != null && m['endpoint'].toString().isNotEmpty) {
              moduleUrl = m['endpoint'].toString();
              break;
            }
          }
        }
      }
    } catch (_) {}

    if (moduleUrl == null || moduleUrl.isEmpty) {
      debugPrint('ModularSourceService: No endpoint configured for module "$moduleKey"');
      return [];
    }

    try {
      final customDomain = await DomainService.getDomain(moduleKey);

      final uri = Uri.parse(moduleUrl).replace(queryParameters: {
        'title': title,
        'query': title,
        'year': year.toString(),
        if (season != null) 'season': season.toString(),
        if (episode != null) 'episode': episode.toString(),
        if (customDomain.isNotEmpty) 'domain': customDomain,
        if (tmdbId != null && tmdbId.isNotEmpty) 'tmdb_id': tmdbId,
        if (imdbId != null && imdbId.isNotEmpty) 'imdb_id': imdbId,
      });

      debugPrint('ModularSourceService: Querying module $moduleKey -> $uri');
      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data['success'] == true && data['streams'] is List) {
          final streamsList = <StreamSourceInfo>[];
          for (final item in data['streams']) {
            var name = item['name']?.toString() ?? '$moduleKey Direct';
            // Clean branding
            name = name
                .replaceAll(RegExp(r'\bMovies\s*Hunt\b[:\s-]*', caseSensitive: false), '')
                .replaceAll(RegExp(r'\bHDHub4u\b[:\s-]*', caseSensitive: false), '')
                .replaceAll(RegExp(r'\bMoviesDrive\b[:\s-]*', caseSensitive: false), '')
                .trim();
            if (name.startsWith('•')) name = name.substring(1).trim();
            if (name.isEmpty) name = 'Direct Stream';

            final url = item['url']?.toString() ?? '';
            final quality = item['quality']?.toString() ?? '1080p Full HD';
            final size = item['size']?.toString();
            Map<String, String>? headers;
            if (item['headers'] is Map) {
              headers = Map<String, String>.from(item['headers']);
            }

            if (url.isNotEmpty) {
              final lowerUrl = url.toLowerCase();
              // Exclude broken landing pages and dead dummy streams
              if (lowerUrl.contains('pixel.hubcloud') ||
                  lowerUrl.contains('pixeldrain') ||
                  lowerUrl.contains('fuckingfast') ||
                  lowerUrl.contains('istreamcdn_disabled/hls/') ||
                  lowerUrl.contains('iasbase.net/stream/')) {
                continue;
              }

              streamsList.add(StreamSourceInfo(
                name: name,
                url: url,
                type: StreamSourceType.movieshunt,
                quality: quality,
                size: size,
                moduleKey: moduleKey,
                headers: headers,
              ));
            }
          }

          return sortStreamsByQuality<StreamSourceInfo>(
            streamsList,
            getName: (s) => s.name,
            getUrl: (s) => s.url,
            getQuality: (s) => s.quality,
            getSize: (s) => s.size,
          );
        }
      }
    } catch (e) {
      debugPrint('ModularSourceService: Error querying module $moduleKey: $e');
    }

    return [];
  }
}
