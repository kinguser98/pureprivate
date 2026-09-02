import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  print('--- Testing Kattalan search on HDHub4u & MoviesDrive ---');
  final titles = ['Kattalan', 'kattalan', 'Katlan', 'Pushpa', 'Devara', 'GOAT', 'Amaran', 'Lokah', 'Leo'];
  
  for (final t in titles) {
    // MoviesDrive
    try {
      final mdRes = await http.get(Uri.parse('https://new3.moviesdrive.christmas/?s=$t'), headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/150.0.0.0 Safari/537.36',
      });
      final hasMd = mdRes.body.toLowerCase().contains(t.toLowerCase());
      print('MoviesDrive search "$t" -> $hasMd (length: ${mdRes.body.length})');
    } catch (e) {
      print('MoviesDrive error for "$t": $e');
    }

    // HDHub4u
    try {
      final hdRes = await http.get(Uri.parse('https://new5.hdhub4u.cl/?s=$t'), headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/150.0.0.0 Safari/537.36',
        'Cookie': 'xla=s4t',
      });
      final hasHd = hdRes.body.toLowerCase().contains(t.toLowerCase());
      print('HDHub4u search "$t" -> $hasHd (length: ${hdRes.body.length})');
    } catch (e) {
      print('HDHub4u error for "$t": $e');
    }
  }
}
