import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:private_cinema_mobile/data/logo_service.dart';
import 'package:private_cinema_mobile/models/movie.dart';
import 'package:private_cinema_mobile/utils/logo_cache_manager.dart';

class CarouselLogoWidget extends StatefulWidget {
  final Movie movie;
  final double maxHeight;
  final double maxWidth;

  const CarouselLogoWidget({
    super.key,
    required this.movie,
    this.maxHeight = 54.0,
    this.maxWidth = 270.0,
  });

  @override
  State<CarouselLogoWidget> createState() => _CarouselLogoWidgetState();
}

class _CarouselLogoWidgetState extends State<CarouselLogoWidget> {
  String? _resolvedLogoUrl;

  @override
  void initState() {
    super.initState();
    _resolvedLogoUrl = LogoService.getCachedLogoSync(widget.movie);
    _resolveLogo();
  }

  @override
  void didUpdateWidget(covariant CarouselLogoWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.movie.id != widget.movie.id || oldWidget.movie.title != widget.movie.title) {
      _resolvedLogoUrl = LogoService.getCachedLogoSync(widget.movie);
      _resolveLogo();
    }
  }

  Future<void> _resolveLogo() async {
    final logo = await LogoService.resolveLogo(widget.movie);
    if (mounted && logo != _resolvedLogoUrl) {
      setState(() {
        _resolvedLogoUrl = logo;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.95, end: 1.0).animate(animation),
            child: child,
          ),
        );
      },
      child: (_resolvedLogoUrl != null && _resolvedLogoUrl!.isNotEmpty)
          ? SizedBox(
              key: ValueKey('logo_${widget.movie.id}_$_resolvedLogoUrl'),
              height: widget.maxHeight,
              width: widget.maxWidth,
              child: CachedNetworkImage(
                imageUrl: _resolvedLogoUrl!,
                cacheManager: LogoCacheManager.instance,
                fit: BoxFit.contain,
                alignment: Alignment.center,
                placeholder: (_, __) => _buildTextTitle(key: 'text_ph_${widget.movie.id}'),
                errorWidget: (_, __, ___) => _buildTextTitle(key: 'text_err_${widget.movie.id}'),
              ),
            )
          : _buildTextTitle(key: 'text_title_${widget.movie.id}'),
    );
  }

  Widget _buildTextTitle({required String key}) {
    return SizedBox(
      key: ValueKey(key),
      height: widget.maxHeight,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            widget.movie.title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
              shadows: [
                Shadow(
                  color: Colors.black.withOpacity(0.6),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
