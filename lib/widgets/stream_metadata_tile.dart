import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:private_cinema_mobile/theme/app_colors.dart';

class ParsedStreamMeta {
  final String? quality;
  final Color? qualityColor;
  final String? size;
  final List<String> languages;
  final String site;
  final bool isSeedr;
  final String raw;

  ParsedStreamMeta({
    this.quality,
    this.qualityColor,
    this.size,
    this.languages = const [],
    this.site = '',
    this.isSeedr = false,
    required this.raw,
  });
}

ParsedStreamMeta parseStreamMeta(String name, String url) {
  var raw = name;
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
    quality = qMatch.group(0)!.toUpperCase().replaceAll('UHD', '4K').replaceAll('HD', '720P').replaceAll('4K', '4K');
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

  // Languages
  const knownLangs = ['Hindi', 'English', 'Tamil', 'Telugu', 'Malayalam', 'Kannada', 'Bengali', 'Punjabi', 'Japanese', 'Korean', 'Spanish', 'French', 'German', 'Arabic', 'Turkish'];
  final languages = knownLangs.where((l) => raw.contains(RegExp(l, caseSensitive: false))).toList();

  final isSeedr = url.startsWith('magnet:');
  final isStalker = url.startsWith('stalker:') || raw.toLowerCase().startsWith('portal') || raw.toLowerCase().contains('stalker');

  // Site/source name: format Stalker VOD as "Portal Num - Full Database Movie Name"
  String site = '';
  if (isStalker) {
    if (RegExp(r'^(Portal|Stalker)\s*\d+', caseSensitive: false).hasMatch(raw)) {
      site = raw;
    } else {
      // Default to Portal 1 prefix if portal index isn't prefixed
      site = 'Portal 1 - $raw';
    }
  } else if (url.contains('.mkv') || url.contains('.mp4')) {
    final ext = url.contains('.mkv') ? 'MKV' : 'MP4';
    site = '$ext Stream - $raw';
  } else if (url.startsWith('http')) {
    site = raw;
  } else {
    final parts = raw.split(' - ');
    if (parts.length >= 2) {
      final lastPart = parts.last.trim();
      final hasQuality = RegExp(r'(2160p|1080p|720p|480p|360p|4k|UHD|HD)', caseSensitive: false).hasMatch(lastPart);
      final hasSize = RegExp(r'[\d.]+\s*(GB|MB|GIB|MIB)', caseSensitive: false).hasMatch(lastPart);
      final hasLang = knownLangs.any((l) => lastPart.contains(RegExp(l, caseSensitive: false)));
      if (hasQuality || hasSize || hasLang || lastPart.isEmpty) {
        if (parts.length >= 3) {
          site = parts.sublist(1, parts.length - 1).join(' - ');
        } else {
          site = parts.first.trim();
        }
      } else {
        site = lastPart;
      }
    } else {
      final lastPipe = raw.lastIndexOf(' | ');
      if (lastPipe > 0 && lastPipe < raw.length - 3) {
        site = raw.substring(lastPipe + 3).trim();
      } else {
        site = raw.trim();
      }
    }
  }

  if (site.isEmpty) site = raw;

  return ParsedStreamMeta(quality: quality, qualityColor: qualityColor, size: size, languages: languages, site: site, isSeedr: isSeedr, raw: raw);
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
                    color: isSeedr ? const Color(0xFF00E676).withValues(alpha: 0.12) : (isStalker ? AppColors.accentBright.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.05)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isSeedr ? Icons.cloud_download_rounded : (isStalker ? Icons.movie_filter_rounded : Icons.play_arrow_rounded),
                    color: isSeedr ? const Color(0xFF00E676) : (isStalker ? AppColors.accentBright : Colors.white54),
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
                      // Title: quality + site
                      Row(
                        children: [
                          if (meta.quality != null)
                            Container(
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
                          if (meta.site.isNotEmpty && meta.quality != null) const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              meta.site.isNotEmpty ? meta.site : name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.outfit(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // Metadata row: size + languages + badges
                      Row(
                        children: [
                          if (meta.size != null)
                            Padding(
                              padding: const EdgeInsets.only(right: 10),
                              child: Text(meta.size!, style: const TextStyle(color: Colors.white38, fontSize: 10)),
                            ),
                          if (meta.languages.isNotEmpty)
                            Expanded(
                              child: Text(
                                meta.languages.join(', '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white38, fontSize: 10),
                              ),
                            ),
                          if (isSeedr)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(color: const Color(0xFF00E676).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.cloud_download_rounded, size: 8, color: const Color(0xFF00E676)),
                                const SizedBox(width: 2),
                                Text('SEEDR', style: TextStyle(color: const Color(0xFF00E676), fontSize: 7, fontWeight: FontWeight.bold)),
                              ]),
                            ),
                          if (isStalker)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(color: AppColors.accentBright.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                              child: Text('VOD', style: TextStyle(color: AppColors.accentBright, fontSize: 7, fontWeight: FontWeight.bold)),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Colors.white12, size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
