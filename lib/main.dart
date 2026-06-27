import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:private_cinema_mobile/data/dns_proxy.dart';
import 'package:private_cinema_mobile/data/download_manager.dart';
import 'package:private_cinema_mobile/screens/navigation_holder.dart';
import 'package:private_cinema_mobile/theme/app_colors.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

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
