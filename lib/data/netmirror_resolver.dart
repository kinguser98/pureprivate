import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/special_search_dialog.dart'; // To access StreamSourceInfo and StreamSourceType
import 'api_service.dart';

class NetmirrorResolver {
  static final List<String> _defaultDomains = [
    "aHR0cHM6Ly9uZXQyMi5jYw==",
    "aHR0cHM6Ly9uZXQ1Mi5jYw==",
    "aHR0cHM6Ly9tb2JpbGVkZXRlY3RzLmNvbQ==",
    "aHR0cHM6Ly9tb2JpbGVkZXRlY3QuYXBw",
    "aHR0cHM6Ly9tb2JpZGV0ZWN0LmFydA==",
    "aHR0cHM6Ly9tb2JpZGV0ZWN0LmNj",
    "aHR0cHM6Ly9tb2JpZGV0ZWN0LmNsaWNr",
    "aHR0cHM6Ly9tb2JpZGV0ZWN0Lmluaw==",
    "aHR0cHM6Ly9tb2JpZGV0ZWN0LmxpdmU=",
    "aHR0cHM6Ly9tb2JpZGV0ZWN0LnBybw==",
    "aHR0cHM6Ly9tb2JpZGV0ZWN0LnNob3A=",
    "aHR0cHM6Ly9tb2JpZGV0ZWN0LnNpdGU=",
    "aHR0cHM6Ly9tb2JpZGV0ZWN0LnNwYWNl",
    "aHR0cHM6Ly9tb2JpZGV0ZWN0LnN0b3Jl",
    "aHR0cHM6Ly9tb2JpZGV0ZWN0LnZpcA==",
    "aHR0cHM6Ly9tb2JpZGV0ZWN0Lndpa2k=",
    "aHR0cHM6Ly9tb2JpZGV0ZWN0Lnh5eg==",
    "aHR0cHM6Ly9tb2JpZGV0ZWN0cy5hcnQ=",
    "aHR0cHM6Ly9tb2JpZGV0ZWN0cy5jYw==",
    "aHR0cHM6Ly9tb2JpZGV0ZWN0cy5pbmZv",
    "aHR0cHM6Ly9tb2JpZGV0ZWN0cy5pbms=",
    "aHR0cHM6Ly9tb2JpZGV0ZWN0cy5saXZl",
    "aHR0cHM6Ly9tb2JpZGV0ZWN0cy5wcm8=",
    "aHR0cHM6Ly9tb2JpZGV0ZWN0cy5zdG9yZQ==",
    "aHR0cHM6Ly9tb2JpZGV0ZWN0cy50b3A=",
    "aHR0cHM6Ly9tb2JpZGV0ZWN0cy54eXo="
  ];

