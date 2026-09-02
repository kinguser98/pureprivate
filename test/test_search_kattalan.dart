import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  print('--- Testing HDHub4u HTML Search for kattalan ---');
  final queries = ['kattalan', 'Kattalan', 'kattalan 2026', 'kattalan hindi'];
  for (final q in queries) {
    final url = 'https://new5.hdhub4u.cl/?s=${Uri.encodeComponent(q)}';
    final res = await http.get(Uri.parse(url), headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/150.0.0.0 Safari/537.36',
      'Cookie': 'xla=s4t',
    });
    print('Query "$q" -> status ${res.statusCode}');
    final linkRegex = RegExp(r'<a[^>]+href="([^"]+)"[^>]*>(.*?)<\/a>', caseSensitive: false, dotAll: true);
    for (final m in linkRegex.allMatches(res.body)) {
      final href = m.group(1) ?? '';
      final txt = m.group(2)?.replaceAll(RegExp(r'<[^>]*>'), '').trim() ?? '';
      if (href.contains('kattalan')) {
        print('  Found match: $txt -> $href');
      }
    }
  }
}
