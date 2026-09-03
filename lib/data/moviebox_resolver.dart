import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:private_cinema_mobile/data/sync_service.dart';
import '../widgets/special_search_dialog.dart';

class MovieboxResolver {
  static const List<String> _hostPool = [
    'https://api4sg.aoneroom.com',
    'https://api4.aoneroom.com',
    'https://api3.aoneroom.com',
    'https://api5.aoneroom.com',
    'https://api6.aoneroom.com',
  ];

  static const String _keyB64Default =
      'NzZpUmwwN3MweFNOOWpxbUVXQXQ3OUVCSlp1bElRSXNWNjRGWnIyTw==';

  static String? _cachedActiveHost;
  static String? _bearerToken;
  static String? _deviceId;
  static String? _brand;
  static String? _model;

  static void _init() {
    if (_deviceId != null) return;
    final r = Random();
    const hex = '0123456789abcdef';
    _deviceId = List.generate(32, (_) => hex[r.nextInt(16)]).join();
    _brand = 'samsung';
    _model = 'SM-S918B';
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

  static String _buildSig(
      String method, String accept, String ct, String url, String? body, int ts) {
    final uri = Uri.parse(url);
    final keys = uri.queryParametersAll.keys.toList()..sort();
    final parts = <String>[];
    for (final k in keys) {
      final vals = List<String>.from(uri.queryParametersAll[k]!)..sort();
      for (final v in vals) {
        parts.add('$k=$v');
      }
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

  static Future<String> _getCustomDomain() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final custom = prefs.getString('domain_moviebox');
      if (custom != null && custom.trim().isNotEmpty) {
        return custom.trim().replaceAll(RegExp(r'/+$'), '');
      }
      final cloud = await SyncService.fetchAppSettings();
      if (cloud.containsKey('domain_moviebox') &&
          cloud['domain_moviebox']!.trim().isNotEmpty) {
        return cloud['domain_moviebox']!.trim().replaceAll(RegExp(r'/+$'), '');
      }
    } catch (_) {}
    return '';
  }

  static Future<(Map<String, dynamic>?, Map<String, String>)> _requestOnHost({
    required String host,
    required String method,
    required String endpoint,
    String? body,
    String? token,
  }) async {
    _init();
    final url = '$host$endpoint';
    final ts = DateTime.now().millisecondsSinceEpoch;
    final ct = body != null ? 'application/json; charset=utf-8' : 'application/json';
    const accept = 'application/json';
    final sig = _buildSig(method, accept, ct, url, body, ts);

    final clientInfo = jsonEncode({
      'package_name': 'com.community.oneroom',
      'version_name': '3.0.13.0325.03',
      'version_code': 50020088,
      'os': 'android',
      'os_version': '13',
      'install_ch': 'ps',
      'device_id': _deviceId,
      'install_store': 'ps',
      'gaid': 'd7578036d13336cc',
      'brand': _brand,
      'model': _model,
      'system_language': 'en',
      'net': 'NETWORK_WIFI',
      'region': 'IN',
      'timezone': 'Asia/Calcutta',
      'sp_code': '',
    });

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 4);
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
          'com.community.oneroom/50020088 (Linux; U; Android 13; en_IN; $_model; Build/TP1A.220624.014; Cronet/133.0.6876.3)');
      req.headers.set('x-client-info', clientInfo);
      req.headers.set('x-client-status', '1');
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

      final respHeaders = <String, String>{};
      res.headers.forEach((name, values) {
        respHeaders[name.toLowerCase()] = values.join('; ');
      });

