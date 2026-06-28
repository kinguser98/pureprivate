import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_service.dart';

/// Simple response wrapper for dart:io HttpClient responses
class _StalkerHttpResponse {
  final int statusCode;
  final String body;
  _StalkerHttpResponse(this.statusCode, this.body);
}

class StalkerStream {
  final String url;
  final Map<String, String> headers;

  StalkerStream({required this.url, required this.headers});
}

class StalkerResolver {
  static final Map<int, String> _cachedTokens = {};
  static final Map<int, String> _cachedCookiesMap = {};
  static final Map<int, DateTime> _tokenExpiries = {};
  
  static final Map<int, Map<String, dynamic>> _stalkerSettingsMap = {};
  
  static final Map<int, Map<String, String>> _portalCookiesJar = {};

  /// Merges new cookie header strings into the jar for the portal
  static void _saveCookies(int portalId, List<String> setCookieHeaders) {
    if (setCookieHeaders.isEmpty) return;
    final jar = _portalCookiesJar.putIfAbsent(portalId, () => {});
    for (final header in setCookieHeaders) {
      final parts = header.split(';');
      if (parts.isNotEmpty) {
        final pair = parts.first.split('=');
        if (pair.length >= 2) {
          final key = pair.first.trim();
          final val = pair.sublist(1).join('=').trim();
          if (key.isNotEmpty) {
            jar[key] = val;
          }
        }
      }
    }
  }

