import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Cinematic Netflix-Style Intro Badge with two-stage staggered animation:
/// 1. Entrance: Vertical red accent line drops down from the top, then the
///    title and metadata wipe/scroll horizontally out from behind the line.
/// 2. Exit: The title and metadata scroll horizontally back into the line,
///    then the red accent line collapses back upward to the top.
class NetflixIntroBadge extends StatefulWidget {
  final bool isVisible;
  final String title;
  final String metaText;

  const NetflixIntroBadge({
    super.key,
    required this.isVisible,
    required this.title,
    required this.metaText,
  });

  @override
  State<NetflixIntroBadge> createState() => _NetflixIntroBadgeState();
}

class _NetflixIntroBadgeState extends State<NetflixIntroBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _lineAnimation;
  late final Animation<double> _textAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
      reverseDuration: const Duration(milliseconds: 800),
    );

    // Phase 1: Line drops down / collapses upward
    _lineAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.42, curve: Curves.easeOutCubic),
      reverseCurve: const Interval(0.0, 0.42, curve: Curves.easeInCubic),
    );

    // Phase 2: Text reveals horizontally to the right / retracts back into line
    _textAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.38, 1.0, curve: Curves.easeOutCubic),
      reverseCurve: const Interval(0.38, 1.0, curve: Curves.easeInCubic),
    );

    if (widget.isVisible) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(covariant NetflixIntroBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible != oldWidget.isVisible) {
      if (widget.isVisible) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.title.isEmpty) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        if (_controller.value == 0.0 && !widget.isVisible) {
          return const SizedBox.shrink();
        }

        final lineVal = _lineAnimation.value;
        final textVal = _textAnimation.value;

        return IgnorePointer(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Colors.black.withValues(alpha: 0.55 * textVal),
                  Colors.black.withValues(alpha: 0.0),
                ],
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 1. Vertical Red Accent Line (Drops down from top, retracts up to top)
                Transform.scale(
                  scaleY: lineVal,
                  alignment: Alignment.topCenter,
                  child: Opacity(
                    opacity: lineVal.clamp(0.0, 1.0),
                    child: Container(
                      width: 4.5,
                      height: 42,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE50914),
                        borderRadius: BorderRadius.circular(2.5),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFE50914).withValues(alpha: 0.8),
                            blurRadius: 10,
                            spreadRadius: 1.5,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // 2. Movie Title & Metadata (Scrolls/reveals horizontally out from the line)
                ClipRect(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    widthFactor: textVal,
                    child: FractionalTranslation(
                      translation: Offset(-0.35 * (1.0 - textVal), 0.0),
                      child: Opacity(
                        opacity: textVal.clamp(0.0, 1.0),
                        child: Padding(
                          padding: const EdgeInsets.only(left: 14),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                  shadows: const [
                                    Shadow(color: Colors.black, blurRadius: 10, offset: Offset(0, 2)),
                                    Shadow(color: Colors.black87, blurRadius: 6, offset: Offset(0, 1)),
                                  ],
                                ),
                              ),
                              if (widget.metaText.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text(
                                  widget.metaText,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.outfit(
                                    color: Colors.white.withValues(alpha: 0.82),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.2,
                                    shadows: const [
                                      Shadow(color: Colors.black, blurRadius: 8, offset: Offset(0, 1)),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
