import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:private_cinema_mobile/data/domain_service.dart';

class NetmirrorCenterStreamInfo {
  final String name;
  final String url;
  final String quality;
  final String? language;
  final Map<String, String> headers;

  const NetmirrorCenterStreamInfo({
    required this.name,
    required this.url,
    required this.quality,
    this.language,
    required this.headers,
  });
}

class _NetmirrorCandidate {
  final dynamic item;
  final String rawTitle;
  final String language;
  final bool hasExplicitLang;

  const _NetmirrorCandidate({
    required this.item,
    required this.rawTitle,
    required this.language,
    required this.hasExplicitLang,
  });
}

class NetmirrorCenterResolver {
  static const String defaultCenterDomain = 'https://netmirror.center';
  static const String defaultApi3Domain = 'https://api2.imdb3.shop';
  static const String defaultApi4Domain = 'https://api2.imdb4.shop';
  static const String defaultWatchboxDomain = 'https://bet.watch21.shop';
  static const String _secretKey = 'net###@@sss';

  static String get centerDomain =>
      DomainService.getDomainSync('netmirror_center', defaultFallback: defaultCenterDomain);
  static String get api3Domain =>
      DomainService.getDomainSync('netmirror_api3', defaultFallback: defaultApi3Domain);
  static String get api4Domain =>
      DomainService.getDomainSync('netmirror_api4', defaultFallback: defaultApi4Domain);
  static String get watchboxDomain =>
      DomainService.getDomainSync('netmirror_watchbox', defaultFallback: defaultWatchboxDomain);

  static const Map<String, String> _playerHeaders = {
    'Referer': 'https://fmoviesunblocked.net/',
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  };

  static String _generateSignature(String id, int timestamp) {
    final key = utf8.encode(_secretKey);
    final bytes = utf8.encode('$id:$timestamp');
    final hmac = Hmac(sha256, key);
    return hmac.convert(bytes).toString();
  }

