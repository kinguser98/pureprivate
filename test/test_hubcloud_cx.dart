import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final hubcloudUrl = 'https://hubcloud.cx/drive/b1b1g1noildibhs';
  print('--- Testing HubCloud: $hubcloudUrl ---');
  try {
    final res = await http.get(Uri.parse(hubcloudUrl), headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/150.0.0.0 Safari/537.36',
      'Referer': 'https://hubdrive.tips/',
    });
    print('Status: ${res.statusCode}');
    print('Body: ${res.body}');
  } catch (e) {
    print('Error: $e');
  }
}
