import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';

class SpecialBadge {
  final String label;
  final Color bg;
  final Color fg;
  final IconData? icon;

  const SpecialBadge({
    required this.label,
    required this.bg,
    required this.fg,
    this.icon,
  });
}

class ParsedStreamMeta {
  final String? quality;
  final Color? qualityColor;
  final int qualityRank; // 4K=4, 1080p=3, 720p=2, 480p=1, other=0
  final String? size;
  final double sizeInMb;
  final List<String> languages;
  final List<SpecialBadge> specialBadges;
  final String cleanTitle;
  final String site;
  final bool isSeedr;
  final bool isStalker;
  final String raw;

  ParsedStreamMeta({
    this.quality,
    this.qualityColor,
    this.qualityRank = 0,
    this.size,
    this.sizeInMb = 0.0,
    this.languages = const [],
    this.specialBadges = const [],
    required this.cleanTitle,
    this.site = '',
    this.isSeedr = false,
    this.isStalker = false,
    required this.raw,
  });
}

ParsedStreamMeta parseStreamMeta(String name, String url, {String? explicitQuality, String? explicitSize, List<String>? explicitLanguages}) {
  var raw = name;

  // Clean prefixes like "MoviesDrive • ", "Cinejoy.to • ", "HDHub4u • ", "Vegamovies • ", "Movy.bz • ", etc.
  raw = raw.replaceAll(RegExp(r'^(MKV|MP4)\s*Stream\s*[-•:]\s*', caseSensitive: false), '');
  raw = raw.replaceAll(RegExp(r'^(MoviesDrive|HDHub4u|Movy\.bz|Movy|Cinejoy(\.to)?|Vegamovies(\.futbol|\.se|\.catering)?|StreamPlay|MovieBox|FilmU|NetMirror)\s*[-•:]\s*', caseSensitive: false), '');
  raw = raw.replaceAll(RegExp(r'^(MoviesDrive|HDHub4u|Movy|Cinejoy|Vegamovies)\s+', caseSensitive: false), '');

  // Clean up TG tag suffixes/delimiters (e.g. -TG, _TG, [TG])
  raw = raw.replaceAll(RegExp(r'[-_.]?[tT][gG]\b'), '');
  raw = raw.replaceAll(RegExp(r'\[[tT][gG]\]'), '');
  raw = raw.replaceAll(RegExp(r'\b[tT][gG]\b'), '');
  raw = raw.replaceAll(RegExp(r'\s+'), ' ').trim();

  // Decode filename for metadata extraction without matching on URL hash tokens or query params
  String filename = '';
  try {
    final uri = Uri.parse(url);
    filename = Uri.decodeFull(uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '');
  } catch (_) {
    filename = '';
  }

  // Only check raw title, explicit quality/size, and clean filename
  final searchScope = '$raw $filename ${explicitQuality ?? ''} ${explicitSize ?? ''}'.toLowerCase();

  // 1. Quality & Rank (Strict token matching - avoid matching hash substrings in URLs)
  String? quality;
  Color? qualityColor;
  int qualityRank = 0;

  final has4k = RegExp(r'\b(2160p|4k|uhd)\b', caseSensitive: false).hasMatch(searchScope);
  final has1080p = RegExp(r'\b(1080p|fhd|1080)\b', caseSensitive: false).hasMatch(searchScope) || searchScope.contains('full hd');
  final has720p = RegExp(r'\b(720p|720)\b', caseSensitive: false).hasMatch(searchScope) || RegExp(r'\bhd\b', caseSensitive: false).hasMatch(searchScope);
  final has480p = RegExp(r'\b(480p|480)\b', caseSensitive: false).hasMatch(searchScope) || RegExp(r'\bsd\b', caseSensitive: false).hasMatch(searchScope);
  final has360p = RegExp(r'\b(360p|240p)\b', caseSensitive: false).hasMatch(searchScope);

  if (has4k && !has1080p && !has720p && !has480p) {
    quality = '4K (2160p)';
    qualityColor = const Color(0xFFA855F7); // Purple / Violet
    qualityRank = 4;
  } else if (has1080p && !has720p && !has480p) {
    quality = '1080p Full HD';
    qualityColor = const Color(0xFF3B82F6); // Blue
    qualityRank = 3;
  } else if (has720p && !has480p) {
    quality = '720p HD';
    qualityColor = const Color(0xFF10B981); // Emerald Green
    qualityRank = 2;
  } else if (has480p) {
    quality = '480p SD';
    qualityColor = const Color(0xFFF59E0B); // Amber
    qualityRank = 1;
  } else if (has360p) {
    quality = '360p';
    qualityColor = Colors.grey;
    qualityRank = 0;
  } else if (explicitQuality != null && explicitQuality.isNotEmpty) {
    quality = explicitQuality;
    qualityColor = AppColors.accentBright;
    if (explicitQuality.toLowerCase().contains('4k') || explicitQuality.contains('2160')) {
      qualityRank = 4;
    } else if (explicitQuality.toLowerCase().contains('1080')) {
      qualityRank = 3;
    } else if (explicitQuality.toLowerCase().contains('720')) {
      qualityRank = 2;
    } else if (explicitQuality.toLowerCase().contains('480')) {
      qualityRank = 1;
    }
  }

  // 2. Size
  String? size = explicitSize;
  double sizeInMb = 0.0;
  if (size == null || size.isEmpty) {
    final sMatch = RegExp(r'\b([\d.]+)\s*(GB|MB|GIB|MIB)\b', caseSensitive: false).firstMatch('$raw $filename');
    if (sMatch != null) {
      final numStr = sMatch.group(1)!;
      final unit = sMatch.group(2)!.toUpperCase().replaceAll('GIB', 'GB').replaceAll('MIB', 'MB');
      size = '$numStr $unit';
      final val = double.tryParse(numStr) ?? 0.0;
      sizeInMb = unit.contains('GB') ? (val * 1024) : val;
    }
  } else {
    final sMatch = RegExp(r'\b([\d.]+)\s*(GB|MB)\b', caseSensitive: false).firstMatch(size);
    if (sMatch != null) {
      final val = double.tryParse(sMatch.group(1)!) ?? 0.0;
      sizeInMb = size.toUpperCase().contains('GB') ? (val * 1024) : val;
    }
  }

  // 3. Languages
  final languages = <String>[];
  if (explicitLanguages != null && explicitLanguages.isNotEmpty) {
    languages.addAll(explicitLanguages);
  } else {
    const knownLangs = [
      'Malayalam',
      'Hindi',
      'Tamil',
      'Telugu',
      'Kannada',
      'English',
      'Bengali',
      'Punjabi',
      'Marathi',
      'Japanese',
      'Korean',
      'Spanish',
      'French',
      'German',
    ];
    for (final l in knownLangs) {
      if (RegExp(r'\b' + l + r'\b', caseSensitive: false).hasMatch(searchScope)) {
        if (!languages.contains(l)) languages.add(l);
      }
    }
    if (languages.isEmpty && (searchScope.contains('multi audio') || searchScope.contains('multi-audio') || searchScope.contains('multiaudio'))) {
      languages.add('Multi-Audio');
    } else if (languages.isEmpty && (searchScope.contains('dual audio') || searchScope.contains('dual-audio') || searchScope.contains('dualaudio'))) {
      languages.add('Dual-Audio');
    }
  }

  // 4. Special Badges (Dolby Vision, Atmos, HDR, 10-bit, IMAX, HEVC - 3D completely removed)
  final specialBadges = <SpecialBadge>[];

  // Dolby Vision
  if (RegExp(r'\b(dolby\s*vision|dovi|dv)\b', caseSensitive: false).hasMatch(searchScope)) {
    specialBadges.add(const SpecialBadge(
      label: 'DOLBY VISION',
      bg: Color(0xFF6B21A8),
      fg: Color(0xFFE9D5FF),
      icon: Icons.brightness_high_rounded,
    ));
  }

  // HDR / HDR10+
  if (RegExp(r'\b(hdr10\+|hdr10|hdr)\b', caseSensitive: false).hasMatch(searchScope)) {
    specialBadges.add(const SpecialBadge(
      label: 'HDR',
      bg: Color(0xFF854D0E),
      fg: Color(0xFFFEF08A),
      icon: Icons.hdr_on_rounded,
    ));
  }

  // Dolby Atmos / Surround
  if (RegExp(r'\b(atmos|dolby\s*atmos)\b', caseSensitive: false).hasMatch(searchScope)) {
    specialBadges.add(const SpecialBadge(
      label: 'ATMOS',
      bg: Color(0xFF0E7490),
      fg: Color(0xFFA5F3FC),
      icon: Icons.surround_sound_rounded,
    ));
  } else if (RegExp(r'\b(5\.1|ddp5\.1|dd5\.1|7\.1)\b', caseSensitive: false).hasMatch(searchScope)) {
    specialBadges.add(const SpecialBadge(
      label: '5.1 SURROUND',
      bg: Color(0xFF1E293B),
      fg: Color(0xFF38BDF8),
      icon: Icons.surround_sound_rounded,
    ));
  }

  // 10-Bit Color Depth
  if (RegExp(r'\b(10-?bit|hevc\s*10)\b', caseSensitive: false).hasMatch(searchScope)) {
    specialBadges.add(const SpecialBadge(
      label: '10-BIT',
      bg: Color(0xFF064E3B),
      fg: Color(0xFF6EE7B7),
      icon: Icons.palette_rounded,
    ));
  }

  // HEVC / x265 / AV1 Codec
  if (RegExp(r'\b(hevc|x265|h\.?265)\b', caseSensitive: false).hasMatch(searchScope)) {
    specialBadges.add(const SpecialBadge(
      label: 'HEVC',
      bg: Color(0xFF14532D),
      fg: Color(0xFF86EFAC),
      icon: Icons.memory_rounded,
    ));
  } else if (RegExp(r'\bav1\b', caseSensitive: false).hasMatch(searchScope)) {
    specialBadges.add(const SpecialBadge(
      label: 'AV1',
      bg: Color(0xFF1E3A8A),
      fg: Color(0xFF93C5FD),
      icon: Icons.memory_rounded,
    ));
  }

  // IMAX / BluRay (3D removed per user request)
  if (RegExp(r'\bimax\b', caseSensitive: false).hasMatch(searchScope)) {
    specialBadges.add(const SpecialBadge(
      label: 'IMAX',
      bg: Color(0xFF312E81),
      fg: Color(0xFFC7D2FE),
      icon: Icons.aspect_ratio_rounded,
    ));
  } else if (RegExp(r'\b(bluray|bdrip|brrip)\b', caseSensitive: false).hasMatch(searchScope)) {
    specialBadges.add(const SpecialBadge(
      label: 'BLURAY',
      bg: Color(0xFF1E1B4B),
      fg: Color(0xFF818CF8),
      icon: Icons.disc_full_rounded,
    ));
  }

  final isSeedr = url.startsWith('magnet:');
  final isStalker = url.startsWith('stalker:') || raw.toLowerCase().startsWith('portal') || raw.toLowerCase().contains('stalker');

  // Clean Title
  String cleanTitle = raw;
  // Clean trailing technical details from the main title since they are now chips
  cleanTitle = cleanTitle
      .replaceAll(RegExp(r'\s*•\s*(4K|2160p|1080p|720p|480p|Full HD|HD|SD|Multi-Audio|Dual Audio).*', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s*\[[\d.]+\s*[GM]B\]', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s*\([\d.]+\s*[GM]B\)', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s+[-•]\s*$', caseSensitive: false), '')
      .trim();

  if (cleanTitle.isEmpty || cleanTitle.toLowerCase() == 'stream') {
    cleanTitle = 'Fast Direct Stream';
  }

  return ParsedStreamMeta(
    quality: quality,
    qualityColor: qualityColor,
    qualityRank: qualityRank,
    size: size,
    sizeInMb: sizeInMb,
    languages: languages,
    specialBadges: specialBadges,
    cleanTitle: cleanTitle,
    isSeedr: isSeedr,
    isStalker: isStalker,
    raw: raw,
  );
}

/// Centralized quality sorting function: 4K (rank 4) -> 1080p (3) -> 720p (2) -> 480p (1) -> other
List<T> sortStreamsByQuality<T>(
  List<T> items, {
  required String Function(T) getName,
  required String Function(T) getUrl,
  String? Function(T)? getQuality,
  String? Function(T)? getSize,
}) {
  final list = List<T>.from(items);
  list.sort((a, b) {
    final metaA = parseStreamMeta(getName(a), getUrl(a), explicitQuality: getQuality?.call(a), explicitSize: getSize?.call(a));
    final metaB = parseStreamMeta(getName(b), getUrl(b), explicitQuality: getQuality?.call(b), explicitSize: getSize?.call(b));

    // Primary: Quality Rank (4K > 1080p > 720p > 480p)
    if (metaA.qualityRank != metaB.qualityRank) {
      return metaB.qualityRank.compareTo(metaA.qualityRank);
    }

    // Secondary: Special Badges count (HDR / Dolby Vision / Atmos preferred)
    if (metaA.specialBadges.length != metaB.specialBadges.length) {
      return metaB.specialBadges.length.compareTo(metaA.specialBadges.length);
    }

    // Tertiary: File Size (larger size = higher bitrate = better quality)
    if (metaA.sizeInMb > 0 && metaB.sizeInMb > 0 && (metaA.sizeInMb != metaB.sizeInMb)) {
      return metaB.sizeInMb.compareTo(metaA.sizeInMb);
    }

    // Language priority: Malayalam (first priority) > Tamil > Telugu > Kannada > Hindi > others
    int langRank(ParsedStreamMeta meta) {
      final langs = meta.languages.map((l) => l.toLowerCase()).toList();
      final title = meta.raw.toLowerCase();
      if (langs.contains('malayalam') || title.contains('malayalam')) return 0;
      if (langs.contains('tamil') || title.contains('tamil')) return 1;
      if (langs.contains('telugu') || title.contains('telugu')) return 2;
      if (langs.contains('kannada') || title.contains('kannada')) return 3;
      if (langs.contains('hindi') || title.contains('hindi')) return 4;
      return 5;
    }

    final langA = langRank(metaA);
    final langB = langRank(metaB);
    if (langA != langB) {
      return langA.compareTo(langB);
    }

    return 0;
  });
  return list;
}

class StreamMetadataTile extends StatelessWidget {
  final String name;
  final String url;
  final Map<String, String>? headers;
  final String? explicitQuality;
  final String? explicitSize;
  final List<String>? explicitLanguages;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onDownload;
  final bool isSelected;

  const StreamMetadataTile({
    super.key,
    required this.name,
    required this.url,
    this.headers,
    this.explicitQuality,
    this.explicitSize,
    this.explicitLanguages,
    this.onTap,
    this.onLongPress,
    this.onDownload,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final meta = parseStreamMeta(
      name,
      url,
      explicitQuality: explicitQuality,
      explicitSize: explicitSize,
      explicitLanguages: explicitLanguages,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isSelected ? AppColors.accent.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected
                    ? AppColors.accent.withValues(alpha: 0.4)
                    : (meta.qualityRank == 4
                        ? const Color(0xFFA855F7).withValues(alpha: 0.25)
                        : Colors.white.withValues(alpha: 0.05)),
                width: meta.qualityRank == 4 ? 1.2 : 1.0,
              ),
            ),
            child: Row(
              children: [
                // Source Icon / Indicator
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: meta.isSeedr
                        ? const Color(0xFF00E676).withValues(alpha: 0.12)
                        : (meta.isStalker
                            ? AppColors.accentBright.withValues(alpha: 0.12)
                            : (meta.qualityColor ?? AppColors.accent).withValues(alpha: 0.12)),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    meta.isSeedr
                        ? Icons.cloud_download_rounded
                        : (meta.isStalker
                            ? Icons.movie_filter_rounded
                            : (meta.qualityRank >= 3 ? Icons.hd_rounded : Icons.play_arrow_rounded)),
                    color: meta.isSeedr
                        ? const Color(0xFF00E676)
                        : (meta.isStalker ? AppColors.accentBright : (meta.qualityColor ?? Colors.white70)),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                // Title + Metadata Badges Row
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Title row with primary quality pill
                      Row(
                        children: [
                          if (meta.quality != null)
                            Container(
                              margin: const EdgeInsets.only(right: 7),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: (meta.qualityColor ?? AppColors.accentBright).withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(
                                  color: (meta.qualityColor ?? AppColors.accentBright).withValues(alpha: 0.4),
                                  width: 0.8,
                                ),
                              ),
                              child: Text(
                                meta.quality!,
                                style: TextStyle(
                                  color: meta.qualityColor ?? AppColors.accentBright,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              child: Text(
                                meta.cleanTitle,
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Metadata badges: Special formats (Dolby Vision, Atmos, HDR, 10-bit) + Languages + Size
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: Row(
                          children: [
                            // Special Format Badges
                            for (final badge in meta.specialBadges)
                              Container(
                                margin: const EdgeInsets.only(right: 5),
                                padding: const EdgeInsets.symmetric(horizontal: 5.5, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: badge.bg.withValues(alpha: 0.85),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (badge.icon != null) ...[
                                      Icon(badge.icon, size: 9, color: badge.fg),
                                      const SizedBox(width: 2.5),
                                    ],
                                    Text(
                                      badge.label,
                                      style: TextStyle(
                                        color: badge.fg,
                                        fontSize: 8.5,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            // Audio Language Badges
                            for (final lang in meta.languages)
                              Container(
                                margin: const EdgeInsets.only(right: 5),
                                padding: const EdgeInsets.symmetric(horizontal: 5.5, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF59E0B).withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
                                    width: 0.6,
                                  ),
                                ),
                                child: Text(
                                  lang,
                                  style: const TextStyle(
                                    color: Color(0xFFFBBF24),
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            // File Size Badge
                            if (meta.size != null)
                              Container(
                                margin: const EdgeInsets.only(right: 5),
                                padding: const EdgeInsets.symmetric(horizontal: 5.5, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  meta.size!,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                if (onDownload != null)
                  IconButton(
                    icon: const Icon(Icons.file_download_rounded, size: 20),
                    color: Colors.white70,
                    tooltip: 'Download Stream',
                    onPressed: onDownload,
                  )
                else
                  const Icon(Icons.chevron_right_rounded, color: Colors.white24, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
