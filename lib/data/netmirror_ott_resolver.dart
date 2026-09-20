import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/special_search_dialog.dart';

/// NetMirror OTT Resolver -- mirrors CNCVerse (normal) CloudStream plugin logic.
/// Handles Netflix (nf), Prime Video (pv), and Hotstar (hs) streams with per-OTT Usertokens.
class NetmirrorOttResolver {
  static const String _prefUsertokenPrefix = 'netmirror_ott_usertoken_';
  static const String _prefUtTimestamp      = 'netmirror_ott_ut_ts_';
  static const String _prefApiBase          = 'netmirror_ott_api_base';
  static const Duration _tokenTtl           = Duration(hours: 23);

  // Active verified fallback tokens from CloudStream
  static const String _fallbackNfToken = '0071c1f56cba693a6b4cce0ece6df232::4eae4e810ce622019143ed0d7bfb58b5::1789884245::ni';
  static const String _fallbackPvToken = '2af06c575e64959eeb5b1d45f7f47e2a::f8ee3b3d4f6cd34e3b0a9fad764ecad9::1789884246::ni';
  static const String _fallbackHsToken = '9b6887c289e0d4a7516ad3f2b427d33f::9e99c77d87d5e60cea267a30669dad12::1789884247::ni';

  static const List<String> _detectionDomains = [
    'https://mobiledetects.com',
    'https://mobiledetect.app',
    'https://mobidetect.cc',
    'https://mobidetects.cc',
    'https://mobidetects.xyz',
    'https://mobidetect.art',
  ];

  static const String _defaultApiBase = 'https://tv.imgcdn.kim';
  static const String verifyUrl       = 'https://net52.cc/verify.php';

