import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:private_cinema_mobile/models/movie.dart';

Widget getOttLogo(String name, {String? logoUrl, double size = 38}) {
  final lower = name.toLowerCase().trim();

  String? primaryUrl = (logoUrl != null && logoUrl.trim().isNotEmpty) ? logoUrl.trim() : null;
  Color bg;
  Color accentColor;
  String text;
  IconData? icon;

  if (lower.contains('netflix') || lower.contains('(nf)')) {
    primaryUrl ??= 'https://assets.nflxext.com/us/ffe/siteui/common/icons/nficon2016.png';
    bg = const Color(0xFF000000);
    accentColor = const Color(0xFFE50914);
    text = 'N';
  } else if (lower.contains('prime') || lower.contains('amazon') || lower.contains('(pv)')) {
    primaryUrl ??= 'https://upload.wikimedia.org/wikipedia/commons/thumb/1/11/Amazon_Prime_Video_logo.svg/185px-Amazon_Prime_Video_logo.svg.png';
    bg = const Color(0xFF00A8E1);
    accentColor = Colors.white;
    text = 'PRIME';
  } else if (lower.contains('hotstar') || lower.contains('disney') || lower.contains('jiohotstar') || lower.contains('(hs)')) {
    primaryUrl ??= 'https://upload.wikimedia.org/wikipedia/commons/thumb/1/1e/Disney%2B_Hotstar_logo.svg/185px-Disney%2B_Hotstar_logo.svg.png';
    bg = const Color(0xFF0F1016);
    accentColor = const Color(0xFF00E5FF);
    text = 'HOTSTAR';
    icon = Icons.star_rounded;
  } else if (lower.contains('sony') || lower.contains('liv')) {
    primaryUrl ??= 'https://upload.wikimedia.org/wikipedia/commons/thumb/5/58/SonyLIV_logo.svg/185px-SonyLIV_logo.svg.png';
    bg = const Color(0xFF16151A);
    accentColor = const Color(0xFFFF5500);
    text = 'LIV';
  } else if (lower.contains('zee')) {
    primaryUrl ??= 'https://upload.wikimedia.org/wikipedia/commons/thumb/5/5a/ZEE5_logo.svg/185px-ZEE5_logo.svg.png';
    bg = const Color(0xFF8230C6);
    accentColor = const Color(0xFFFFC107);
    text = 'ZEE5';
  } else if (lower.contains('jio')) {
    primaryUrl ??= 'https://upload.wikimedia.org/wikipedia/commons/thumb/e/e4/JioCinema_logo.svg/185px-JioCinema_logo.svg.png';
    bg = const Color(0xFFE20074);
    accentColor = Colors.white;
    text = 'Jio';
  } else if (lower.contains('sun')) {
    primaryUrl ??= 'https://upload.wikimedia.org/wikipedia/commons/thumb/a/a2/Sun_NXT_logo.png/185px-Sun_NXT_logo.png';
    bg = const Color(0xFFFF5500);
    accentColor = Colors.yellow;
    text = 'SUN';
  } else if (lower.contains('aha')) {
    primaryUrl ??= 'https://upload.wikimedia.org/wikipedia/commons/thumb/8/87/Aha_OTT_logo.png/185px-Aha_OTT_logo.png';
    bg = const Color(0xFFFF5100);
    accentColor = Colors.white;
    text = 'aha';
  } else if (lower.contains('apple')) {
    primaryUrl ??= 'https://upload.wikimedia.org/wikipedia/commons/thumb/2/28/Apple_TV_Plus_Logo.svg/185px-Apple_TV_Plus_Logo.svg.png';
    bg = const Color(0xFF1C1C1E);
    accentColor = Colors.white;
    text = 'tv+';
    icon = Icons.apple;
  } else if (lower.contains('manorama')) {
    primaryUrl ??= 'https://upload.wikimedia.org/wikipedia/en/thumb/e/e4/ManoramaMAX_logo.png/185px-ManoramaMAX_logo.png';
    bg = const Color(0xFF0F172A);
    accentColor = const Color(0xFF38BDF8);
    text = 'MAX';
  } else {
    bg = const Color(0xFF25293A);
    accentColor = Colors.white70;
    text = name.isNotEmpty ? name[0].toUpperCase() : 'O';
  }

  final fallbackWidget = Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(size * 0.28),
      border: Border.all(color: accentColor.withValues(alpha: 0.5), width: 1.0),
      boxShadow: [
        BoxShadow(
          color: bg.withValues(alpha: 0.4),
          blurRadius: 4,
        ),
      ],
    ),
    child: Center(
      child: icon != null
          ? Icon(icon, color: accentColor, size: size * 0.55)
          : Text(
              text,
              style: TextStyle(
                color: accentColor,
                fontWeight: FontWeight.bold,
                fontSize: size * 0.36,
                letterSpacing: -0.5,
              ),
            ),
    ),
  );

  if (primaryUrl != null && primaryUrl.isNotEmpty) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.28),
      child: CachedNetworkImage(
        imageUrl: primaryUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        memCacheWidth: 100,
        memCacheHeight: 100,
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        placeholder: (_, __) => fallbackWidget,
        errorWidget: (_, __, ___) => fallbackWidget,
      ),
    );
  }

  return fallbackWidget;
}

