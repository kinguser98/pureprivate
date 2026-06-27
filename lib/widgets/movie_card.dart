import 'dart:ui';
import 'package:flutter/material.dart';
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
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
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

                // Dark Bottom Scrim
                if (!hideTitle)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.9),
                        ],
                        stops: const [0.6, 1.0],
                      ),
                    ),
                  ),

                // Movie Title (inside card overlay)
                if (!hideTitle)
                  Positioned(
                    left: 10,
                    right: 10,
                    bottom: 10,
                    child: Text(
                      movie.title,
                      maxLines: isLandscape ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.2,
                      ),
                    ),
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
                              color: Colors.white.withValues(alpha: 0.1),
                              width: 0.5,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.star_rounded,
                                color: Colors.amber,
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
    );
  }
}
