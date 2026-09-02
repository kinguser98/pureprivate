import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  print('--- Testing PixelDrain conversion ---');
  final pxUrl = 'https://pixeldrain.com/u/abc12345';
  final idMatch = RegExp(r'pixeldrain\.com/u/([A-Za-z0-9_-]+)').firstMatch(pxUrl);
  if (idMatch != null) {
    final directPx = 'https://pixeldrain.com/api/file/${idMatch.group(1)}';
    print('Converted $pxUrl -> $directPx');
  }

  print('\n--- Testing HDHub4u search on new3.hdhub4u.cl for Alpha ---');
  try {
    final res = await http.get(Uri.parse('https://new3.hdhub4u.cl/?s=Alpha'), headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/150.0.0.0 Safari/537.36',
      'Cookie': 'xla=s4t',
      'Referer': 'https://new3.hdhub4u.cl/',
    });
    print('HDHub4u search status: ${res.statusCode}');
    final hrefRegex = RegExp(r'<a[^>]+href="([^"]+)"[^>]*>(.*?)<\/a>', caseSensitive: false, dotAll: true);
    for (final m in hrefRegex.allMatches(res.body)) {
      final href = m.group(1) ?? '';
      final txt = m.group(2) ?? '';
      if (href.contains('/alpha') || txt.toLowerCase().contains('alpha')) {
        print('  Found Alpha Post: $href -> $txt');
        // Fetch post
        final pRes = await http.get(Uri.parse(href), headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/150.0.0.0 Safari/537.36',
          'Cookie': 'xla=s4t',
        });
        for (final pm in hrefRegex.allMatches(pRes.body)) {
          final phref = pm.group(1) ?? '';
          final ptxt = pm.group(2) ?? '';
          if (phref.contains('hubcloud') || phref.contains('pixeldrain') || phref.contains('drive')) {
            print('    Download link: $phref (text: $ptxt)');
            if (phref.contains('hubcloud')) {
              // Test resolving hubcloud in HTTP!
              await testHubcloudResolve(phref);
            }
          }
        }
        break;
      }
    }
  } catch (e) {
    print('HDHub4u error: $e');
  }
}

Future<void> testHubcloudResolve(String hubUrl) async {
  print('    --> Resolving HubCloud: $hubUrl');
  try {
    final res = await http.get(Uri.parse(hubUrl), headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/150.0.0.0 Safari/537.36',
      'Referer': 'https://new3.hdhub4u.cl/',
    });
    print('    HubCloud initial status: ${res.statusCode}');
    // Check if there is next url
    final match = RegExp(r"var\s+url\s*=\s*'([^']+)'").firstMatch(res.body) ??
                  RegExp(r'id="download"[^>]*href="([^"]+)"').firstMatch(res.body);
    if (match != null) {
      final nextUrl = match.group(1)!;
      print('    HubCloud next page: $nextUrl');
      final p2Res = await http.get(Uri.parse(nextUrl), headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/150.0.0.0 Safari/537.36',
        'Referer': hubUrl,
      });
      print('    HubCloud page 2 status: ${p2Res.statusCode}');
      // Find stream buttons (FSL, S3, R2, Mega, PixelDrain)
      final btnRegex = RegExp(r'<a[^>]+href="([^"]+)"[^>]*>(.*?)<\/a>', caseSensitive: false, dotAll: true);
      for (final bm in btnRegex.allMatches(p2Res.body)) {
        final bhref = bm.group(1) ?? '';
        final btxt = bm.group(2)?.replaceAll(RegExp(r'<[^>]*>'), '').trim() ?? '';
        if (bhref.contains('r2.dev') || bhref.contains('workers.dev') || bhref.contains('pixeldrain') || btxt.toLowerCase().contains('download') || btxt.toLowerCase().contains('fsl') || btxt.toLowerCase().contains('server')) {
          print('      >>> Direct Server Button: $bhref [$btxt]');
        }
      }
    }
  } catch (e) {
    print('    HubCloud test error: $e');
  }
}
