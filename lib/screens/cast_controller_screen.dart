import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:private_cinema_mobile/theme/app_colors.dart';
import 'package:private_cinema_mobile/data/wifi_cast_service.dart';

class CastControllerScreen extends StatelessWidget {
  const CastControllerScreen({
    super.key,
    required this.title,
    required this.proxyUrl,
  });

  final String title;
  final String proxyUrl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Casting Icon Indicator
              Center(
                child: Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.accent.withOpacity(0.12),
                  ),
                  child: Icon(
                    Icons.cell_tower_rounded,
                    color: AppColors.accentBright,
                    size: 64,
                  ),
                ),
              ),
              const SizedBox(height: 36),
              
              // Casting Text Info
              Text(
                'Casting to TV App',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              
              // Proxy URL
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                child: Text(
                  'Local Proxy IP: $proxyUrl',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white30,
                    fontSize: 11.5,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(height: 48),

              // Casting tips
              const Text(
                'Keep this app running. Your TV is streaming the movie directly from your mobile data link.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 6),
              const Text(
                'You can minimize the app or lock the screen. Playback will continue in the background.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white24, fontSize: 12, height: 1.4),
              ),
              const Spacer(),

              // Stop casting button
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  await WifiCastService.stopProxyServer();
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                },
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.cast_connected_rounded, color: Colors.white),
                    SizedBox(width: 10),
                    Text(
                      'Stop Casting & Close Stream',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
