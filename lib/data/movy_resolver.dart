import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:private_cinema_mobile/widgets/special_search_dialog.dart';

class MovyResolver {
  static const String baseUrl = 'https://www.movy.sx';
  static const String apiBaseUrl = 'https://api.wecollege.net';

  static const String _browserUa =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  static const List<int> _l = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174
  ];

  static const List<int> _magic = [109, 118, 109, 49]; // "mvm1"

  static const List<Map<String, String>> _servers = [
    {'id': 'miami', 'name': 'Miami', 'note': 'Original Audio'},
    {'id': 'boise', 'name': 'Boise', 'note': 'Original Audio'},
    {'id': 'delhi', 'name': 'Delhi', 'note': 'Multi-Audio'},
    {'id': 'vegas', 'name': 'Vegas', 'note': 'Original Audio'},
    {'id': 'reno', 'name': 'Reno', 'note': 'Original Audio'},
    {'id': 'oakland', 'name': 'Oakland', 'note': 'Original Audio'},
    {'id': 'seattle', 'name': 'Seattle', 'note': 'Original Audio'},
    {'id': 'cancun', 'name': 'Cancun', 'note': 'Spanish Audio'},
    {'id': 'munich', 'name': 'Munich', 'note': 'German Audio'},
    {'id': 'paris', 'name': 'Paris', 'note': 'French Audio'},
  ];

  static bool _r(int e) => ((e * (e + 1)) & 1) == 0;

  static int _imul(int a, int b) {
    final aLo = a & 0xffff;
    final aHi = (a >> 16) & 0xffff;
    final bLo = b & 0xffff;
    final bHi = (b >> 16) & 0xffff;
    final lo = aLo * bLo;
    final mid = (aLo * bHi + aHi * bLo) & 0xffff;
    return ((lo + (mid << 16)) & 0xFFFFFFFF);
  }

  static int _o(int e) {
    e &= 0xFFFFFFFF;
    e ^= (e >> 16);
    e = _imul(e, 0x85ebca6b);
    e ^= (e >> 13);
    e = _imul(e, 0xc2b2ae35);
    e ^= (e >> 16);
    return e & 0xFFFFFFFF;
  }

  static int _u(int e, int a) {
    e &= 0xFFFFFFFF;
    a &= 31;
    if (a == 0) return e;
    return ((e << a) | (e >> (32 - a))) & 0xFFFFFFFF;
  }

  static String? _decryptMovy(String encryptedB64, String seedStr, int mediaId) {
    try {
      var b64 = encryptedB64.replaceAll('-', '+').replaceAll('_', '/');
      while (b64.length % 4 != 0) {
        b64 += '=';
      }
      final n = Uint8List.fromList(base64.decode(b64));
      final t = n.length;

      final len = seedStr.length;
      final sMap = <int, int>{};
      int acc;

      if (((len * (len + 1)) & 1) == 1) {
        final sList = List<int>.generate(256, (idx) => idx);
        var j = 0;
        for (var sIdx = 0; sIdx < 256; sIdx++) {
          j = (j + sList[sIdx] + seedStr.codeUnitAt(sIdx % seedStr.length)) & 255;
          final temp = sList[sIdx];
          sList[sIdx] = sList[j];
          sList[j] = temp;
        }
        for (var idx = 0; idx < 256; idx++) {
          sMap[idx] = sList[idx];
        }
        var a = 0x67452301;
        for (var tIdx = 0; tIdx < seedStr.length; tIdx++) {
          a = _u((a ^ _imul(seedStr.codeUnitAt(tIdx), _l[15 & tIdx])) & 0xFFFFFFFF, 5);
        }
        acc = _o(a);
      } else {
        var a = 0x811c9dc5;
        for (var tIdx = 0; tIdx < seedStr.length; tIdx++) {
          a = _imul(a ^ seedStr.codeUnitAt(tIdx), 0x1000193);
        }
        var nVal = _o((_o(a) ^ _o((mediaId & 0xFFFFFFFF) ^ 0x9e3779b9)) & 0xFFFFFFFF);

        for (var e = 0; e < 8; e++) {
          if (_r(e)) {
            final aIdx = nVal % 61;
            nVal = _u((nVal + 0x9e3779b9) & 0xFFFFFFFF, 7 + (7 & e));
            sMap[aIdx] = (nVal ^ _o(nVal)) & 0xFFFFFFFF;
            nVal = _o((nVal + aIdx) & 0xFFFFFFFF);
          } else {
            sMap[e] = _l[15 & e];
          }
        }
        acc = _o((0xa5a5a5a5 ^ nVal) & 0xFFFFFFFF);
      }

      final keyStream = Uint8List(t);
      var counter = 0;
      for (var e = 0; e < t;) {
        final lIdx = acc % 61;
        final hasKey = sMap.containsKey(lIdx);
        final iFlag = hasKey ? -1 : 0;
        final rVal = (hasKey ? sMap[lIdx]! : 0) & 0xFFFFFFFF;
        final cVal = _imul(0x9e3779b9, counter + 1);
        final tVal = acc;
        final sVal = (rVal ^ cVal) & 0xFFFFFFFF;
        var bVal = ((tVal ^ sVal) | (tVal & sVal & iFlag)) & 0xFFFFFFFF;
        acc = _o(((_u((bVal + acc) & 0xFFFFFFFF, 31 & lIdx) ^
                    _u(acc, 31 & _imul(lIdx, 7))) &
                0xFFFFFFFF) +
            0x9e3779b9);
        sMap[lIdx] = acc & 0xFFFFFFFF;
        final aVal = acc & 0xFFFFFFFF;
        counter++;

        keyStream[e++] = 255 & aVal;
        if (e < t) keyStream[e++] = (aVal >> 8) & 255;
        if (e < t) keyStream[e++] = (aVal >> 16) & 255;
        if (e < t) keyStream[e++] = (aVal >> 24) & 255;
      }

      for (var e = 0; e < n.length; e++) {
        n[e] ^= keyStream[e];
      }

      for (var e = 0; e < _magic.length; e++) {
        if (n[e] != _magic[e]) return null;
      }

      return utf8.decode(n.sublist(_magic.length));
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _fetchSeed(int mediaId) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final req = await client.getUrl(Uri.parse('$apiBaseUrl/seed?mediaId=$mediaId'));
      req.headers.set(HttpHeaders.userAgentHeader, _browserUa);
      req.headers.set(HttpHeaders.refererHeader, '$baseUrl/');
      req.headers.set('Origin', baseUrl);
      final resp = await req.close();
      if (resp.statusCode == 200) {
        final body = await resp.transform(utf8.decoder).join();
        client.close();
        final json = jsonDecode(body);
        if (json is Map && json['seed'] != null) {
          return json['seed'].toString();
        }
      }
    } catch (_) {
      client.close();
    }
    return null;
  }

  static String buildMovieUrl(String tmdbId) {
    return '$baseUrl/movie/$tmdbId?play=true';
  }

  static String buildSeriesUrl(String tmdbId, int season, int episode) {
    return '$baseUrl/tv/$tmdbId?s=$season&e=$episode&play=true';
  }

  /// Resolves direct stream sources for a given movie across all Movy servers
  static Future<List<StreamSourceInfo>> resolveMovieStreams({
    required String tmdbId,
    String? title,
    String? year,
  }) async {
    final mediaId = int.tryParse(tmdbId.trim());
    if (mediaId == null || mediaId <= 0) return [];

    final cleanTitle = (title ?? '').trim();
    if (cleanTitle.isEmpty) return [];

    final seed = await _fetchSeed(mediaId);
    if (seed == null || seed.isEmpty) {
      debugPrint('MovyResolver: failed to obtain seed for $cleanTitle');
      return [];
    }

    final sources = <StreamSourceInfo>[];
    final seenUrls = <String>{};

    final futures = _servers.map((srv) async {
      final serverId = srv['id']!;
      final serverName = srv['name']!;
      final note = srv['note']!;
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);

      try {
        final queryParams = {
          'title': cleanTitle,
          'mediaType': 'movie',
          'year': year ?? '',
          'tmdbId': mediaId.toString(),
          'enc': '2',
          'seed': seed,
        };
        final uri = Uri.parse('$apiBaseUrl/$serverId/sources').replace(queryParameters: queryParams);
        final req = await client.getUrl(uri);
        req.headers.set(HttpHeaders.userAgentHeader, _browserUa);
        req.headers.set(HttpHeaders.refererHeader, '$baseUrl/');
        req.headers.set('Origin', baseUrl);

        final resp = await req.close();
        if (resp.statusCode != 200) {
          client.close();
          return <StreamSourceInfo>[];
        }

        final body = await resp.transform(utf8.decoder).join();
        client.close();

        if (body.isEmpty || body.startsWith('{')) {
          return <StreamSourceInfo>[];
        }

        final decrypted = _decryptMovy(body, seed, mediaId);
        if (decrypted == null || decrypted.isEmpty) {
          return <StreamSourceInfo>[];
        }

        final data = jsonDecode(decrypted);
        if (data is! Map) return <StreamSourceInfo>[];

        final serverSources = <StreamSourceInfo>[];
        final list = data['sources'] as List? ?? [];

        for (final item in list) {
          if (item is! Map) continue;
          final streamUrl = item['url']?.toString() ?? '';
          if (streamUrl.isEmpty) continue;

          final rawQuality = item['quality']?.toString() ?? '1080p';
          final isLangQuality = ['Hindi', 'Tamil', 'Telugu', 'English', 'Spanish', 'German', 'French']
              .any((lang) => rawQuality.toLowerCase() == lang.toLowerCase());

          final qualityStr = isLangQuality ? '1080p' : (rawQuality.contains('p') ? rawQuality : '${rawQuality}p');
          final audioLabel = isLangQuality ? '$rawQuality Audio' : note;
          final label = 'Movy • $serverName • $qualityStr • $audioLabel';

          final languages = isLangQuality
              ? [rawQuality]
              : (serverId == 'delhi'
                  ? ['Hindi', 'English']
                  : ['Original Audio', 'English']);

          serverSources.add(
            StreamSourceInfo(
              name: label,
              url: streamUrl,
              type: StreamSourceType.movy,
              addonName: 'Movy ($serverName)',
              originalTitle: cleanTitle,
              quality: qualityStr,
              languages: languages,
              headers: {
                'Referer': '$baseUrl/',
                'Origin': baseUrl,
                'User-Agent': _browserUa,
              },
            ),
          );
        }

        return serverSources;
      } catch (e) {
        client.close();
        return <StreamSourceInfo>[];
      }
    });

    final results = await Future.wait(futures);
    for (final list in results) {
      for (final s in list) {
        if (seenUrls.add(s.url)) {
          sources.add(s);
        }
      }
    }

    debugPrint('MovyResolver: resolved ${sources.length} active streams for "$cleanTitle"');
    return sources;
  }

  /// Resolves direct stream sources for a TV show episode across all Movy servers
  static Future<List<StreamSourceInfo>> resolveSeriesStreams({
    required String tmdbId,
    required int season,
    required int episode,
    String? title,
  }) async {
    final mediaId = int.tryParse(tmdbId.trim());
    if (mediaId == null || mediaId <= 0) return [];

    final cleanTitle = (title ?? '').trim();
    if (cleanTitle.isEmpty) return [];

    final seed = await _fetchSeed(mediaId);
    if (seed == null || seed.isEmpty) {
      debugPrint('MovyResolver: failed to obtain seed for $cleanTitle');
      return [];
    }

    final sources = <StreamSourceInfo>[];
    final seenUrls = <String>{};

    final futures = _servers.map((srv) async {
      final serverId = srv['id']!;
      final serverName = srv['name']!;
      final note = srv['note']!;
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);

      try {
        final queryParams = {
          'title': cleanTitle,
          'mediaType': 'tv',
          'seasonId': season.toString(),
          'episodeId': episode.toString(),
          'totalSeasons': '1',
          'tmdbId': mediaId.toString(),
          'enc': '2',
          'seed': seed,
        };
        final uri = Uri.parse('$apiBaseUrl/$serverId/sources').replace(queryParameters: queryParams);
        final req = await client.getUrl(uri);
        req.headers.set(HttpHeaders.userAgentHeader, _browserUa);
        req.headers.set(HttpHeaders.refererHeader, '$baseUrl/');
        req.headers.set('Origin', baseUrl);

        final resp = await req.close();
        if (resp.statusCode != 200) {
          client.close();
          return <StreamSourceInfo>[];
        }

        final body = await resp.transform(utf8.decoder).join();
        client.close();

        if (body.isEmpty || body.startsWith('{')) {
          return <StreamSourceInfo>[];
        }

        final decrypted = _decryptMovy(body, seed, mediaId);
        if (decrypted == null || decrypted.isEmpty) {
          return <StreamSourceInfo>[];
        }

        final data = jsonDecode(decrypted);
        if (data is! Map) return <StreamSourceInfo>[];

        final serverSources = <StreamSourceInfo>[];
        final list = data['sources'] as List? ?? [];

        for (final item in list) {
          if (item is! Map) continue;
          final streamUrl = item['url']?.toString() ?? '';
          if (streamUrl.isEmpty) continue;

          final rawQuality = item['quality']?.toString() ?? '1080p';
          final isLangQuality = ['Hindi', 'Tamil', 'Telugu', 'English', 'Spanish', 'German', 'French']
              .any((lang) => rawQuality.toLowerCase() == lang.toLowerCase());

          final qualityStr = isLangQuality ? '1080p' : (rawQuality.contains('p') ? rawQuality : '${rawQuality}p');
          final audioLabel = isLangQuality ? '$rawQuality Audio' : note;
          final label = 'Movy • $serverName • S${season}E$episode • $qualityStr • $audioLabel';

          final languages = isLangQuality
              ? [rawQuality]
              : (serverId == 'delhi'
                  ? ['Hindi', 'English']
                  : ['Original Audio', 'English']);

          serverSources.add(
            StreamSourceInfo(
              name: label,
              url: streamUrl,
              type: StreamSourceType.movy,
              addonName: 'Movy ($serverName)',
              originalTitle: '$cleanTitle S${season}E$episode',
              quality: qualityStr,
              languages: languages,
              headers: {
                'Referer': '$baseUrl/',
                'Origin': baseUrl,
                'User-Agent': _browserUa,
              },
            ),
          );
        }

        return serverSources;
      } catch (e) {
        client.close();
        return <StreamSourceInfo>[];
      }
    });

    final results = await Future.wait(futures);
    for (final list in results) {
      for (final s in list) {
        if (seenUrls.add(s.url)) {
          sources.add(s);
        }
      }
    }

    debugPrint('MovyResolver: resolved ${sources.length} active series streams for "$cleanTitle" S${season}E$episode');
    return sources;
  }
}
