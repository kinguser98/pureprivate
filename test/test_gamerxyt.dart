import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final gamerUrl = 'https://gamerxyt.com/hubcloud.php?host=hubcloud&id=b1b1g1noildibhs&token=UStadnF5V0FKb1pTc29oemJEU3VrQmNFZlhHVDhhR3hHU0ZpOHpRRzFLVT0=';
  print('--- Testing gamerxyt.com HubCloud destination ---');
  try {
    final res = await http.get(Uri.parse(gamerUrl), headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/150.0.0.0 Safari/537.36',
      'Referer': 'https://hubcloud.cx/',
    });
    print('Status: ${res.statusCode}');
    print('Body length: ${res.body.length}');
    final btnRegex = RegExp(r'<a[^>]+href="([^"]+)"[^>]*>(.*?)<\/a>', caseSensitive: false, dotAll: true);
    for (final m in btnRegex.allMatches(res.body)) {
      final href = m.group(1) ?? '';
      final txt = m.group(2)?.replaceAll(RegExp(r'<[^>]*>'), '').trim() ?? '';
      print('  Direct Stream / Download Button: $href [$txt]');
    }
  } catch (e) {
    print('Error: $e');
  }
}
