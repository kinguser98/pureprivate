import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  print('--- Testing HDHub4u WordPress & Search Endpoints ---');
  final endpoints = [
    'https://new5.hdhub4u.cl/wp-json/wp/v2/posts?search=kattalan',
    'https://new5.hdhub4u.cl/wp-json/wp/v2/posts?search=alpha',
    'https://new5.hdhub4u.cl/wp-admin/admin-ajax.php?action=search&keyword=kattalan',
    'https://new5.hdhub4u.cl/?s=kattalan&post_type=post',
    'https://new5.hdhub4u.cl/search/kattalan',
    'https://new5.hdhub4u.cl/kattalan-2026-hindi-line-webrip-full-movie/',
  ];

  for (final ep in endpoints) {
    try {
      final res = await http.get(Uri.parse(ep), headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/150.0.0.0 Safari/537.36',
        'Cookie': 'xla=s4t',
      });
      print('Endpoint $ep -> status ${res.statusCode}, len: ${res.body.length}');
      if (res.statusCode == 200 && (ep.contains('wp-json') || ep.contains('ajax'))) {
        print('  Response preview: ${res.body.substring(0, res.body.length > 200 ? 200 : res.body.length)}');
      }
    } catch (e) {
      print('Error on $ep: $e');
    }
  }
}