Widget buildSmallOttBadge(String name, String? logoUrl, {double size = 20}) {
  if (logoUrl != null && logoUrl.isNotEmpty) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 0.6),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 4,
            ),
          ],
        ),
        child: CachedNetworkImage(
          imageUrl: logoUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          memCacheWidth: 60,
          memCacheHeight: 60,
          fadeInDuration: Duration.zero,
          fadeOutDuration: Duration.zero,
          errorWidget: (_, __, ___) => buildSmallTextOttBadge(name, size: size),
        ),
      ),
    );
  }
  return buildSmallTextOttBadge(name, size: size);
}

Widget buildSmallTextOttBadge(String name, {double size = 20}) {
  if (name.isEmpty) return const SizedBox.shrink();
  final displayName = name.length > 5 ? name.substring(0, 5) : name;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.8),
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: const Color(0xFFC084FC).withValues(alpha: 0.5), width: 0.8),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.4),
          blurRadius: 4,
        ),
      ],
    ),
    child: Text(
      displayName,
      style: const TextStyle(
        color: Color(0xFFC084FC),
        fontSize: 8,
        fontWeight: FontWeight.bold,
      ),
    ),
  );
}

Widget buildNewBadge() {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFFEC4899), Color(0xFF8B5CF6)],
      ),
      borderRadius: BorderRadius.circular(6),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF8B5CF6).withValues(alpha: 0.45),
          blurRadius: 6,
          spreadRadius: 1,
        ),
      ],
    ),
    child: const Text(
      'NEW',
      style: TextStyle(
        color: Colors.white,
        fontSize: 8,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.8,
      ),
    ),
  );
}

/// Global shared clock for OTT/NEW badge cross-fades across the entire app.
/// Eliminates dozens of concurrent AnimationControllers and saves battery & GPU cycles.
class BadgeAnimationClock {
  static final BadgeAnimationClock instance = BadgeAnimationClock._();
  BadgeAnimationClock._();

  final ValueNotifier<double> progress = ValueNotifier<double>(0.0);
  Ticker? _ticker;
  int _refCount = 0;
  
  // 2.5s hold for NEW + 0.8s smooth fade + 2.5s hold for OTT + 0.8s smooth fade
  static const int _holdMs = 2300;
  static const int _fadeMs = 800;
  static const int _cycleMs = (_holdMs + _fadeMs) * 2; // 6200ms

  void addRef() {
    _refCount++;
    if (_ticker == null) {
      _ticker = Ticker(_tick)..start();
    }
  }

  void removeRef() {
    _refCount = (_refCount - 1).clamp(0, 999999);
    if (_refCount == 0) {
      _ticker?.stop();
      _ticker?.dispose();
      _ticker = null;
    }
  }

