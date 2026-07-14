import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:private_cinema_ios/models/movie.dart';
import 'package:private_cinema_ios/theme/app_colors.dart';
import 'package:private_cinema_ios/widgets/movie_card.dart';

class MovieSectionRow extends StatelessWidget {
  const MovieSectionRow({
    super.key,
    required this.title,
    required this.movies,
    this.onMoviePressed,
    this.onSeeAllPressed,
    this.isLandscape = false,
    this.hideTitle = false,
  });

  final String title;
  final List<Movie> movies;
  final ValueChanged<Movie>? onMoviePressed;
  final VoidCallback? onSeeAllPressed;
  final bool isLandscape;
  final bool hideTitle;

  @override
  Widget build(BuildContext context) {
    if (movies.isEmpty) {
      return const SizedBox.shrink();
    }

    final double cardWidth = isLandscape ? 180.0 : 115.0;
    final double cardHeight = isLandscape ? 101.25 : 172.5; // Aspect ratios 16:9 vs 2:3
    final double rowHeight = cardHeight + 40.0;

    return SizedBox(
      height: rowHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Title & See All Button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (onSeeAllPressed != null && movies.length > 5)
                  GestureDetector(
                    onTap: onSeeAllPressed,
                    child: Text(
                      'See All',
                      style: GoogleFonts.outfit(
                        color: AppColors.accentBright,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Horizontal Scroll List
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: movies.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final movie = movies[index];
                return MovieCard(
                  movie: movie,
                  width: cardWidth,
                  height: cardHeight,
                  isLandscape: isLandscape,
                  hideTitle: hideTitle,
                  onTap: onMoviePressed != null ? () => onMoviePressed!(movie) : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
