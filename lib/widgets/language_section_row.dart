import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:private_cinema_ios/models/language_item.dart';
import 'package:private_cinema_ios/widgets/movie_image.dart';

class LanguageSectionRow extends StatelessWidget {
  const LanguageSectionRow({
    super.key,
    required this.onLanguageSelected,
    required this.languages,
  });

  final ValueChanged<String> onLanguageSelected;
  final List<LanguageItem> languages;

  @override
  Widget build(BuildContext context) {
    if (languages.isEmpty) {
      return const SizedBox.shrink();
    }

    final double cardWidth = 140.0;
    final double cardHeight = 84.0; // 1.6 aspect ratio
    final double rowHeight = cardHeight + 40.0;

    return SizedBox(
      height: rowHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Languages',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: languages.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final item = languages[index];
                return _buildLanguageCard(context, item, cardWidth, cardHeight);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageCard(
    BuildContext context,
    LanguageItem item,
    double width,
    double height,
  ) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => onLanguageSelected(item.filterValue),
            splashColor: Colors.white.withValues(alpha: 0.15),
            highlightColor: Colors.white.withValues(alpha: 0.05),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Backdrop Image
                MovieImage(
                  source: item.backdropUrl,
                  fit: BoxFit.cover,
                ),
                // Gradient Overlay
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: item.gradient.begin,
                      end: item.gradient.end,
                      colors: item.gradient.colors
                          .map((c) => c.withValues(alpha: 0.68))
                          .toList(),
                    ),
                  ),
                ),
                // Extra dark blend at bottom
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.3),
                      ],
                    ),
                  ),
                ),
                // Frosted central text block
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                        ),
                        child: Text(
                          item.name,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