  void _tick(Duration elapsed) {
    final ms = elapsed.inMilliseconds % _cycleMs;
    double p;
    if (ms < _holdMs) {
      p = 0.0; // Hold NEW badge
    } else if (ms < _holdMs + _fadeMs) {
      final t = (ms - _holdMs) / _fadeMs;
      // Smooth Hermite easing curve (3t^2 - 2t^3)
      p = t * t * (3.0 - 2.0 * t);
    } else if (ms < 2 * _holdMs + _fadeMs) {
      p = 1.0; // Hold OTT Logo
    } else {
      final t = (ms - (2 * _holdMs + _fadeMs)) / _fadeMs;
      p = 1.0 - (t * t * (3.0 - 2.0 * t));
    }
    progress.value = p.clamp(0.0, 1.0);
  }
}

/// Animated Poster Badge for Mobile/iOS:
/// If the movie is 'new' and has an OTT logo/name, smoothly cross-fades
/// between the 'NEW' badge and the OTT logo using a single shared app clock.
/// If not new, keeps the OTT logo fixed.
/// If new with no OTT, keeps the 'NEW' badge fixed.
class AnimatedPosterBadge extends StatefulWidget {
  final Movie movie;
  final double ottSize;

  const AnimatedPosterBadge({
    super.key,
    required this.movie,
    this.ottSize = 20,
  });

  @override
  State<AnimatedPosterBadge> createState() => _AnimatedPosterBadgeState();
}

class _AnimatedPosterBadgeState extends State<AnimatedPosterBadge> {
  bool _subscribed = false;
  late Widget _newBadge;
  late Widget _ottBadge;

  @override
  void initState() {
    super.initState();
    _rebuildBadges();
    _updateSubscription();
  }

  void _rebuildBadges() {
    _newBadge = buildNewBadge();
    _ottBadge = buildSmallOttBadge(
      widget.movie.ottName ?? '',
      widget.movie.ottLogo,
      size: widget.ottSize,
    );
  }

  void _updateSubscription() {
    final hasOtt = (widget.movie.ottLogo != null && widget.movie.ottLogo!.isNotEmpty) ||
        (widget.movie.ottName != null && widget.movie.ottName!.isNotEmpty);
    final isNew = widget.movie.isNew;

    if (isNew && hasOtt) {
      if (!_subscribed) {
        BadgeAnimationClock.instance.addRef();
        _subscribed = true;
      }
    } else {
      if (_subscribed) {
        BadgeAnimationClock.instance.removeRef();
        _subscribed = false;
      }
    }
  }

  @override
  void didUpdateWidget(covariant AnimatedPosterBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.movie.ottLogo != widget.movie.ottLogo ||
        oldWidget.movie.ottName != widget.movie.ottName ||
        oldWidget.movie.isNew != widget.movie.isNew ||
        oldWidget.ottSize != widget.ottSize) {
      _rebuildBadges();
      _updateSubscription();
    }
  }

  @override
  void dispose() {
    if (_subscribed) {
      BadgeAnimationClock.instance.removeRef();
      _subscribed = false;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasOtt = (widget.movie.ottLogo != null && widget.movie.ottLogo!.isNotEmpty) ||
        (widget.movie.ottName != null && widget.movie.ottName!.isNotEmpty);
    final isNew = widget.movie.isNew;

    if (!isNew && !hasOtt) {
      return const SizedBox.shrink();
    }

    if (!isNew && hasOtt) {
      return _ottBadge;
    }

    if (isNew && !hasOtt) {
      return _newBadge;
    }

    // New AND has OTT: Synchronized, smooth cross-fade with zero CPU lag
    return ValueListenableBuilder<double>(
      valueListenable: BadgeAnimationClock.instance.progress,
      builder: (context, t, _) {
        return Stack(
          alignment: Alignment.topLeft,
          children: [
            Opacity(
              opacity: (1.0 - t).clamp(0.0, 1.0),
              child: _newBadge,
            ),
            Opacity(
              opacity: t.clamp(0.0, 1.0),
              child: _ottBadge,
            ),
          ],
        );
      },
    );
  }
}
