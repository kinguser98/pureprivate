import 'dart:async';
import 'package:flutter/material.dart';

class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final double velocity;
  final Duration pauseDuration;
  final bool active;

  const MarqueeText({
    super.key,
    required this.text,
    this.style,
    this.velocity = 30.0, // pixels per second
    this.pauseDuration = const Duration(milliseconds: 1200),
    this.active = true,
  });

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText> {
  final ScrollController _scrollController = ScrollController();
  Timer? _timer;
  bool _isScrolling = false;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    if (widget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startMarquee());
    }
  }

  @override
  void didUpdateWidget(covariant MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.active != widget.active) {
      _timer?.cancel();
      _isScrolling = false;
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0.0);
      }
      if (widget.active) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _startMarquee());
      }
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _timer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _startMarquee() async {
    if (!mounted || _isDisposed || !widget.active || _isScrolling) return;
    if (!_scrollController.hasClients) {
      _timer = Timer(const Duration(milliseconds: 300), _startMarquee);
      return;
    }

    final maxScroll = _scrollController.position.maxScrollExtent;
    if (maxScroll <= 0) return; // Text fits, no scrolling needed

    _isScrolling = true;

    while (mounted && !_isDisposed && widget.active) {
      // Pause at start
      await Future.delayed(widget.pauseDuration);
      if (!mounted || _isDisposed || !widget.active || !_scrollController.hasClients) break;

      // Scroll to end
      final duration = Duration(milliseconds: (maxScroll / widget.velocity * 1000).round().clamp(1000, 15000));
      try {
        await _scrollController.animateTo(
          maxScroll,
          duration: duration,
          curve: Curves.linear,
        );
      } catch (_) {
        break;
      }

      // Pause at end
      await Future.delayed(widget.pauseDuration);
      if (!mounted || _isDisposed || !widget.active || !_scrollController.hasClients) break;

      // Scroll back to start
      try {
        await _scrollController.animateTo(
          0.0,
          duration: duration,
          curve: Curves.linear,
        );
      } catch (_) {
        break;
      }
    }

    _isScrolling = false;
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      child: Text(
        widget.text,
        style: widget.style,
        maxLines: 1,
        softWrap: false,
      ),
    );
  }
}
