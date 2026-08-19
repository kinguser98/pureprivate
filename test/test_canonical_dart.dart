import 'dart:convert';
import 'package:crypto/crypto.dart';

const String _keyB64Default = 'NzZpUmwwN3MweFNOOWpxbUVXQXQ3OUVCSlp1bElRSXNWNjRGWnIyTw==';

String _hmacMd5B64(List<int> key, String data) =>
    base64.encode(Hmac(md5, key).convert(utf8.encode(data)).bytes);

List<int> get _secretKey {
  final s = utf8.decode(base64.decode(_keyB64Default));
  return base64.decode(s);
}

String _buildSig(String method, String accept, String ct, String url, String? body, int ts) {
  final uri = Uri.parse(url);
  final keys = uri.queryParametersAll.keys.toList()..sort();
  final parts = <String>[];
  for (final k in keys) {
    final vals = List<String>.from(uri.queryParametersAll[k]!)..sort();
    for (final v in vals) parts.add('$k=$v');
  }
  final q = parts.join('&');
  final cu = q.isNotEmpty ? '${uri.path}?$q' : uri.path;
  var bh = '';
  var bl = '';
  if (body != null && body.isNotEmpty) {
    final bb = utf8.encode(body);
    bl = bb.length.toString();
    bh = md5.convert(bb).toString();
  }
  final canonical =
      '${method.toUpperCase()}\n$accept\n$ct\n$bl\n$ts\n$bh\n$cu';
  print('=== DART DUMP ===');
  print('Canonical:');
  print(jsonEncode(canonical));
  print('Sig: ${_hmacMd5B64(_secretKey, canonical)}');
  return '';
}

void main() {
  final ts = 1785418013000;
  final url = "https://api3.aoneroom.com/wefeed-mobile-bff/subject-api/search/v2";
  final method = "POST";
  final accept = "application/json";
  final ct = "application/json; charset=utf-8";
  final body = '{"page":1,"perPage":20,"keyword":"KGF"}';
  _buildSig(method, accept, ct, url, body, ts);
}
