import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomeWallpaperSettings {
  final bool enabled;
  final String wallpaperUrl;
  final String? localPath;
  final double blur;
  final double vignette;
  final double darkness;

  const HomeWallpaperSettings({
    this.enabled = false,
    this.wallpaperUrl = 'https://images.unsplash.com/photo-1536440136628-849c177e76a1?q=80&w=1280&auto=format&fit=crop',
    this.localPath,
    this.blur = 12.0,
    this.vignette = 0.65,
    this.darkness = 0.60,
  });

  HomeWallpaperSettings copyWith({
    bool? enabled,
    String? wallpaperUrl,
    String? localPath,
    bool clearLocalPath = false,
    double? blur,
    double? vignette,
    double? darkness,
  }) {
    return HomeWallpaperSettings(
      enabled: enabled ?? this.enabled,
      wallpaperUrl: wallpaperUrl ?? this.wallpaperUrl,
      localPath: clearLocalPath ? null : (localPath ?? this.localPath),
      blur: blur ?? this.blur,
      vignette: vignette ?? this.vignette,
      darkness: darkness ?? this.darkness,
    );
  }
}

class HomeWallpaperManager {
  static final ValueNotifier<HomeWallpaperSettings> notifier =
      ValueNotifier<HomeWallpaperSettings>(const HomeWallpaperSettings());

  static HomeWallpaperSettings get current => notifier.value;

  static const List<Map<String, String>> presets = [
    {
      'name': 'Cinema Velvet',
      'url': 'https://images.unsplash.com/photo-1536440136628-849c177e76a1?q=80&w=1280&auto=format&fit=crop',
    },
    {
      'name': 'Deep Nebula',
      'url': 'https://images.unsplash.com/photo-1506703719100-a0f3a48c0f86?q=80&w=1280&auto=format&fit=crop',
    },
    {
      'name': 'Golden Noir',
      'url': 'https://images.unsplash.com/photo-1489599849927-2ee91cede3ba?q=80&w=1280&auto=format&fit=crop',
    },
    {
      'name': 'Cyber Reel',
      'url': 'https://images.unsplash.com/photo-1517604931442-7e0c8ed2963c?q=80&w=1280&auto=format&fit=crop',
    },
    {
      'name': 'Midnight Neon',
      'url': 'https://images.unsplash.com/photo-1518709268805-4e9042af9f23?q=80&w=1280&auto=format&fit=crop',
    },
  ];

  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('home_bg_enabled') ?? false;
      final url = prefs.getString('home_bg_url') ?? presets[0]['url']!;
      final localPath = prefs.getString('home_bg_local_path');
      final blur = prefs.getDouble('home_bg_blur') ?? 12.0;
      final vignette = prefs.getDouble('home_bg_vignette') ?? 0.65;
      final darkness = prefs.getDouble('home_bg_darkness') ?? 0.60;

      // Validate local path exists
      String? validLocalPath = localPath;
      if (validLocalPath != null && validLocalPath.isNotEmpty) {
        if (!File(validLocalPath).existsSync()) {
          validLocalPath = null;
        }
      }

      notifier.value = HomeWallpaperSettings(
        enabled: enabled,
        wallpaperUrl: url,
        localPath: validLocalPath,
        blur: blur,
        vignette: vignette,
        darkness: darkness,
      );
    } catch (e) {
      debugPrint('Error loading home wallpaper settings: $e');
    }
  }

  static Future<void> update(HomeWallpaperSettings settings) async {
    notifier.value = settings;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('home_bg_enabled', settings.enabled);
      await prefs.setString('home_bg_url', settings.wallpaperUrl);
      if (settings.localPath != null) {
        await prefs.setString('home_bg_local_path', settings.localPath!);
      } else {
        await prefs.remove('home_bg_local_path');
      }
      await prefs.setDouble('home_bg_blur', settings.blur);
      await prefs.setDouble('home_bg_vignette', settings.vignette);
      await prefs.setDouble('home_bg_darkness', settings.darkness);
    } catch (e) {
      debugPrint('Error saving home wallpaper settings: $e');
    }
  }

  static Future<bool> pickFromGallery() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty && result.files.single.path != null) {
        final path = result.files.single.path!;
        await update(current.copyWith(
          localPath: path,
          enabled: true,
        ));
        return true;
      }
    } catch (e) {
      debugPrint('Error picking wallpaper from gallery: $e');
    }
    return false;
  }
}
