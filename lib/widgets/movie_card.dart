import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:private_cinema_mobile/models/movie.dart';
import 'package:private_cinema_mobile/theme/app_colors.dart';
import 'package:private_cinema_mobile/widgets/movie_image.dart';

class MovieCard extends StatelessWidget {
  const MovieCard({
    super.key,
    required this.movie,
    this.width = 120,
    this.height = 180,
    this.isLandscape = false,
    this.hideTitle = false,
    this.onTap,
  });

  final Movie movie;
  final double width;
  final double height;
  final bool isLandscape;
  final bool hideTitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final posterHeight = hideTitle ? height : (height - 44).clamp(100.0, 500.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 1. Poster Card with Theme-based Border
        Container(
          width: width,
          height: posterHeight,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.accent, // Selected accent color from settings!
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14.5),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                splashColor: AppColors.accent.withValues(alpha: 0.2),
                highlightColor: AppColors.accent.withValues(alpha: 0.1),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Backdrop/Poster Image
                    MovieImage(
                      source: isLandscape ? movie.displayBackdrop : movie.posterUrl,
                      fit: BoxFit.cover,
                      fallbackColor: movie.posterColor,
                    ),

                    // IMDb Rating Badge (top-right)
                    if (movie.rating > 0)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: AppColors.accent.withValues(alpha: 0.3),
                                  width: 0.8,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.star_rounded,
                                    color: AppColors.accentBright, // Selected settings color!
                                    size: 12,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    movie.rating.toStringAsFixed(1),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                    // Watch Progress Indicator (bottom edge)
                    if (movie.watchProgress != null && movie.watchProgress! > 0.0)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: 4,
                        child: Container(
                          color: Colors.black38,
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: movie.watchProgress!.clamp(0.0, 1.0),
                            child: Container(
                              color: AppColors.accentBright,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // 2. Title & Genre below poster
        if (!hideTitle) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  movie.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  movie.genre.replaceAll(',', ' •'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: AppColors.accentBright, // Selected settings text color!
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
