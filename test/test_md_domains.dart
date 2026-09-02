import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final domains = [
    'https://moviesdrive.art',
    'https://moviesdrive.fun',
    'https://new3.moviesdrive.christmas',
    'https://moviesdrive.cloud',
  ];

  for (final domain in domains) {
    try {
      final res = await http.get(Uri.parse('$domain/?s=Alpha'), headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/150.0.0.0 Safari/537.36',
      }).timeout(const Duration(seconds: 5));
      print('MD $domain status: ${res.statusCode}, len: ${res.body.length}');
      if (res.body.contains('Alpha') || res.body.contains('alpha')) {
        print('  Found Alpha on $domain!');
      }
    } catch (e) {
      print('MD $domain error: $e');
    }
  }
}
