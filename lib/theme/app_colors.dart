import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum CinemaTheme {
  purple,
  crimson,
  emerald,
  oceanic,
  gold,
  amoled;

  String get displayName {
    switch (this) {
      case CinemaTheme.purple:
        return 'Purple Glow';
      case CinemaTheme.crimson:
        return 'Crimson Cinematic';
      case CinemaTheme.emerald:
        return 'Emerald Lounge';
      case CinemaTheme.oceanic:
        return 'Oceanic Deep';
      case CinemaTheme.gold:
        return 'Electric Gold';
      case CinemaTheme.amoled:
        return 'Pure AMOLED Black';
    }
  }

  Color get accent {
    switch (this) {
      case CinemaTheme.purple:
        return const Color(0xFF9333EA);
      case CinemaTheme.crimson:
        return const Color(0xFFE50914);
      case CinemaTheme.emerald:
        return const Color(0xFF10B981);
      case CinemaTheme.oceanic:
        return const Color(0xFF0EA5E9);
      case CinemaTheme.gold:
        return const Color(0xFFF59E0B);
      case CinemaTheme.amoled:
        return const Color(0xFF8B5CF6);
    }
  }

  Color get accentBright {
    switch (this) {
      case CinemaTheme.purple:
        return const Color(0xFFA855F7);
      case CinemaTheme.crimson:
        return const Color(0xFFF87171);
      case CinemaTheme.emerald:
        return const Color(0xFF34D399);
      case CinemaTheme.oceanic:
        return const Color(0xFF38BDF8);
      case CinemaTheme.gold:
        return const Color(0xFFFBBF24);
      case CinemaTheme.amoled:
        return const Color(0xFFA855F7);
    }
  }

  Color get accentGlow {
    switch (this) {
      case CinemaTheme.purple:
        return const Color(0x809333EA);
      case CinemaTheme.crimson:
        return const Color(0x80E50914);
      case CinemaTheme.emerald:
        return const Color(0x8010B981);
      case CinemaTheme.oceanic:
        return const Color(0x800EA5E9);
      case CinemaTheme.gold:
        return const Color(0x80F59E0B);
      case CinemaTheme.amoled:
        return const Color(0x808B5CF6);
    }
  }

  Color get focusGlow {
    switch (this) {
      case CinemaTheme.purple:
        return const Color(0x669333EA);
      case CinemaTheme.crimson:
        return const Color(0x66E50914);
      case CinemaTheme.emerald:
        return const Color(0x6610B981);
      case CinemaTheme.oceanic:
        return const Color(0x660EA5E9);
      case CinemaTheme.gold:
        return const Color(0x66F59E0B);
      case CinemaTheme.amoled:
        return const Color(0x668B5CF6);
    }
  }

  LinearGradient get playButton {
    switch (this) {
      case CinemaTheme.purple:
        return const LinearGradient(
          colors: [Color(0xFF7C3AED), Color(0xFFA855F7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case CinemaTheme.crimson:
        return const LinearGradient(
          colors: [Color(0xFFB91C1C), Color(0xFFEF4444)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case CinemaTheme.emerald:
        return const LinearGradient(
          colors: [Color(0xFF047857), Color(0xFF10B981)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case CinemaTheme.oceanic:
        return const LinearGradient(
          colors: [Color(0xFF0369A1), Color(0xFF0EA5E9)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case CinemaTheme.gold:
        return const LinearGradient(
          colors: [Color(0xFFD97706), Color(0xFFF59E0B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case CinemaTheme.amoled:
        return const LinearGradient(
          colors: [Color(0xFF6D28D9), Color(0xFF8B5CF6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
    }
  }

  LinearGradient get edgeAccentGlow {
    switch (this) {
      case CinemaTheme.purple:
        return const LinearGradient(
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
          colors: [Color(0x409333EA), Color(0x009333EA)],
        );
      case CinemaTheme.crimson:
        return const LinearGradient(
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
          colors: [Color(0x40E50914), Color(0x00E50914)],
        );
      case CinemaTheme.emerald:
        return const LinearGradient(
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
          colors: [Color(0x4010B981), Color(0x0010B981)],
        );
      case CinemaTheme.oceanic:
        return const LinearGradient(
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
          colors: [Color(0x400EA5E9), Color(0x000EA5E9)],
        );
      case CinemaTheme.gold:
        return const LinearGradient(
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
          colors: [Color(0x40F59E0B), Color(0x00F59E0B)],
        );
      case CinemaTheme.amoled:
        return const LinearGradient(
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
          colors: [Color(0x408B5CF6), Color(0x008B5CF6)],
        );
    }
  }
}

class ThemeManager {
  static final notifier = ValueNotifier<CinemaTheme>(CinemaTheme.purple);

  static CinemaTheme get currentTheme => notifier.value;

  static void setTheme(CinemaTheme theme) async {
    notifier.value = theme;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('theme_index', theme.index);
    } catch (e) {
      debugPrint('Error saving theme index: $e');
    }
  }
}

abstract final class AppColors {
  static Color get background => ThemeManager.currentTheme == CinemaTheme.amoled 
      ? const Color(0xFF000000) 
      : const Color(0xFF06080F);
  static const surface = Color(0xFF12151F);
  static const rail = Color(0xFF0B0E17);
  static const card = Color(0xFF1A1F2E);

  static Color get accent => ThemeManager.currentTheme.accent;
  static Color get accentBright => ThemeManager.currentTheme.accentBright;
  static Color get accentGlow => ThemeManager.currentTheme.accentGlow;

  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFFD1D5DB);
  static const textMuted = Color(0xFF9CA3AF);

  static const pillBackground = Color(0x33FFFFFF);
  static const actionSecondary = Color(0x99000000);
  static const focusBorder = Color(0xFFFFFFFF);

  static Color get focusGlow => ThemeManager.currentTheme.focusGlow;

  /// Heavy left + bottom cinematic scrim over hero art.
  static const heroScrim = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [
      Color(0xF0101218),
      Color(0xCC101218),
      Color(0x66101218),
      Color(0x00101218),
    ],
    stops: [0.0, 0.35, 0.55, 1.0],
  );

  static const heroBottomScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0x00000000),
      Color(0xAA000000),
      Color(0xF506080F),
    ],
    stops: [0.35, 0.72, 1.0],
  );

  static LinearGradient get edgeAccentGlow => ThemeManager.currentTheme.edgeAccentGlow;
  static LinearGradient get playButton => ThemeManager.currentTheme.playButton;
}
