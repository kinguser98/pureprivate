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

  
  // Set system bar styling
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

  runApp(const PrivateCinemaMobileApp());
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
