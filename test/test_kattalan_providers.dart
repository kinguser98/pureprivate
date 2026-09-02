import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  print('--- Testing Eclipsia providers for Kattalan ---');
  final sources = {
    'VegaMovies': 'https://vegamovies.im/?s=Kattalan',
    'BollyFlix': 'https://bollyflix.christmas/?s=Kattalan',
    'MkvCinemas': 'https://mkvcinemas.cx/?s=Kattalan',
    'TopMovies': 'https://topmovies.bar/?s=Kattalan',
    'Movies4u': 'https://movies4u.cloud/?s=Kattalan',
    'HDHub4u (search)': 'https://new5.hdhub4u.cl/?s=Kathalan',
    'MoviesDrive (Kathalan)': 'https://new3.moviesdrive.christmas/?s=Kathalan',
  };

  for (final entry in sources.entries) {
    try {
      final res = await http.get(Uri.parse(entry.value), headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/150.0.0.0 Safari/537.36',
      }).timeout(const Duration(seconds: 8));
      print('${entry.key}: status ${res.statusCode}, body length ${res.body.length}');
      if (res.body.toLowerCase().contains('kathalan') || res.body.toLowerCase().contains('kattalan')) {
        print('  ==> FOUND ON ${entry.key}!');
      }
    } catch (e) {
      print('${entry.key} error: $e');
    }
  }
}