  static const Map<String, String> _baseHeaders = {
    'User-Agent'      : 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:136.0) Gecko/20100101 Firefox/136.0 /OS.GatuNewTV v1.0',
    'X-Requested-With': 'NetmirrorNewTV v1.0',
    'Accept'          : 'application/json, text/plain, */*',
  };

  // ─── Token Management ──────────────────────────────────────────────────────

  static bool _isValidToken(String? token) {
    if (token == null) return false;
    final t = token.trim();
    return t.isNotEmpty && t != '{}' && t != 'null' && t != 'undefined' && t != '0' && t.length > 10;
  }

  static Future<String?> getSavedUsertoken({String ott = 'nf'}) async {
    // 1. Always try importing freshest token from CloudStream shared_prefs if root is available
    final imported = await tryImportFromCloudStream(ott: ott);
    if (_isValidToken(imported)) {
      return imported;
    }

    // 2. Check local SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final key = '$_prefUsertokenPrefix$ott';
    final token = prefs.getString(key) ?? '';
    
    if (_isValidToken(token)) {
      final ts = prefs.getInt('$_prefUtTimestamp$ott') ?? 0;
      final age = DateTime.now().millisecondsSinceEpoch - ts;
      if (ts > 0 && age < _tokenTtl.inMilliseconds) {
        return token;
      }
    }

    // 3. Fallback
    if (ott == 'pv') return _fallbackPvToken;
    if (ott == 'hs') return _fallbackHsToken;
    return _fallbackNfToken;
  }

  static Future<void> saveUsertoken(String token, {String ott = 'nf'}) async {
    final clean = token.trim();
    if (!_isValidToken(clean)) return;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefUsertokenPrefix$ott', clean);
    await prefs.setInt('$_prefUtTimestamp$ott', DateTime.now().millisecondsSinceEpoch);
    debugPrint('NetmirrorOtt: Saved valid Usertoken for [$ott]: $clean');
  }

  static Future<void> invalidateUsertoken({String? ott}) async {
    final prefs = await SharedPreferences.getInstance();
    if (ott != null) {
      await prefs.remove('$_prefUsertokenPrefix$ott');
      await prefs.remove('$_prefUtTimestamp$ott');
      debugPrint('NetmirrorOtt: Invalidated token for [$ott]');
    } else {
      for (final o in ['nf', 'pv', 'hs']) {
        await prefs.remove('$_prefUsertokenPrefix$o');
        await prefs.remove('$_prefUtTimestamp$o');
      }
      debugPrint('NetmirrorOtt: Invalidated all tokens');
    }
  }

  // ─── CloudStream Root Sync ─────────────────────────────────────────────────

  static Future<String?> tryImportFromCloudStream({String ott = 'nf'}) async {
    try {
      final res = await Process.run('su', ['-c', 'cat /data/data/com.lagradost.cloudstream3/shared_prefs/NetflixMirrorPrefs.xml']);
      if (res.exitCode == 0 && res.stdout != null) {
        final xml = res.stdout.toString();

        final nfMatch = RegExp(r'<string name="usertoken_nf">([^<]+)</string>').firstMatch(xml);
        final pvMatch = RegExp(r'<string name="usertoken_pv">([^<]+)</string>').firstMatch(xml);
        final hsMatch = RegExp(r'<string name="usertoken_hs">([^<]+)</string>').firstMatch(xml);

        if (nfMatch != null && _isValidToken(nfMatch.group(1))) {
          await saveUsertoken(nfMatch.group(1)!, ott: 'nf');
        }
        if (pvMatch != null && _isValidToken(pvMatch.group(1))) {
          await saveUsertoken(pvMatch.group(1)!, ott: 'pv');
        }
        if (hsMatch != null && _isValidToken(hsMatch.group(1))) {
          await saveUsertoken(hsMatch.group(1)!, ott: 'hs');
        }

        if (ott == 'pv' && pvMatch != null && _isValidToken(pvMatch.group(1))) return pvMatch.group(1);
        if (ott == 'hs' && hsMatch != null && _isValidToken(hsMatch.group(1))) return hsMatch.group(1);
        if (nfMatch != null && _isValidToken(nfMatch.group(1))) return nfMatch.group(1);
      }
    } catch (e) {
      debugPrint('NetmirrorOtt: CloudStream root import error: $e');
    }
    return null;
  }

  // ─── Fetch Usertoken via OTP ───────────────────────────────────────────────

  static Future<String?> fetchUsertokenWithOtp(String otp, {String ott = 'nf'}) async {
    final cleanOtp = otp.trim().replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanOtp.isEmpty) return null;

    final apiBase = await _resolveApiBase();
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 8);
    client.badCertificateCallback = (_, __, ___) => true;

    try {
      final uri = Uri.parse('$apiBase/newtv/otp.php');
      final req = await client.getUrl(uri);
      req.headers.set('otp', cleanOtp);
      req.headers.set('Ott', ott);
      req.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:136.0) Gecko/20100101 Firefox/136.0 /OS.Gatu v1.0');
      req.headers.set('X-Requested-With', 'NetmirrorNewTV v1.0');
      req.headers.set('Accept', 'application/json, text/plain, */*');
      req.headers.set('Cache-Control', 'no-cache, no-store, must-revalidate');
      req.headers.set('Pragma', 'no-cache');
      req.headers.set('Expires', '0');
      req.headers.set('Connection', 'Keep-Alive');

      final res = await req.close().timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final body = await res.transform(utf8.decoder).join();
        final data = jsonDecode(body) as Map<String, dynamic>;
        final status = data['status']?.toString() ?? '';
        final usertoken = data['usertoken']?.toString() ?? data['otp']?.toString() ?? '';
        
        debugPrint('NetmirrorOtt: fetchUsertokenWithOtp [$ott] status=$status, usertoken=$usertoken');
        if (status == 'ok' || (status != 'error' && _isValidToken(usertoken))) {
          final tokenToSave = _isValidToken(usertoken) ? usertoken : cleanOtp;
          await saveUsertoken(tokenToSave, ott: ott);
          client.close();
          return tokenToSave;
        }
      }
    } catch (e) {
      debugPrint('NetmirrorOtt: fetchUsertokenWithOtp error: $e');
    }
    client.close();
    return null;
  }

  // ─── API Base Resolution ───────────────────────────────────────────────────

  static Future<String> _resolveApiBase() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_prefApiBase) ?? '';
    if (cached.isNotEmpty) return cached;

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 4);
    client.badCertificateCallback = (_, __, ___) => true;

    for (final domain in _detectionDomains) {
      try {
        final uri = Uri.parse('$domain/checknewtv.php');
        final req = await client.getUrl(uri);
        _baseHeaders.forEach((k, v) => req.headers.set(k, v));
        final res = await req.close().timeout(const Duration(seconds: 5));
        if (res.statusCode == 200) {
          final body = await res.transform(utf8.decoder).join();
          final data = jsonDecode(body) as Map<String, dynamic>;
          final tokenHash = data['token_hash']?.toString() ?? '';
          if (tokenHash.isNotEmpty) {
            final apiBase = utf8.decode(base64.decode(tokenHash)).trim().replaceAll(RegExp(r'/$'), '');
            if (apiBase.startsWith('http')) {
              await prefs.setString(_prefApiBase, apiBase);
              debugPrint('NetmirrorOtt: apiBase resolved to $apiBase');
              client.close();
              return apiBase;
            }
          }
        }
      } catch (e) {
        debugPrint('NetmirrorOtt: checknewtv.php failed for $domain: $e');
      }
    }
    client.close();
    return _defaultApiBase;
  }

  // ─── HTTP Helper ───────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> _getJson(
    String url, {
    String? usertoken,
    String? ott,
  }) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 8);
    client.badCertificateCallback = (_, __, ___) => true;
    try {
      final req = await client.getUrl(Uri.parse(url));
      _baseHeaders.forEach((k, v) => req.headers.set(k, v));
      req.headers.set('Referer', '$_defaultApiBase/');
      if (_isValidToken(usertoken)) {
        req.headers.set('Usertoken', usertoken!.trim());
      }
      if (ott != null && ott.isNotEmpty) {
        req.headers.set('Ott', ott);
      }
      final res = await req.close().timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        client.close();
        return null;
      }
      final body = await res.transform(utf8.decoder).join();
      client.close();
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (e) {
      client.close();
      debugPrint('NetmirrorOtt: _getJson error for $url: $e');
      return null;
    }
  }

  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static String _clean(String s) =>
      s.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim().toLowerCase();

  // ─── Main Entry Point ──────────────────────────────────────────────────────

  static Future<NetmirrorOttResult> resolveStreams({
    required String title,
    String? year,
    bool isSeries = false,
    int? season,
    int? episode,
  }) async {
    final apiBase = await _resolveApiBase();
    final searchTitle = title
        .trim()
        .replaceAll(RegExp(r'\s+S\d+E\d+', caseSensitive: false), '')
        .trim();

    final sources = <StreamSourceInfo>[];
    bool encounteredOtp = false;

    // Search and resolve across Netflix (nf), Prime Video (pv), and Hotstar (hs)
    for (final testOtt in ['nf', 'pv', 'hs']) {
      // 1. Search catalog for this OTT provider using unified newtv search endpoint
      final searchUrl = '$apiBase/newtv/search.php?s=${Uri.encodeComponent(searchTitle)}';

      final searchData = await _getJson(searchUrl, ott: testOtt);
      if (searchData == null) continue;

      final results = (searchData['searchResult'] as List? ?? []);
      if (results.isEmpty) continue;

      // 2. Find best match with strict criteria (never fallback to results.first)
      final normTarget = _norm(searchTitle);
      final cleanTarget = _norm(_clean(searchTitle));
      Map<String, dynamic>? best;

      // Exact match
      for (final r in results) {
        final item = r as Map<String, dynamic>;
        final itemTitle = item['t']?.toString() ?? '';
        if (_norm(itemTitle) == normTarget) {
          best = item;
          break;
        }
      }

      // Cleaned match without parentheticals (e.g. "(Tamil)", "(Season 1)")
      if (best == null && cleanTarget.isNotEmpty) {
        for (final r in results) {
          final item = r as Map<String, dynamic>;
          final itemTitle = item['t']?.toString() ?? '';
          if (_norm(_clean(itemTitle)) == cleanTarget) {
            best = item;
            break;
          }
        }
      }

      // Strong containment with close length (length difference <= 8 characters)
      if (best == null && normTarget.length >= 3) {
        for (final r in results) {
          final item = r as Map<String, dynamic>;
          final itemTitle = item['t']?.toString() ?? '';
          final normItem = _norm(itemTitle);
          if (normItem.contains(normTarget) && (normItem.length - normTarget.length) <= 8) {
            best = item;
            break;
          } else if (normTarget.contains(normItem) && (normTarget.length - normItem.length) <= 8) {
            best = item;
            break;
          }
        }
      }

      // If no valid title match found for this provider, skip it
      if (best == null) continue;

      final contentId = best['id']?.toString() ?? '';
      if (contentId.isEmpty) continue;
      debugPrint('NetmirrorOtt: [$testOtt] Matched "${best["t"]}" (id=$contentId)');

      // 3. Resolve series episode
      String resolvedId = contentId;
      if (isSeries && season != null && episode != null) {
        final postData = await _getJson('$apiBase/newtv/post.php?id=$contentId', ott: testOtt);
        if (postData != null && postData.isNotEmpty) {
          final epId = _findEpisodeId(postData, season, episode);
          if (epId != null && epId.isNotEmpty) {
            resolvedId = epId;
            debugPrint('NetmirrorOtt: [$testOtt] Resolved S${season}E$episode → id=$resolvedId');
          }
        } else if (testOtt != 'nf') {
          final epData = await _getJson('https://net52.cc/mobile/$testOtt/episodes.php?s=$contentId', ott: testOtt);
          if (epData != null && epData.isNotEmpty) {
            final epId = _findEpisodeId(epData, season, episode);
            if (epId != null && epId.isNotEmpty) {
              resolvedId = epId;
              debugPrint('NetmirrorOtt: [$testOtt] Resolved S${season}E$episode from episodes.php → id=$resolvedId');
            }
          }
        }
      }

      // 4. Resolve player link with Usertoken
      final usertoken = await getSavedUsertoken(ott: testOtt);
      debugPrint('NetmirrorOtt: Calling player testOtt=$testOtt, id=$resolvedId, token=${usertoken != null && usertoken.length > 15 ? usertoken.substring(0, 15) : usertoken}...');
      
      final playerData = await _getJson(
        '$apiBase/newtv/player.php?id=$resolvedId',
        usertoken: usertoken,
        ott: testOtt,
      );

      if (playerData != null) {
        final status    = playerData['status']?.toString() ?? '';
        final videoLink = playerData['video_link']?.toString() ?? '';
        final referer   = playerData['referer']?.toString() ?? 'https://net52.cc';
        final ottLabel  = (playerData['ott']?.toString() ?? testOtt).toUpperCase();

        debugPrint('NetmirrorOtt: player testOtt=$testOtt, status=$status, video_link=$videoLink');

        if (status == 'otp') {
          encounteredOtp = true;
          await invalidateUsertoken(ott: testOtt);
        }

        if (status == 'ok' && videoLink.isNotEmpty && !videoLink.contains('error')) {
          final hasVideo = await _hasVideoStreams(videoLink, referer);
          if (hasVideo) {
            sources.add(StreamSourceInfo(
              name   : 'NetMirror OTT [$ottLabel] • HD',
              url    : videoLink,
              type   : StreamSourceType.netmirrorOtt,
              quality: 'HD',
              headers: {
                'Referer'   : referer,
                'Cookie'    : 'hd=on',
                'Usertoken' : usertoken ?? '',
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
              },
            ));
          } else {
            debugPrint('NetmirrorOtt: Skipping $testOtt because master playlist has no video streams');
          }
        }
      }
    }

    if (sources.isNotEmpty) {
      return NetmirrorOttResult(needsOtp: false, streams: sources);
    }

    return NetmirrorOttResult(needsOtp: encounteredOtp, streams: sources);
  }

  static Future<bool> _hasVideoStreams(String m3u8Url, String referer) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);
    client.badCertificateCallback = (_, __, ___) => true;
    try {
      final req = await client.getUrl(Uri.parse(m3u8Url));
      req.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36');
      req.headers.set('Referer', referer);
      req.headers.set('Cookie', 'hd=on');
      final res = await req.close().timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final body = await res.transform(utf8.decoder).join();
        client.close();
        return body.contains('#EXT-X-STREAM-INF') || body.contains('.m3u8') || body.contains('.jpg') || body.contains('.ts');
      }
    } catch (e) {
      debugPrint('NetmirrorOtt: _hasVideoStreams check failed for $m3u8Url: $e');
    }
    client.close();
    return false;
  }

  static String? _findEpisodeId(
    Map<String, dynamic> postData,
    int season,
    int episode,
  ) {
    final episodes = postData['episodes'] as List?;
    if (episodes != null) {
      for (final ep in episodes) {
        final epMap = ep as Map<String, dynamic>;
        final epStr = epMap['ep']?.toString().replaceAll(RegExp(r'[^0-9]'), '') ?? '';
        final sStr  = epMap['s']?.toString().replaceAll(RegExp(r'[^0-9]'), '') ??
                      epMap['season']?.toString().replaceAll(RegExp(r'[^0-9]'), '') ?? '1';
        final epNum = int.tryParse(epStr) ?? 0;
        final sNum  = int.tryParse(sStr) ?? 1;
        if (sNum == season && epNum == episode) {
          return epMap['id']?.toString();
        }
      }
    }

    final seasons = postData['season'] as List?;
    if (seasons != null && season <= seasons.length) {
      final seasonData = seasons[season - 1] as Map<String, dynamic>?;
      final eps = seasonData?['episodes'] as List?;
      if (eps != null) {
        for (final ep in eps) {
          final epMap = ep as Map<String, dynamic>;
          final epStr = epMap['ep']?.toString().replaceAll(RegExp(r'[^0-9]'), '') ?? '';
          final epNum = int.tryParse(epStr) ?? 0;
          if (epNum == episode) return epMap['id']?.toString();
        }
      }
    }
    return null;
  }
}

class NetmirrorOttResult {
  final bool needsOtp;
  final List<StreamSourceInfo> streams;
  const NetmirrorOttResult({required this.needsOtp, required this.streams});
}
