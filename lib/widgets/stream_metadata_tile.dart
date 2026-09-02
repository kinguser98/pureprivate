import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:private_cinema_mobile/theme/app_colors.dart';

class ParsedStreamMeta {
  final String? quality;
  final Color? qualityColor;
  final String? size;
  final List<String> languages;
  final String? audioTag;
  final String site;
  final bool isSeedr;
  final String raw;

  ParsedStreamMeta({
    this.quality,
    this.qualityColor,
    this.size,
    this.languages = const [],
    this.audioTag,
    this.site = '',
    this.isSeedr = false,
    required this.raw,
  });
}

ParsedStreamMeta parseStreamMeta(String name, String url) {
  var raw = name;

  // Clean prefixes like "MKV Stream - ", "MP4 Stream - ", "MoviesDrive • ", "HDHub4u • ", "MKVBase • "
  raw = raw.replaceAll(RegExp(r'^(MKV|MP4)\s*Stream\s*[-•:]\s*', caseSensitive: false), '');
  raw = raw.replaceAll(RegExp(r'^(MoviesDrive|HDHub4u|MKVBase|Movy)\s*[-•:]\s*', caseSensitive: false), '');
  raw = raw.replaceAll(RegExp(r'^(MoviesDrive|HDHub4u|MKVBase|Movy)\s*[-•:]\s*', caseSensitive: false), '');

  // Clean up TG tag suffixes/delimiters (e.g. -TG, _TG, [TG])
  raw = raw.replaceAll(RegExp(r'[-_.]?[tT][gG]\b'), '');
  raw = raw.replaceAll(RegExp(r'\[[tT][gG]\]'), '');
  raw = raw.replaceAll(RegExp(r'\b[tT][gG]\b'), '');
  raw = raw.replaceAll(RegExp(r'\s+'), ' ').trim();

  // Quality
  String? quality;
  Color? qualityColor;
  final qMatch = RegExp(r'(2160p|1080p|720p|480p|360p|4k|UHD|HD)', caseSensitive: false).firstMatch(raw);
  if (qMatch != null) {
    quality = qMatch.group(0)!.toUpperCase().replaceAll('UHD', '4K').replaceAll('HD', '720P');
    final ql = quality.toLowerCase();
    if (ql.contains('2160') || ql.contains('4k')) {
      qualityColor = const Color(0xFF8B5CF6);
    } else if (ql.contains('1080')) {
      qualityColor = const Color(0xFF3B82F6);
    } else if (ql.contains('720')) {
      qualityColor = const Color(0xFF10B981);
    } else if (quality.length < 5) {
      quality = null;
    }
  }

  // Size
  String? size;
  final sMatch = RegExp(r'([\d.]+)\s*(GB|MB|GIB|MIB)', caseSensitive: false).firstMatch(raw);
  if (sMatch != null) {
    final num = sMatch.group(1);
    final unit = sMatch.group(2)!.toUpperCase().replaceAll('GIB', 'GB').replaceAll('MIB', 'MB');
    size = '$num $unit';
  }

  // Languages & Audio: check both raw name and decoded URL
  String decodedUrl = '';
  try {
    decodedUrl = Uri.decodeFull(url);
  } catch (_) {
    decodedUrl = url;
  }
  final combinedText = '$raw $decodedUrl';

  const knownLangs = [
    'Hindi',
    'Malayalam',
    'Tamil',
    'Telugu',
    'Kannada',
    'English',
    'Bengali',
    'Punjabi',
    'Japanese',
    'Korean',
    'Spanish',
    'French',
    'German',
  ];
  final languages = <String>[];
  for (final l in knownLangs) {
    if (combinedText.contains(RegExp(r'\b' + l + r'\b', caseSensitive: false))) {
      languages.add(l);
    }
  }
  if (languages.isEmpty && (combinedText.contains(RegExp(r'Multi[-\s]?Audio', caseSensitive: false)) || combinedText.contains(RegExp(r'Dual[-\s]?Audio', caseSensitive: false)))) {
    languages.add('Multi-Audio');
  }

  // Audio surround tags
  String? audioTag;
  if (combinedText.contains(RegExp(r'Atmos|Dolby Atmos', caseSensitive: false))) {
    audioTag = 'Dolby Atmos';
  } else if (combinedText.contains(RegExp(r'DDP\s*5\.1|DDPA5\.1|DD5\.1|5\.1', caseSensitive: false))) {
    audioTag = '5.1 Surround';
  }

  final isSeedr = url.startsWith('magnet:');
  final isStalker = url.startsWith('stalker:') || raw.toLowerCase().startsWith('portal') || raw.toLowerCase().contains('stalker');

  // Site/source name: format cleanly
  String site = raw;
  if (isStalker) {
    if (RegExp(r'^(Portal|Stalker)\s*\d+', caseSensitive: false).hasMatch(raw)) {
      site = raw;
    } else {
      site = 'Portal 1 - $raw';
    }
  }

  return ParsedStreamMeta(
    quality: quality,
    qualityColor: qualityColor,
    size: size,
    languages: languages,
    audioTag: audioTag,
    site: site,
    isSeedr: isSeedr,
    raw: raw,
  );
}

