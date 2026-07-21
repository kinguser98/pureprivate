import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/movie.dart';

class MovieCard extends StatelessWidget {
  final Movie movie;
  final VoidCallback? onTap;

  const MovieCard({
    super.key,
    required this.movie,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: const Color(0xFF1A1F2E).withOpacity(0.45),
          border: Border.all(
            color: movie.isBroken
                ? Colors.red.withOpacity(0.3)
                : Colors.white.withOpacity(0.08),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Poster image
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
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
                        child: Icon(Icons.movie, size: 32, color: Colors.grey[600]),
                      ),
                    ),
                    // Status badges
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
                          child: const Icon(Icons.broken_image, size: 12, color: Colors.white),
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
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // Movie info
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    movie.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.remove_red_eye, size: 10, color: Colors.white.withOpacity(0.5)),
                      const SizedBox(width: 4),
                      Text(
                        _formatViews(movie.views),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 10,
                        ),
                      ),
                      const Spacer(),
                      Icon(Icons.folder, size: 10, color: Colors.white.withOpacity(0.3)),
                    ],
                  ),
                ],
              ),
            ),
          ],
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
