import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:private_cinema_ios/widgets/special_search_dialog.dart';

class MovieboxResolver {
  static const String _apiBase = 'https://api3.aoneroom.com';
  static const String _keyB64Default =
      'NzZpUmwwN3MweFNOOWpxbUVXQXQ3OUVCSlp1bElRSXNWNjRGWnIyTw==';

  static const Map<String, List<String>> _brandModels = {
    'Samsung': ['SM-S918B', 'SM-A528B'],
    'Xiaomi': ['2201117TI', 'Redmi Note 11'],
    'Google': ['Pixel 7', 'Pixel 8'],
  };

  static String? _bearerToken;
  static String? _deviceId;
  static String? _brand;
  static String? _model;

  static void _init() {
    if (_deviceId != null) return;
    final r = Random();
    const hex = '0123456789abcdef';
    _deviceId = List.generate(32, (_) => hex[r.nextInt(16)]).join();
    final brands = _brandModels.keys.toList();
    _brand = brands[r.nextInt(brands.length)];
    _model = _brandModels[_brand!]![r.nextInt(_brandModels[_brand!]!.length)];
  }

  static String _md5(String s) => md5.convert(utf8.encode(s)).toString();

  static String _hmacMd5B64(List<int> key, String data) =>
      base64.encode(Hmac(md5, key).convert(utf8.encode(data)).bytes);

  static List<int> get _secretKey {
    final s = utf8.decode(base64.decode(_keyB64Default));
    return base64.decode(s);
  }

  static String _xClientToken(int ts) {
    final s = ts.toString();
    return '$s,${_md5(s.split('').reversed.join())}';
  }

  static String _buildSig(String method, String accept, String ct, String url, String? body, int ts) {
    final uri = Uri.parse(url);
    final keys = uri.queryParametersAll.keys.toList()..sort();
    final parts = <String>[];
    for (final k in keys) {
      final vals = List<String>.from(uri.queryParametersAll[k]!)..sort();
      for (final v in vals) parts.add('$k=$v');
    }
    final q = parts.join('&');
    final cu = q.isNotEmpty ? '${uri.path}?$q' : uri.path;
    var bh = '';
    var bl = '';
    if (body != null && body.isNotEmpty) {
      final bb = utf8.encode(body);
      bl = bb.length.toString();
      bh = md5.convert(bb).toString();
    }
    final canonical =
        '${method.toUpperCase()}\n$accept\n$ct\n$bl\n$ts\n$bh\n$cu';
    return '$ts|2|${_hmacMd5B64(_secretKey, canonical)}';
  }

