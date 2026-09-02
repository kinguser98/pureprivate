import 'dart:convert';

Map<String, dynamic> parseCleanStreamTitle(String name, String url) {
  var clean = name;

  // Remove prefixes
  clean = clean.replaceAll(RegExp(r'^(MKV|MP4)\s*Stream\s*[-•:]\s*', caseSensitive: false), '');
  clean = clean.replaceAll(RegExp(r'^(MoviesDrive|HDHub4u|MKVBase|Movy)\s*[-•:]\s*', caseSensitive: false), '');
  clean = clean.replaceAll(RegExp(r'^(MoviesDrive|HDHub4u|MKVBase|Movy)\s*[-•:]\s*', caseSensitive: false), '');
  clean = clean.replaceAll(RegExp(r'[-_.]?[tT][gG]\b'), '');
  clean = clean.replaceAll(RegExp(r'\s+'), ' ').trim();

  // Extract language & audio details from URL or name
  final decodedUrl = Uri.decodeFull(url);
  final fullText = '$clean $decodedUrl';

  final langList = <String>[];
  if (fullText.contains(RegExp(r'Malayalam', caseSensitive: false))) langList.add('Malayalam');
  if (fullText.contains(RegExp(r'Hindi', caseSensitive: false))) langList.add('Hindi');
  if (fullText.contains(RegExp(r'Tamil', caseSensitive: false))) langList.add('Tamil');
  if (fullText.contains(RegExp(r'Telugu', caseSensitive: false))) langList.add('Telugu');
  if (fullText.contains(RegExp(r'Kannada', caseSensitive: false))) langList.add('Kannada');
  if (fullText.contains(RegExp(r'English', caseSensitive: false))) langList.add('English');
  if (fullText.contains(RegExp(r'Bengali', caseSensitive: false))) langList.add('Bengali');
  if (fullText.contains(RegExp(r'Punjabi', caseSensitive: false))) langList.add('Punjabi');

  String audioTag = '';
  if (fullText.contains(RegExp(r'DDP\s*5\.1|DDPA5\.1|DD5\.1|5\.1', caseSensitive: false))) {
    audioTag = '5.1 Surround';
  }
  if (fullText.contains(RegExp(r'Atmos|Dolby Atmos', caseSensitive: false))) {
    audioTag = audioTag.isEmpty ? 'Dolby Atmos' : '$audioTag • Atmos';
  }
  if (fullText.contains(RegExp(r'LiNE', caseSensitive: false))) {
    audioTag = audioTag.isEmpty ? 'LiNE Audio' : '$audioTag (LiNE)';
  }

  return {
    'cleanTitle': clean,
    'languages': langList,
    'audioTag': audioTag,
  };
}

void main() {
  final testSamples = [
    {
      'name': 'MKV Stream - MoviesDrive • Cloudflare R2 Direct • 1080p Full HD',
      'url': 'https://3a771b2296d1c87878ede7f6b1346c1e.r2.cloudflarestorage.com/hub/c475864658bfd1b92c01a7ea008d41c9?...Kattalan.2026.1080p.AMZN.WEB-DL.Hindi.LiNE-Multi.DDP5.1.ESub.x264-MoviesDrives.mov.mkv',
    },
    {
      'name': 'MKV Stream - HDHub4u • FSLv2 CDN • 720p HD',
      'url': 'https://cdn.lenin.buzz/Alpha.2026.720p.HEVC.Hindi.DS4K.WEB-DL.ESub.x265-HDHub4u.Ms.mkv?token=12bc89ddc971b847f8eb1cf3da07be6d',
    },
    {
      'name': 'MKV Stream - HDHub4u • Cloudflare R2 Direct • 4K (2160p)',
      'url': 'https://da194e3e41011e58ea95b0914c6212d3.r2.cloudflarestorage.com/hub/74ab33afb47267726851a51bd678a30d?...Kattalan.2026.4K-2160p.SDR.MMAX.WEB-DL.Hindi.LiNE-Multi.DDP5.1.HEVC.x265-HDHub4u.Ms.mkv',
    },
  ];

  for (final s in testSamples) {
    final res = parseCleanStreamTitle(s['name']!, s['url']!);
    print('Original: ${s['name']}');
    print('Clean: ${res['cleanTitle']}');
    print('Languages: ${res['languages']}');
    print('Audio Tag: ${res['audioTag']}\n');
  }
}
