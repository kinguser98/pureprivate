import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final mkvUrl = 'https://cdn.lenin.buzz/Alpha.2026.720p.HEVC.Hindi.DS4K.WEB-DL.ESub.x265-HDHub4u.Ms.mkv?token=12bc89ddc971b847f8eb1cf3da07be6d';
  final pxUrl = 'https://pixeldrain.com/api/file/negn6f';

  print('--- Testing HEAD request for MKV Stream ---');
  try {
    final res = await http.head(Uri.parse(mkvUrl), headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/150.0.0.0 Safari/537.36',
    });
    print('MKV Status: ${res.statusCode}');
    print('MKV Content-Type: ${res.headers['content-type']}');
    print('MKV Content-Length: ${res.headers['content-length']}');
    print('MKV Accept-Ranges: ${res.headers['accept-ranges']}');
  } catch (e) {
    print('MKV HEAD error: $e');
  }

  print('\n--- Testing HEAD request for PixelDrain Stream ---');
  try {
    final res = await http.head(Uri.parse(pxUrl), headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/150.0.0.0 Safari/537.36',
    });
    print('PixelDrain Status: ${res.statusCode}');
    print('PixelDrain Content-Type: ${res.headers['content-type']}');
    print('PixelDrain Content-Length: ${res.headers['content-length']}');
    print('PixelDrain Accept-Ranges: ${res.headers['accept-ranges']}');
  } catch (e) {
    print('PixelDrain HEAD error: $e');
  }
}
