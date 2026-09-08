import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:private_cinema_mobile/data/domain_service.dart';

class NetmirrorCenterStreamInfo {
  final String name;
  final String url;
  final String quality;
  final Map<String, String> headers;

  const NetmirrorCenterStreamInfo({
    required this.name,
    required this.url,
    required this.quality,
    required this.headers,
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

  /// Searches and resolves direct video streams for a movie or TV series.
  static Future<List<NetmirrorCenterStreamInfo>> resolveStreams(
    String title,
    String year, {
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

      // Find best match: check year or title similarity
      final titleLower = cleanTitle.toLowerCase();
      dynamic matchedItem;
      for (final item in items) {
        final itemTitle = (item['title'] ?? '').toString().toLowerCase();
        final itemYear = (item['release_date'] ?? '').toString();
        final itemType = (item['media_type'] ?? '').toString().toLowerCase();

        final matchesType = isSeries ? itemType == 'tv' : itemType != 'tv';
        if (!matchesType && items.length > 1) continue;

        if (titleLower.split(' ').every((w) => w.length < 3 || itemTitle.contains(w))) {
          matchedItem = item;
          if (year.isNotEmpty && itemYear.contains(year)) {
            break; // Ideal match
          }
        }
      }

      matchedItem ??= items.first;
      final String itemId = matchedItem['id']?.toString() ?? '';
      final String itemType = matchedItem['media_type']?.toString() == 'tv' ? 'tv' : 'movie';
      final String matchedTitle = matchedItem['title']?.toString().replaceAll('\n', '').trim() ?? cleanTitle;

      if (itemId.isEmpty) return results;

      debugPrint('NetmirrorCenter: Found candidate "$matchedTitle" (ID: $itemId, Type: $itemType)');

      // Fetch metadata from api3
      final detailUrl = Uri.parse('$api3Domain/api/$itemType/$itemId');
      final detailRes = await http.get(detailUrl, headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Referer': '$centerDomain/',
        'Origin': centerDomain,
      }).timeout(const Duration(seconds: 10));

      if (detailRes.statusCode != 200) {
        debugPrint('NetmirrorCenter: Metadata fetch failed for $itemId: ${detailRes.statusCode}');
        return results;
      }

      final detailData = jsonDecode(detailRes.body) as Map<String, dynamic>;
      final detailResults = detailData['results'] as List<dynamic>?;
      if (detailResults == null || detailResults.isEmpty) return results;

      final detail = detailResults.first as Map<String, dynamic>;
      final String subjectId = detail['subjectid']?.toString() ?? '';
      final String dp = detail['dp']?.toString() ?? '';

      if (subjectId.isEmpty) {
        debugPrint('NetmirrorCenter: No subjectid found for $itemId');
        return results;
      }

      // Prepare watchbox URL
      final ts = (DateTime.now().millisecondsSinceEpoch / 1000).floor();
      final sig = _generateSignature(itemId, ts);
      final na = Uri.encodeComponent(base64Encode(utf8.encode(matchedTitle)));

      final seParam = isSeries ? (season ?? 1).toString() : '0';
      final epParam = isSeries ? (episode ?? 1).toString() : '0';

      final watchboxUrl = Uri.parse(
        '$watchboxDomain/play/watchbox.php?id=$subjectId&se=$seParam&ep=$epParam&dp=${Uri.encodeComponent(dp)}&na=$na&ts=$ts&sig=$sig&nid=$itemId&exten=1&tv=&token=',
      );

      debugPrint('NetmirrorCenter: Fetching watchbox player from $watchboxUrl');

      final playerRes = await http.get(watchboxUrl, headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Referer': '$centerDomain/',
        'Origin': centerDomain,
      }).timeout(const Duration(seconds: 10));

      if (playerRes.statusCode != 200) {
        debugPrint('NetmirrorCenter: Watchbox returned status ${playerRes.statusCode}');
        return results;
      }

      final playerHtml = playerRes.body;

      // Parse Artplayer selector qualities:
      // html: '1080P', url: 'https://...'
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
          results.add(NetmirrorCenterStreamInfo(
            name: 'NetMirror Center • $qLabel MP4',
            url: streamUrl,
            quality: qLabel.toUpperCase(),
            headers: _playerHeaders,
          ));
        }
      }

      // Fallback: extract any MP4 URLs in script if selector blocks were not matched
      if (results.isEmpty) {
        final rawMp4Regex = RegExp(r"""url:\s*['"](https?://[^'"]+\.mp4[^'"]*)['"]""");
        for (final m in rawMp4Regex.allMatches(playerHtml)) {
          final streamUrl = m.group(1)?.trim() ?? '';
          if (streamUrl.isNotEmpty && !seenUrls.contains(streamUrl)) {
            seenUrls.add(streamUrl);
            results.add(NetmirrorCenterStreamInfo(
              name: 'NetMirror Center • Direct Stream',
              url: streamUrl,
              quality: 'HD',
              headers: _playerHeaders,
            ));
          }
        }
      }

      debugPrint('NetmirrorCenter: Successfully extracted ${results.length} stream(s)');
    } catch (e) {
      debugPrint('NetmirrorCenter: Resolution error: $e');
    }

    return results;
  }
}
