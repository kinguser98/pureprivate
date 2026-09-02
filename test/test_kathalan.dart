import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  print('--- Checking Kathalan on HDHub4u ---');
  final res = await http.get(Uri.parse('https://new5.hdhub4u.cl/?s=Kathalan'), headers: {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/150.0.0.0 Safari/537.36',
    'Cookie': 'xla=s4t',
  });
  final regex = RegExp(r'<a[^>]+href="([^"]+)"[^>]*>(.*?)<\/a>', caseSensitive: false, dotAll: true);
  for (final m in regex.allMatches(res.body)) {
    final href = m.group(1) ?? '';
    final txt = m.group(2)?.replaceAll(RegExp(r'<[^>]*>'), '').trim() ?? '';
    if (txt.toLowerCase().contains('kathalan') || href.contains('kathalan')) {
      print('  Found Kathalan post: $txt -> $href');
    }
  }
}
