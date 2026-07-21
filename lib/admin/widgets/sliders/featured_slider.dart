import 'package:flutter/material.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/movie.dart';

class FeaturedSlider extends StatelessWidget {
  final String title;
  final List<Movie> movies;
  final bool isBroken;
  final VoidCallback? onMovieTap;

  const FeaturedSlider({
    super.key,
    required this.title,
    required this.movies,
    this.isBroken = false,
    this.onMovieTap,
  });

  @override
  Widget build(BuildContext context) {
    if (movies.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  if (isBroken) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'BROKEN',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              TextButton(
                onPressed: () {},
                child: Text(
                  'See All',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 220,
          child: CarouselSlider.builder(
            itemCount: movies.length,
            options: CarouselOptions(
              height: 220,
              viewportFraction: 0.4,
              enlargeCenterPage: true,
              enlargeStrategy: CenterPageEnlargeStrategy.height,
              enableInfiniteScroll: movies.length > 3,
              padEnds: false,
              autoPlay: true,
              autoPlayInterval: const Duration(seconds: 4),
              autoPlayAnimationDuration: const Duration(milliseconds: 800),
              autoPlayCurve: Curves.easeOutCubic,
            ),
            itemBuilder: (context, index, realIndex) {
              final movie = movies[index];
              return _buildMovieCard(context, movie);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMovieCard(BuildContext context, Movie movie) {
    return GestureDetector(
      onTap: onMovieTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isBroken
                ? Colors.red.withOpacity(0.5)
                : Colors.white.withOpacity(0.15),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 15,
              spreadRadius: 2,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: movie.posterUrl,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  color: Colors.grey[850],
                  child: const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  color: Colors.grey[850],
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.movie, size: 40, color: Colors.grey[600]),
                      const SizedBox(height: 4),
                      Text(
                        'No Poster',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Gradient overlay for text
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.85),
                      ],
                    ),
                  ),
                  child: Text(
                    movie.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              if (movie.qualityTag != null && movie.qualityTag!.isNotEmpty)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      movie.qualityTag!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              if (movie.isBroken)
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.broken_image,
                      color: Colors.white,
                      size: 14,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