  static Future<(Map<String, dynamic>?, Map<String, String>)> _request({
    required String method,
    required String url,
    String? body,
    String? token,
  }) async {
    _init();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final ct = body != null ? 'application/json; charset=utf-8' : 'application/json';
    const accept = 'application/json';
    final sig = _buildSig(method, accept, ct, url, body, ts);
    final clientInfo = jsonEncode({
      'package_name': 'com.community.mbox.in',
      'version_name': '3.0.03.0529.03',
      'version_code': 50020042,
      'os': 'android',
      'os_version': '16',
      'device_id': _deviceId,
      'install_store': 'ps',
      'gaid': 'd7578036d13336cc',
      'brand': _brand!.toLowerCase(),
      'model': _model,
      'system_language': 'en',
      'net': 'NETWORK_WIFI',
      'region': 'IN',
      'timezone': 'Asia/Calcutta',
      'sp_code': '',
    });

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final uri = Uri.parse(url);
      final req = method.toUpperCase() == 'POST'
          ? await client.postUrl(uri)
          : await client.getUrl(uri);

      req.headers.set(HttpHeaders.acceptHeader, accept);
      req.headers.set(HttpHeaders.contentTypeHeader, ct);
      req.headers.set('x-client-token', _xClientToken(ts));
      req.headers.set('x-tr-signature', sig);
      req.headers.set(HttpHeaders.userAgentHeader,
          'com.community.mbox.in/50020042 (Linux; U; Android 16; en_IN; $_model; Build/BP22.250325.006; Cronet/133.0.6876.3)');
      req.headers.set('x-client-info', clientInfo);
      req.headers.set('x-client-status', '0');
      if (token != null && token.isNotEmpty) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      if (body != null) {
        final bodyBytes = utf8.encode(body);
        req.contentLength = bodyBytes.length;
        req.add(bodyBytes);
      }

      final res = await req.close();
      final respBody = await res.transform(utf8.decoder).join();
      client.close();

      debugPrint('MovieboxResolver [${method.toUpperCase()}] ${res.statusCode} $url');

      final respHeaders = <String, String>{};
      res.headers.forEach((name, values) {
        respHeaders[name.toLowerCase()] = values.join('; ');
      });

      final data = jsonDecode(respBody);
      if (data is Map) {
        return (Map<String, dynamic>.from(data), respHeaders);
      }
      return (null, respHeaders);
    } catch (e) {
      debugPrint('MovieboxResolver error [$url]: $e');
      client.close(force: true);
      return (null, <String, String>{});
    }
  }

  static Future<String?> _getBearerToken() async {
    if (_bearerToken != null) return _bearerToken;
    const rankUrl =
        '$_apiBase/wefeed-mobile-bff/tab/ranking-list?tabId=0&categoryType=4516404531735022304&page=1&perPage=1';
    final (_, headers) = await _request(method: 'GET', url: rankUrl);

    final xUser = headers['x-user'];
    if (xUser != null && xUser.isNotEmpty) {
      try {
        final j = jsonDecode(xUser) as Map?;
        _bearerToken = j?['token']?.toString();
      } catch (e) {
        debugPrint('MovieboxResolver: failed to parse x-user: $e');
      }
    }
    return _bearerToken;
  }

  static Future<List<StreamSourceInfo>> resolveStreams({
    required String title,
    String? year,
    bool isSeries = false,
    int? season,
    int? episode,
  }) async {
    try {
      final token = await _getBearerToken();
      if (token == null) {
        debugPrint('MovieboxResolver: no token, cannot search');
        return [];
      }

      final searchBody = jsonEncode({'page': 1, 'perPage': 20, 'keyword': title});
      final (searchRes, _) = await _request(
        method: 'POST',
        url: '$_apiBase/wefeed-mobile-bff/subject-api/search/v2',
        body: searchBody,
        token: token,
      );

      if (searchRes == null || searchRes['code'] != 0) {
        debugPrint('MovieboxResolver: search failed');
        return [];
      }

      final allSubjects = <dynamic>[];
      for (final g in (searchRes['data']?['results'] as List? ?? [])) {
        if (g is Map && g['subjects'] is List) allSubjects.addAll(g['subjects'] as List);
      }
      allSubjects.addAll(searchRes['data']?['list'] as List? ?? []);
      if (searchRes['data'] is List) allSubjects.addAll(searchRes['data'] as List);

      debugPrint('MovieboxResolver: ${allSubjects.length} subjects found for "$title"');

      final normSearch = _norm(title);
      final matchedSubjects = <Map<String, dynamic>>[];

      for (final item in allSubjects) {
        if (item is! Map) continue;
        final itemTitle = item['title']?.toString() ?? '';

        if (!_sharesSignificantWord(title, itemTitle)) {
          debugPrint('  Skip (no shared words): "$itemTitle"');
          continue;
        }

        final nt = _norm(itemTitle);
        final nsFuzzy = normSearch.replaceAll(RegExp(r'\s+'), '');
        final ntFuzzy = nt.replaceAll(RegExp(r'\s+'), '');

        var score = 0;
        if (nt == normSearch) {
          score += 50;
        } else if (ntFuzzy == nsFuzzy) {
          score += 45;
        } else if (nt.contains(normSearch) || normSearch.contains(nt)) {
          score += 20;
        } else if (ntFuzzy.contains(nsFuzzy) || nsFuzzy.contains(ntFuzzy)) {
          score += 15;
        }

        final rawYear = item['year']?.toString() ?? '';
        final yr = rawYear.length >= 4
            ? rawYear.substring(0, 4)
            : (item['releaseDate']?.toString().length ?? 0) >= 4
                ? item['releaseDate'].toString().substring(0, 4)
                : null;

        bool yearMismatch = false;
        if (year != null && year.isNotEmpty && yr != null && yr.isNotEmpty) {
          final diff = ((int.tryParse(year) ?? 0) - (int.tryParse(yr) ?? 0)).abs();
          if (diff > 1) {
            yearMismatch = true;
          }
        }

        if (year != null && year.isNotEmpty && yr != null) {
          if (year == yr) score += 30;
          else if (((int.tryParse(year) ?? 0) - (int.tryParse(yr) ?? 0)).abs() == 1) score += 5;
        }

        debugPrint('  Subject: "$itemTitle" (score: $score, yr: $yr, mismatch: $yearMismatch)');
        if (score >= 15 && !yearMismatch) {
          matchedSubjects.add(Map<String, dynamic>.from(item));
        }
      }

      if (matchedSubjects.isEmpty) {
        debugPrint('MovieboxResolver: no matching subjects found');
        return [];
      }

      final allSources = <StreamSourceInfo>[];
      final limitedSubjects = matchedSubjects.take(5).toList();
      for (final subject in limitedSubjects) {
        try {
          final streams = await _streams(subject, token, isSeries, season, episode);
          allSources.addAll(streams);
        } catch (e) {
          debugPrint('MovieboxResolver: failed to fetch streams for subject: $e');
        }
      }

      return allSources;
    } catch (e, st) {
      debugPrint('MovieboxResolver.resolveStreams: $e\n$st');
      return [];
    }
  }

  static Future<List<StreamSourceInfo>> _streams(
    Map<String, dynamic> subject,
    String token,
    bool isSeries,
    int? season,
    int? episode,
  ) async {
    final sid = subject['subjectId']?.toString() ?? '';
    if (sid.isEmpty) return [];
    final se = isSeries ? (season ?? 1) : 0;
    final ep = isSeries ? (episode ?? 1) : 0;
    final title = subject['title']?.toString() ?? 'MovieBox';

    final (playRes, _) = await _request(
      method: 'GET',
      url: '$_apiBase/wefeed-mobile-bff/subject-api/play-info?subjectId=$sid&se=$se&ep=$ep',
      token: token,
    );

    if (playRes == null || playRes['code'] != 0) {
      debugPrint('MovieboxResolver: play-info failed for $sid code=${playRes?['code']}');
      return [];
    }

    final data = playRes['data'] as Map? ?? {};
    final sources = <StreamSourceInfo>[];

    Map<String, String> baseHeaders() => {
      'Referer': _apiBase,
      'User-Agent': 'com.community.mbox.in/50020042 (Linux; U; Android 16; en_IN; MovieBox; Build/BP22.250325.006; Cronet/133.0.6876.3)',
    };

    // streams[] format
    for (final item in (data['streams'] as List? ?? [])) {
      if (item is! Map) continue;
      final url = item['url']?.toString() ?? '';
      if (url.isEmpty) continue;
      final resStr = item['resolutions']?.toString() ?? '';
      final res = resStr.isNotEmpty ? '${resStr.split(',').first.trim()}p' : 'HD';
      final fmt = item['format']?.toString() ?? _fmt(url);
      final codec = item['codecName']?.toString() ?? '';
      final size = _size(item['size']);
      final label = '$title • $res • $fmt${codec.isNotEmpty ? " ($codec)" : ""}${size != null ? " ($size)" : ""}';
      final h = baseHeaders();
      final cookie = item['signCookie']?.toString();
      if (cookie != null && cookie.isNotEmpty) h['Cookie'] = cookie;
      sources.add(StreamSourceInfo(name: label, url: url, type: StreamSourceType.moviebox, headers: h));
    }

    // resourceDetectors format
    if (sources.isEmpty) {
      for (final det in (data['resourceDetectors'] as List? ?? [])) {
        if (det is! Map) continue;
        for (final v in (det['resolutionList'] as List? ?? [])) {
          if (v is! Map) continue;
          final url = v['resourceLink']?.toString() ?? '';
          if (url.isEmpty) continue;
          sources.add(StreamSourceInfo(
            name: '$title • ${v['resolution'] ?? 'HD'} • ${_fmt(url)}',
            url: url, type: StreamSourceType.moviebox, headers: baseHeaders(),
          ));
        }
      }
    }

    debugPrint('MovieboxResolver: ${sources.length} streams for "$title"');
    return sources;
  }

  static String _norm(String s) => s
      .replaceAll(RegExp(r'\[.*?\]'), ' ')
      .replaceAll(RegExp(r'\(.*?\)'), ' ')
      .replaceAll(RegExp(r'\b(dub|dubbed|hd|4k|hindi|tamil|telugu|dual audio)\b', caseSensitive: false), ' ')
      .replaceAll(':', ' ')
      .replaceAll(RegExp(r'[^\w\s]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .toLowerCase();

  static String _normWithSpaces(String s) => s
      .replaceAll(RegExp(r'\[.*?\]'), ' ')
      .replaceAll(RegExp(r'\(.*?\)'), ' ')
      .replaceAll(RegExp(r'\b(dub|dubbed|hd|4k|hindi|tamil|telugu|dual audio)\b', caseSensitive: false), ' ')
      .replaceAll(':', ' ')
      .replaceAll(RegExp(r'[^\w\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .toLowerCase();

  static bool _sharesSignificantWord(String title1, String title2) {
    final stopWords = {
      'the', 'a', 'of', 'and', 'in', 'to', 'for', 'with', 'on', 'at', 'by', 'an',
      'movie', 'show', 'film', 'series', 's', 'd', 't'
    };

    Set<String> getWords(String text) {
      final n1 = _norm(text);
      final n2 = _normWithSpaces(text);
      
      final set1 = n1.split(' ').map((w) => w.trim()).where((w) => w.length > 1 && !stopWords.contains(w));
      final set2 = n2.split(' ').map((w) => w.trim()).where((w) => w.length > 1 && !stopWords.contains(w));
      
      return {...set1, ...set2};
    }

    final words1 = getWords(title1);
    final words2 = getWords(title2);

    if (words1.isEmpty || words2.isEmpty) {
      final n1 = _norm(title1).replaceAll(' ', '');
      final n2 = _norm(title2).replaceAll(' ', '');
      return n1.contains(n2) || n2.contains(n1);
    }

    return words1.intersection(words2).isNotEmpty;
  }

  static String _fmt(String url) {
    final u = url.toLowerCase();
    if (u.contains('.mpd') || u.contains('dash')) return 'DASH';
    if (u.contains('.m3u8') || u.contains('hls')) return 'HLS';
    if (u.contains('.mp4')) return 'MP4';
    return 'VIDEO';
  }

  static String? _size(dynamic size) {
    final b = double.tryParse(size?.toString() ?? '');
    if (b == null || b <= 0) return null;
    if (b >= 1024 * 1024 * 1024) return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    return '${(b / (1024 * 1024)).toStringAsFixed(0)} MB';
  }
}
