import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:private_cinema_mobile/theme/app_colors.dart';

int parseSizeToMb(String? sizeStr) {
  if (sizeStr == null || sizeStr.isEmpty) return 0;
  final cleaned = sizeStr.trim().toUpperCase();
  final RegExp regex = RegExp(r'^([\d.]+)\s*(GB|MB|GIB|MIB)$');
  final match = regex.firstMatch(cleaned);
  if (match == null) return 0;
  final num = double.tryParse(match.group(1)!) ?? 0;
  final unit = match.group(2)!;
  if (unit == 'GB' || unit == 'GIB') return (num * 1024).round();
  if (unit == 'MB' || unit == 'MIB') return num.round();
  return 0;
}

Future<int> getMaxSizeMb() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getInt('max_source_size_mb') ?? 0;
}

class HlsPreflightResult {
  final String url;
  final String? selectedLanguage;
  final String? selectedQuality;

  HlsPreflightResult({
    required this.url,
    this.selectedLanguage,
    this.selectedQuality,
  });
}

Future<HlsPreflightResult?> runHlsPreflight({
  required BuildContext context,
  required String url,
  String movieTitle = '',
  Map<String, String>? headers,
}) async {
  final uri = Uri.parse(url);
  final baseHeaders = <String, String>{};
  if (headers != null) baseHeaders.addAll(headers);

  if (uri.queryParameters.containsKey('headers')) {
    try {
      final jsonHeaders = jsonDecode(uri.queryParameters['headers']!);
      if (jsonHeaders is Map) {
        jsonHeaders.forEach((k, v) {
          baseHeaders[k.toString()] = v.toString();
        });
      }
    } catch (_) {}
  }

  String body = '';
  bool isHls = false;

  try {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 8);
    final req = await client.getUrl(uri);
    baseHeaders.forEach((k, v) => req.headers.set(k, v));
    final res = await req.close();

    if (res.statusCode == 200) {
      final firstBytes = <int>[];
      await for (final chunk in res) {
        firstBytes.addAll(chunk);
        if (firstBytes.length >= 512) break;
      }
      client.close(force: true);

      final checkStr = utf8.decode(firstBytes, allowMalformed: true);
      if (checkStr.startsWith('#EXTM3U')) {
        isHls = true;
        final playlistClient = HttpClient();
        playlistClient.connectionTimeout = const Duration(seconds: 8);
        final pReq = await playlistClient.getUrl(uri);
        baseHeaders.forEach((k, v) => pReq.headers.set(k, v));
        final pRes = await pReq.close();
        if (pRes.statusCode == 200) {
          body = await pRes.transform(utf8.decoder).join();
        }
        playlistClient.close();
      }
    } else {
      client.close(force: true);
    }
  } catch (_) {
    return null;
  }

  if (!isHls || body.isEmpty) return HlsPreflightResult(url: url);

  final audioLines = body
      .split('\n')
      .where((line) => line.startsWith('#EXT-X-MEDIA:TYPE=AUDIO'))
      .toList();
  final List<String> audioLanguages = [];
  for (final line in audioLines) {
    final nameMatch = RegExp(r'NAME="([^"]+)"').firstMatch(line);
    if (nameMatch != null) {
      final langName = nameMatch.group(1)!;
      if (!audioLanguages.contains(langName)) audioLanguages.add(langName);
    }
  }

  final lines = body.split('\n');
  final List<String> videoQualities = [];
  for (final line in lines) {
    if (line.startsWith('#EXT-X-STREAM-INF')) {
      final resolutionMatch = RegExp(r'RESOLUTION=(\d+x\d+)').firstMatch(line);
      if (resolutionMatch != null) {
        final height = resolutionMatch.group(1)!.split('x')[1];
        final q = '${height}p';
        if (!videoQualities.contains(q)) videoQualities.add(q);
      } else {
        final bandwidthMatch = RegExp(r'BANDWIDTH=(\d+)').firstMatch(line);
        if (bandwidthMatch != null) {
          final bw = int.tryParse(bandwidthMatch.group(1)!) ?? 0;
          String q = '360p';
          if (bw > 3000000) q = '1080p';
          else if (bw > 1500000) q = '720p';
          else if (bw > 800000) q = '480p';
          if (!videoQualities.contains(q)) videoQualities.add(q);
        }
      }
    }
  }

  String? selectedLanguage;
  if (audioLanguages.length > 1 && context.mounted) {
    selectedLanguage = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Select Audio Language',
          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: audioLanguages.length,
            itemBuilder: (_, i) => ListTile(
              title: Text(audioLanguages[i], style: const TextStyle(color: Colors.white)),
              leading: const Icon(Icons.audiotrack_rounded, color: Colors.tealAccent),
              onTap: () => Navigator.of(ctx).pop(audioLanguages[i]),
            ),
          ),
        ),
      ),
    );
  }

  String? selectedQuality;
  if (videoQualities.isNotEmpty && context.mounted) {
    videoQualities.sort((a, b) {
      final va = int.tryParse(a.replaceAll('p', '')) ?? 0;
      final vb = int.tryParse(b.replaceAll('p', '')) ?? 0;
      return vb.compareTo(va);
    });
    selectedQuality = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Select Video Quality',
          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: videoQualities.length + 1,
            itemBuilder: (_, i) {
              if (i == 0) return ListTile(
                title: const Text('Auto / Best Quality', style: TextStyle(color: Colors.white)),
                leading: const Icon(Icons.settings_backup_restore_rounded, color: Colors.tealAccent),
                onTap: () => Navigator.of(ctx).pop('Auto'),
              );
              final q = videoQualities[i - 1];
              return ListTile(
                title: Text(q, style: const TextStyle(color: Colors.white)),
                leading: const Icon(Icons.video_settings_rounded, color: Colors.tealAccent),
                onTap: () => Navigator.of(ctx).pop(q),
              );
            },
          ),
        ),
      ),
    );
  }

  var finalUrl = url;
  final queryParams = <String, String>{};
  if (selectedLanguage != null && selectedLanguage.isNotEmpty) {
    queryParams['selected_audio'] = selectedLanguage;
  }
  if (selectedQuality != null && selectedQuality.isNotEmpty && selectedQuality != 'Auto') {
    queryParams['selected_quality'] = selectedQuality;
  }
  if (queryParams.isNotEmpty) {
    final sourceUri = Uri.parse(url);
    finalUrl = sourceUri
        .replace(queryParameters: {...sourceUri.queryParameters, ...queryParams})
        .toString();
  }

  return HlsPreflightResult(
    url: finalUrl,
    selectedLanguage: selectedLanguage,
    selectedQuality: selectedQuality,
  );
}
