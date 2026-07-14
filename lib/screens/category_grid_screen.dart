import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:private_cinema_ios/models/movie.dart';
import 'package:private_cinema_ios/theme/app_colors.dart';
import 'package:private_cinema_ios/widgets/movie_card.dart';
import 'package:private_cinema_ios/screens/movie_detail_screen.dart';

class CategoryGridScreen extends StatelessWidget {
  const CategoryGridScreen({
    super.key,
    required this.title,
    required this.movies,
  });

  final String title;
  final List<Movie> movies;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final isLandscape = mediaQuery.orientation == Orientation.landscape;
    
    // Calculate adaptive column count
    final int crossAxisCount = isLandscape ? 5 : 3;
    final double spacing = 12.0;

    // Grid aspect ratio (width / height) -> based on MovieCard size
    final double cardWidth = 115.0;
    final double cardHeight = 172.5;
    final double childAspectRatio = cardWidth / cardHeight;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          title,
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: movies.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.movie_filter_rounded, color: Colors.white30, size: 64),
                  const SizedBox(height: 16),
                  Text(
                    'No movies found in this list.',
                    style: TextStyle(color: Colors.white54, fontSize: 16),
                  ),
                ],
              ),
            )
          : GridView.builder(
              padding: EdgeInsets.fromLTRB(16, 8, 16, mediaQuery.padding.bottom + 24),
              itemCount: movies.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: spacing,
                mainAxisSpacing: spacing,
                childAspectRatio: childAspectRatio,
              ),
              itemBuilder: (context, index) {
                final movie = movies[index];
                return MovieCard(
                  movie: movie,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => MovieDetailScreen(movie: movie),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