  static String _cleanQuery(String title) {
    return title
        .replaceAll(RegExp(r'[\(\)\[\]\{\}\:\-_,\.]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static int _getLangRank(String lang, String? origLang) {
    final l = lang.toLowerCase();
    final orig = (origLang ?? 'malayalam').toLowerCase();

    // If matches movie's main / original language, it gets Rank 0
    if (orig.isNotEmpty) {
      if ((orig.startsWith('ml') || orig.contains('malayalam')) && l.contains('malayalam')) return 0;
      if ((orig.startsWith('ta') || orig.contains('tamil')) && l.contains('tamil')) return 0;
      if ((orig.startsWith('te') || orig.contains('telugu')) && l.contains('telugu')) return 0;
      if ((orig.startsWith('kn') || orig.contains('kannada')) && l.contains('kannada')) return 0;
      if ((orig.startsWith('hi') || orig.contains('hindi')) && l.contains('hindi')) return 0;
    }

    if (l.contains('malayalam')) return 1;
    if (l.contains('tamil')) return 2;
    if (l.contains('telugu')) return 3;
    if (l.contains('kannada')) return 4;
    if (l.contains('hindi')) return 5;
    if (l.contains('english')) return 6;
    return 7;
  }

  static int _getQualityRank(String q) {
    final u = q.toUpperCase();
    if (u.contains('4K') || u.contains('2160')) return 4;
    if (u.contains('1080')) return 3;
    if (u.contains('720')) return 2;
    if (u.contains('480')) return 1;
    return 0;
  }

  /// Searches and resolves direct video streams for a movie or TV series across all languages.
  static Future<List<NetmirrorCenterStreamInfo>> resolveStreams(
    String title,
    String year, {
    String? originalLanguage,
    bool isSeries = false,
    int? season,
    int? episode,
  }) async {
    final List<NetmirrorCenterStreamInfo> results = [];
    final cleanTitle = _cleanQuery(title);
    if (cleanTitle.isEmpty) return results;

    try {
      final searchUrl = Uri.parse(
        '$api4Domain/api/search2/${Uri.encodeComponent(cleanTitle)}?page=0',
      );

      final searchRes = await http.get(searchUrl, headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Referer': '$centerDomain/',
        'Origin': centerDomain,
      }).timeout(const Duration(seconds: 10));

      if (searchRes.statusCode != 200) {
        debugPrint('NetmirrorCenter: Search failed with status ${searchRes.statusCode}');
        return results;
      }

      final searchData = jsonDecode(searchRes.body) as Map<String, dynamic>;
      final items = searchData['results'] as List<dynamic>?;
      if (items == null || items.isEmpty) {
        debugPrint('NetmirrorCenter: No search results found for "$cleanTitle"');
        return results;
      }

      final cleanTarget = cleanTitle.toLowerCase();
      final targetWords = cleanTarget.split(' ').where((w) => w.length >= 2).toList();
      final List<_NetmirrorCandidate> candidates = [];

      for (final item in items) {
        final rawTitle = (item['title'] ?? '').toString().replaceAll('\n', '').trim();
        final baseTitle = rawTitle.replaceAll(RegExp(r'\[.*?\]'), '').trim().toLowerCase();
        final itemType = (item['media_type'] ?? '').toString().toLowerCase();

        final matchesType = isSeries ? itemType == 'tv' : itemType != 'tv';
        if (!matchesType && items.length > 1) continue;

        final baseWords = baseTitle.split(' ').where((w) => w.length >= 2).toList();
        bool isMatch = false;
        if (targetWords.length <= 1) {
          isMatch = baseTitle == cleanTarget || (baseWords.isNotEmpty && baseWords.first == cleanTarget);
        } else {
          final wordsMatch = targetWords.every((w) => baseTitle.contains(w));
          isMatch = baseTitle == cleanTarget || (wordsMatch && baseWords.length <= targetWords.length + 1);
        }

        if (isMatch) {
          final itemYear = (item['release_date'] ?? '').toString();
          if (year.isNotEmpty && itemYear.isNotEmpty) {
            final py = int.tryParse(year);
            final iy = int.tryParse(itemYear);
            if (py != null && iy != null && (py - iy).abs() > 1) {
              continue; // Year mismatch
            }
          }

          final langMatch = RegExp(r'\[([^\]]+)\]').firstMatch(rawTitle);
          String lang = langMatch != null ? langMatch.group(1)!.trim() : '';
          final bool hasExplicit = langMatch != null;
          if (lang.isEmpty) {
            lang = (originalLanguage != null && originalLanguage.isNotEmpty)
                ? originalLanguage
                : 'Original';
          }

          candidates.add(_NetmirrorCandidate(
            item: item,
            rawTitle: rawTitle,
            language: lang,
            hasExplicitLang: hasExplicit,
          ));
        }
      }

      if (candidates.isEmpty) {
        final first = items.first;
        final rawTitle = (first['title'] ?? '').toString().replaceAll('\n', '').trim();
        candidates.add(_NetmirrorCandidate(
          item: first,
          rawTitle: rawTitle,
          language: originalLanguage ?? 'HD',
          hasExplicitLang: false,
        ));
      }

      // Deduplicate by language, keeping candidates with explicit bracket tags when available
      final Map<String, _NetmirrorCandidate> uniqueByLang = {};
      for (final c in candidates) {
        final key = c.language.toLowerCase();
        if (!uniqueByLang.containsKey(key) || (!uniqueByLang[key]!.hasExplicitLang && c.hasExplicitLang)) {
          uniqueByLang[key] = c;
        }
      }

      final filteredCandidates = uniqueByLang.values.toList();
      filteredCandidates.sort((a, b) =>
          _getLangRank(a.language, originalLanguage).compareTo(_getLangRank(b.language, originalLanguage)));

      debugPrint('NetmirrorCenter: Found ${filteredCandidates.length} language candidate(s): '
          '${filteredCandidates.map((c) => c.language).join(", ")}');

      // Fetch streams for all matching candidates concurrently
      final streamLists = await Future.wait(
        filteredCandidates.map((c) => _extractStreamsForCandidate(
          c,
          cleanTitle,
          isSeries: isSeries,
          season: season,
          episode: episode,
        )),
      );

      for (final list in streamLists) {
        results.addAll(list);
      }

      debugPrint('NetmirrorCenter: Successfully extracted ${results.length} total stream(s)');
    } catch (e) {
      debugPrint('NetmirrorCenter: Resolution error: $e');
    }

    return results;
  }

  static Future<List<NetmirrorCenterStreamInfo>> _extractStreamsForCandidate(
    _NetmirrorCandidate candidate,
    String cleanTitle, {
    bool isSeries = false,
    int? season,
    int? episode,
  }) async {
    final List<NetmirrorCenterStreamInfo> candidateResults = [];
    final itemId = candidate.item['id']?.toString() ?? '';
    final itemType = candidate.item['media_type']?.toString() == 'tv' ? 'tv' : 'movie';
    if (itemId.isEmpty) return candidateResults;

    try {
      final detailUrl = Uri.parse('$api3Domain/api/$itemType/$itemId');
      final detailRes = await http.get(detailUrl, headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Referer': '$centerDomain/',
        'Origin': centerDomain,
      }).timeout(const Duration(seconds: 10));

      if (detailRes.statusCode != 200) return candidateResults;

      final detailData = jsonDecode(detailRes.body) as Map<String, dynamic>;
      final detailResults = detailData['results'] as List<dynamic>?;
      if (detailResults == null || detailResults.isEmpty) return candidateResults;

      final detail = detailResults.first as Map<String, dynamic>;
      final String subjectId = detail['subjectid']?.toString() ?? '';
      final String dp = detail['dp']?.toString() ?? '';
      if (subjectId.isEmpty) return candidateResults;

      final ts = (DateTime.now().millisecondsSinceEpoch / 1000).floor();
      final sig = _generateSignature(itemId, ts);
      final na = Uri.encodeComponent(base64Encode(utf8.encode(candidate.rawTitle)));

      final seParam = isSeries ? (season ?? 1).toString() : '0';
      final epParam = isSeries ? (episode ?? 1).toString() : '0';

      final watchboxUrl = Uri.parse(
        '$watchboxDomain/play/watchbox.php?id=$subjectId&se=$seParam&ep=$epParam&dp=${Uri.encodeComponent(dp)}&na=$na&ts=$ts&sig=$sig&nid=$itemId&exten=1&tv=&token=',
      );

      final playerRes = await http.get(watchboxUrl, headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Referer': '$centerDomain/',
        'Origin': centerDomain,
      }).timeout(const Duration(seconds: 10));

      if (playerRes.statusCode != 200) return candidateResults;

      final playerHtml = playerRes.body;

      final qualityRegex = RegExp(
        r"""html:\s*['"]([^'"]+)['"],\s*url:\s*['"](https?://[^'"]+\.mp4[^'"]*)['"]""",
        caseSensitive: false,
      );

      final Set<String> seenUrls = {};
      final matches = qualityRegex.allMatches(playerHtml);

      for (final m in matches) {
        final qLabel = m.group(1)?.trim() ?? 'HD';
        final streamUrl = m.group(2)?.trim() ?? '';
        if (streamUrl.isNotEmpty && !seenUrls.contains(streamUrl)) {
          seenUrls.add(streamUrl);
          candidateResults.add(NetmirrorCenterStreamInfo(
            name: '${candidate.language} • $qLabel',
            url: streamUrl,
            quality: qLabel.toUpperCase(),
            language: candidate.language,
            headers: _playerHeaders,
          ));
        }
      }

      if (candidateResults.isEmpty) {
        final rawMp4Regex = RegExp(r"""url:\s*['"](https?://[^'"]+\.mp4[^'"]*)['"]""");
        for (final m in rawMp4Regex.allMatches(playerHtml)) {
          final streamUrl = m.group(1)?.trim() ?? '';
          if (streamUrl.isNotEmpty && !seenUrls.contains(streamUrl)) {
            seenUrls.add(streamUrl);
            candidateResults.add(NetmirrorCenterStreamInfo(
              name: '${candidate.language} • HD',
              url: streamUrl,
              quality: 'HD',
              language: candidate.language,
              headers: _playerHeaders,
            ));
          }
        }
      }

      // Sort qualities within candidate: 1080P > 720P > 480P > 360P
      candidateResults.sort((a, b) => _getQualityRank(b.quality).compareTo(_getQualityRank(a.quality)));
    } catch (e) {
      debugPrint('NetmirrorCenter: Candidate extraction error for $itemId: $e');
    }

    return candidateResults;
  }
}
