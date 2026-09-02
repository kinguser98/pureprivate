import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

void main() async {
  print('--- Testing HDHub4u (search.pingora.fyi) for Kattalan ---');
  final uriKattalan = Uri.parse('https://search.pingora.fyi/collections/post/documents/search').replace(
    queryParameters: {'q': 'Kattalan', 'query_by': 'post_title', 'per_page': '10'},
  );
  try {
    final res = await http.get(uriKattalan, headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/150.0.0.0 Safari/537.36',
    });
    print('Kattalan status: ${res.statusCode}');
    print('Kattalan body: ${res.body}');
  } catch (e) {
    print('Kattalan error: $e');
  }

  print('\n--- Testing HDHub4u (search.pingora.fyi) for Alpha ---');
  final uriAlpha = Uri.parse('https://search.pingora.fyi/collections/post/documents/search').replace(
    queryParameters: {'q': 'Alpha', 'query_by': 'post_title', 'per_page': '10'},
  );
  try {
    final res = await http.get(uriAlpha, headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/150.0.0.0 Safari/537.36',
    });
    print('Alpha status: ${res.statusCode}');
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      final hits = data['hits'] as List;
      print('Found ${hits.length} hits for Alpha');
      for (final h in hits.take(2)) {
        final doc = h['document'];
        print('Post: ${doc['post_title']} -> ${doc['permalink']}');
        final postRes = await http.get(Uri.parse(doc['permalink']), headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/150.0.0.0 Safari/537.36',
          'Cookie': 'xla=s4t',
        });
        print('Post HTML length: ${postRes.body.length}');
        // Find links
        final hrefRegex = RegExp(r'<a[^>]+href="([^"]+)"[^>]*>(.*?)<\/a>', caseSensitive: false, dotAll: true);
        for (final m in hrefRegex.allMatches(postRes.body)) {
          final href = m.group(1) ?? '';
          final txt = m.group(2) ?? '';
          if (href.contains('hubcloud') || href.contains('pixeldrain') || href.contains('gdflix') || href.contains('drive')) {
            print('  Found Link: $href (text: $txt)');
          }
        }
      }
    }
  } catch (e) {
    print('Alpha error: $e');
  }

  print('\n--- Testing MoviesDrive for Kattalan ---');
  try {
    final mdRes = await http.get(Uri.parse('https://new3.moviesdrive.christmas/?s=Kattalan'), headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/150.0.0.0 Safari/537.36',
    });
    print('MoviesDrive Kattalan status: ${mdRes.statusCode}, body length: ${mdRes.body.length}');
    if (mdRes.body.contains('Kattalan') || mdRes.body.contains('kattalan')) {
      print('MoviesDrive contains Kattalan!');
    } else {
      print('MoviesDrive does NOT contain Kattalan in response');
    }
  } catch (e) {
    print('MoviesDrive error: $e');
  }
}
