import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  print('--- Testing hubcdn and greenmountmotors ---');
  final urls = [
    'https://hubcdn.sbs/file/vUWRZcdsLKuc5nrHCKb5otJZB',
    'https://greenmountmotors.com/?id=dU5ySVJqckJ6c3BMZkJOVWZrQWI0SzNHSUJuOGg1emE3a2RKTWE0ZlJ1Z0p3dFhmTDQ3L3lSUUNNMVp3SFMwbUtLZWRTcENISTdpUFJaUGRpc0wvOEo2c2JyZ1NrZ1cya2lKd0pKeVRBU0k9',
  ];

  for (final u in urls) {
    try {
      final res = await http.get(Uri.parse(u), headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/150.0.0.0 Safari/537.36',
      });
      print('URL $u -> status ${res.statusCode}');
      final m = RegExp(r'href="(https?://[^"]*(?:hubcloud|drive|r2|mkv)[^"]*)"').firstMatch(res.body);
      if (m != null) {
        print('  Found target: ${m.group(1)}');
      }
    } catch (e) {
      print('Error: $e');
    }
  }
}
