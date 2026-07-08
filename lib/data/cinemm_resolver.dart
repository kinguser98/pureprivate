import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:private_cinema_mobile/widgets/special_search_dialog.dart';

class CinemmResolver {
  static const String _mainUrl = 'https://cinemm.com';
  static const Map<String, String> _actions = {
    'search': '6018fac11e9b775fd3a7f877cdc4ab1b312b8e978c',
    'quotaReset': '6077a1a88313137459881a82cca9e76114af8993f6',
    'movieServers': '401dd7f7ed7453fdfdcc55d28458444ecec9e4cc8d',
  };

  static const List<String> _mobileUserAgents = [
    'Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
    'Mozilla/5.0 (Linux; Android 13; SM-G991B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Mobile Safari/537.36',
    'Mozilla/5.0 (Linux; Android 12; Pixel 6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/115.0.0.0 Mobile Safari/537.36',
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
  ];

  static Future<List<StreamSourceInfo>> resolveStreams({
    required String title,
    String? year,
  }) async {
    final userAgent =
        _mobileUserAgents[Random().nextInt(_mobileUserAgents.length)];

    try {
      final cookie = await _resetQuota(userAgent);
      if (cookie == null || cookie.isEmpty) return [];

      final results = await _search(title, cookie, userAgent);
      if (results.isEmpty) return [];

      final match = _findBestMatch(title, year, results);
      if (match == null) return [];

      final id = match['id']?.toString();
      if (id == null || id.isEmpty) return [];

      final servers = await _getMovieServers(id, cookie, userAgent);
      return _buildSources(
        servers,
        match['name']?.toString() ?? title,
        userAgent,
      );
    } catch (e) {
      debugPrint('CinemmResolver failed: $e');
      return [];
    }
  }