class StreamMetadataTile extends StatelessWidget {
  final String name;
  final String url;
  final Map<String, String>? headers;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool isSelected;

  const StreamMetadataTile({
    super.key,
    required this.name,
    required this.url,
    this.headers,
    this.onTap,
    this.onLongPress,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final meta = parseStreamMeta(name, url);
    final isStalker = url.startsWith('stalker:');
    final isSeedr = url.startsWith('magnet:');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isSelected ? AppColors.accent.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                // Icon
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isSeedr
                        ? const Color(0xFF00E676).withValues(alpha: 0.12)
                        : (isStalker
                            ? AppColors.accentBright.withValues(alpha: 0.12)
                            : Colors.white.withValues(alpha: 0.05)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isSeedr
                        ? Icons.cloud_download_rounded
                        : (isStalker ? Icons.movie_filter_rounded : Icons.play_arrow_rounded),
                    color: isSeedr
                        ? const Color(0xFF00E676)
                        : (isStalker ? AppColors.accentBright : Colors.white54),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                // Title + metadata
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Scrollable Title Row to view full text in mobile
                      Row(
                        children: [
                          if (meta.quality != null)
                            Container(
                              margin: const EdgeInsets.only(right: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: (meta.qualityColor ?? AppColors.accentBright).withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                meta.quality!,
                                style: TextStyle(
                                  color: meta.qualityColor ?? AppColors.accentBright,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              child: Text(
                                meta.site.isNotEmpty ? meta.site : name,
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      // Metadata row: size + languages pills + surround badge
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: Row(
                          children: [
                            if (meta.size != null)
                              Container(
                                margin: const EdgeInsets.only(right: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  meta.size!,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            for (final lang in meta.languages)
                              Container(
                                margin: const EdgeInsets.only(right: 5),
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  lang,
                                  style: const TextStyle(
                                    color: Color(0xFFFBBF24),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            if (meta.audioTag != null)
                              Container(
                                margin: const EdgeInsets.only(right: 5),
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF06B6D4).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  meta.audioTag!,
                                  style: const TextStyle(
                                    color: Color(0xFF22D3EE),
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            if (isSeedr)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00E676).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.cloud_download_rounded, size: 8, color: Color(0xFF00E676)),
                                    const SizedBox(width: 2),
                                    const Text('SEEDR', style: TextStyle(color: Color(0xFF00E676), fontSize: 7, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            if (isStalker)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: AppColors.accentBright.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text('VOD', style: TextStyle(color: AppColors.accentBright, fontSize: 7, fontWeight: FontWeight.bold)),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right_rounded, color: Colors.white12, size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
