import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/special_search_dialog.dart'; // To access StreamSourceInfo and StreamSourceType

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

  /// Searches and resolves streams for a given movie title
  static Future<List<StreamSourceInfo>> resolveStreams(String title) async {
    final List<StreamSourceInfo> sources = [];
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 8);

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
          final searchUrl = '$apiBase/newtv/search.php?s=${Uri.encodeComponent(title)}';
          final req = await client.getUrl(Uri.parse(searchUrl));

          _baseHeaders.forEach((k, v) {
            req.headers.set(k, v);
          });
          req.headers.set('Ott', ottVal);

          final res = await req.close();
          if (res.statusCode == 200) {
            final body = await res.transform(utf8.decoder).join();
            final searchData = jsonDecode(body);
            final results = searchData['searchResult'] as List<dynamic>? ?? [];

            for (final result in results) {
              final contentId = result['id']?.toString() ?? '';
              final resultTitle = result['t']?.toString() ?? '';
              
              if (contentId.isNotEmpty) {
                // Get player link
                final playerUrl = '$apiBase/newtv/player.php?id=$contentId';
                final playerReq = await client.getUrl(Uri.parse(playerUrl));
                
                _baseHeaders.forEach((k, v) {
                  playerReq.headers.set(k, v);
                });
                playerReq.headers.set('Ott', ottVal);
                playerReq.headers.set('Usertoken', '');

                final playerRes = await playerReq.close();
                if (playerRes.statusCode == 200) {
                  final playerBody = await playerRes.transform(utf8.decoder).join();
                  final playerData = jsonDecode(playerBody);

                  if (playerData['status'] == 'ok' && playerData['video_link'] != null) {
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
    } finally {
      client.close();
    }

    return sources;
  }
}
