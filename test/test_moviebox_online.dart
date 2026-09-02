import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';

void main() async {
  const String keyB64 = 'NzZpUmwwN3MweFNOOWpxbUVXQXQ3OUVCSlp1bElRSXNWNjRGWnIyTw==';
  final secretKey = base64.decode(utf8.decode(base64.decode(keyB64)));

  String md5Str(String s) => md5.convert(utf8.encode(s)).toString();
  String hmacMd5B64(List<int> key, String data) =>
      base64.encode(Hmac(md5, key).convert(utf8.encode(data)).bytes);

  String buildSig(String method, String accept, String ct, String url, String? body, int ts) {
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
    final canonical = '${method.toUpperCase()}\n$accept\n$ct\n$bl\n$ts\n$bh\n$cu';
    return '$ts|2|${hmacMd5B64(secretKey, canonical)}';
  }

  final client = HttpClient();
  
  // 1. Get bearer token
  const rankUrl = 'https://api3.aoneroom.com/wefeed-mobile-bff/tab/ranking-list?tabId=0&categoryType=4516404531735022304&page=1&perPage=1';
  int ts = DateTime.now().millisecondsSinceEpoch;
  var sig = buildSig('GET', 'application/json', 'application/json', rankUrl, null, ts);
  var req = await client.getUrl(Uri.parse(rankUrl));
  req.headers.set('accept', 'application/json');
  req.headers.set('content-type', 'application/json');
  req.headers.set('x-tr-signature', sig);
  req.headers.set('x-client-token', '$ts,${md5Str(ts.toString().split('').reversed.join())}');
  req.headers.set('x-client-info', jsonEncode({
    'package_name': 'com.community.mbox.in',
    'version_name': '3.0.03.0529.03',
    'version_code': 50020042,
    'os': 'android',
    'os_version': '16',
    'device_id': '0123456789abcdef0123456789abcdef',
    'brand': 'samsung',
    'model': 'SM-S918B',
  }));
  var res = await req.close();
  var xUser = res.headers.value('x-user');
  print('xUser: $xUser');
  var token = jsonDecode(xUser ?? '{}')['token'];
  print('Token: $token');

  // 2. Query Avatar play-info
  // Search avatar
  const searchUrl = 'https://api3.aoneroom.com/wefeed-mobile-bff/subject-api/search/v2';
  final searchBody = jsonEncode({'page': 1, 'perPage': 5, 'keyword': 'Inception'});
  ts = DateTime.now().millisecondsSinceEpoch;
  sig = buildSig('POST', 'application/json', 'application/json; charset=utf-8', searchUrl, searchBody, ts);
  req = await client.postUrl(Uri.parse(searchUrl));
  req.headers.set('accept', 'application/json');
  req.headers.set('content-type', 'application/json; charset=utf-8');
  req.headers.set('authorization', 'Bearer $token');
  req.headers.set('x-tr-signature', sig);
  req.headers.set('x-client-token', '$ts,${md5Str(ts.toString().split('').reversed.join())}');
  req.headers.set('x-client-info', jsonEncode({
    'package_name': 'com.community.mbox.in',
    'version_name': '3.0.03.0529.03',
    'version_code': 50020042,
    'os': 'android',
    'os_version': '16',
    'device_id': '0123456789abcdef0123456789abcdef',
    'brand': 'samsung',
    'model': 'SM-S918B',
  }));
  req.add(utf8.encode(searchBody));
  res = await req.close();
  var body = await res.transform(utf8.decoder).join();
  print('Search body: $body');

  final searchData = jsonDecode(body);
  final subject = (searchData['data']['results'] as List)[0]['subjects'][0];
  final subjectId = subject['subjectId'];
  print('SubjectId: $subjectId (${subject['title']})');

  // 3. Get play info
  final playUrl = 'https://api3.aoneroom.com/wefeed-mobile-bff/subject-api/play-info?subjectId=$subjectId&se=0&ep=0';
  ts = DateTime.now().millisecondsSinceEpoch;
  sig = buildSig('GET', 'application/json', 'application/json', playUrl, null, ts);
  req = await client.getUrl(Uri.parse(playUrl));
  req.headers.set('accept', 'application/json');
  req.headers.set('content-type', 'application/json');
  req.headers.set('authorization', 'Bearer $token');
  req.headers.set('x-tr-signature', sig);
  req.headers.set('x-client-token', '$ts,${md5Str(ts.toString().split('').reversed.join())}');
  req.headers.set('x-client-info', jsonEncode({
    'package_name': 'com.community.mbox.in',
    'version_name': '3.0.03.0529.03',
    'version_code': 50020042,
    'os': 'android',
    'os_version': '16',
    'device_id': '0123456789abcdef0123456789abcdef',
    'brand': 'samsung',
    'model': 'SM-S918B',
  }));
  res = await req.close();
  body = await res.transform(utf8.decoder).join();
  print('Play-info response: $body');

  client.close();
}
