import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:private_cinema_ios/theme/app_colors.dart';

class SeedrCountdownDialog extends StatefulWidget {
  final String title;
  final int maxSeconds;

  const SeedrCountdownDialog({
    super.key,
    required this.title,
    this.maxSeconds = 30,
  });

  @override
  State<SeedrCountdownDialog> createState() => _SeedrCountdownDialogState();
}

class _SeedrCountdownDialogState extends State<SeedrCountdownDialog> {
  int _secondsLeft = 30;
  int _messageIndex = 0;
  Timer? _timer;

  final List<String> _loadingMessages = [
    'Clearing existing files from Seedr...',
    'Connecting to Seedr cloud servers...',
    'Adding torrent to cloud storage...',
    'Downloading torrent pieces...',
    'Waiting for CDN distribution...',
    'Finalizing cloud transfer...',
  ];

  @override
  void initState() {
    super.initState();
    _secondsLeft = widget.maxSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (mounted) {
        setState(() {
          if (_secondsLeft > 0) _secondsLeft--;
        });
      }
    });
    // Rotate messages
    Timer.periodic(const Duration(milliseconds: 1500), (t) {
      if (mounted) {
        setState(() {
          _messageIndex = (_messageIndex + 1) % _loadingMessages.length;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withOpacity(0.06),
                  Colors.white.withOpacity(0.02),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.12), width: 1.5),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 32, spreadRadius: -8),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(alignment: Alignment.center, children: [
                  SizedBox(
                    width: 68, height: 68,
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.accentBright),
                      strokeWidth: 3,
                      backgroundColor: Colors.white10,
                    ),
                  ),
                  Icon(Icons.cloud_download_rounded, color: AppColors.accentBright.withOpacity(0.8), size: 32),
                ]),
                const SizedBox(height: 20),
                Text(widget.title, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.accentBright.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Text('$_secondsLeft s',
                    style: GoogleFonts.outfit(color: AppColors.accentBright, fontSize: 22, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 12),
                Text('Downloading via Seedr...',
                  style: GoogleFonts.outfit(color: Colors.white54, fontSize: 11, fontStyle: FontStyle.italic)),
                const SizedBox(height: 10),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(_loadingMessages[_messageIndex],
                    key: ValueKey<int>(_messageIndex),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white38, fontSize: 12, fontStyle: FontStyle.italic)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
