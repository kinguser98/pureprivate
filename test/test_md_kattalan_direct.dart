import 'dart:convert';
import 'package:http/http.dart' as http;

Future<List<Map<String, String>>> unpackHubDriveOrHubCloud(String initialUrl) async {
  final results = <Map<String, String>>[];
  try {
    String currentUrl = initialUrl;

    if (currentUrl.contains('hubdrive.') || currentUrl.contains('drive.')) {
      final res1 = await http.get(Uri.parse(currentUrl), headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/150.0.0.0 Safari/537.36',
      }).timeout(const Duration(seconds: 6));
      
      final hubcloudMatch = RegExp(r'href="(https?://[^"]*hubcloud[^"]*)"').firstMatch(res1.body);
      if (hubcloudMatch != null) {
        currentUrl = hubcloudMatch.group(1)!;
      }
    }

    if (currentUrl.contains('hubcloud.')) {
      final res2 = await http.get(Uri.parse(currentUrl), headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/150.0.0.0 Safari/537.36',
        'Referer': initialUrl,
      }).timeout(const Duration(seconds: 6));

      final targetMatch = RegExp(r"var\s+url\s*=\s*'([^']+)'").firstMatch(res2.body) ??
                          RegExp(r'id="download"[^>]*href="([^"]+)"').firstMatch(res2.body);
      if (targetMatch != null) {
        currentUrl = targetMatch.group(1)!;
      }
    }

    final res3 = await http.get(Uri.parse(currentUrl), headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/150.0.0.0 Safari/537.36',
      'Referer': 'https://hubcloud.cx/',
    }).timeout(const Duration(seconds: 6));

    final btnRegex = RegExp(r'<a[^>]+href="([^"]+)"[^>]*>(.*?)<\/a>', caseSensitive: false, dotAll: true);
    for (final m in btnRegex.allMatches(res3.body)) {
      var href = m.group(1) ?? '';
      final label = m.group(2)?.replaceAll(RegExp(r'<[^>]*>'), '').trim() ?? '';
      final lowerHref = href.toLowerCase();

      if (lowerHref.contains('.r2.cloudflarestorage.com') ||
          lowerHref.contains('cdn.') ||
          lowerHref.endsWith('.mkv') ||
          lowerHref.endsWith('.mp4') ||
          lowerHref.contains('.mkv?') ||
          lowerHref.contains('.mp4?')) {
        results.add({
          'name': label.isNotEmpty ? label : 'Direct Video Stream',
          'url': href,
        });
      }
    }
  } catch (e) {
    print('Unpack error: $e');
  }
  return results;
}

void main() async {
  print('--- Testing MoviesDrive Kattalan Unpacking ---');
  final postUrl = 'https://new3.moviesdrive.christmas/kattalan-2026-ds4k-web-dl-hindi-line-malayalam-org-5-1-480p-720p-1080p-2160p-4k-sdr-x264-esubs-full-movie/';
  final postRes = await http.get(Uri.parse(postUrl), headers: {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/150.0.0.0 Safari/537.36',
  });
  print('Post status: ${postRes.statusCode}');

  final btnRegex = RegExp(r'<a[^>]+href="([^"]+)"[^>]*>(.*?)<\/a>', caseSensitive: false, dotAll: true);
  for (final m in btnRegex.allMatches(postRes.body)) {
    final href = m.group(1) ?? '';
    final txt = m.group(2)?.replaceAll(RegExp(r'<[^>]*>'), '').trim() ?? '';
    if (href.contains('hubcloud') || href.contains('hubdrive') || href.contains('drive') || txt.toLowerCase().contains('download') || txt.toLowerCase().contains('fast server')) {
      if (href.startsWith('http') && !href.contains('moviesdrive')) {
        print('\nUnpacking MD button: $txt -> $href');
        final direct = await unpackHubDriveOrHubCloud(href);
        for (final d in direct) {
          print('  ==> DIRECT STREAM: ${d['name']} | ${d['url']}');
        }
      }
    }
  }
}
