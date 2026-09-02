import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  print('--- Testing MoviesDrive wp-json search for kattalan ---');
  final res = await http.get(Uri.parse('https://new3.moviesdrive.christmas/wp-json/wp/v2/posts?search=kattalan'), headers: {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/150.0.0.0 Safari/537.36',
  });
  print('MoviesDrive Kattalan status: ${res.statusCode}');
  if (res.statusCode == 200) {
    final data = jsonDecode(res.body) as List;
    print('Found ${data.length} posts for kattalan on MoviesDrive');
    for (final p in data) {
      print('  Post: ${p['title']?['rendered']} -> ${p['link']}');
    }
  }
}
