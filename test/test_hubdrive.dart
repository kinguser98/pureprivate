import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final hubdriveUrl = 'https://hubdrive.tips/file/1849952845';
  print('--- Testing hubdrive.tips: $hubdriveUrl ---');
  try {
    final res = await http.get(Uri.parse(hubdriveUrl), headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/150.0.0.0 Safari/537.36',
      'Referer': 'https://new5.hdhub4u.cl/',
    });
    print('Status: ${res.statusCode}');
    print('Body length: ${res.body.length}');
    final hrefRegex = RegExp(r'<a[^>]+href="([^"]+)"[^>]*>(.*?)<\/a>', caseSensitive: false, dotAll: true);
    for (final m in hrefRegex.allMatches(res.body)) {
      final href = m.group(1) ?? '';
      final txt = m.group(2)?.replaceAll(RegExp(r'<[^>]*>'), '').trim() ?? '';
      print('  Link on HubDrive: $href [$txt]');
    }
  } catch (e) {
    print('Error: $e');
  }
}
