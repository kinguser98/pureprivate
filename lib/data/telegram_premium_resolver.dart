import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'sync_service.dart';
import '../models/movie.dart';

class TelegramPremiumStream {
  final String cleanTitle;
  final String rawTitle;
  final int fileSize;
  final String sizeFormatted;
  final String quality;
  final List<String> languages;
  final List<String> badges;
  final String shortCode;
  final int postId;
  final int? season;
  final int? episode;
  final String? mime;
  final String playUrl;
  final String? thumbnailUrl;
  final String botStartUrl;
  final String botStartParam;

  TelegramPremiumStream({
    required this.cleanTitle,
    required this.rawTitle,
    required this.fileSize,
    required this.sizeFormatted,
    required this.quality,
    required this.languages,
    required this.badges,
    required this.shortCode,
    required this.postId,
    this.season,
    this.episode,
    this.mime,
    required this.playUrl,
    this.thumbnailUrl,
    required this.botStartUrl,
    required this.botStartParam,
  });
}

class ServerConfig {
  final String baseUrl;
  final String token;
  final bool isLocal;

  ServerConfig({
    required this.baseUrl,
    required this.token,
    required this.isLocal,
  });

  String get tokenPath => token.isNotEmpty ? '/$token' : '';
}

class TelegramPremiumResolver {
  static const String keyServerMode = 'tg_prem_server_mode'; // 'koyeb' or 'local'
  static const String keyKoyebUrl = 'tg_prem_koyeb_url';
  static const String keyKoyebToken = 'tg_prem_koyeb_token';
  static const String keyLocalUrl = 'tg_prem_local_url';
  static const String keyLocalToken = 'tg_prem_local_token';
  static const String keyAutoDetect = 'tg_prem_auto_detect';

  static const String defaultCloudUrl = 'http://68.233.107.119:8088';
  static const String defaultKoyebUrl = defaultCloudUrl; // Backwards-compatible alias
  static const String defaultKoyebToken = '';
  static const String defaultLocalUrl = 'http://192.168.1.8:8088';
  static const String defaultLocalToken = '';
  static const String _defaultBot = 'CrawlerXbot';

  static const String _primaryDomain = 'https://pencarimovie.com';
  static const String _fallbackDomain = 'https://telegra.my';

  // --- Configuration Helpers ---

  static const String keyEnabled = 'source_show_telegram_premium';

  /// Normalizes and cleans server URL by trimming whitespace and stripping trailing '#' and '/'
  static String cleanServerUrl(String url) {
    var u = url.trim();
    while (u.endsWith('#') || u.endsWith('/')) {
      u = u.substring(0, u.length - 1).trim();
    }
    return u;
  }

