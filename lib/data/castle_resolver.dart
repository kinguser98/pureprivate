import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:pointycastle/export.dart';
import '../widgets/special_search_dialog.dart';

/**
 * High-Performance Native Dart Castle TV Resolver
 * - Full CNCVerse CloudStream Parity
 * - Pure Dart PointyCastle AES-128-CBC Decryption
 * - Multi-language audio tracks & 720p HD + 480p SD stream extraction
 */
class CastleResolver {
  static const String _castleBase = 'https://api.hlowb.com';
  static const String _pkg = 'com.external.castle';
  static const String _channel = 'IndiaA';
  static const String _client = '1';
  static const String _lang = 'en-US';
  static const String _castleSuffix = 'T!BgJB';
  static const String _apkSignKey = 'ED0955EB04E67A1D9F3305B95454FED485261475';

  static const Map<String, String> _apiHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
    'Accept': 'application/json, text/plain, */*',
    'Accept-Language': 'en-US,en;q=0.9',
    'Connection': 'Keep-Alive',
    'Referer': _castleBase,
  };

  static const Map<String, String> playbackHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36',
    'Accept':
        'video/webm,video/ogg,video/*;q=0.9,application/ogg;q=0.7,audio/*;q=0.6,*/*;q=0.5',
    'Referer': _castleBase,
  };

  static Uint8List _deriveKey(String secKeyB64) {
    final decoded = base64.decode(secKeyB64.trim());
    final suffix = ascii.encode(_castleSuffix);
    final combined = Uint8List(decoded.length + suffix.length);
    combined.setRange(0, decoded.length, decoded);
    combined.setRange(decoded.length, combined.length, suffix);
    if (combined.length < 16) {
      final padded = Uint8List(16);
      padded.setRange(0, combined.length, combined);
      return padded;
    }
    return combined.sublist(0, 16);
  }

  static String _decryptCastle(String cipherTextB64, String secKeyB64) {
    try {
      final keyBytes = _deriveKey(secKeyB64);
      final cipherBytes = base64.decode(cipherTextB64.trim());
      final cipher = CBCBlockCipher(AESEngine())
        ..init(false, ParametersWithIV(KeyParameter(keyBytes), keyBytes));

      final paddedOut = Uint8List(cipherBytes.length);
      var offset = 0;
      while (offset < cipherBytes.length) {
        offset += cipher.processBlock(cipherBytes, offset, paddedOut, offset);
      }
      final padLen = paddedOut.last;
      if (padLen <= 0 || padLen > 16) {
        return utf8.decode(paddedOut, allowMalformed: true);
      }
      final unpadded = paddedOut.sublist(0, paddedOut.length - padLen);
      return utf8.decode(unpadded);
    } catch (e) {
      debugPrint('CastleResolver: Decrypt failed: $e');
      return '';
    }
  }

  static String _extractCipher(String body) {
    final trimmed = body.trim();
    if (trimmed.startsWith('{')) {
      try {
        final map = jsonDecode(trimmed);
        if (map is Map && map['data'] is String) {
          return (map['data'] as String).trim();
        }
      } catch (_) {}
    }
    return trimmed;
  }

  static Future<String?> _getSecurityKey() async {
    try {
      final url =
          '$_castleBase/v0.1/system/getSecurityKey/1?channel=$_channel&clientType=$_client&lang=$_lang';
      final res = await http
          .get(Uri.parse(url), headers: _apiHeaders)
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final map = jsonDecode(res.body);
        if (map is Map && map['code'] == 200 && map['data'] != null) {
          return map['data'].toString();
        }
      }
    } catch (e) {
      debugPrint('CastleResolver: Fetch security key failed: $e');
    }
    return null;
  }

  /// Resolves all available 720p HD and 480p SD streams for all audio languages
  static Future<List<StreamSourceInfo>> resolveStreams({
    required String title,
    int? year,
    String? tmdbId,
    bool isSeries = false,
    int? season,
    int? episode,
  }) async {
    final List<StreamSourceInfo> sources = [];
    try {
      final securityKey = await _getSecurityKey();
      if (securityKey == null) return [];

      // 1. Clean title and prepare search keywords
      final cleanTitle = title
          .replaceAll(RegExp(r'\(\d{4}\)'), '')
          .replaceAll(RegExp(r'\[[^\]]+\]'), '')
          .replaceAll(
            RegExp(
              r'\b(Hindi|Tamil|Telugu|Malayalam|Kannada|English|Dubbed|Dual Audio|4k|1080p|720p)\b',
              caseSensitive: false,
            ),
            '',
          )
          .trim();

      final searchKeywords = <String>[];
      if (cleanTitle.isNotEmpty) searchKeywords.add(cleanTitle);
      if (cleanTitle != title.trim() && title.trim().isNotEmpty) {
        searchKeywords.add(title.trim());
      }
      if (year != null && cleanTitle.isNotEmpty) {
        searchKeywords.add('$cleanTitle $year');
      }

      String? targetMovieId;
      String matchedTitle = cleanTitle;

      for (final kw in searchKeywords) {
        if (targetMovieId != null) break;
        try {
          final sUrl =
              '$_castleBase/film-api/v1.1.0/movie/searchByKeyword?channel=$_channel&clientType=$_client&keyword=${Uri.encodeComponent(kw)}&lang=$_lang&mode=1&packageName=$_pkg&page=1&size=30';
          final sRes = await http
              .get(Uri.parse(sUrl), headers: _apiHeaders)
              .timeout(const Duration(seconds: 8));
          if (sRes.statusCode != 200) continue;
          final cipher = _extractCipher(sRes.body);
          final decrypted = _decryptCastle(cipher, securityKey);
          if (decrypted.isEmpty) continue;

          final sMap = jsonDecode(decrypted);
          final dataObj = (sMap is Map && sMap['data'] is Map)
              ? sMap['data']
              : sMap;
          final rows = (dataObj is Map && dataObj['rows'] is List)
              ? dataObj['rows'] as List
              : [];

          for (final elem in rows) {
            if (elem is! Map) continue;
            final rTitle = elem['title']?.toString() ??
                elem['name']?.toString() ??
                '';
            final rId = elem['id']?.toString() ??
                elem['redirectId']?.toString() ??
                '';

            if (rId.isNotEmpty) {
              final lowerR = rTitle.toLowerCase().replaceAll(' ', '');
              final lowerKw = cleanTitle.toLowerCase().replaceAll(' ', '');
              if (lowerR == lowerKw ||
                  lowerR.contains(lowerKw) ||
                  lowerKw.contains(lowerR) ||
                  rows.length == 1) {
                targetMovieId = rId;
                matchedTitle = rTitle;
                break;
              }
            }
          }

          if (targetMovieId == null && rows.isNotEmpty) {
            final first = rows.first as Map;
            targetMovieId = first['id']?.toString() ??
                first['redirectId']?.toString();
            if (first['title'] != null) {
              matchedTitle = first['title'].toString();
            }
          }
        } catch (e) {
          debugPrint('CastleResolver: Search error for "$kw": $e');
        }
      }

      final movieId = targetMovieId;
      if (movieId == null) return [];

      // 2. Fetch Details
      final detUrl =
          '$_castleBase/film-api/v1.9.9/movie?channel=$_channel&clientType=$_client&lang=$_lang&movieId=$movieId&packageName=$_pkg';
      final dRes = await http
          .get(Uri.parse(detUrl), headers: _apiHeaders)
          .timeout(const Duration(seconds: 8));
      if (dRes.statusCode != 200) return [];
      final detCipher = _extractCipher(dRes.body);
      final detDecrypted = _decryptCastle(detCipher, securityKey);
      if (detDecrypted.isEmpty) return [];

      final dMap = jsonDecode(detDecrypted);
      final dData = (dMap is Map && dMap['data'] is Map)
          ? dMap['data'] as Map
          : dMap as Map;

      String currentMovieId = movieId;
      if (isSeries && season != null && episode != null) {
        final seasons = dData['seasons'] as List?;
        if (seasons != null) {
          for (final s in seasons) {
            if (s is Map && s['number'] == season) {
              final sMovieId = s['movieId']?.toString();
              if (sMovieId != null && sMovieId.isNotEmpty) {
                currentMovieId = sMovieId;
              }
              break;
            }
          }
        }
      }

      final episodes = dData['episodes'] as List?;
      if (episodes == null || episodes.isEmpty) return [];

      String? targetEpisodeId;
      final targetTracks = <Map>[];

      if (isSeries && season != null && episode != null) {
        for (final e in episodes) {
          if (e is Map && e['number'] == episode) {
            targetEpisodeId = e['id']?.toString();
            final tr = e['tracks'] as List?;
            if (tr != null) {
              for (final item in tr) {
                if (item is Map) targetTracks.add(item);
              }
            }
            break;
          }
        }
      }

      if (targetEpisodeId == null && episodes.isNotEmpty) {
        final firstEp = episodes.first as Map;
        targetEpisodeId = firstEp['id']?.toString();
        final tr = firstEp['tracks'] as List?;
        if (tr != null) {
          for (final item in tr) {
            if (item is Map) targetTracks.add(item);
          }
        }
      }

      final episodeId = targetEpisodeId;
      if (episodeId == null) return [];

      // 3. Resolve Video Streams across audio tracks and resolutions (720p HD & 480p SD)
      final postHeaders = {
        ..._apiHeaders,
        'Content-Type': 'application/json; charset=utf-8',
      };

      final tasks = <Future<StreamSourceInfo?>>[];

      for (final t in targetTracks) {
        final langId = t['languageId']?.toString();
        final langName = t['languageName']?.toString() ??
            t['abbreviate']?.toString() ??
            'Audio';

        if (langId != null && langId.isNotEmpty) {
          // 720p HD
          tasks.add(
            _fetchSingleStream(
              securityKey: securityKey,
              movieId: currentMovieId,
              episodeId: episodeId,
              languageId: langId,
              languageLabel: langName,
              resolutionId: 2,
              qualityLabel: '720p HD',
              postHeaders: postHeaders,
            ),
          );
          // 480p SD
          tasks.add(
            _fetchSingleStream(
              securityKey: securityKey,
              movieId: currentMovieId,
              episodeId: episodeId,
              languageId: langId,
              languageLabel: langName,
              resolutionId: 1,
              qualityLabel: '480p SD',
              postHeaders: postHeaders,
            ),
          );
        }
      }

      if (targetTracks.isEmpty) {
        // Shared 720p & 480p
        tasks.add(
          _fetchSingleStream(
            securityKey: securityKey,
            movieId: currentMovieId,
            episodeId: episodeId,
            languageId: null,
            languageLabel: 'Multi-Audio',
            resolutionId: 2,
            qualityLabel: '720p HD',
            postHeaders: postHeaders,
          ),
        );
        tasks.add(
          _fetchSingleStream(
            securityKey: securityKey,
            movieId: currentMovieId,
            episodeId: episodeId,
            languageId: null,
            languageLabel: 'Multi-Audio',
            resolutionId: 1,
            qualityLabel: '480p SD',
            postHeaders: postHeaders,
          ),
        );
      }

      final results = await Future.wait(tasks);
      final seenUrls = <String>{};
      for (final s in results) {
        if (s != null && s.url.isNotEmpty && seenUrls.add(s.url)) {
          sources.add(s);
        }
      }
    } catch (e) {
      debugPrint('CastleResolver: Overall resolution error: $e');
    }

    // Sort 720p on top
    sources.sort((a, b) {
      final qA = (a.quality?.contains('720') ?? false) ? 2 : 1;
      final qB = (b.quality?.contains('720') ?? false) ? 2 : 1;
      return qB.compareTo(qA);
    });

    debugPrint('CastleResolver: Resolved ${sources.length} stream(s) for $title');
    return sources;
  }

  static Future<StreamSourceInfo?> _fetchSingleStream({
    required String securityKey,
    required String movieId,
    required String episodeId,
    required String? languageId,
    required String languageLabel,
    required int resolutionId,
    required String qualityLabel,
    required Map<String, String> postHeaders,
  }) async {
    try {
      final payload = {
        'mode': '1',
        'appMarket': 'GuanWang',
        'clientType': _client,
        'woolUser': 'false',
        'apkSignKey': _apkSignKey,
        'androidVersion': '13',
        'movieId': movieId,
        'episodeId': episodeId,
        if (languageId != null) 'languageId': languageId,
        'isNewUser': 'true',
        'resolution': resolutionId.toString(),
        'packageName': _pkg,
      };

      final url =
          '$_castleBase/film-api/v2.0.1/movie/getVideo2?clientType=$_client&packageName=$_pkg&channel=$_channel&lang=$_lang';
      final res = await http
          .post(
            Uri.parse(url),
            headers: postHeaders,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 8));

      if (res.statusCode != 200) return null;
      final cipher = _extractCipher(res.body);
      final decrypted = _decryptCastle(cipher, securityKey);
      if (decrypted.isEmpty) return null;

      final vMap = jsonDecode(decrypted);
      final vData = (vMap is Map && vMap['data'] is Map)
          ? vMap['data'] as Map
          : null;

      final videoUrl = vData?['videoUrl']?.toString();
      final isDenied = vData?['permissionDenied'] == true;

      if (videoUrl != null && videoUrl.isNotEmpty && !isDenied) {
        final label = 'Castle TV • $languageLabel • $qualityLabel • HLS';
        return StreamSourceInfo(
          name: label,
          url: videoUrl,
          type: StreamSourceType.castle,
          quality: qualityLabel,
          size: resolutionId == 2 ? 'HD Stream' : 'SD Stream',
          headers: playbackHeaders,
        );
      }
    } catch (e) {
      debugPrint('CastleResolver: Single stream fetch error ($languageLabel $qualityLabel): $e');
    }
    return null;
  }
}