      if (res.statusCode == 200) {
        final data = jsonDecode(respBody);
        if (data is Map) {
          return (Map<String, dynamic>.from(data), respHeaders);
        }
      }
      return (null, respHeaders);
    } catch (e) {
      client.close(force: true);
      return (null, <String, String>{});
    }
  }

  static Future<(Map<String, dynamic>?, Map<String, String>)> _requestWithFailover({
    required String method,
    required String endpoint,
    String? body,
    String? token,
  }) async {
    final customDomain = await _getCustomDomain();
    final hostsToTry = <String>[];
    if (customDomain.isNotEmpty) {
      hostsToTry.add(customDomain);
    }
    if (_cachedActiveHost != null && !hostsToTry.contains(_cachedActiveHost)) {
      hostsToTry.add(_cachedActiveHost!);
    }
    for (final h in _hostPool) {
      if (!hostsToTry.contains(h)) {
        hostsToTry.add(h);
      }
    }

    for (final host in hostsToTry) {
      final (data, headers) = await _requestOnHost(
        host: host,
        method: method,
        endpoint: endpoint,
        body: body,
        token: token,
      );
      if (data != null) {
        _cachedActiveHost = host;
        return (data, headers);
      }
    }
    return (null, <String, String>{});
  }

  static Future<String?> _getBearerToken() async {
    if (_bearerToken != null && _bearerToken!.isNotEmpty) return _bearerToken;

    const rankEndpoint =
        '/wefeed-mobile-bff/tab/ranking-list?tabId=0&categoryType=4516404531735022304&page=1&perPage=1';
    final (_, headers) = await _requestWithFailover(
      method: 'GET',
      endpoint: rankEndpoint,
    );

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
      if (token == null || token.isEmpty) {
        debugPrint('MovieboxResolver: no bearer token available');
        return [];
      }

      final searchBody =
          jsonEncode({'page': 1, 'perPage': 20, 'keyword': title.trim()});
      final (searchRes, _) = await _requestWithFailover(
        method: 'POST',
        endpoint: '/wefeed-mobile-bff/subject-api/search/v2',
        body: searchBody,
        token: token,
      );

      if (searchRes == null || searchRes['code'] != 0) {
        debugPrint('MovieboxResolver: search request returned no code 0');
        return [];
      }

      final allSubjects = <dynamic>[];
      for (final g in (searchRes['data']?['results'] as List? ?? [])) {
        if (g is Map && g['subjects'] is List) {
          allSubjects.addAll(g['subjects'] as List);
        }
      }
      allSubjects.addAll(searchRes['data']?['list'] as List? ?? []);
      if (searchRes['data'] is List) allSubjects.addAll(searchRes['data'] as List);

      debugPrint('MovieboxResolver: found ${allSubjects.length} subjects for "$title"');

      final normSearch = _norm(title);
      final matchedSubjects = <Map<String, dynamic>>[];

      for (final item in allSubjects) {
        if (item is! Map) continue;
        final itemTitle = item['title']?.toString() ?? '';

        final nt = _norm(itemTitle);
        final nsFuzzy = normSearch.replaceAll(RegExp(r'\s+'), '');
        final ntFuzzy = nt.replaceAll(RegExp(r'\s+'), '');

        var score = 0;
        if (nt == normSearch) {
          score += 100;
        } else if (ntFuzzy == nsFuzzy) {
          score += 90;
        } else if (nt.startsWith(normSearch) || normSearch.startsWith(nt)) {
          score += 70;
        } else if (nt.contains(normSearch) || normSearch.contains(nt)) {
          score += 50;
        }

        if (score == 0) {
          final overlapRatio = _wordOverlapRatio(title, itemTitle);
          if (overlapRatio < 0.45) continue;
          score += (overlapRatio * 40).toInt();
        }

        if (score < 30) continue;

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

        if (score >= 40 && !yearMismatch) {
          matchedSubjects.add(Map<String, dynamic>.from(item));
        }
      }

      if (matchedSubjects.isEmpty) {
        debugPrint('MovieboxResolver: no matching subjects after filter');
        return [];
      }

      final allSources = <StreamSourceInfo>[];
      final limitedSubjects = matchedSubjects.take(2).toList();
      final subjectFutures = limitedSubjects.map((subject) =>
          _extractStreamsForSubject(subject, token, isSeries, season, episode));
      final subjectStreamLists = await Future.wait(subjectFutures);
      for (final streams in subjectStreamLists) {
        allSources.addAll(streams);
      }

      return allSources;
    } catch (e, st) {
      debugPrint('MovieboxResolver.resolveStreams: $e\n$st');
      return [];
    }
  }

  static bool _isUpdateVideo(String url) {
    if (url.isEmpty) return false;
    final u = url.toLowerCase();
    return u.contains('update') ||
        u.contains('upgrade') ||
        u.contains('notice') ||
        u.contains('force_up') ||
        u.contains('version_limit') ||
        u.contains('outdated') ||
        u.contains('please_update') ||
        u.contains('app_update') ||
        u.contains('needupgrade');
  }

  static Future<List<StreamSourceInfo>> _extractStreamsForSubject(
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

    // 1. Fetch subject details to extract all multi-language dubs
    final subjectIds = <Map<String, String>>[];
    try {
      final (detailRes, _) = await _requestWithFailover(
        method: 'GET',
        endpoint: '/wefeed-mobile-bff/subject-api/get?subjectId=$sid',
        token: token,
      );
      if (detailRes != null && detailRes['data'] is Map) {
        final dubs = detailRes['data']['dubs'] as List? ?? [];
        for (final dub in dubs) {
          if (dub is Map) {
            final dubSid = dub['subjectId']?.toString() ?? '';
            final lang = dub['lanName']?.toString() ?? 'Dub';
            if (dubSid.isNotEmpty && !lang.toLowerCase().contains('sub')) {
              subjectIds.add({'id': dubSid, 'lang': lang});
            }
          }
        }
      }
    } catch (_) {}

    if (subjectIds.isEmpty) {
      subjectIds.add({'id': sid, 'lang': 'Original'});
    }

    final sources = <StreamSourceInfo>[];
    Map<String, String> baseHeaders() => {
          'User-Agent':
              'com.community.oneroom/50020088 (Linux; U; Android 13; en_IN; SM-S918B; Build/TP1A.220624.014; Cronet/133.0.6876.3)',
        };

    // 2. Fetch play-info for all dubs in PARALLEL for near-instant results
    final dubFutures = subjectIds.map((dubItem) async {
      final currentSid = dubItem['id']!;
      final lang = dubItem['lang']!;
      final dubSources = <StreamSourceInfo>[];

      try {
        final (playRes, _) = await _requestWithFailover(
          method: 'GET',
          endpoint:
              '/wefeed-mobile-bff/subject-api/play-info?subjectId=$currentSid&se=$se&ep=$ep',
          token: token,
        );

        if (playRes != null && playRes['code'] == 0) {
          final data = playRes['data'] as Map? ?? {};
          if (data['needUpdate'] != true && data['forceUpdate'] != true) {
            for (final item in (data['streams'] as List? ?? [])) {
              if (item is! Map) continue;
              final url = item['url']?.toString() ?? '';
              if (url.isEmpty || _isUpdateVideo(url)) continue;

              final resStr = item['resolutions']?.toString() ?? '';
              final res = resStr.isNotEmpty
                  ? '${resStr.split(',').first.trim()}p'
                  : 'HD';
              final fmt = item['format']?.toString() ?? _fmt(url);
              final codec = item['codecName']?.toString() ?? '';
              final size = _size(item['size']);
              final label =
                  '$lang • $res • $fmt${codec.isNotEmpty ? " ($codec)" : ""}${size != null ? " ($size)" : ""}';

              final h = baseHeaders();
              final cookie = item['signCookie']?.toString();
              if (cookie != null && cookie.isNotEmpty) {
                h['Cookie'] = cookie;
              }

              dubSources.add(StreamSourceInfo(
                name: label,
                url: url,
                type: StreamSourceType.moviebox,
                quality: res,
                size: size,
                headers: h.isNotEmpty ? h : null,
              ));
            }
          }
        }
      } catch (e) {
        debugPrint('MovieboxResolver dub fetch error: $e');
      }
      return dubSources;
    });

    final dubResults = await Future.wait(dubFutures);
    for (final list in dubResults) {
      sources.addAll(list);
    }

    debugPrint('MovieboxResolver: ${sources.length} valid streams for "$title"');
    return sources;
  }

  static String _norm(String s) => s
      .replaceAll(RegExp(r'\[.*?\]'), ' ')
      .replaceAll(RegExp(r'\(.*?\)'), ' ')
      .replaceAll(
          RegExp(r'\b(dub|dubbed|hd|4k|hindi|tamil|telugu|dual audio)\b',
              caseSensitive: false),
          ' ')
      .replaceAll(':', ' ')
      .replaceAll(RegExp(r'[^\w\s]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .toLowerCase();

  static double _wordOverlapRatio(String searchTitle, String resultTitle) {
    final stopWords = {
      'the', 'a', 'of', 'and', 'in', 'to', 'for', 'with', 'on', 'at', 'by', 'an',
      'movie', 'show', 'film', 'series', 's', 'd', 't'
    };

    Set<String> getWords(String text) {
      final n = _norm(text);
      return n
          .split(' ')
          .map((w) => w.trim())
          .where((w) => w.length > 1 && !stopWords.contains(w))
          .toSet();
    }

    final searchWords = getWords(searchTitle);
    final resultWords = getWords(resultTitle);

    if (searchWords.isEmpty) return 0.0;
    final matched = searchWords.intersection(resultWords).length;
    return matched / searchWords.length;
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
    if (b >= 1024 * 1024 * 1024) {
      return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    return '${(b / (1024 * 1024)).toStringAsFixed(0)} MB';
  }
}
