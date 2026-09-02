import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  print('--- Inspecting MoviesDrive JavaScript Search API ---');
  final mainPage = await http.get(Uri.parse('https://new3.moviesdrive.christmas/'), headers: {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/150.0.0.0 Safari/537.36',
  });
  print('Main page status: ${mainPage.statusCode}');
  // Find script tags
  final scriptRegex = RegExp(r'<script[^>]+src="([^"]+)"', caseSensitive: false);
  for (final m in scriptRegex.allMatches(mainPage.body)) {
    print('Script: ${m.group(1)}');
  }

  // Check search query endpoints
  final testEndpoints = [
    'https://new3.moviesdrive.christmas/wp-json/wp/v2/posts?search=Alpha',
    'https://new3.moviesdrive.christmas/api/search?q=Alpha',
    'https://new3.moviesdrive.christmas/search-recover.php?q=Alpha',
  ];
  for (final ep in testEndpoints) {
    try {
      final res = await http.get(Uri.parse(ep), headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/150.0.0.0 Safari/537.36',
      });
      print('Endpoint $ep -> status ${res.statusCode}, length: ${res.body.length}');
      if (res.statusCode == 200) {
        print('  Body preview: ${res.body.substring(0, res.body.length > 200 ? 200 : res.body.length)}');
      }
    } catch (e) {
      print('Endpoint $ep error: $e');
    }
  }
}
