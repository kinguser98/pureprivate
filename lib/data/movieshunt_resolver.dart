import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:private_cinema_mobile/data/sync_service.dart';
import 'package:private_cinema_mobile/data/domain_service.dart';
import 'package:private_cinema_mobile/widgets/stream_metadata_tile.dart';
import '../widgets/special_search_dialog.dart';

class MovieshuntResolver {
  static const List<String> _domains = [
    'https://movieshunt.monster',
    'https://movieshunt.buzz',
    'https://movieshunt.cc',
    'https://movieshunt.info',
  ];

  static const Map<String, String> _requestHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36',
    'Cookie': 'xla=s4t',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
  };

  static Future<String> getBaseDomain() async {
    try {
      final dyn = await DomainService.getDomain('movieshunt');
      if (dyn.isNotEmpty) return dyn;
    } catch (_) {}
    try {
      final cloud = await SyncService.fetchAppSettings();
      if (cloud.containsKey('domain_movieshunt') && cloud['domain_movieshunt']!.isNotEmpty) {
        final d = cloud['domain_movieshunt']!;
        return d.endsWith('/') ? d.substring(0, d.length - 1) : d;
      }
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('domain_movieshunt') ?? '';
      if (saved.isNotEmpty) {
        return saved.endsWith('/') ? saved.substring(0, saved.length - 1) : saved;
      }
    } catch (_) {}
    return _domains.first;
  }

  /// Resolves direct streaming links from MoviesHunt.
  /// First checks the remote shared-hosting module for zero-rebuild updates;
  /// falls back to direct client-side resolution if unreachable.
  static Future<List<StreamSourceInfo>> resolveStreams({
    required String title,
    required int year,
    String? originalLanguage,
    int? season,
    int? episode,
    bool isSeries = false,
  }) async {
    final cleanTitle = _cleanQuery(title);
    debugPrint('MovieshuntResolver: Resolving streams for "$cleanTitle" ($year)...');

    // 1. Try remote module first (Stremio-style dynamic scraper)
    try {
      final remoteStreams = await _tryRemoteModule(cleanTitle, year);
      if (remoteStreams.isNotEmpty) {
        debugPrint('MovieshuntResolver: Got ${remoteStreams.length} streams via remote module');
        return remoteStreams;
      }
    } catch (e) {
      debugPrint('MovieshuntResolver: Remote module bypass/failed: $e. Using client engine.');
    }

    // 2. Direct client-side unpacker engine
    return await _resolveClientDirect(cleanTitle, year);
  }

  static Future<List<StreamSourceInfo>> _tryRemoteModule(String cleanTitle, int year) async {
    // Check if remote module URL is set in settings or use default shared hosting path
    String remoteUrl = 'https://ot.goprivate.fun/sources/movieshunt.php';
    try {
      final cloud = await SyncService.fetchAppSettings();
      if (cloud.containsKey('module_movieshunt') && cloud['module_movieshunt']!.isNotEmpty) {
        remoteUrl = cloud['module_movieshunt']!;
      }
    } catch (_) {}

    final activeDomain = await getBaseDomain();
    final uri = Uri.parse('$remoteUrl?title=${Uri.encodeComponent(cleanTitle)}&year=$year&domain=${Uri.encodeComponent(activeDomain)}');
    final response = await http.get(uri).timeout(const Duration(seconds: 12));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success'] == true && data['streams'] is List) {
        final rawList = data['streams'] as List;
        final list = <StreamSourceInfo>[];
        for (final item in rawList) {
          var name = item['name']?.toString() ?? 'Cloudflare R2 Direct';
          name = name
              .replaceAll(RegExp(r'\bMovies\s*Hunt\b[:\s-]*', caseSensitive: false), '')
              .trim();
          if (name.startsWith('•')) name = name.substring(1).trim();
          if (name.isEmpty) name = 'Cloudflare R2 Direct';

          final url = item['url']?.toString() ?? '';
          final quality = item['quality']?.toString() ?? '1080p Full HD';
          final size = item['size']?.toString();
          Map<String, String>? headers;
          if (item['headers'] is Map) {
            headers = Map<String, String>.from(item['headers']);
          }
          if (url.isNotEmpty) {
            final lowerUrl = url.toLowerCase();
            // Strictly exclude landing pages
            if (lowerUrl.contains('pixel.hubcloud') || lowerUrl.contains('pixeldrain') || lowerUrl.contains('fuckingfast')) {
              continue;
            }
            list.add(StreamSourceInfo(
              name: name,
              url: url,
              type: StreamSourceType.movieshunt,
              quality: quality,
              size: size,
              headers: headers,
            ));
          }
        }
        if (list.isNotEmpty) {
          return sortStreamsByQuality<StreamSourceInfo>(
            list,
            getName: (s) => s.name,
            getUrl: (s) => s.url,
            getQuality: (s) => s.quality,
            getSize: (s) => s.size,
          );
        }
      }
    }
    return [];
  }

  static Future<List<StreamSourceInfo>> _resolveClientDirect(String cleanTitle, int year) async {
    final baseDomain = await getBaseDomain();
    final candidateDomains = [baseDomain, ..._domains.where((d) => d != baseDomain)];
    final sources = <StreamSourceInfo>[];

    for (final domain in candidateDomains) {
      try {
        // WordPress REST API
        final apiUrl = '$domain/wp-json/wp/v2/posts?search=${Uri.encodeComponent(cleanTitle)}';
        debugPrint('MovieshuntResolver: Probing $apiUrl');
        final res = await http.get(Uri.parse(apiUrl), headers: _requestHeaders).timeout(const Duration(seconds: 8));

        if (res.statusCode == 200) {
          final posts = json.decode(res.body);
          if (posts is List && posts.isNotEmpty) {
            final targetPost = _findBestPost(posts, cleanTitle);
            if (targetPost != null) {
              final postUrl = targetPost['link']?.toString() ?? '';
              if (postUrl.isNotEmpty) {
                final pageStreams = await _extractStreamsFromPost(postUrl, domain);
                sources.addAll(pageStreams);
                if (sources.isNotEmpty) break;
              }
            }
          }
        }
      } catch (e) {
        debugPrint('MovieshuntResolver: Error probing $domain: $e');
      }
    }

    final uniqueSources = <StreamSourceInfo>[];
    final seenUrls = <String>{};
    for (final s in sources) {
      if (!seenUrls.contains(s.url)) {
        seenUrls.add(s.url);
        uniqueSources.add(s);
      }
    }

    final sorted = sortStreamsByQuality<StreamSourceInfo>(
      uniqueSources,
      getName: (s) => s.name,
      getUrl: (s) => s.url,
      getQuality: (s) => s.quality,
      getSize: (s) => s.size,
    );

    debugPrint('MovieshuntResolver: Successfully resolved ${sorted.length} streams for "$cleanTitle"');
    return sorted;
  }

  static dynamic _findBestPost(List<dynamic> posts, String cleanTitle) {
    const languageStopWords = {'mal', 'tam', 'hin', 'tel', 'kan', 'eng', 'sub', 'dub', 'hd', '4k', 'uhd', 'fhd', 'movie', 'full'};
    final words = cleanTitle
        .toLowerCase()
        .split(' ')
        .map((w) => w.trim())
        .where((w) => w.length >= 3 && !languageStopWords.contains(w))
        .toList();

    for (final p in posts) {
      final title = (p['title']?['rendered']?.toString() ?? '').toLowerCase();
      if (words.isNotEmpty && words.every((w) => title.contains(w))) {
        return p;
      }
    }
    return posts.first;
  }

  static Future<List<StreamSourceInfo>> _extractStreamsFromPost(String postUrl, String domain) async {
    final streams = <StreamSourceInfo>[];
    try {
      final res = await http.get(Uri.parse(postUrl), headers: _requestHeaders).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return streams;
      final html = res.body;

      final secRegex = RegExp(r'<h4>(.*?)<\/h4>\s*<div[^>]*downloads-btns-div[^>]*>\s*<a[^>]+href="([^"]+)"', caseSensitive: false, dotAll: true);
      final secMatches = secRegex.allMatches(html);

      for (final m in secMatches) {
        final heading = m.group(1)?.replaceAll(RegExp(r'<[^>]*>'), '').trim() ?? '';
        final abhiUrl = m.group(2)?.trim() ?? '';

        String quality = '1080p Full HD';
        if (heading.toLowerCase().contains('2160p') || heading.toLowerCase().contains('4k') || heading.toLowerCase().contains('uhd')) {
          quality = '4K (2160p)';
        } else if (heading.toLowerCase().contains('1080p')) {
          quality = '1080p Full HD';
        } else if (heading.toLowerCase().contains('720p')) {
          quality = '720p HD';
        } else if (heading.toLowerCase().contains('480p')) {
          quality = '480p SD';
        }

        String? size;
        final sizeMatch = RegExp(r'\b([0-9.]+\s*[GM]B)\b', caseSensitive: false).firstMatch(heading);
        if (sizeMatch != null) {
          size = sizeMatch.group(1);
        }

        if (abhiUrl.isNotEmpty) {
          final abhiStreams = await _unpackAbhilinks(abhiUrl, quality: quality, size: size, referer: postUrl);
          streams.addAll(abhiStreams);
        }
      }
    } catch (e) {
      debugPrint('MovieshuntResolver: Error extracting post $postUrl: $e');
    }
    return streams;
  }

  static Future<List<StreamSourceInfo>> _unpackAbhilinks(
    String abhiUrl, {
    required String quality,
    String? size,
    required String referer,
  }) async {
    final streams = <StreamSourceInfo>[];
    try {
      final headers = Map<String, String>.from(_requestHeaders)..['Referer'] = referer;
      final res = await http.get(Uri.parse(abhiUrl), headers: headers).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return streams;

      final hubMatches = RegExp(r'href="([^"]*hubcloud[^"]*)"', caseSensitive: false).allMatches(res.body);
      for (final hm in hubMatches) {
        final hubUrl = hm.group(1);
        if (hubUrl != null && hubUrl.isNotEmpty) {
          final hubStreams = await _unpackHubcloud(hubUrl, quality: quality, size: size, referer: abhiUrl);
          streams.addAll(hubStreams);
          if (streams.isNotEmpty) break;
        }
      }
    } catch (e) {
      debugPrint('MovieshuntResolver: Error unpacking abhilinks: $e');
    }
    return streams;
  }

  static Future<List<StreamSourceInfo>> _unpackHubcloud(
    String hubUrl, {
    required String quality,
    String? size,
    required String referer,
  }) async {
    final streams = <StreamSourceInfo>[];
    try {
      final headers = Map<String, String>.from(_requestHeaders)..['Referer'] = referer;
      final res = await http.get(Uri.parse(hubUrl), headers: headers).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return streams;

      final sportMatch = RegExp(
        r'href="([^"]*(?:sportverse\.cc|gamerxyt\.com|gadgetxyt\.com|hubcloud\.php)[^"]*)"',
        caseSensitive: false,
      ).firstMatch(res.body);
      if (sportMatch != null) {
        var sportUrl = sportMatch.group(1)!;
        sportUrl = sportUrl.replaceAll('&amp;', '&');

        final sportHeaders = Map<String, String>.from(_requestHeaders)..['Referer'] = hubUrl;
        final sportRes = await http.get(Uri.parse(sportUrl), headers: sportHeaders).timeout(const Duration(seconds: 8));
        if (sportRes.statusCode == 200) {
          final linkRegex = RegExp(r'<a[^>]+href="([^"]+)"[^>]*>(.*?)<\/a>', caseSensitive: false, dotAll: true);
          final matches = linkRegex.allMatches(sportRes.body);

          for (final m in matches) {
            final href = m.group(1)?.trim() ?? '';
            final label = m.group(2)?.replaceAll(RegExp(r'<[^>]*>'), '').trim() ?? '';
            final lowerHref = href.toLowerCase();

            final isR2 = lowerHref.contains('.r2.dev') || lowerHref.contains('.r2.cloudflarestorage.com');
            final isDirectMedia = lowerHref.endsWith('.mkv') || lowerHref.endsWith('.mp4') || lowerHref.contains('.mkv?') || lowerHref.contains('.mp4?');

            if ((isR2 || isDirectMedia) && !lowerHref.contains('pixel.hubcloud') && !lowerHref.contains('pixeldrain') && !lowerHref.contains('fuckingfast')) {
              final serverName = isR2 ? 'Cloudflare R2 Direct' : 'Direct High-Speed CDN';
              final displayName = '$serverName • $quality${size != null ? " [$size]" : ""}';
              streams.add(StreamSourceInfo(
                name: displayName,
                url: href,
                type: StreamSourceType.movieshunt,
                quality: quality,
                size: size,
                headers: {
                  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
                  'Referer': 'https://hubcloud.cx/',
                },
              ));
            }
          }
        }
      }
    } catch (e) {
      debugPrint('MovieshuntResolver: Error unpacking hubcloud: $e');
    }
    return streams;
  }

  static String _cleanQuery(String query) {
    return query
        .replaceAll(RegExp(r'\[.*?\]'), ' ')
        .replaceAll(RegExp(r'\(.*?\)'), ' ')
        .replaceAll(RegExp(r'\b(dub|dubbed|hd|4k|hindi|tamil|telugu|malayalam|kannada|multi|dual audio)\b', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'[-–—:.]'), ' ')
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