  /// Builds the full Cookie header string merging manual cookies with jar cookies
  static String _getMergedCookies(int portalId, String manualCookiesStr) {
    final jar = _portalCookiesJar[portalId];
    if (jar == null || jar.isEmpty) return manualCookiesStr;
    
    final merged = <String, String>{};
    final manualParts = manualCookiesStr.split(';');
    for (final part in manualParts) {
      final pair = part.split('=');
      if (pair.length >= 2) {
        merged[pair.first.trim()] = pair.sublist(1).join('=').trim();
      }
    }
    
    jar.forEach((key, value) {
      merged[key] = value;
    });
    
    return merged.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  /// Fetches the list of all configured portals from the backend
  static Future<List<Map<String, dynamic>>> getAllPortals() async {
    final uri = Uri.parse('${ApiService.apiUrl}?action=get_stalker_settings');
    final response = await http.get(uri).timeout(const Duration(seconds: 8));
    if (response.statusCode == 200) {
      final data = json.decode(utf8.decode(response.bodyBytes));
      if (data is List) {
        return List<Map<String, dynamic>>.from(data);
      }
    }
    return [];
  }

  /// Fetches Stalker Portal settings from the OTT backend api
  static Future<Map<String, dynamic>> _getSettings(int portalId) async {
    if (_stalkerSettingsMap.containsKey(portalId)) return _stalkerSettingsMap[portalId]!;

    final uri = Uri.parse('${ApiService.apiUrl}?action=get_stalker_settings&portal_id=$portalId');
    final response = await http.get(uri).timeout(const Duration(seconds: 8));
    
    if (response.statusCode == 200) {
      final data = json.decode(utf8.decode(response.bodyBytes));
      if (data is Map<String, dynamic> && !data.containsKey('error')) {
        _stalkerSettingsMap[portalId] = data;
        return data;
      }
      throw Exception(data['error'] ?? 'Stalker Portal settings not configured on backend.');
    }
    throw Exception('Failed to load Stalker credentials from backend.');
  }

  /// Reset cache to force re-authentication (called on playback failures)
  static void clearCache({int? portalId}) {
    if (portalId != null) {
      _cachedTokens.remove(portalId);
      _cachedCookiesMap.remove(portalId);
      _tokenExpiries.remove(portalId);
      _portalCookiesJar.remove(portalId);
    } else {
      _cachedTokens.clear();
      _cachedCookiesMap.clear();
      _tokenExpiries.clear();
      _portalCookiesJar.clear();
    }
  }

  /// Cleans the portal URL to point to portal.php
  static String _cleanPortalUrl(String rawUrl) {
    var url = rawUrl.trim();
    if (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (url.contains('/c')) {
      url = url.replaceAll(RegExp(r'\/c$'), '/server/load.php');
      url = url.replaceAll(RegExp(r'\/c\/'), '/server/load.php');
    }
    if (!url.contains('portal.php') && !url.contains('load.php')) {
      if (url.endsWith('/server')) {
        url = '$url/load.php';
      } else {
        url = '$url/server/load.php';
      }
    }
    return url;
  }

  static String _appendDeviceParams(String url, String deviceId) {
    if (deviceId.isEmpty) return url;
    final separator = url.contains('?') ? '&' : '?';
    return '$url${separator}device_id=${Uri.encodeComponent(deviceId)}&device_id2=${Uri.encodeComponent(deviceId)}';
  }

  static String _getXUserAgent(String userAgent) {
    var model = 'MAG250';
    final lowerUA = userAgent.toLowerCase();
    final match = RegExp(r'mag\d+').firstMatch(lowerUA);
    if (match != null) {
      model = match.group(0)!.toUpperCase();
    }
    return 'Model: $model; Link: Ethernet';
  }

  /// Centralized GET helper using dart:io HttpClient for better Cloudflare compatibility.
  /// dart:io handles cookies, redirects, and connection reuse properly which allows
  /// requests to pass through Cloudflare-protected Stalker portals.
  static Future<_StalkerHttpResponse> _stalkerGet(
    String url, {
    required Map<String, String> headers,
    int? portalId,
    int timeoutSeconds = 12,
  }) async {
    int attempts = 0;
    const maxAttempts = 5;
    final backoffs = [2000, 4000, 8000, 16000];

    // If portalId is provided, merge cached session cookies (like PHPSESSID)
    final Map<String, String> processedHeaders = Map.from(headers);
    if (portalId != null && processedHeaders.containsKey('Cookie')) {
      processedHeaders['Cookie'] = _getMergedCookies(portalId, processedHeaders['Cookie']!);
    }

    while (attempts < maxAttempts) {
      attempts++;
      try {
        final ioClient = HttpClient();
        ioClient.connectionTimeout = Duration(seconds: timeoutSeconds);
        // Set User-Agent from headers if provided
        if (processedHeaders.containsKey('User-Agent')) {
          ioClient.userAgent = processedHeaders['User-Agent'];
        }
        
        final request = await ioClient.getUrl(Uri.parse(url));
        // Apply all headers
        processedHeaders.forEach((key, value) {
          if (key != 'User-Agent') { // Already set above
            request.headers.set(key, value);
          }
        });
        
        final response = await request.close().timeout(Duration(seconds: timeoutSeconds));
        final body = await response.transform(utf8.decoder).join();
        ioClient.close();
        
        // Save any set cookies (like PHPSESSID) for future requests
        if (portalId != null) {
          final setCookies = response.headers[HttpHeaders.setCookieHeader];
          if (setCookies != null && setCookies.isNotEmpty) {
            _saveCookies(portalId, setCookies);
          }
        }
        
        final statusCode = response.statusCode;

        if (statusCode == 429) {
          if (attempts < maxAttempts) {
            final delay = backoffs[attempts - 1];
            debugPrint('Stalker GET rate-limited (429) on attempt $attempts. Waiting ${delay}ms to retry url: $url');
            await Future.delayed(Duration(milliseconds: delay));
            continue;
          }
        }
        return _StalkerHttpResponse(statusCode, body);
      } catch (e) {
        if (attempts >= maxAttempts) {
          rethrow;
        }
        final delay = backoffs[attempts - 1] ~/ 2;
        debugPrint('Stalker GET error on attempt $attempts ($e). Waiting ${delay}ms to retry...');
        await Future.delayed(Duration(milliseconds: delay));
      }
    }
    throw Exception('Failed after $maxAttempts attempts');
  }

  /// Performs Stalker authentication and returns session cookies & token
  static Future<String> _authenticate(int portalId, Map<String, dynamic> settings) async {
    // Return cached token if valid (less than 2 hours old)
    if (_cachedTokens.containsKey(portalId) && 
        _cachedCookiesMap.containsKey(portalId) && 
        _tokenExpiries.containsKey(portalId) && 
        _tokenExpiries[portalId]!.isAfter(DateTime.now())) {
      return _cachedTokens[portalId]!;
    }

    final portalUrl = _cleanPortalUrl(settings['portal_url'] ?? '');
    final macAddress = (settings['mac_address'] ?? '').toString().trim();
    final serialNumber = (settings['serial_number'] ?? '').toString().trim();
    var deviceId = (settings['device_id'] ?? '').toString().trim();
    if (deviceId.contains(' ')) {
      deviceId = deviceId.split(' ').last.trim();
    }
    final userAgent = (settings['user_agent'] ?? 'Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) MAG250 stbapp ver: 2 rev: 250 Safari/533.3').toString().trim();

    if (portalUrl.isEmpty || macAddress.isEmpty) {
      throw Exception('Stalker Portal URL and MAC Address must not be empty.');
    }

    // 1. Handshake request
    var handshakeUrl = '$portalUrl?type=stb&action=handshake&js=true';
    handshakeUrl = _appendDeviceParams(handshakeUrl, deviceId);
    
    var cookieStr = 'mac=$macAddress; stb_lang=en; timezone=GMT';
    if (deviceId.isNotEmpty) {
      cookieStr += '; device_id=$deviceId; device_id2=$deviceId';
    }
    
    final handshakeHeaders = {
      'User-Agent': userAgent,
      'Cookie': cookieStr,
      'X-User-Agent': _getXUserAgent(userAgent),
    };

    debugPrint('Stalker Handshake URL: $handshakeUrl');
    var handshakeRes = await _stalkerGet(handshakeUrl, headers: handshakeHeaders, portalId: portalId, timeoutSeconds: 10);
    
    if (handshakeRes.statusCode != 200) {
      throw Exception('Handshake HTTP Error: ${handshakeRes.statusCode}');
    }

    final handshakeData = json.decode(handshakeRes.body);
    String token = '';
    if (handshakeData is Map) {
      final jsVal = handshakeData['js'];
      if (jsVal is Map) {
        token = jsVal['token']?.toString() ?? '';
      } else if (jsVal is String) {
        token = jsVal;
      }
      if (token.isEmpty) {
        token = handshakeData['token']?.toString() ?? '';
      }
    } else if (handshakeData is List && handshakeData.isNotEmpty) {
      final first = handshakeData.first;
      if (first is Map) {
        final jsVal = first['js'];
        if (jsVal is Map) {
          token = jsVal['token']?.toString() ?? '';
        } else if (jsVal is String) {
          token = jsVal;
        }
        if (token.isEmpty) {
          token = first['token']?.toString() ?? '';
        }
      }
    } else if (handshakeData is String) {
      token = handshakeData;
    }
    
    if (token.isEmpty) {
      throw Exception('Failed to retrieve authentication token from handshake. Response: ${handshakeRes.body}');
    }

    // 2. Load Profile (Stalker standard initialization)
    var cookiesStr = 'mac=$macAddress; token=$token; Bearer=$token; stb_lang=en; timezone=GMT';
    if (deviceId.isNotEmpty) {
      cookiesStr += '; device_id=$deviceId; device_id2=$deviceId';
    }
    
    var profileUrl = '$portalUrl?type=stb&action=get_profile&hd=1&ver=ImageDescription&num_err=0&mac=${Uri.encodeComponent(macAddress)}&sn=${Uri.encodeComponent(serialNumber)}';
    profileUrl = _appendDeviceParams(profileUrl, deviceId);
    
    final profileHeaders = {
      'User-Agent': userAgent,
      'Cookie': cookiesStr,
      'Authorization': 'Bearer $token',
      'X-User-Agent': _getXUserAgent(userAgent),
    };

    var profileRes = await _stalkerGet(profileUrl, headers: profileHeaders, portalId: portalId, timeoutSeconds: 10);
    
    if (profileRes.statusCode != 200) {
      throw Exception('Stalker profile init failed: ${profileRes.statusCode}');
    }

    final profileData = json.decode(profileRes.body);
    if (profileData is Map && profileData['js'] is Map && profileData['js']['status'] == 1) {
      throw Exception('Stalker profile validation failed: ${profileData['js']['msg'] ?? 'Device Conflict'}');
    }

    // Cache credentials
    _cachedTokens[portalId] = token;
    _cachedCookiesMap[portalId] = cookiesStr;
    _tokenExpiries[portalId] = DateTime.now().add(const Duration(hours: 2));

    debugPrint('Stalker Auth successful. Token acquired.');
    return token;
  }

  /// Resolves the direct channel stream link from Stalker cmd
  static Future<StalkerStream> resolveStream(String cmd, int portalId, {bool isLive = true}) async {
    final settings = await _getSettings(portalId);
    
    final cmdVariations = <String>[];
    cmdVariations.add(cmd);
    
    if (!cmd.startsWith('ffmpeg ') && !cmd.startsWith('auto ')) {
      cmdVariations.add('ffmpeg $cmd');
      cmdVariations.add('auto $cmd');
    } else if (cmd.startsWith('ffmpeg ')) {
      final stripped = cmd.substring(7);
      cmdVariations.add('auto $stripped');
      cmdVariations.add(stripped);
    } else if (cmd.startsWith('auto ')) {
      final stripped = cmd.substring(5);
      cmdVariations.add('ffmpeg $stripped');
      cmdVariations.add(stripped);
    }

    dynamic lastError;

    for (int i = 0; i < cmdVariations.length; i++) {
      final currentCmd = cmdVariations[i];
      debugPrint('Stalker resolveStream trying variation $i: "$currentCmd"');
      
      try {
        final token = await _authenticate(portalId, settings);
        final stream = await _resolveSingleCmd(portalId, currentCmd, settings, token, isLive);
        debugPrint('Stalker resolveStream successful with variation: "$currentCmd"');
        return stream;
      } catch (e) {
        lastError = e;
        debugPrint('Stalker resolveStream failed for variation "$currentCmd": $e');
        
        final errStr = e.toString().toLowerCase();
        // ONLY clear auth cache if the error is related to authentication/authorization.
        // Doing so for standard stream resolution issues (like "nothing_to_play") leads to
        // rapid handshake calls and HTTP 429 Rate Limiting.
        if (!errStr.contains('nothing_to_play')) {
          debugPrint('Stalker clearing cache due to potential auth/network error: $e');
          clearCache(portalId: portalId);
        }
        
        // Short pause before next attempt if there are more variations to try
        if (i < cmdVariations.length - 1) {
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }
    }

    // Fallback: If all variations failed, check if we can play the HTTP link directly
    final userAgent = (settings['user_agent'] ?? 'Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) MAG250 stbapp ver: 2 rev: 250 Safari/533.3').toString().trim();
    final macAddress = (settings['mac_address'] ?? '').toString().trim();
    var deviceId = (settings['device_id'] ?? '').toString().trim();
    if (deviceId.contains(' ')) {
      deviceId = deviceId.split(' ').last.trim();
    }

    final portalUrl = _cleanPortalUrl(settings['portal_url'] ?? '');
    String hostBase = '';
    try {
      final uri = Uri.parse(portalUrl);
      hostBase = '${uri.scheme}://${uri.host}${uri.hasPort ? ":${uri.port}" : ""}';
    } catch (_) {}

    for (final cmdVar in cmdVariations) {
      var urlToCheck = cmdVar;
      if (urlToCheck.startsWith('ffmpeg ')) {
        urlToCheck = urlToCheck.substring(7);
      }
      if (urlToCheck.startsWith('auto ')) {
        urlToCheck = urlToCheck.substring(5);
      }
      urlToCheck = urlToCheck.trim();
      
      if (urlToCheck.startsWith('/')) {
        urlToCheck = '$hostBase$urlToCheck';
      }

      if (urlToCheck.startsWith('http://') || urlToCheck.startsWith('https://')) {
        debugPrint('Stalker VOD resolution failed via create_link, falling back to direct HTTP link: $urlToCheck');
        var playerCookies = 'mac=${Uri.encodeComponent(macAddress)}';
        if (deviceId.isNotEmpty) {
          playerCookies += '; device_id=$deviceId; device_id2=$deviceId';
        }
        return StalkerStream(
          url: urlToCheck,
          headers: {
            'User-Agent': userAgent,
            'Cookie': playerCookies,
          },
        );
      }
    }

    throw lastError ?? Exception('Failed to resolve stalker stream for cmd: $cmd');
  }

  /// Helper to resolve a single command variation
  static Future<String> _performResolveRequest(int portalId, String linkUrl, Map<String, String> headers) async {
    final response = await _stalkerGet(linkUrl, headers: headers, portalId: portalId, timeoutSeconds: 12);
    if (response.statusCode != 200) {
      throw Exception('Stalker response code: ${response.statusCode}');
    }

    final body = response.body;
    if (body.contains('Authorization failed') || body.contains('Authorisation failed')) {
      throw Exception('Authorization failed on Stalker Portal.');
    }

    final data = json.decode(body);
    String streamUrl = '';

    if (data is Map) {
      final jsVal = data['js'];
      final resultVal = data['result'];
      if (jsVal is Map) {
        streamUrl = jsVal['cmd']?.toString() ?? jsVal['url']?.toString() ?? '';
      } else if (jsVal is String) {
        streamUrl = jsVal;
      } else if (resultVal is Map) {
        streamUrl = resultVal['url']?.toString() ?? resultVal['cmd']?.toString() ?? '';
      } else if (resultVal is String) {
        streamUrl = resultVal;
      }
    } else if (data is List) {
      if (data.isNotEmpty) {
        final first = data.first;
        if (first is Map) {
          streamUrl = first['cmd']?.toString() ?? first['url']?.toString() ?? '';
        } else if (first is String) {
          streamUrl = first;
        }
      }
    } else if (data is String) {
      streamUrl = data;
    }

    return streamUrl;
  }

  static Future<StalkerStream> _resolveSingleCmd(
    int portalId,
    String cmd,
    Map<String, dynamic> settings,
    String token,
    bool isLive,
  ) async {
    final portalUrl = _cleanPortalUrl(settings['portal_url'] ?? '');
    final userAgent = (settings['user_agent'] ?? 'Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) MAG250 stbapp ver: 2 rev: 250 Safari/533.3').toString().trim();
    final macAddress = (settings['mac_address'] ?? '').toString().trim();
    var deviceId = (settings['device_id'] ?? '').toString().trim();
    if (deviceId.contains(' ')) {
      deviceId = deviceId.split(' ').last.trim();
    }

    final typeParam = isLive ? 'itv' : 'vod';
    final headers = {
      'User-Agent': userAgent,
      'Cookie': _cachedCookiesMap[portalId] ?? 'mac=${Uri.encodeComponent(macAddress)}',
      'Authorization': 'Bearer $token',
      'X-User-Agent': _getXUserAgent(userAgent),
    };

    String streamUrl = '';
    dynamic lastErr;

    // Try variation 1: standard url with extra parameters
    try {
      var linkUrl = '$portalUrl?type=$typeParam&action=create_link&cmd=${Uri.encodeComponent(cmd)}&series=0&disable_ad=1&download=0&play_lite=0';
      linkUrl = _appendDeviceParams(linkUrl, deviceId);
      debugPrint('Stalker Resolving Single Cmd (V1): $linkUrl');
      streamUrl = await _performResolveRequest(portalId, linkUrl, headers);
    } catch (e) {
      lastErr = e;
      debugPrint('Stalker resolving V1 failed: $e');
    }

    // Try variation 2: simple url if variation 1 fails
    if (streamUrl.isEmpty || streamUrl == 'nothing_to_play') {
      try {
        var linkUrl = '$portalUrl?type=$typeParam&action=create_link&cmd=${Uri.encodeComponent(cmd)}';
        linkUrl = _appendDeviceParams(linkUrl, deviceId);
        debugPrint('Stalker Resolving Single Cmd (V2 Fallback): $linkUrl');
        streamUrl = await _performResolveRequest(portalId, linkUrl, headers);
      } catch (e) {
        lastErr = e;
        debugPrint('Stalker resolving V2 fallback failed: $e');
      }
    }

    if (streamUrl.isEmpty || streamUrl == 'nothing_to_play') {
      throw lastErr ?? Exception('nothing_to_play');
    }

    // Strip ffmpeg prefix if present
    if (streamUrl.startsWith('ffmpeg ')) {
      streamUrl = streamUrl.substring(7);
    }

    // Resolve localhost / 127.0.0.1 loopbacks back to portal host
    if (streamUrl.contains('://localhost') || streamUrl.contains('://127.0.0.1')) {
      try {
        final uri = Uri.parse(portalUrl);
        streamUrl = streamUrl
            .replaceAll('://localhost', '://${uri.host}')
            .replaceAll('://127.0.0.1', '://${uri.host}');
      } catch (_) {}
    }

    var playerCookies = 'mac=${Uri.encodeComponent(macAddress)}';
    if (deviceId.isNotEmpty) {
      playerCookies += '; device_id=$deviceId; device_id2=$deviceId';
    }

    return StalkerStream(
      url: streamUrl,
      headers: {
        'User-Agent': userAgent,
        'Cookie': playerCookies,
      },
    );
  }

  /// Resolves logo request headers including user agent and portal MAC cookie.
  static Future<Map<String, String>> getLogoHeaders(int portalId) async {
    try {
      final settings = await _getSettings(portalId);
      final macAddress = (settings['mac_address'] ?? '').toString().trim();
      final userAgent = (settings['user_agent'] ?? 'Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) MAG250 stbapp ver: 2 rev: 250 Safari/533.3').toString().trim();
      var deviceId = (settings['device_id'] ?? '').toString().trim();
      if (deviceId.contains(' ')) {
        deviceId = deviceId.split(' ').last.trim();
      }
      var playerCookies = 'mac=${Uri.encodeComponent(macAddress)}';
      if (deviceId.isNotEmpty) {
        playerCookies += '; device_id=$deviceId; device_id2=$deviceId';
      }
      return {
        'User-Agent': userAgent,
        'Cookie': playerCookies,
      };
    } catch (e) {
      debugPrint('Error getting logo headers: $e');
      return {};
    }
  }

  /// Resolves relative Stalker Portal logo paths to absolute URLs
  static String resolveStalkerLogo(String logo, String portalUrl) {
    logo = logo.trim();
    if (logo.isEmpty) return '';
    if (logo.startsWith('http://') || logo.startsWith('https://')) {
      return logo;
    }
    
    try {
      final uri = Uri.parse(portalUrl);
      final hostBase = '${uri.scheme}://${uri.host}${uri.hasPort ? ":${uri.port}" : ""}';
      
      var portalBase = portalUrl.trim();
      if (portalBase.endsWith('/')) {
        portalBase = portalBase.substring(0, portalBase.length - 1);
      }
      portalBase = portalBase.replaceAll(RegExp(r'\/server\/load\.php$'), '');
      portalBase = portalBase.replaceAll(RegExp(r'\/c$'), '');
      portalBase = portalBase.replaceAll(RegExp(r'\/portal\.php$'), '');
      if (portalBase.endsWith('/')) {
        portalBase = portalBase.substring(0, portalBase.length - 1);
      }

      String resolved = logo;
      if (logo.startsWith('/')) {
        resolved = '$hostBase$logo';
      } else if (logo.contains('/')) {
        resolved = '$portalBase/$logo';
      } else {
        // Just a filename (e.g. 1.png), map to standard misc/logos/240/ folder
        resolved = '$portalBase/misc/logos/240/$logo';
      }

      // Ensure resolution folder is present in the path if it is under misc/logos
      if (resolved.contains('/misc/logos/') && !resolved.contains('/misc/logos/240/') && !resolved.contains('/misc/logos/320/')) {
        resolved = resolved.replaceAll('/misc/logos/', '/misc/logos/240/');
      }

      return resolved;
    } catch (e) {
      return logo;
    }
  }

  /// Syncs all channels from the Stalker Portal directly to the OTT backend server database.
  /// Bypasses server-side Cloudflare blocks because this runs from a clean client-side IP.
  static Future<Map<String, dynamic>> syncChannelsToServer(int portalId) async {
    try {
      final settings = await _getSettings(portalId);
      final token = await _authenticate(portalId, settings);
      
      final portalUrl = _cleanPortalUrl(settings['portal_url'] ?? '');
      final userAgent = (settings['user_agent'] ?? 'Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) MAG250 stbapp ver: 2 rev: 250 Safari/533.3').toString().trim();
      var deviceId = (settings['device_id'] ?? '').toString().trim();
      if (deviceId.contains(' ')) {
        deviceId = deviceId.split(' ').last.trim();
      }

      // 1. Fetch categories (genres)
      var genresUrl = '$portalUrl?type=itv&action=get_genres';
      genresUrl = _appendDeviceParams(genresUrl, deviceId);

      final headers = {
        'User-Agent': userAgent,
        'Cookie': _cachedCookiesMap[portalId]!,
        'Authorization': 'Bearer $token',
        'X-User-Agent': _getXUserAgent(userAgent),
      };

      final genresResponse = await _stalkerGet(genresUrl, headers: headers, portalId: portalId, timeoutSeconds: 12);
      final Map<String, String> genresMap = {};
      
      if (genresResponse.statusCode == 200) {
        final genresData = json.decode(genresResponse.body);
        dynamic genresList = [];
        if (genresData is Map) {
          genresList = genresData['js'] ?? genresData['result'] ?? [];
          if (genresList is! List && genresData['js'] is Map) {
            genresList = genresData['js']['data'] ?? [];
          }
        } else if (genresData is List) {
          genresList = genresData;
        }
        if (genresList is List) {
          for (final g in genresList) {
            if (g is Map) {
              final id = g['id']?.toString() ?? '';
              final title = g['title']?.toString() ?? '';
              if (id.isNotEmpty && title.isNotEmpty) {
                genresMap[id] = title;
              }
            }
          }
        }
      }

      // 2. Fetch all channels
      var channelsUrl = '$portalUrl?type=itv&action=get_all_channels';
      channelsUrl = _appendDeviceParams(channelsUrl, deviceId);

      final channelsResponse = await _stalkerGet(channelsUrl, headers: headers, portalId: portalId, timeoutSeconds: 20);
      
      if (channelsResponse.statusCode != 200) {
        throw Exception('Failed to fetch channels from portal. HTTP: ${channelsResponse.statusCode}');
      }

      final channelsData = json.decode(channelsResponse.body);
      dynamic rawChannelsList = [];
      if (channelsData is Map) {
        rawChannelsList = channelsData['result'] ?? [];
        if (rawChannelsList is! List && channelsData['result'] is Map) {
          rawChannelsList = channelsData['result']['data'] ?? [];
        }
        if (rawChannelsList is! List || rawChannelsList.isEmpty) {
          if (channelsData['js'] is Map) {
            rawChannelsList = channelsData['js']['data'] ?? [];
          } else if (channelsData['js'] is List) {
            rawChannelsList = channelsData['js'];
          }
        }
      } else if (channelsData is List) {
        rawChannelsList = channelsData;
      }

      if (rawChannelsList is! List || rawChannelsList.isEmpty) {
        throw Exception('Stalker Portal returned no channels or invalid response format. Response: ${channelsResponse.body}');
      }

      // 3. Format channels payload
      final List<Map<String, dynamic>> payload = [];
      for (final ch in rawChannelsList) {
        final id = ch['id']?.toString() ?? ch['number']?.toString() ?? '';
        final name = ch['name']?.toString() ?? '';
        final logo = ch['logo']?.toString() ?? '';
        final cmd = ch['cmd']?.toString() ?? '';
        
        final catId = ch['tv_genre_id']?.toString() ?? '';
        var category = ch['genres_str']?.toString() ?? '';
        if (category.isEmpty && catId.isNotEmpty && genresMap.containsKey(catId)) {
          category = genresMap[catId]!;
        }
        if (category.isEmpty) {
          category = 'General';
        }

        final logoUrl = resolveStalkerLogo(logo, portalUrl);

        if (id.isNotEmpty && name.isNotEmpty && cmd.isNotEmpty) {
          payload.add({
            'id': id,
            'name': name,
            'logo_url': logoUrl,
            'cmd': cmd,
            'category_name': category,
          });
        }
      }

      // 4. Send to OTT backend
      final uploadUrl = '${ApiService.apiUrl}?action=import_channels_client&portal_id=$portalId';
      final uploadResponse = await http.post(
        Uri.parse(uploadUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(payload),
      ).timeout(const Duration(seconds: 15));

      if (uploadResponse.statusCode == 200) {
        final uploadResult = json.decode(uploadResponse.body);
        if (uploadResult['success'] == true) {
          return {
            'success': true,
            'imported': uploadResult['imported'] ?? payload.length,
          };
        }
        throw Exception(uploadResult['error'] ?? 'Server failed to save channels.');
      }
      throw Exception('Server returned HTTP Error: ${uploadResponse.statusCode}');
    } catch (e) {
      debugPrint('Stalker client-side sync failed: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Fetches VOD categories from Stalker Portal.
  static Future<List<Map<String, String>> > getVodCategories(int portalId) async {
    final settings = await _getSettings(portalId);
    final portalUrl = _cleanPortalUrl(settings['portal_url'] ?? '');
    final userAgent = (settings['user_agent'] ?? 'Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) MAG250 stbapp ver: 2 rev: 250 Safari/533.3').toString().trim();
    var deviceId = (settings['device_id'] ?? '').toString().trim();
    if (deviceId.contains(' ')) {
      deviceId = deviceId.split(' ').last.trim();
    }

    Future<_StalkerHttpResponse> getWithRetry(String url) async {
      final currentToken = _cachedTokens[portalId] ?? await _authenticate(portalId, settings);
      final currentHeaders = {
        'User-Agent': userAgent,
        'Cookie': _cachedCookiesMap[portalId]!,
        'Authorization': 'Bearer $currentToken',
        'X-User-Agent': _getXUserAgent(userAgent),
      };
      
      var response = await _stalkerGet(url, headers: currentHeaders, portalId: portalId, timeoutSeconds: 15);

      if (response.statusCode == 200) {
        final body = response.body;
        if (!body.contains('Authorization failed') && !body.contains('Authorisation failed')) {
          return response;
        }
      }
      
      debugPrint('Stalker request failed or unauthorized, retrying handshake...');
      clearCache(portalId: portalId);
      
      final newToken = await _authenticate(portalId, settings);
      final newHeaders = {
        'User-Agent': userAgent,
        'Cookie': _cachedCookiesMap[portalId]!,
        'Authorization': 'Bearer $newToken',
        'X-User-Agent': _getXUserAgent(userAgent),
      };
      
      var responseRetry = await _stalkerGet(url, headers: newHeaders, portalId: portalId, timeoutSeconds: 15);

      if (responseRetry.statusCode != 200 || responseRetry.body.contains('Authorization failed') || responseRetry.body.contains('Authorisation failed')) {
        throw Exception('Stalker request failed: HTTP ${responseRetry.statusCode}');
      }
      
      return responseRetry;
    }

    var categoriesUrl = '$portalUrl?type=vod&action=get_categories';
    categoriesUrl = _appendDeviceParams(categoriesUrl, deviceId);
    final categoriesResponse = await getWithRetry(categoriesUrl);
    
    final List<Map<String, String>> categoriesList = [];
    if (categoriesResponse.statusCode == 200) {
      final categoriesData = json.decode(categoriesResponse.body);
      dynamic rawList = [];
      if (categoriesData is Map) {
        rawList = categoriesData['js'] ?? categoriesData['result'] ?? [];
        if (rawList is! List && categoriesData['js'] is Map) {
          rawList = categoriesData['js']['data'] ?? [];
        }
      } else if (categoriesData is List) {
        rawList = categoriesData;
      }
      if (rawList is List) {
        for (final c in rawList) {
          if (c is Map) {
            final id = c['id']?.toString() ?? '';
            final title = c['title']?.toString() ?? c['name']?.toString() ?? '';
            if (id.isNotEmpty) {
              categoriesList.add({'id': id, 'title': title});
            }
          }
        }
      }
    }
    return categoriesList;
  }

  /// Syncs all or selected VOD movies from the Stalker Portal directly to the OTT backend server database.
  /// Bypasses server-side Cloudflare/datacenter IP blocks because this runs from a clean client-side IP.
  static Future<Map<String, dynamic>> syncVodsToServer({
    required int portalId,
    List<String>? selectedCategoryIds,
    void Function(String categoryName, int currentPage, int totalPages, int totalAccumulated)? onProgress,
  }) async {
    try {
      final settings = await _getSettings(portalId);
      final portalUrl = _cleanPortalUrl(settings['portal_url'] ?? '');
      final userAgent = (settings['user_agent'] ?? 'Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) MAG250 stbapp ver: 2 rev: 250 Safari/533.3').toString().trim();
      var deviceId = (settings['device_id'] ?? '').toString().trim();
      if (deviceId.contains(' ')) {
        deviceId = deviceId.split(' ').last.trim();
      }

      // Auto-retry helper for requests that handle authorization loss or rate limit (429)
       Future<_StalkerHttpResponse> getWithRetry(String url) async {
        final currentToken = _cachedTokens[portalId] ?? await _authenticate(portalId, settings);
        final currentHeaders = {
          'User-Agent': userAgent,
          'Cookie': _cachedCookiesMap[portalId]!,
          'Authorization': 'Bearer $currentToken',
          'X-User-Agent': _getXUserAgent(userAgent),
        };
        
        var response = await _stalkerGet(url, headers: currentHeaders, portalId: portalId, timeoutSeconds: 15);

        if (response.statusCode == 200) {
          final body = response.body;
          if (!body.contains('Authorization failed') && !body.contains('Authorisation failed')) {
            return response;
          }
        }
        
        // Clear cache and try once more
        debugPrint('Stalker request failed or unauthorized, retrying handshake...');
        clearCache(portalId: portalId);
        
        final newToken = await _authenticate(portalId, settings);
        final newHeaders = {
          'User-Agent': userAgent,
          'Cookie': _cachedCookiesMap[portalId]!,
          'Authorization': 'Bearer $newToken',
          'X-User-Agent': _getXUserAgent(userAgent),
        };
        
        var responseRetry = await _stalkerGet(url, headers: newHeaders, portalId: portalId, timeoutSeconds: 15);

        if (responseRetry.statusCode != 200 || responseRetry.body.contains('Authorization failed') || responseRetry.body.contains('Authorisation failed')) {
          throw Exception('Stalker request failed: HTTP ${responseRetry.statusCode}');
        }
        
        return responseRetry;
      }

      // 1. Fetch VOD categories
      var categoriesUrl = '$portalUrl?type=vod&action=get_categories';
      categoriesUrl = _appendDeviceParams(categoriesUrl, deviceId);
      final categoriesResponse = await getWithRetry(categoriesUrl);
      
      final List<Map<String, String>> categoriesList = [];
      if (categoriesResponse.statusCode == 200) {
        final categoriesData = json.decode(categoriesResponse.body);
        dynamic rawList = [];
        if (categoriesData is Map) {
          rawList = categoriesData['js'] ?? categoriesData['result'] ?? [];
          if (rawList is! List && categoriesData['js'] is Map) {
            rawList = categoriesData['js']['data'] ?? [];
          }
        } else if (categoriesData is List) {
          rawList = categoriesData;
        }
        if (rawList is List) {
          for (final c in rawList) {
            if (c is Map) {
              final id = c['id']?.toString() ?? '';
              final title = c['title']?.toString() ?? c['name']?.toString() ?? '';
              if (id.isNotEmpty) {
                categoriesList.add({'id': id, 'title': title});
              }
            }
          }
        }
      }

      if (categoriesList.isEmpty) {
        throw Exception('No VOD categories found on Stalker Portal.');
      }

      final Set<String> seenIds = {};
      int totalImported = 0;

      // Filter target categories based on selection or defaults
      final List<Map<String, String>> targetCategories;
      if (selectedCategoryIds != null) {
        targetCategories = categoriesList.where((cat) => selectedCategoryIds.contains(cat['id'])).toList();
      } else {
        // Filter out 'All' categories if there are other specific categories available
        final specificCategories = categoriesList.where((cat) {
          final id = cat['id']!;
          final title = cat['title']!;
          final lowerId = id.toLowerCase().trim();
          final lowerTitle = title.toLowerCase().trim();
          return lowerId != '*' &&
                 lowerId != '0' &&
                 lowerId != 'all' &&
                 lowerTitle != 'all' &&
                 lowerTitle != 'all movies' &&
                 lowerTitle != 'all vods' &&
                 lowerTitle != 'all vod' &&
                 !lowerTitle.contains('all channels');
        }).toList();
        targetCategories = specificCategories.isNotEmpty ? specificCategories : categoriesList;
      }

      // 2. Fetch movies per category
      for (final cat in targetCategories) {
        final catId = cat['id']!;
        final catTitle = cat['title']!;
        final List<Map<String, dynamic>> categoryPayload = [];
        int totalPagesVal = 1;
        
        // Notify start of category
        onProgress?.call(catTitle, 1, 1, totalImported);
        
        try {
          // Pacing delay between categories to prevent HTTP 429
          await Future.delayed(const Duration(milliseconds: 200));
          
          final Set<String> seenIdsThisCategory = {};
          int currentPage = 1;
          bool hasMore = true;
          int consecutiveFailures = 0;
          
          while (hasMore && currentPage <= 3000) { // Limit to 3000 pages to prevent infinite loops
            dynamic moviesData;
            dynamic rawMoviesList;
            
            try {
              var moviesUrl = '$portalUrl?type=vod&action=get_ordered_list&category=$catId&p=$currentPage';
              moviesUrl = _appendDeviceParams(moviesUrl, deviceId);
              
              final moviesResponse = await getWithRetry(moviesUrl);
              final responseBody = moviesResponse.body;
              moviesData = json.decode(responseBody);
              rawMoviesList = [];
              
              if (moviesData is Map) {
                rawMoviesList = moviesData['result'] ?? [];
                if (rawMoviesList is! List && moviesData['result'] is Map) {
                  rawMoviesList = moviesData['result']['data'] ?? [];
                }
                if (rawMoviesList is! List || rawMoviesList.isEmpty) {
                  if (moviesData['js'] is Map) {
                    rawMoviesList = moviesData['js']['data'] ?? [];
                  } else if (moviesData['js'] is List) {
                    rawMoviesList = moviesData['js'];
                  }
                }
              } else if (moviesData is List) {
                rawMoviesList = moviesData;
              }
              consecutiveFailures = 0; // Reset count on success
            } catch (pageError) {
              consecutiveFailures++;
              debugPrint('Error syncing page $currentPage of category $catTitle: $pageError. Consecutive failures: $consecutiveFailures');
              if (consecutiveFailures >= 3) {
                debugPrint('Too many consecutive failures on page $currentPage. Skipping page.');
                currentPage++;
                consecutiveFailures = 0;
              } else {
                await Future.delayed(const Duration(seconds: 1));
              }
              continue;
            }
            
            if (rawMoviesList is! List || rawMoviesList.isEmpty) {
              hasMore = false;
              break;
            }
            
            int newItemsThisCategoryCount = 0;
            for (final m in rawMoviesList) {
              final id = m['id']?.toString() ?? '';
              final name = m['name']?.toString() ?? m['title']?.toString() ?? m['o_name']?.toString() ?? '';
              final logo = m['logo']?.toString() ?? 
                           m['logo_url']?.toString() ?? 
                           m['pic']?.toString() ?? 
                           m['screenshot_uri']?.toString() ?? '';
              final cmd = m['cmd']?.toString() ?? m['path']?.toString() ?? '';
              
              final logoUrl = resolveStalkerLogo(logo, portalUrl);
              
              if (id.isNotEmpty && name.isNotEmpty && cmd.isNotEmpty) {
                if (!seenIdsThisCategory.contains(id)) {
                  seenIdsThisCategory.add(id);
                  newItemsThisCategoryCount++;
                }
                if (!seenIds.contains(id)) {
                  seenIds.add(id);
                  categoryPayload.add({
                    'id': id,
                    'name': name,
                    'logo_url': logoUrl,
                    'cmd': cmd,
                    'category_name': catTitle,
                  });
                }
              }
            }
            
            // If we didn't find any new items for this CATEGORY on this page, it means we are looping
            // or we reached the end of the category VODs.
            if (newItemsThisCategoryCount == 0) {
              hasMore = false;
              break;
            }
            
            // Check if we retrieved all items or reached end of pagination
            if (moviesData is Map) {
              final jsVal = moviesData['js'];
              final resultVal = moviesData['result'];
              dynamic totalItems;
              if (jsVal is Map) {
                totalItems = jsVal['total_items'];
              }
              if (totalItems == null && resultVal is Map) {
                totalItems = resultVal['total_items'];
              }
              if (totalItems != null) {
                final totalCount = int.tryParse(totalItems.toString()) ?? 0;
                totalPagesVal = (totalCount / 14).ceil();
                if (currentPage >= totalPagesVal) {
                  hasMore = false;
                }
              }
            }
            
            if (rawMoviesList.length < 14) {
              hasMore = false;
            }
            
            // Notify page progress
            onProgress?.call(catTitle, currentPage, totalPagesVal, totalImported);

            // Incremental Upload in chunks of 300 to prevent OOM
            if (categoryPayload.isNotEmpty && categoryPayload.length >= 300) {
              final uploadUrl = '${ApiService.apiUrl}?action=import_stalker_vods_client&portal_id=$portalId';
              final uploadResponse = await http.post(
                Uri.parse(uploadUrl),
                headers: {'Content-Type': 'application/json'},
                body: json.encode(categoryPayload),
              ).timeout(const Duration(seconds: 25));

              if (uploadResponse.statusCode == 200) {
                final uploadResult = json.decode(uploadResponse.body);
                if (uploadResult is Map && uploadResult['success'] == true) {
                  final importedThisBatch = (uploadResult['imported'] as num?)?.toInt() ?? categoryPayload.length;
                  totalImported += importedThisBatch;
                  onProgress?.call(catTitle, currentPage, totalPagesVal, totalImported);
                }
              }
              categoryPayload.clear();
            }
            
            if (hasMore) {
              currentPage++;
              // Pause slightly between requests (200ms is safe and fast)
              await Future.delayed(const Duration(milliseconds: 200));
            }
          }

          // Upload remaining VOD movies for this category
          if (categoryPayload.isNotEmpty) {
            final uploadUrl = '${ApiService.apiUrl}?action=import_stalker_vods_client&portal_id=$portalId';
            final uploadResponse = await http.post(
              Uri.parse(uploadUrl),
              headers: {'Content-Type': 'application/json'},
              body: json.encode(categoryPayload),
            ).timeout(const Duration(seconds: 25));

            if (uploadResponse.statusCode == 200) {
              final uploadResult = json.decode(uploadResponse.body);
              if (uploadResult is Map && uploadResult['success'] == true) {
                final importedThisCat = (uploadResult['imported'] as num?)?.toInt() ?? categoryPayload.length;
                totalImported += importedThisCat;
                onProgress?.call(catTitle, currentPage, totalPagesVal, totalImported);
              }
            }
          }
        } catch (e) {
          debugPrint('Error syncing category $catTitle (ID: $catId): $e. Skipping.');
        }
      }

      if (totalImported == 0) {
        debugPrint('Stalker sync finished: 0 new movies imported (library is up-to-date).');
      }

      return {
        'success': true,
        'imported': totalImported,
      };
    } catch (e) {
      debugPrint('Stalker client-side VOD sync failed: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }
}
