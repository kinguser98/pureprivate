import 'dart:convert';
import 'package:http/http.dart' as http;

Future<List<Map<String, String>>> unpackHubDriveOrHubCloud(String initialUrl) async {
  final results = <Map<String, String>>[];
  try {
    String currentUrl = initialUrl;

    // Step 1: If hubdrive.tips / hubdrive.me / etc., fetch it to get hubcloud.cx
    if (currentUrl.contains('hubdrive.') || currentUrl.contains('drive.')) {
      final res1 = await http.get(Uri.parse(currentUrl), headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/150.0.0.0 Safari/537.36',
      }).timeout(const Duration(seconds: 6));
      
      final hubcloudMatch = RegExp(r'href="(https?://[^"]*hubcloud[^"]*)"').firstMatch(res1.body);
      if (hubcloudMatch != null) {
        currentUrl = hubcloudMatch.group(1)!;
      }
    }

    // Step 2: If hubcloud.cx / hubcloud.club / hubcloud.one, extract gamerxyt or target redirect
    if (currentUrl.contains('hubcloud.')) {
      final res2 = await http.get(Uri.parse(currentUrl), headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/150.0.0.0 Safari/537.36',
        'Referer': 'https://hubdrive.tips/',
      }).timeout(const Duration(seconds: 6));

      final targetMatch = RegExp(r"var\s+url\s*=\s*'([^']+)'").firstMatch(res2.body) ??
                          RegExp(r'id="download"[^>]*href="([^"]+)"').firstMatch(res2.body);
      if (targetMatch != null) {
        currentUrl = targetMatch.group(1)!;
      }
    }

    // Step 3: Fetch the gateway page (gamerxyt.com / hubcloud.php / etc.) to extract direct streaming URLs!
    final res3 = await http.get(Uri.parse(currentUrl), headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/150.0.0.0 Safari/537.36',
      'Referer': 'https://hubcloud.cx/',
    }).timeout(const Duration(seconds: 6));

    final btnRegex = RegExp(r'<a[^>]+href="([^"]+)"[^>]*>(.*?)<\/a>', caseSensitive: false, dotAll: true);
    for (final m in btnRegex.allMatches(res3.body)) {
      var href = m.group(1) ?? '';
      final label = m.group(2)?.replaceAll(RegExp(r'<[^>]*>'), '').trim() ?? '';
      final lowerHref = href.toLowerCase();

      // Convert pixeldrain web url to direct api video
      if (lowerHref.contains('pixeldrain.com/u/') || lowerHref.contains('pixeldrain.dev/u/')) {
        final pxId = RegExp(r'pixeldrain\.(?:com|dev)/u/([A-Za-z0-9_-]+)').firstMatch(href)?.group(1);
        if (pxId != null) {
          results.add({
            'name': 'PixelDrain API Stream',
            'url': 'https://pixeldrain.com/api/file/$pxId',
            'quality': 'Direct',
          });
        }
      } else if (lowerHref.contains('.r2.cloudflarestorage.com') ||
                 lowerHref.contains('cdn.') ||
                 lowerHref.endsWith('.mkv') ||
                 lowerHref.endsWith('.mp4') ||
                 lowerHref.contains('.mkv?') ||
                 lowerHref.contains('.mp4?')) {
        String name = 'Direct Fast Server';
        if (label.contains('FSLv2')) name = 'FSLv2 Dedicated CDN';
        if (label.contains('FSL Server')) name = 'Cloudflare R2 Direct';
        if (label.contains('10Gbps')) name = '10Gbps Fast Server';

        results.add({
          'name': name,
          'url': href,
          'quality': 'Direct Video',
        });
      }
    }
  } catch (e) {
    print('Unpack error: $e');
  }
  return results;
}

void main() async {
  print('--- Testing HDHub4u Full Flow for Alpha ---');
  final postRes = await http.get(Uri.parse('https://new5.hdhub4u.cl/alpha-2026-hindi-webrip-full-movie/'), headers: {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/150.0.0.0 Safari/537.36',
    'Cookie': 'xla=s4t',
  });
  final btnRegex = RegExp(r'<a[^>]+href="([^"]+)"[^>]*>(.*?)<\/a>', caseSensitive: false, dotAll: true);
  for (final m in btnRegex.allMatches(postRes.body)) {
    final href = m.group(1) ?? '';
    final txt = m.group(2)?.replaceAll(RegExp(r'<[^>]*>'), '').trim() ?? '';
    if (href.contains('hubdrive') || href.contains('hubcloud')) {
      print('\nUnpacking post button: $txt -> $href');
      final direct = await unpackHubDriveOrHubCloud(href);
      for (final d in direct) {
        print('  ==> DIRECT STREAM: ${d['name']} | ${d['url']}');
      }
    }
  }
}
