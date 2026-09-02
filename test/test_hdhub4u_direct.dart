import 'dart:convert';
import 'package:http/http.dart' as http;

class StreamSourceInfo {
  final String name;
  final String url;
  final String quality;
  final String? size;
  final Map<String, String>? headers;
  StreamSourceInfo({required this.name, required this.url, required this.quality, this.size, this.headers});
}

class Hdhub4uResolverTest {
  static const List<String> _domains = [
    'https://new5.hdhub4u.cl',
    'https://new3.hdhub4u.cl',
    'https://new4.hdhub4u.cl',
  ];

  static const Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/150.0.0.0 Safari/537.36',
    'Cookie': 'xla=s4t',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
  };

  static Future<List<StreamSourceInfo>> resolveStreams(String query) async {
    final cleanQuery = query.replaceAll(RegExp(r'[^\w\s]'), ' ').trim();
    print('Searching HDHub4u for "$cleanQuery"...');

    for (final domain in _domains) {
      try {
        final searchUrl = '$domain/?s=${Uri.encodeComponent(cleanQuery)}';
        final res = await http.get(Uri.parse(searchUrl), headers: _headers).timeout(const Duration(seconds: 8));
        if (res.statusCode != 200) continue;

        final linkRegex = RegExp(r'<a[^>]+href="([^"]+)"[^>]*>(.*?)<\/a>', caseSensitive: false, dotAll: true);
        final postUrls = <String>[];

        for (final m in linkRegex.allMatches(res.body)) {
          final href = m.group(1) ?? '';
          final txt = m.group(2)?.replaceAll(RegExp(r'<[^>]*>'), '').trim() ?? '';
          if (href.startsWith(domain) && !href.contains('/category') && !href.contains('/page') && !href.contains('/tag') && href != '$domain/') {
            final words = cleanQuery.toLowerCase().split(' ').where((w) => w.length > 2).toList();
            bool match = words.isEmpty;
            for (final w in words) {
              if (href.toLowerCase().contains(w) || txt.toLowerCase().contains(w)) match = true;
            }
            if (match && !postUrls.contains(href)) {
              postUrls.add(href);
            }
          }
        }

        print('Found ${postUrls.length} posts for "$cleanQuery" on $domain');
        if (postUrls.isEmpty) continue;

        final allStreams = <StreamSourceInfo>[];
        for (final targetPost in postUrls.take(2)) {
          print('Processing post: $targetPost');
          final postRes = await http.get(Uri.parse(targetPost), headers: _headers).timeout(const Duration(seconds: 8));
          if (postRes.statusCode != 200) continue;

          final postHtml = postRes.body;
          final buttonMatches = linkRegex.allMatches(postHtml);
          final unpackFutures = <Future<List<StreamSourceInfo>>>[];

          for (final bm in buttonMatches) {
            final btnUrl = bm.group(1)?.trim() ?? '';
            final btnText = bm.group(2)?.replaceAll(RegExp(r'<[^>]*>'), '').trim() ?? '';
            final lowerBtnUrl = btnUrl.toLowerCase();
            final lowerBtnText = btnText.toLowerCase();

            if (lowerBtnUrl.contains('hubdrive') ||
                lowerBtnUrl.contains('hubcloud') ||
                lowerBtnUrl.contains('gdflix') ||
                lowerBtnText.contains('720p') ||
                lowerBtnText.contains('1080p') ||
                lowerBtnText.contains('2160p') ||
                lowerBtnText.contains('4k') ||
                lowerBtnText.contains('hevc') ||
                lowerBtnText.contains('web-dl')) {
              if (btnUrl.startsWith('http') && !btnUrl.contains('hdhub4u')) {
                unpackFutures.add(_unpackDirectStreams(btnUrl, btnText));
              }
            }
          }

          final results = await Future.wait(unpackFutures);
          for (final list in results) {
            allStreams.addAll(list);
          }
        }

        if (allStreams.isNotEmpty) {
          return allStreams;
        }
      } catch (e) {
        print('Error searching on $domain: $e');
      }
    }
    return [];
  }

  static Future<List<StreamSourceInfo>> _unpackDirectStreams(String initialUrl, String buttonText) async {
    final streams = <StreamSourceInfo>[];
    String quality = '1080p';
    String? size;

    final lowerText = buttonText.toLowerCase();
    if (lowerText.contains('2160p') || lowerText.contains('4k')) {
      quality = '4K (2160p)';
    } else if (lowerText.contains('1080p')) {
      quality = '1080p Full HD';
    } else if (lowerText.contains('720p')) {
      quality = '720p HD';
    } else if (lowerText.contains('480p')) {
      quality = '480p SD';
    }

    final sizeMatch = RegExp(r'\[([0-9.]+\s*[GM]B)\]', caseSensitive: false).firstMatch(buttonText);
    if (sizeMatch != null) {
      size = sizeMatch.group(1);
    }

    try {
      String currentUrl = initialUrl;

      // Hop 1: HubDrive -> HubCloud
      if (currentUrl.contains('hubdrive.') || currentUrl.contains('drive.')) {
        final res1 = await http.get(Uri.parse(currentUrl), headers: _headers).timeout(const Duration(seconds: 5));
        final hubMatch = RegExp(r'href="(https?://[^"]*hubcloud[^"]*)"').firstMatch(res1.body);
        if (hubMatch != null) currentUrl = hubMatch.group(1)!;
      }

      // Hop 2: HubCloud -> Gateway / gamerxyt
      if (currentUrl.contains('hubcloud.')) {
        final res2 = await http.get(Uri.parse(currentUrl), headers: {
          ..._headers,
          'Referer': initialUrl,
        }).timeout(const Duration(seconds: 5));

        final targetMatch = RegExp(r"var\s+url\s*=\s*'([^']+)'").firstMatch(res2.body) ??
                            RegExp(r'id="download"[^>]*href="([^"]+)"').firstMatch(res2.body);
        if (targetMatch != null) currentUrl = targetMatch.group(1)!;
      }

      // Hop 3: Gateway -> Direct MKV streams
      final res3 = await http.get(Uri.parse(currentUrl), headers: {
        ..._headers,
        'Referer': 'https://hubcloud.cx/',
      }).timeout(const Duration(seconds: 5));

      final btnRegex = RegExp(r'<a[^>]+href="([^"]+)"[^>]*>(.*?)<\/a>', caseSensitive: false, dotAll: true);
      for (final m in btnRegex.allMatches(res3.body)) {
        final href = m.group(1) ?? '';
        final label = m.group(2)?.replaceAll(RegExp(r'<[^>]*>'), '').trim() ?? '';
        final lowerHref = href.toLowerCase();

        if (lowerHref.contains('.r2.cloudflarestorage.com') ||
            lowerHref.contains('cdn.') ||
            lowerHref.endsWith('.mkv') ||
            lowerHref.endsWith('.mp4') ||
            lowerHref.contains('.mkv?') ||
            lowerHref.contains('.mp4?')) {
          String serverName = 'Fast Server';
          if (label.contains('FSLv2') || lowerHref.contains('lenin.buzz') || lowerHref.contains('pongala.life') || lowerHref.contains('cocktail.beer')) {
            serverName = 'FSLv2 CDN';
          } else if (label.contains('FSL Server') || lowerHref.contains('.r2.')) {
            serverName = 'Cloudflare R2 Direct';
          } else if (label.contains('10Gbps')) {
            serverName = '10Gbps Dedicated';
          }

          final displayName = 'HDHub4u • $serverName • $quality';
          streams.add(StreamSourceInfo(
            name: displayName,
            url: href,
            quality: quality,
            size: size,
          ));
        }
      }
    } catch (e) {
      // Return initialUrl if unpack fails
    }
    return streams;
  }
}

void main() async {
  final streams = await Hdhub4uResolverTest.resolveStreams('Alpha');
  print('\n=== TOTAL DIRECT STREAMS RESOLVED: ${streams.length} ===');
  for (final s in streams) {
    print('${s.name} [Size: ${s.size}]: ${s.url}');
  }
}
