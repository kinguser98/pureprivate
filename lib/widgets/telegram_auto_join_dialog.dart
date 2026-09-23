import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class TelegramAutoJoinDialog extends StatefulWidget {
  final String initialStatus;
  final ValueNotifier<String> statusNotifier;
  final VoidCallback onCancel;

  const TelegramAutoJoinDialog({
    super.key,
    required this.initialStatus,
    required this.statusNotifier,
    required this.onCancel,
  });

  @override
  State<TelegramAutoJoinDialog> createState() => _TelegramAutoJoinDialogState();
}

class _TelegramAutoJoinDialogState extends State<TelegramAutoJoinDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.94, end: 1.06).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 28),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              colors: [
                Color(0xFF00E5FF),
                Color(0xFF8B5CF6),
                Color(0xFF3B82F6),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00E5FF).withValues(alpha: 0.25),
                blurRadius: 30,
                spreadRadius: 2,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          padding: const EdgeInsets.all(1.5), // Gradient border width
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(23),
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF0F172A), // Deep Slate
                  Color(0xFF131B31),
                  Color(0xFF0B0F19),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Glowing Pulsing Telegram Icon
                  ScaleTransition(
                    scale: _pulseAnimation,
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFF00C6FF),
                            Color(0xFF0072FF),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00C6FF).withValues(alpha: 0.45),
                            blurRadius: 20,
                            spreadRadius: 2,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.send_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Pill Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E5FF).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFF00E5FF).withValues(alpha: 0.35),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: Color(0xFF00E5FF),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'AUTO-BYPASS & STREAM',
                          style: GoogleFonts.outfit(
                            color: const Color(0xFF00E5FF),
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Title
                  Text(
                    'Resolving Telegram Stream',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Stylish progress indicator
                  SizedBox(
                    width: 38,
                    height: 38,
                    child: CircularProgressIndicator(
                      strokeWidth: 3.2,
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF00E5FF)),
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Live Status Text
                  ValueListenableBuilder<String>(
                    valueListenable: widget.statusNotifier,
                    builder: (context, status, _) {
                      return AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: Text(
                          status,
                          key: ValueKey(status),
                          textAlign: TextAlign.center,
                          style: GoogleFonts.outfit(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 8),

                  // Sub-status info
                  Text(
                    'Auto-joining channels & bypassing verification...',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 22),

                  // Cancel Button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.15),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: widget.onCancel,
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