  static const Map<String, String> _baseHeaders = {
    "Cache-Control": "no-cache, no-store, must-revalidate",
    "Pragma": "no-cache",
    "Expires": "0",
    "X-Requested-With": "NetmirrorNewTV v1.0",
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:136.0) Gecko/20100101 Firefox/136.0 /OS.GatuNewTV v1.0",
    "Accept": "application/json, text/plain, */*"
  };

  static String _cachedApiBase = "";

  /// Resolves the active NetMirror API base URL
  static Future<String> _resolveApiBase() async {
    if (_cachedApiBase.isNotEmpty) return _cachedApiBase;

    final prefs = await SharedPreferences.getInstance();
    final customDomainsStr = prefs.getString('netmirror_domains') ?? '';
    final List<String> domainsToTry = [];

    // Parse custom user domains first
    if (customDomainsStr.isNotEmpty) {
      final parts = customDomainsStr.split(',');
      for (var part in parts) {
        part = part.trim();
        if (part.isNotEmpty) {
          domainsToTry.add(part);
        }
      }
    }

    // Add decoded default domains
    for (final encoded in _defaultDomains) {
      try {
        final decodedBytes = base64.decode(encoded);
        final decodedUrl = utf8.decode(decodedBytes).trim();
        if (decodedUrl.isNotEmpty && !domainsToTry.contains(decodedUrl)) {
          domainsToTry.add(decodedUrl);
        }
      } catch (_) {}
    }

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 4);

    for (var base in domainsToTry) {
      if (base.endsWith('/')) {
        base = base.substring(0, base.length - 1);
      }

      debugPrint('NetmirrorResolver: Trying domain $base');
      try {
        final uri = Uri.parse('$base/checknewtv.php');
        final req = await client.getUrl(uri);
        
        _baseHeaders.forEach((k, v) {
          req.headers.set(k, v);
        });
        req.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36');

        final res = await req.close();
        if (res.statusCode == 200) {
          final body = await res.transform(utf8.decoder).join();
          final data = jsonDecode(body);
          final tokenHash = data['token_hash']?.toString() ?? '';
          if (tokenHash.isNotEmpty) {
            final decodedBytes = base64.decode(tokenHash);
            var apiBase = utf8.decode(decodedBytes).trim();
            if (apiBase.endsWith('/')) {
              apiBase = apiBase.substring(0, apiBase.length - 1);
            }
            _cachedApiBase = apiBase;
            debugPrint('NetmirrorResolver: Successfully resolved apiBase: $_cachedApiBase');
            client.close();
            return _cachedApiBase;
          }
        }
      } catch (e) {
        debugPrint('NetmirrorResolver: Domain $base failed: $e');
      }
    }

    client.close();
    if (_cachedApiBase.isNotEmpty) return _cachedApiBase;
    throw Exception('Failed to resolve Netmirror API base URL');
  }

  /// Proxies NetMirror API calls through the server backend to bypass rate limits
  static Future<String> _proxyRequest(String url, Map<String, String> extraHeaders) async {
    try {
      final encodedUrl = Uri.encodeComponent(url);
      final encodedHeaders = Uri.encodeComponent(jsonEncode(extraHeaders));
      final proxyUrl = '${ApiService.apiUrl}?action=proxy_fetch&url=$encodedUrl&headers=$encodedHeaders';
      final res = await http.get(Uri.parse(proxyUrl)).timeout(const Duration(seconds: 20));
      if (res.statusCode == 200) return res.body;
      throw Exception('Proxy returned ${res.statusCode}');
    } catch (e) {
      // Fallback to direct request if proxy fails
      debugPrint('NetmirrorResolver: Proxy failed, falling back to direct: $e');
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 8);
      final uri = Uri.parse(url);
      final req = await client.getUrl(uri);
      _baseHeaders.forEach((k, v) => req.headers.set(k, v));
      extraHeaders.forEach((k, v) => req.headers.set(k, v));
      final res = await req.close();
      if (res.statusCode == 200) {
        final body = await res.transform(utf8.decoder).join();
        client.close();
        return body;
      }
      client.close();
      throw Exception('Direct request failed: ${res.statusCode}');
    }
  }

  /// Searches and resolves streams for a given movie title
  static Future<List<StreamSourceInfo>> resolveStreams(String title) async {
    final List<StreamSourceInfo> sources = [];

    // Parse series Season and Episode if present, e.g. "Breaking Bad S01E01" -> "Breaking Bad", season=1, episode=1
    int? season;
    int? episode;
    String cleanSearchTitle = title;

    final regExp = RegExp(r'\s+S(\d+)E(\d+)', caseSensitive: false);
    final match = regExp.firstMatch(title);
    if (match != null) {
      season = int.tryParse(match.group(1) ?? '');
      episode = int.tryParse(match.group(2) ?? '');
      cleanSearchTitle = title.substring(0, match.start).trim();
    }

    try {
      final apiBase = await _resolveApiBase();
      final ottPlatforms = {
        'netflix': 'nf',
        'primevideo': 'pv',
        'hotstar': 'hs',
        'disney': 'hs'
      };

      for (final entry in ottPlatforms.entries) {
        final platformKey = entry.key;
        final ottVal = entry.value;

        try {
          final searchUrl = '$apiBase/newtv/search.php?s=${Uri.encodeComponent(cleanSearchTitle)}';
          final body = await _proxyRequest(searchUrl, {'Ott': ottVal});
          if (body.isNotEmpty) {
            final searchData = jsonDecode(body);
            final results = searchData['searchResult'] as List<dynamic>? ?? [];

            for (final result in results) {
              final seriesId = result['id']?.toString() ?? '';
              final resultTitle = result['t']?.toString() ?? '';
              
              if (seriesId.isNotEmpty) {
                String contentId = seriesId;
                
                if (season != null && episode != null) {
                  // Retrieve the exact episode sub-content ID via post.php and episodes.php
                  try {
                    final postUrl = '$apiBase/newtv/post.php?id=$seriesId';
                    final postBody = await _proxyRequest(postUrl, {'Ott': ottVal});
                    if (postBody.isNotEmpty) {
                      final postData = jsonDecode(postBody);
                      final episodes = await _getAllEpisodes(seriesId, postData, ottVal, apiBase);
                      
                      final targetEp = episodes.firstWhere(
                        (ep) => ep['s'] == season && ep['ep'] == episode,
                        orElse: () => {},
                      );
                      
                      if (targetEp.isNotEmpty && targetEp['id'] != null) {
                        contentId = targetEp['id'].toString();
                      } else {
                        // Skip if episode is not found in this platform's seasons
                        continue;
                      }
                    } else {
                      continue;
                    }
                  } catch (e) {
                    debugPrint('NetmirrorResolver series pre-flight error: $e');
                    continue;
                  }
                }

                // Get player link
                final playerUrl = '$apiBase/newtv/player.php?id=$contentId';
                final playerBody = await _proxyRequest(playerUrl, {'Ott': ottVal, 'Usertoken': ''});
                if (playerBody.isNotEmpty) {
                  final playerData = jsonDecode(playerBody);

                  if ((playerData['status'] == 'ok' || playerData['status'] == 'otp') && playerData['video_link'] != null) {
                    final videoLink = playerData['video_link']?.toString() ?? '';
                    final referer = playerData['referer']?.toString() ?? apiBase;
                    
                    final displayTitle = resultTitle.isNotEmpty ? resultTitle : title;
                    final sourceName = 'NetMirror: $displayTitle (${platformKey.substring(0, 1).toUpperCase()}${platformKey.substring(1)})';

                    // Encode Referer header into URL query parameter
                    final encodedHeaders = jsonEncode({
                      'Referer': referer,
                    });
                    
                    final resolvedUri = Uri.parse(videoLink).replace(queryParameters: {
                      ...Uri.parse(videoLink).queryParameters,
                      'headers': encodedHeaders
                    });

                    sources.add(StreamSourceInfo(
                      name: sourceName,
                      url: resolvedUri.toString(),
                      type: StreamSourceType.netmirror,
                    ));
                  }
                }
              }
            }
          }
        } catch (e) {
          debugPrint('NetmirrorResolver: Error searching platform $platformKey: $e');
        }
      }
    } catch (e) {
      debugPrint('NetmirrorResolver failed: $e');
    }

    return sources;
  }

  static Future<List<Map<String, dynamic>>> _getAllEpisodes(
    String seriesId,
    Map<String, dynamic> postData,
    String ottVal,
    String apiBase,
  ) async {
    final List<Map<String, dynamic>> episodesList = [];

    Future<void> fetchEpisodesPage(String seasonId, int page, int seasonNumber) async {
      int pg = page;
      while (true) {
        final epUrl = '$apiBase/newtv/episodes.php?id=$seasonId&page=$pg';
        try {
          final body = await _proxyRequest(epUrl, {'Ott': ottVal});
          if (body.isNotEmpty) {
            final data = jsonDecode(body);
            final eps = data['episodes'] as List<dynamic>? ?? [];
            
            for (final ep in eps) {
              if (ep != null) {
                final epNum = int.tryParse(ep['ep']?.toString() ?? '') ?? 
                              int.tryParse(ep['epNum']?.toString().replaceAll('E', '') ?? '') ?? 
                              0;
                episodesList.add({
                  'id': ep['id']?.toString() ?? '',
                  's': seasonNumber,
                  'ep': epNum,
                });
              }
            }
            if (data['nextPageShow'] != 1) {
              break;
            }
            pg++;
          } else {
            break;
          }
        } catch (_) {
          break;
        }
      }
    }

    final selectedSeasonIdx = postData['season'] is List 
        ? (postData['season'] as List).indexWhere((s) => s['selected'] == true) 
        : -1;
    final selectedSeasonId = selectedSeasonIdx >= 0 
        ? postData['season'][selectedSeasonIdx]['id']?.toString() 
        : postData['nextPageSeason']?.toString();
    final selectedSeasonNumber = selectedSeasonIdx >= 0 ? selectedSeasonIdx + 1 : 1;

    if (postData['episodes'] is List) {
      final eps = postData['episodes'] as List;
      for (final ep in eps) {
        if (ep != null) {
          final epNum = int.tryParse(ep['ep']?.toString() ?? '') ?? 
                        int.tryParse(ep['epNum']?.toString().replaceAll('E', '') ?? '') ?? 
                        0;
          episodesList.add({
            'id': ep['id']?.toString() ?? '',
            's': selectedSeasonNumber,
            'ep': epNum,
          });
        }
      }
    }

    if (postData['nextPageShow'] == 1 && selectedSeasonId != null) {
      await fetchEpisodesPage(selectedSeasonId, 2, selectedSeasonNumber);
    }

    if (postData['season'] is List) {
      final seasons = postData['season'] as List;
      for (int i = 0; i < seasons.length; i++) {
        final sId = seasons[i]['id']?.toString();
        if (sId != null && sId != selectedSeasonId) {
          await fetchEpisodesPage(sId, 1, i + 1);
        }
      }
    }

    return episodesList;
  }
}
