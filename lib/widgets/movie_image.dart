import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:private_cinema_ios/theme/app_colors.dart';

class MovieImage extends StatelessWidget {
  const MovieImage({
    super.key,
    required this.source,
    this.fit = BoxFit.cover,
    this.fallbackColor,
  });

  final String source;
  final BoxFit fit;
  final Color? fallbackColor;

  bool get _isAsset => source.startsWith('assets/');

  @override
  Widget build(BuildContext context) {
    if (source.isEmpty) {
      return _fallback();
    }

    if (_isAsset) {
      return Image.asset(
        source,
        fit: fit,
        errorBuilder: (_, _, _) => _fallback(),
      );
    }

    return CachedNetworkImage(
      imageUrl: source,
      fit: fit,
      placeholder: (_, _) => _fallback(),
      errorWidget: (_, _, _) => _fallback(),
    );
  }

  Widget _fallback() {
    final base = fallbackColor ?? AppColors.card;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            base,
            Color.lerp(base, Colors.black, 0.45)!,
          ],
        ),
      ),
      child: const Center(
        child: Icon(Icons.movie_rounded, color: AppColors.textMuted, size: 40),
      ),
    );
  }
}