  static Future<HttpClientResponse> _callAction({
    required String action,
    required String body,
    required String userAgent,
    String? cookie,
    String? referer,
  }) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.postUrl(Uri.parse(_mainUrl));
      req.headers.set(HttpHeaders.userAgentHeader, userAgent);
      req.headers.set(HttpHeaders.acceptHeader, 'text/x-component');
      req.headers.set(
        HttpHeaders.contentTypeHeader,
        'text/plain;charset=UTF-8',
      );
      req.headers.set('next-action', action);
      req.headers.set(HttpHeaders.refererHeader, referer ?? '$_mainUrl/');
      if (cookie != null && cookie.isNotEmpty) {
        req.headers.set(HttpHeaders.cookieHeader, cookie);
      }
      req.write(body);
      final res = await req.close().timeout(const Duration(seconds: 20));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('CineMM action failed: HTTP ${res.statusCode}');
      }
      return res;
    } catch (_) {
      client.close(force: true);
      rethrow;
    }
  }

  static Future<String?> _resetQuota(String userAgent) async {
    final randomHex = List.generate(
      32,
      (_) => Random().nextInt(16).toRadixString(16),
    ).join();
    final res = await _callAction(
      action: _actions['quotaReset']!,
      body: jsonEncode([randomHex, r'$undefined']),
      userAgent: userAgent,
      referer: '$_mainUrl/',
    );

    final headerCookie = _extractCookieFromHeaders(res.headers);
    final body = await res.transform(utf8.decoder).join();
    res.detachSocket().then((s) => s.destroy());
    return headerCookie ?? _extractUuidFromBody(body);
  }

  static Future<List<dynamic>> _search(
    String title,
    String cookie,
    String userAgent,
  ) async {
    final referer =
        '$_mainUrl/?search=${Uri.encodeComponent(title)}&type=movie';
    final res = await _callAction(
      action: _actions['search']!,
      body: jsonEncode([title, 'movie']),
      userAgent: userAgent,
      cookie: cookie,
      referer: referer,
    );
    final body = await res.transform(utf8.decoder).join();
    res.detachSocket().then((s) => s.destroy());
    final parsed = _extractJsonValue(body, '1:[');
    return parsed is List ? parsed : [];
  }

  static Future<List<dynamic>> _getMovieServers(
    String id,
    String cookie,
    String userAgent,
  ) async {
    final res = await _callAction(
      action: _actions['movieServers']!,
      body: jsonEncode([
        [id],
      ]),
      userAgent: userAgent,
      cookie: cookie,
      referer: '$_mainUrl/',
    );
    final body = await res.transform(utf8.decoder).join();
    res.detachSocket().then((s) => s.destroy());
    final parsed = _extractJsonValue(body, '1:{"servers"');
    if (parsed is Map && parsed['servers'] is List) {
      return parsed['servers'] as List<dynamic>;
    }
    return [];
  }

  static Map<String, dynamic>? _findBestMatch(
    String title,
    String? year,
    List<dynamic> results,
  ) {
    Map<String, dynamic>? best;
    var bestScore = 0.0;

    for (final item in results) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final candidateTitle =
          map['name']?.toString() ?? map['title']?.toString() ?? '';
      var score = _similarity(title, candidateTitle, year);
      final candidateYear = map['year']?.toString();
      final isShortTitle = title.trim().split(RegExp(r'\s+')).length <= 3;
      if (isShortTitle &&
          year != null &&
          year.isNotEmpty &&
          candidateYear != null &&
          candidateYear.isNotEmpty) {
        final expected = int.tryParse(year);
        final actual = int.tryParse(candidateYear);
        if (expected != null &&
            actual != null &&
            (expected - actual).abs() > 2) {
          score -= 0.5;
        }
      }
      if (score > bestScore && score >= 0.4) {
        bestScore = score;
        best = map;
      }
    }

    return best;
  }

  static List<StreamSourceInfo> _buildSources(
    List<dynamic> servers,
    String matchedTitle,
    String userAgent,
  ) {
    final seen = <String>{};
    final sources = <StreamSourceInfo>[];

    for (final item in servers) {
      if (item is! Map) continue;
      final server = Map<String, dynamic>.from(item);
      final url = server['url']?.toString() ?? '';
      if (url.isEmpty || seen.contains(url)) continue;
      seen.add(url);

      final quality = _normalizeQuality(
        server['quality']?.toString() ?? server['name']?.toString() ?? '',
      );
      final size = server['size']?.toString();
      final headers = jsonEncode({
        'Referer': '$_mainUrl/',
        'User-Agent': userAgent,
      });
      final finalUrl = Uri.parse(url)
          .replace(
            queryParameters: {
              ...Uri.parse(url).queryParameters,
              'headers': headers,
            },
          )
          .toString();

      sources.add(
        StreamSourceInfo(
          name:
              'CineMM: $matchedTitle | $quality${size != null && size.isNotEmpty ? ' ($size)' : ''}',
          url: finalUrl,
          type: StreamSourceType.cinemm,
        ),
      );
    }

    return sources;
  }

  static dynamic _extractJsonValue(String text, String marker) {
    final start = text.indexOf(marker);
    if (start == -1) return null;

    final jsonStart = start + 2;
    if (jsonStart >= text.length) return null;
    final first = text[jsonStart];
    if (first != '[' && first != '{') return null;

    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = jsonStart; i < text.length; i++) {
      final char = text[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (char == r'\' && inString) {
        escaped = true;
        continue;
      }
      if (char == '"') {
        inString = !inString;
        continue;
      }
      if (!inString) {
        if (char == '[' || char == '{') {
          depth++;
        } else if (char == ']' || char == '}') {
          depth--;
          if (depth == 0) {
            return jsonDecode(text.substring(jsonStart, i + 1));
          }
        }
      }
    }
    return null;
  }

  static String? _extractCookieFromHeaders(HttpHeaders headers) {
    final values = headers[HttpHeaders.setCookieHeader];
    if (values == null) return null;
    for (final value in values) {
      final match = RegExp(r'user_uuid=([^;]+)').firstMatch(value);
      if (match != null) return 'user_uuid=${match.group(1)}';
    }
    return null;
  }

  static String? _extractUuidFromBody(String body) {
    final uuid = RegExp(
      r'"uuid":\s*"([a-f0-9-]{36})"',
      caseSensitive: false,
    ).firstMatch(body);
    if (uuid != null) return 'user_uuid=${uuid.group(1)}';
    final userUuid = RegExp(
      r'"user_uuid":\s*"([^"]+)"',
      caseSensitive: false,
    ).firstMatch(body);
    if (userUuid != null) return 'user_uuid=${userUuid.group(1)}';
    return null;
  }

  static double _similarity(String expected, String actual, String? year) {
    if (expected.isEmpty || actual.isEmpty) return 0;
    final expectedTokens = _tokens(expected);
    final actualTokens = _tokens(actual).toSet();
    if (expectedTokens.isEmpty) return 0;

    final matches = expectedTokens.where(actualTokens.contains).length;
    var score = matches / expectedTokens.length;
    if (year != null && year.isNotEmpty && actual.contains(year)) score += 0.25;
    if (actual.toLowerCase().contains(expected.toLowerCase())) score += 0.15;
    return score.clamp(0.0, 1.0);
  }

  static List<String> _tokens(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
  }

  static String _normalizeQuality(String value) {
    final lower = value.toLowerCase();
    if (lower.contains('2160') ||
        lower.contains('4k') ||
        lower.contains('uhd')) {
      return '2160p';
    }
    if (lower.contains('1440')) return '1440p';
    if (lower.contains('1080')) return '1080p';
    if (lower.contains('720')) return '720p';
    if (lower.contains('480')) return '480p';
    if (lower.contains('360')) return '360p';
    return 'HD';
  }
}
