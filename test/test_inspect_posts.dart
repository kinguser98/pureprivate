import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  print('--- Inspecting HDHub4u for Pushpa & Kattalan ---');
  final res = await http.get(Uri.parse('https://new5.hdhub4u.cl/?s=Pushpa'), headers: {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/150.0.0.0 Safari/537.36',
    'Cookie': 'xla=s4t',
  });
  print('Status: ${res.statusCode}');
  final regex = RegExp(r'<a[^>]+href="([^"]+)"[^>]*>(.*?)<\/a>', caseSensitive: false, dotAll: true);
  for (final m in regex.allMatches(res.body)) {
    final href = m.group(1) ?? '';
    final txt = m.group(2)?.replaceAll(RegExp(r'<[^>]*>'), '').trim() ?? '';
    if (href.contains('hdhub4u') && !href.contains('/category') && !href.contains('/page') && txt.isNotEmpty) {
      print('  Found post: $txt -> $href');
    }
  }

  print('\n--- Inspecting MoviesDrive domain / search ---');
  final md = await http.get(Uri.parse('https://new3.moviesdrive.christmas/?s=Pushpa'), headers: {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/150.0.0.0 Safari/537.36',
  });
  print('MD Status: ${md.statusCode}');
  for (final m in regex.allMatches(md.body)) {
    final href = m.group(1) ?? '';
    final txt = m.group(2)?.replaceAll(RegExp(r'<[^>]*>'), '').trim() ?? '';
    if (txt.isNotEmpty && !href.contains('/category') && !href.contains('/page')) {
      print('  Found MD post: $txt -> $href');
    }
  }
}
