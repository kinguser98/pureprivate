import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:private_cinema_mobile/data/dns_proxy.dart';
import 'package:private_cinema_mobile/data/download_manager.dart';
import 'package:private_cinema_mobile/data/sync_service.dart';
import 'package:freebuff_core/services/telegram/telegram_service.dart';
import 'package:private_cinema_mobile/screens/navigation_holder.dart';
import 'package:private_cinema_mobile/theme/app_colors.dart';

Future<void> fetchHotConfig() async {
  try {
    debugPrint('Fetching dynamic source hot-config...');
    final response = await http.get(
      Uri.parse('https://raw.githubusercontent.com/kinguser98/goxio-config/main/config.json')
    ).timeout(const Duration(seconds: 4));
    
    if (response.statusCode == 200) {
      final config = jsonDecode(response.body) as Map<String, dynamic>;
      final prefs = await SharedPreferences.getInstance();
      
      if (config['stravo_addon_url'] != null) {
        await prefs.setString('stravo_addon_url', config['stravo_addon_url'].toString());
      }
      if (config['vidlink_base_url'] != null) {
        await prefs.setString('vidlink_base_url', config['vidlink_base_url'].toString());
      }
      if (config['dns_proxy_blocklist'] != null) {
        final list = List<String>.from(config['dns_proxy_blocklist'] as List);
        await prefs.setStringList('dns_proxy_blocklist', list);
        MyHttpOverrides.blocklist = list;
      }
      debugPrint('Dynamic hot-config loaded successfully.');
    }
  } catch (e) {
    debugPrint('Failed to load hot-config: $e. Using local cached configuration.');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  // Load cached hot-config blocklist if available
  try {
    final prefs = await SharedPreferences.getInstance();
    final cachedBlocklist = prefs.getStringList('dns_proxy_blocklist');
    if (cachedBlocklist != null) {
      MyHttpOverrides.blocklist = cachedBlocklist;
    }
  } catch (_) {}

  // Asynchronously fetch latest configurations (runs in parallel to not delay launch)
  fetchHotConfig();

  // Start Custom DNS local proxy to resolve DNS blocks via DoH
  final dnsProxy = CustomDnsProxy();
  await dnsProxy.start();
  if (dnsProxy.port != null) {
    HttpOverrides.global = MyHttpOverrides(dnsProxy.port!);
  }

  
  // Set system bar styling and lock to portrait mode
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.background,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  // Load saved theme from SharedPreferences
  try {
    final prefs = await SharedPreferences.getInstance();
    final themeIndex = prefs.getInt('theme_index') ?? 0;
    if (themeIndex >= 0 && themeIndex < CinemaTheme.values.length) {
      ThemeManager.setTheme(CinemaTheme.values[themeIndex]);
    }
  } catch (e) {
    debugPrint('Error loading saved theme: $e');
  }

  // Initialize downloads manager
  try {
    await DownloadManager.init();
  } catch (e) {
    debugPrint('Error initializing DownloadManager: $e');
  }

  // Hook up Telegram credentials to the admin-pushed values so
  // TelegramService.init() can find them on first use.
  TelegramService.registerRemoteCredentialsProvider(() async {
    try {
      final cfg = await SyncService.fetchTelegramConfig();
      if (cfg.apiId == null || cfg.apiHash == null) return null;
      return TelegramCredentials(
          apiId: cfg.apiId!, apiHash: cfg.apiHash!);
    } catch (_) {
      return null;
    }
  });

  // Restore Telegram session and refresh index in the background so that
  // Settings shows "Connected" immediately on every app open without blocking
  // the main UI thread.
  unawaited(_telegramStartup());

  runApp(const PrivateCinemaMobileApp());
}

/// Restores the Telegram session and refreshes the saved-messages index in
/// the background.  Runs as a fire-and-forget from [main] so it never blocks
/// the initial frame render.
Future<void> _telegramStartup() async {
  try {
    await TelegramService.instance.init();
    if (TelegramService.instance.status.value == TelegramStatus.ready) {
      // Silently refresh the index so it's always up-to-date on every launch.
      await TelegramService.instance.loadSavedMessages(limit: 200);
    }
  } catch (e) {
    debugPrint('Telegram startup error: $e');
  }
}


class PrivateCinemaMobileApp extends StatelessWidget {
  const PrivateCinemaMobileApp({super.key});


  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CinemaTheme>(
      valueListenable: ThemeManager.notifier,
      builder: (context, currentTheme, _) {
        return MaterialApp(
          title: 'GoXio',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: Brightness.dark,
            primaryColor: currentTheme.accent,
            scaffoldBackgroundColor: AppColors.background,
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.transparent,
              elevation: 0,
            ),
            colorScheme: ColorScheme.fromSeed(
              seedColor: currentTheme.accent,
              brightness: Brightness.dark,
            ),
          ),
          home: const NavigationHolder(),
        );
      },
    );
  }
}
