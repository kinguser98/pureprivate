import 'package:flutter/material.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/movie.dart';

class HeroSlider extends StatefulWidget {
  final List<Movie> movies;
  final VoidCallback? onMovieTap;

  const HeroSlider({
    super.key,
    required this.movies,
    this.onMovieTap,
  });

  @override
  State<HeroSlider> createState() => _HeroSliderState();
}

class _HeroSliderState extends State<HeroSlider> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.movies.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        SizedBox(
          height: 280,
          child: CarouselSlider.builder(
            itemCount: widget.movies.length,
            options: CarouselOptions(
              height: 280,
              viewportFraction: 0.85,
              autoPlay: true,
              autoPlayInterval: const Duration(seconds: 5),
              autoPlayAnimationDuration: const Duration(milliseconds: 1000),
              enlargeCenterPage: true,
              enlargeStrategy: CenterPageEnlargeStrategy.scale,
              onPageChanged: (index, reason) {
                setState(() => _currentIndex = index);
              },
            ),
            itemBuilder: (context, index, realIndex) {
              return _buildHeroCard(widget.movies[index]);
            },
          ),
        ),
        const SizedBox(height: 12),
        // Indicators
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: widget.movies.asMap().entries.map((entry) {
            return Container(
              width: _currentIndex == entry.key ? 24 : 8,
              height: 8,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: _currentIndex == entry.key
                    ? const Color(0xFFEF4444)
                    : Colors.white.withOpacity(0.3),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildHeroCard(Movie movie) {
    return GestureDetector(
      onTap: widget.onMovieTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 20,
              spreadRadius: 5,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: movie.backdropUrl ?? movie.posterUrl,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  color: Colors.grey[850],
                  child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ),
                errorWidget: (context, url, error) => Container(
                  color: Colors.grey[850],
                  child: const Center(
                    child: Icon(Icons.movie, size: 64, color: Colors.white24),
                  ),
                ),
              ),
              // Gradient overlay
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.7),
                      ],
                    ),
                  ),
                ),
              ),
              // Movie info
              Positioned(
                bottom: 20,
                left: 20,
                right: 20,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      movie.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (movie.qualityTag != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              movie.qualityTag!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Icon(Icons.remove_red_eye, size: 14, color: Colors.white.withOpacity(0.7)),
                        const SizedBox(width: 4),
                        Text(
                          '${_formatViews(movie.views)} views',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 11,
                          ),
                        ),
                        if (movie.releaseDate != null) ...[
                          const SizedBox(width: 12),
                          Icon(Icons.calendar_today, size: 12, color: Colors.white.withOpacity(0.7)),
                          const SizedBox(width: 4),
                          Text(
                            movie.releaseDate!,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatViews(int views) {
    if (views >= 1000000) return '${(views / 1000000).toStringAsFixed(1)}M';
    if (views >= 1000) return '${(views / 1000).toStringAsFixed(1)}K';
    return views.toString();
  }
}
