import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.borderRadius = 20,
    this.blur = 22,
    this.opacity = 0.12,
  });

  final Widget child;
  final EdgeInsets padding;
  final double borderRadius;
  final double blur;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    // Check if we are running on Android (TV) to disable expensive blur effects
    final bool disableBlur = !kIsWeb && (defaultTargetPlatform == TargetPlatform.android);

    final decoratedBox = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        color: Colors.black.withValues(alpha: 0.85),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );

    if (disableBlur) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: decoratedBox,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius),
            color: Colors.white.withValues(alpha: opacity),
            border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
