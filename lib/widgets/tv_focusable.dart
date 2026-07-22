import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:private_cinema_mobile/theme/app_colors.dart';

class TvFocusable extends StatefulWidget {
  const TvFocusable({
    super.key,
    required this.child,
    this.onPressed,
    this.borderRadius = 12,
    this.focusScale = 1.03,
    this.padding = 2,
    this.autofocus = false,
    this.showWhiteFocusBorder = true,
    this.onFocusChange,
    this.focusNode,
    this.onKeyEvent,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final double borderRadius;
  final double focusScale;
  final double padding;
  final bool autofocus;
  final bool showWhiteFocusBorder;
  final ValueChanged<bool>? onFocusChange;
  final FocusNode? focusNode;
  final FocusOnKeyEventCallback? onKeyEvent;

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  bool _focused = false;

  void _activate() {
    widget.onPressed?.call();
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = widget.showWhiteFocusBorder
        ? (_focused ? AppColors.focusBorder : Colors.transparent)
        : (_focused ? AppColors.accentBright : Colors.transparent);

    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (v) {
        setState(() => _focused = v);
        widget.onFocusChange?.call(v);
      },
      onKeyEvent: (node, event) {
        if (widget.onKeyEvent != null) {
          final res = widget.onKeyEvent!(node, event);
          if (res == KeyEventResult.handled) return res;
        }
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.space)) {
          _activate();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: _activate,
        child: AnimatedScale(
          scale: _focused ? widget.focusScale : 1,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: EdgeInsets.all(widget.padding),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              border: Border.all(color: borderColor, width: 2.5),
              boxShadow: _focused && !widget.showWhiteFocusBorder
                  ? [
                      BoxShadow(
                        color: AppColors.focusGlow,
                        blurRadius: 16,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