  /// Authenticates with server password (default: 123456) and caches active token
  static Future<String?> loginAndRefreshToken(String baseUrl, {String password = '123456'}) async {
    try {
      final cleanBase = cleanServerUrl(baseUrl);
      final loginUri = Uri.parse('$cleanBase/api/auth/login');
      final res = await http.post(
        loginUri,
        headers: {'Content-Type': 'application/json', 'User-Agent': 'Mozilla/5.0'},
        body: jsonEncode({'password': password}),
      ).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['ok'] == 1 && data['token'] != null) {
          final newToken = data['token'].toString();
          debugPrint('[TelegramPremium] Auto-authenticated with $cleanBase, got fresh token: $newToken');
          final prefs = await SharedPreferences.getInstance();
          if (!cleanBase.contains('192.168.') && !cleanBase.contains('127.0.0.1') && !cleanBase.contains('localhost')) {
            await prefs.setString(keyKoyebToken, newToken);
          } else {
            await prefs.setString(keyLocalToken, newToken);
          }
          return newToken;
        }
      }
    } catch (e) {
      debugPrint('[TelegramPremium] loginAndRefreshToken error: $e');
    }
    return null;
  }

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(keyEnabled) ?? true;
  }

  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyEnabled, value);
  }

  static Future<bool> isAutoDetect() => getAutoDetect();

  static Future<String> getServerMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(keyServerMode) ?? 'koyeb';
  }

  static Future<void> setServerMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyServerMode, mode);
  }

  static Future<String> getKoyebUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(keyKoyebUrl);
    if (saved != null && saved.contains('koyeb.app')) {
      // Auto-migrate from deprecated Koyeb cloud to Oracle VPS
      await prefs.setString(keyKoyebUrl, defaultCloudUrl);
      await prefs.remove(keyKoyebToken);
      return defaultCloudUrl;
    }
    return saved != null ? cleanServerUrl(saved) : defaultCloudUrl;
  }

  static Future<void> setKoyebUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyKoyebUrl, cleanServerUrl(url));
  }

  static Future<String> getKoyebToken() async {
    final prefs = await SharedPreferences.getInstance();
    final savedToken = prefs.getString(keyKoyebToken);
    if (savedToken == '1ddeccdcf49e759d703aec350478b07e' || savedToken == '1be8ba347bc587835231c9f4a922b58c') {
      await prefs.remove(keyKoyebToken);
      return '';
    }
    return savedToken ?? defaultKoyebToken;
  }

  static Future<void> setKoyebToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyKoyebToken, token.trim());
  }

  static Future<String> getLocalUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(keyLocalUrl) ?? defaultLocalUrl;
  }

  static Future<void> setLocalUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyLocalUrl, cleanServerUrl(url));
  }

  static Future<String> getLocalToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(keyLocalToken) ?? '';
  }

  static Future<void> setLocalToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyLocalToken, token.trim());
  }

  static Future<bool> getAutoDetect() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(keyAutoDetect) ?? true;
  }

  static Future<void> setAutoDetect(bool autoDetect) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyAutoDetect, autoDetect);
  }

  /// Returns the active server configuration based on user preference, cloud settings, and auto-detection.
  static Future<ServerConfig> getActiveConfig({Map<String, String>? cloud}) async {
    final prefs = await SharedPreferences.getInstance();
    if (cloud == null) {
      try {
        cloud = await SyncService.fetchAppSettings();
      } catch (_) {}
    }
    final mode = cloud?[keyServerMode] ?? prefs.getString(keyServerMode) ?? 'koyeb';
    final autoDetect = cloud?.containsKey(keyAutoDetect) == true
        ? cloud![keyAutoDetect] == 'true'
        : (prefs.getBool(keyAutoDetect) ?? true);

    var cloudUrl = cloud?[keyKoyebUrl] ?? prefs.getString(keyKoyebUrl) ?? defaultCloudUrl;
    if (cloudUrl.contains('koyeb.app')) {
      cloudUrl = defaultCloudUrl;
      await prefs.setString(keyKoyebUrl, defaultCloudUrl);
      await prefs.remove(keyKoyebToken);
    }
    cloudUrl = cleanServerUrl(cloudUrl);

    var cloudToken = cloud?[keyKoyebToken] ?? prefs.getString(keyKoyebToken) ?? defaultKoyebToken;
    if (cloudToken == '1ddeccdcf49e759d703aec350478b07e' || cloudToken == '1be8ba347bc587835231c9f4a922b58c') {
      cloudToken = '';
      await prefs.remove(keyKoyebToken);
    }

    final localUrl = cleanServerUrl(cloud?[keyLocalUrl] ?? prefs.getString(keyLocalUrl) ?? defaultLocalUrl);
    final localToken = cloud?[keyLocalToken] ?? prefs.getString(keyLocalToken) ?? defaultLocalToken;

    // If autoDetect is enabled or user explicitly picked 'local', try pinging local server
    if (autoDetect || mode == 'local') {
      try {
        final tokenPath = localToken.trim().isNotEmpty ? '/${localToken.trim()}' : '';
        final pingUrl = Uri.parse('$localUrl$tokenPath/manifest.json');
        final response = await http.get(pingUrl).timeout(const Duration(milliseconds: 1800));
        if (response.statusCode == 200) {
          debugPrint('[TelegramPremium] Auto-detected active Local Server at $localUrl');
          return ServerConfig(baseUrl: localUrl, token: localToken, isLocal: true);
        }
      } catch (_) {
        // Local server unreachable
      }

      if (mode == 'local') {
        // Mode is explicitly set to local even if ping failed
        return ServerConfig(baseUrl: localUrl, token: localToken, isLocal: true);
      }
    }

    // Default to Cloud VPS Server (Oracle)
    return ServerConfig(baseUrl: cloudUrl, token: cloudToken, isLocal: false);
  }

  static bool _isLockedStremioResponse(String body) {
    return body.contains('Addon URL changed') ||
        body.contains('password required') ||
        body.contains('#addon');
  }

  /// Pings a server to test its availability, latency, and version
  static Future<Map<String, dynamic>> testServer({String? url, String? token, String? password}) async {
    final stopwatch = Stopwatch()..start();
    try {
      final targetUrl = cleanServerUrl(url ?? defaultCloudUrl);
      var targetToken = (token ?? defaultKoyebToken).trim();
      if (targetToken == '1ddeccdcf49e759d703aec350478b07e' || targetToken == '1be8ba347bc587835231c9f4a922b58c') {
        targetToken = '';
      }

      // Step 1: Check manifest
      final pingUri = Uri.parse('$targetUrl/manifest.json');
      final client = http.Client();
      final pingRes = await client.get(pingUri).timeout(const Duration(seconds: 5));
      if (pingRes.statusCode != 200) {
        stopwatch.stop();
        return {
          'success': false,
          'error': 'HTTP ${pingRes.statusCode}: Server unreachable',
        };
      }

      final manifestData = jsonDecode(pingRes.body);

      // Step 2: Test stream endpoint to ensure token is valid and not locked
      final testStreamUri = Uri.parse('$targetUrl${targetToken.isNotEmpty ? '/$targetToken' : ''}/stream/movie/tt5463162.json');
      final streamRes = await client.get(testStreamUri).timeout(const Duration(seconds: 6));

      if (streamRes.statusCode == 401 || _isLockedStremioResponse(streamRes.body)) {
        if (password != null && password.trim().isNotEmpty) {
          final freshToken = await loginAndRefreshToken(targetUrl, password: password.trim());
          if (freshToken != null && freshToken.isNotEmpty) {
            targetToken = freshToken;
          } else {
            stopwatch.stop();
            return {
              'success': false,
              'error': 'Authentication failed. Please verify server password.',
            };
          }
        } else if (targetToken.isNotEmpty) {
          stopwatch.stop();
          return {
            'success': false,
            'error': 'Access token invalid or expired.',
          };
        } else {
          stopwatch.stop();
          return {
            'success': true,
            'token': '',
            'latencyMs': stopwatch.elapsedMilliseconds,
            'name': manifestData['name'] ?? 'PencariMovie (Oracle VPS)',
            'version': manifestData['version'] ?? '2.3.8',
            'warning': 'Connected! (Server requires token for stream access)',
          };
        }
      }

      stopwatch.stop();
      return {
        'success': true,
        'token': targetToken,
        'latencyMs': stopwatch.elapsedMilliseconds,
        'name': manifestData['name'] ?? 'PencariMovie (Oracle VPS)',
        'version': manifestData['version'] ?? '2.3.8',
      };
    } catch (e) {
      stopwatch.stop();
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  // --- Stream Search & Resolution ---

  /// Unified search returning List<StreamSource> for player and downloader UI
  static Future<List<StreamSource>> search(
    String title, {
    int? year,
    bool isSeries = false,
    int? season,
    int? episode,
    String? imdbId,
    Map<String, String>? cloud,
  }) async {
    final config = await getActiveConfig(cloud: cloud);
    debugPrint('[TelegramPremium] Resolving using server: ${config.baseUrl} (isLocal: ${config.isLocal})');

    // Method 1: Stremio direct resolution via IMDB ID (Fastest & most accurate)
    if (imdbId != null && imdbId.trim().isNotEmpty && imdbId.startsWith('tt')) {
      final stremioStreams = await _resolveViaStremioImdb(config, imdbId.trim(), isSeries: isSeries, season: season, episode: episode);
      if (stremioStreams.isNotEmpty) {
        return stremioStreams;
      }
    }

    // Method 2: Stremio catalog search on the active server
    final catalogStreams = await _resolveViaStremioCatalog(config, title, year: year, isSeries: isSeries, season: season, episode: episode);
    if (catalogStreams.isNotEmpty) {
      return catalogStreams;
    }

    // Method 3: Fallback via PencariMovie WordPress Search + Server Shortcode Resolver
    final fallbackStreams = isSeries
        ? await _searchInternal(config, title, year: year, isSeries: true, season: season, episode: episode)
        : await _searchInternal(config, title, year: year, isSeries: false);

    return fallbackStreams.map((s) => StreamSource(
      name: 'TG • ${s.cleanTitle}',
      url: s.playUrl,
      quality: s.quality,
      qualityBadgeText: s.quality,
      size: s.sizeFormatted,
      languages: s.languages,
    )).toList();
  }

  /// Resolve streams via Stremio IMDB route: /<token>/stream/{type}/{imdbId}.json
  static Future<List<StreamSource>> _resolveViaStremioImdb(
    ServerConfig config,
    String imdbId, {
    bool isSeries = false,
    int? season,
    int? episode,
  }) async {
    try {
      final type = isSeries ? 'series' : 'movie';
      final streamId = isSeries ? '$imdbId:${season ?? 1}:${episode ?? 1}' : imdbId;
      final uri = Uri.parse('${config.baseUrl}${config.tokenPath}/stream/$type/$streamId.json');

      debugPrint('[TelegramPremium] Fetching Stremio streams from: $uri');
      var response = await http.get(uri, headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 12));

      if (response.statusCode == 401 || _isLockedStremioResponse(response.body)) {
        debugPrint('[TelegramPremium] Server locked or token expired on ${config.baseUrl}, auto-authenticating...');
        final freshToken = await loginAndRefreshToken(config.baseUrl);
        if (freshToken != null && freshToken.isNotEmpty) {
          final retryUri = Uri.parse('${config.baseUrl}/$freshToken/stream/$type/$streamId.json');
          response = await http.get(retryUri, headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            'Accept': 'application/json',
          }).timeout(const Duration(seconds: 12));
        }
      }

      if (response.statusCode != 200 || _isLockedStremioResponse(response.body)) return [];
      return _parseStremioStreamsJson(response.body);
    } catch (e) {
      debugPrint('[TelegramPremium] Stremio IMDB stream error: $e');
      return [];
    }
  }

  /// Resolve streams via Stremio catalog search: /<token>/catalog/{type}/pm_catalog/search={query}.json
  static Future<List<StreamSource>> _resolveViaStremioCatalog(
    ServerConfig config,
    String title, {
    int? year,
    bool isSeries = false,
    int? season,
    int? episode,
  }) async {
    try {
      final type = isSeries ? 'series' : 'movie';
      final cleanTitle = title.replaceAll(RegExp(r'[^\w\s]'), ' ').trim();
      final catUri = Uri.parse('${config.baseUrl}${config.tokenPath}/catalog/$type/pm_catalog/search=${Uri.encodeComponent(cleanTitle)}.json');

      var catRes = await http.get(catUri, headers: {'User-Agent': 'Mozilla/5.0'}).timeout(const Duration(seconds: 8));
      if (catRes.statusCode == 401 || _isLockedStremioResponse(catRes.body)) {
        final freshToken = await loginAndRefreshToken(config.baseUrl);
        if (freshToken != null) {
          final retryCatUri = Uri.parse('${config.baseUrl}/$freshToken/catalog/$type/pm_catalog/search=${Uri.encodeComponent(cleanTitle)}.json');
          catRes = await http.get(retryCatUri, headers: {'User-Agent': 'Mozilla/5.0'}).timeout(const Duration(seconds: 8));
        }
      }
      if (catRes.statusCode != 200 || _isLockedStremioResponse(catRes.body)) return [];

      final catData = jsonDecode(catRes.body);
      final List metas = catData['metas'] ?? [];
      if (metas.isEmpty) return [];

      // Find the best matching meta
      final bestMeta = metas.first;
      final metaId = bestMeta['id']?.toString() ?? '';
      if (metaId.isEmpty) return [];

      final streamId = isSeries ? '$metaId:${season ?? 1}:${episode ?? 1}' : metaId;
      final streamUri = Uri.parse('${config.baseUrl}${config.tokenPath}/stream/$type/$streamId.json');

      var streamRes = await http.get(streamUri, headers: {'User-Agent': 'Mozilla/5.0'}).timeout(const Duration(seconds: 12));
      if (streamRes.statusCode == 401 || _isLockedStremioResponse(streamRes.body)) {
        final freshToken = await loginAndRefreshToken(config.baseUrl);
        if (freshToken != null) {
          final retryStreamUri = Uri.parse('${config.baseUrl}/$freshToken/stream/$type/$streamId.json');
          streamRes = await http.get(retryStreamUri, headers: {'User-Agent': 'Mozilla/5.0'}).timeout(const Duration(seconds: 12));
        }
      }
      if (streamRes.statusCode != 200 || _isLockedStremioResponse(streamRes.body)) return [];

      return _parseStremioStreamsJson(streamRes.body);
    } catch (e) {
      debugPrint('[TelegramPremium] Stremio catalog stream error: $e');
      return [];
    }
  }

  /// Parses Stremio JSON output into unified StreamSource objects
  static List<StreamSource> _parseStremioStreamsJson(String jsonStr) {
    try {
      final data = jsonDecode(jsonStr);
      final List rawStreams = data['streams'] ?? [];
      final List<StreamSource> list = [];

      for (final s in rawStreams) {
        final url = (s['url'] ?? s['externalUrl'] ?? '').toString();
        if (url.isEmpty || !url.contains('/api/download/')) continue;

        final behaviorHints = s['behaviorHints'] is Map ? Map<String, dynamic>.from(s['behaviorHints']) : {};
        var rawTitle = behaviorHints['filename']?.toString() ??
            (s['description']?.toString().split('\n').firstOrNull) ??
            s['name']?.toString() ??
            'Telegram Video';

        final desc = (s['description'] ?? '').toString();
        final nameHeader = (s['name'] ?? '').toString();

        int fileSize = (behaviorHints['videoSize'] as num?)?.toInt() ?? 0;
        // If fileSize is missing, decode the base64 URL payload chunk (/api/download/<base64>/...)
        if (fileSize <= 0) {
          try {
            final match = RegExp(r'/api/download/([^/]+)').firstMatch(url);
            if (match != null) {
              final rawPayload = match.group(1)!;
              final decodedStr = utf8.decode(base64.decode(base64.normalize(rawPayload)));
              final payload = jsonDecode(decodedStr);
              if (payload is Map) {
                fileSize = (payload['file_size'] as num?)?.toInt() ?? 0;
                final pName = payload['file_name']?.toString() ?? '';
                if (pName.isNotEmpty && (rawTitle.isEmpty || rawTitle == 'Telegram Video')) {
                  rawTitle = pName;
                }
              }
            }
          } catch (_) {}
        }

        final fullMeta = '$rawTitle $nameHeader $desc';
        final sizeFormatted = fileSize > 0 ? _formatBytes(fileSize) : _extractSizeFromText(desc);
        final quality = _extractQuality(fullMeta);
        final languages = _extractLanguages(fullMeta, desc);

        list.add(StreamSource(
          name: 'TG • ${_cleanTitle(rawTitle, '')}',
          url: url,
          quality: quality,
          qualityBadgeText: quality,
          size: sizeFormatted,
          languages: languages,
        ));
      }

      // Sort streams descending by file size or quality
      list.sort((a, b) {
        final qOrder = {'4K Ultra HD': 4, '1080p Full HD': 3, '720p HD': 2, '480p SD': 1};
        final qA = qOrder[a.quality] ?? 0;
        final qB = qOrder[b.quality] ?? 0;
        return qB.compareTo(qA);
      });

      return list;
    } catch (e) {
      debugPrint('[TelegramPremium] Error parsing streams JSON: $e');
      return [];
    }
  }

  /// Fallback: Searches via pencarimovie.com WP Ajax and resolves shortcodes
  static Future<List<TelegramPremiumStream>> _searchInternal(
    ServerConfig config,
    String title, {
    int? year,
    bool isSeries = false,
    int? season,
    int? episode,
  }) async {
    try {
      final cleanQuery = title
          .replaceAll(RegExp(r'[^\w\s]'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

      final searchRes = await _get(
        '/wp-admin/admin-ajax.php?action=stream_search&search=${Uri.encodeComponent(cleanQuery)}',
      );

      if (searchRes == null) return [];

      final searchJson = jsonDecode(searchRes.body);
      if (searchJson['success'] != true || searchJson['data'] is! List) return [];

      final List posts = searchJson['data'];
      if (posts.isEmpty) return [];

      // Find the best matching post ID
      Map<String, dynamic>? bestPost;
      int bestScore = -1;
      final queryTokens = cleanQuery.toLowerCase().split(' ').where((t) => t.isNotEmpty).toSet();

      for (final p in posts) {
        final postTitle = (p['title'] ?? '').toString().toLowerCase();
        int score = 0;
        for (final token in queryTokens) {
          if (postTitle.contains(token)) score += 2;
        }
        if (year != null && postTitle.contains(year.toString())) score += 5;
        final isTv = postTitle.contains('tv series') || postTitle.contains('series') || postTitle.contains('season');
        if (isSeries && isTv) score += 4;
        if (!isSeries && !isTv) score += 3;

        if (score > bestScore) {
          bestScore = score;
          bestPost = Map<String, dynamic>.from(p);
        }
      }

      if (bestPost == null || bestPost['id'] == null) return [];
      final postId = bestPost['id'];

      // Fetch files for this post
      final filesRes = await _get(
        '/wp-admin/admin-ajax.php?action=stream_post_files&post_id=$postId',
      );
      if (filesRes == null) return [];

      final filesJson = jsonDecode(filesRes.body);
      if (filesJson['success'] != true || filesJson['data'] == null || filesJson['data']['files'] is! List) {
        return [];
      }

      final List rawFiles = filesJson['data']['files'];
      final List<TelegramPremiumStream> results = [];

      for (final f in rawFiles) {
        final fMap = Map<String, dynamic>.from(f);
        final rawTitle = (fMap['title'] ?? '').toString();
        final shortCode = (fMap['short_code'] ?? '').toString();
        final fileSize = (fMap['file_size'] as num?)?.toInt() ?? 0;
        final fileSeason = (fMap['season_num'] as num?)?.toInt();
        final fileEpisode = (fMap['episode_num'] as num?)?.toInt();
        final mime = fMap['mime']?.toString();
        final thumbnailUrl = fMap['thumbnail_url']?.toString();

        if (shortCode.isEmpty || rawTitle.isEmpty) continue;

        if (isSeries && season != null) {
          final isSeasonMatch = fileSeason == season ||
              RegExp('\\b[sS]0*$season\\b').hasMatch(rawTitle);
          if (!isSeasonMatch) continue;
          if (episode != null) {
            final isEpisodeMatch = fileEpisode == episode ||
                RegExp('\\b[eE]0*$episode\\b').hasMatch(rawTitle) ||
                rawTitle.toLowerCase().contains('complete');
            if (!isEpisodeMatch) continue;
          }
        }

        // Direct seekable stream URL via active server
        final payload = {
          'short_code': shortCode,
          'file_size': fileSize,
          'file_name': rawTitle,
          'mime': mime ?? 'video/mp4',
        };
        final payloadB64 = base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '');
        final safeName = Uri.encodeComponent(rawTitle.replaceAll(RegExp(r'[^\w\.-]'), '_'));
        final playUrl = '${config.baseUrl}${config.tokenPath}/api/download/$payloadB64/$safeName';

        final cleanTitle = _cleanTitle(rawTitle, cleanQuery, year: year);
        final quality = _extractQuality(rawTitle);
        final languages = _extractLanguages(rawTitle, fMap['caption']?.toString());
        final badges = _extractBadges(rawTitle);
        final sizeFormatted = _formatBytes(fileSize);
        final startParam = '$shortCode-$postId-0';
        final botStartUrl = 'https://t.me/$_defaultBot?start=$startParam';

        results.add(TelegramPremiumStream(
          cleanTitle: cleanTitle,
          rawTitle: rawTitle,
          fileSize: fileSize,
          sizeFormatted: sizeFormatted,
          quality: quality,
          languages: languages,
          badges: badges,
          shortCode: shortCode,
          postId: (postId is int) ? postId : int.tryParse(postId.toString()) ?? 0,
          season: fileSeason,
          episode: fileEpisode,
          mime: mime,
          playUrl: playUrl,
          thumbnailUrl: thumbnailUrl,
          botStartUrl: botStartUrl,
          botStartParam: startParam,
        ));
      }

      results.sort((a, b) => b.fileSize.compareTo(a.fileSize));
      return results;
    } catch (e) {
      debugPrint('[TelegramPremium] Fallback search error: $e');
      return [];
    }
  }

  static Future<http.Response?> _get(String pathAndQuery) async {
    final domains = [_primaryDomain, _fallbackDomain];
    final headers = {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      'X-Requested-With': 'XMLHttpRequest',
      'Accept': 'application/json, text/plain, */*',
    };

    for (final domain in domains) {
      try {
        final client = http.Client();
        final response = await client.get(Uri.parse('$domain$pathAndQuery'), headers: headers).timeout(const Duration(seconds: 8));
        if (response.statusCode == 200 && response.body.trim().isNotEmpty) {
          return response;
        }
      } catch (_) {}
    }
    return null;
  }

  // --- Title, Quality, Language Parsers ---

  static String _cleanTitle(String rawTitle, String searchTitle, {int? year}) {
    var t = rawTitle;
    for (final ext in ['.mkv', '.mp4', '.avi', '.webm', '.mov', '.ts', '.m4v']) {
      if (t.toLowerCase().endsWith(ext)) {
        t = t.substring(0, t.length - ext.length);
        break;
      }
    }
    t = t.replaceAll('.', ' ').replaceAll('_', ' ').replaceAll('-', ' ');
    if (searchTitle.isNotEmpty) {
      final words = searchTitle.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
      if (words.isNotEmpty) {
        final pattern = r'\b' + words.map((w) => RegExp.escape(w)).join(r'[\s\.\-_]*') + r'\b';
        t = t.replaceAll(RegExp(pattern, caseSensitive: false), ' ');
      }
    }
    if (year != null) {
      t = t.replaceAll(RegExp('\\b$year\\b'), ' ');
    }
    t = t.replaceAll(RegExp(r'\[.*?\]'), ' ');
    t = t.replaceAll(RegExp(r'\(.*?\)'), ' ');
    t = t.replaceAll(RegExp(r'@\w+'), ' ');
    t = t.replaceAll(RegExp(r'\b(www|http|https|com|net|org)\b', caseSensitive: false), ' ');
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.isEmpty ? rawTitle : t;
  }

  static String _extractQuality(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('2160p') || lower.contains('4k') || lower.contains('uhd')) {
      return '4K Ultra HD';
    }
    if (lower.contains('1080p') || lower.contains('fhd')) {
      return '1080p Full HD';
    }
    if (lower.contains('720p') || lower.contains('hd')) {
      return '720p HD';
    }
    if (lower.contains('480p') || lower.contains('sd')) {
      return '480p SD';
    }
    return '1080p Full HD';
  }

  static List<String> _extractLanguages(String title, String? caption) {
    final combined = '$title ${caption ?? ''}'.toUpperCase();
    final List<String> langs = [];
    if (combined.contains('HIN') || combined.contains('HINDI')) langs.add('HIN');
    if (combined.contains('ENG') || combined.contains('ENGLISH')) langs.add('ENG');
    if (combined.contains('TAM') || combined.contains('TAMIL')) langs.add('TAM');
    if (combined.contains('TEL') || combined.contains('TELUGU')) langs.add('TEL');
    if (combined.contains('MAL') || combined.contains('MALAYALAM')) langs.add('MAL');
    if (combined.contains('KAN') || combined.contains('KANNADA')) langs.add('KAN');
    if (combined.contains('BEN') || combined.contains('BENGALI')) langs.add('BEN');
    if (combined.contains('MULTI') || combined.contains('DUAL AUDIO')) {
      if (!langs.contains('MULTI')) langs.add('MULTI');
    }
    return langs;
  }

  static List<String> _extractBadges(String text) {
    final upper = text.toUpperCase();
    final List<String> badges = [];
    if (upper.contains('10BIT') || upper.contains('10-BIT')) badges.add('10-Bit');
    if (upper.contains('HDR')) badges.add('HDR');
    if (upper.contains('DV') || upper.contains('DOLBY VISION')) badges.add('DV');
    if (upper.contains('HEVC') || upper.contains('X265') || upper.contains('H265')) badges.add('x265');
    if (upper.contains('ATMOS')) badges.add('Atmos');
    if (upper.contains('DDP5.1') || upper.contains('DD5.1') || upper.contains('5.1')) badges.add('5.1');
    if (upper.contains('BLURAY')) badges.add('BluRay');
    return badges;
  }

  static String _extractSizeFromText(String text) {
    final match = RegExp(r'(\d+(?:\.\d+)?\s*(?:GB|MB|KB|B))\b', caseSensitive: false).firstMatch(text);
    return match != null ? match.group(1)! : '';
  }

  static String _formatBytes(int bytes) {
    if (bytes <= 0) return '';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double dBytes = bytes.toDouble();
    while (dBytes >= 1024 && i < suffixes.length - 1) {
      dBytes /= 1024;
      i++;
    }
    return '${dBytes.toStringAsFixed(i >= 3 ? 2 : 1)} ${suffixes[i]}';
  }
}
