import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:private_cinema_mobile/data/device_auth_service.dart';
import 'package:private_cinema_mobile/screens/navigation_holder.dart';

class PendingApprovalScreen extends StatefulWidget {
  const PendingApprovalScreen({super.key});

  @override
  State<PendingApprovalScreen> createState() => _PendingApprovalScreenState();
}

class _PendingApprovalScreenState extends State<PendingApprovalScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late AnimationController _fadeCtrl;
  late Animation<double> _pulse;
  late Animation<double> _fade;

  Timer? _pollTimer;
  bool _checking = false;
  String _deviceId = '';

  @override
  void initState() {
    super.initState();

    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))
      ..forward();

    _pulse = Tween(begin: 0.4, end: 1.0).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _fade = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);

    _loadDeviceId();
    // Poll every 15 seconds automatically
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) => _checkStatus());
  }

  Future<void> _loadDeviceId() async {
    final id = await DeviceAuthService.getDeviceId();
    if (mounted) {
      setState(() => _deviceId = id);
    }
  }

  Future<void> _checkStatus() async {
    if (_checking || !mounted) return;
    setState(() => _checking = true);
    final status = await DeviceAuthService.checkAccess();
    if (!mounted) return;
    setState(() => _checking = false);

    if (status == DeviceStatus.approved) {
      _pollTimer?.cancel();
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, _, _) => const NavigationHolder(),
          transitionsBuilder: (_, anim, _, child) =>
              FadeTransition(opacity: anim, child: child),
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    } else if (status == DeviceStatus.denied) {
      _pollTimer?.cancel();
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, _, _) => const DeniedScreen(),
          transitionsBuilder: (_, anim, _, child) =>
              FadeTransition(opacity: anim, child: child),
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _fadeCtrl.dispose();
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shortId = _deviceId.length >= 8
        ? _deviceId.substring(_deviceId.length - 8).toUpperCase()
        : '…';

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF080808),
        body: FadeTransition(
          opacity: _fade,
          child: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Animated waiting orb
                    AnimatedBuilder(
                      animation: _pulse,
                      builder: (_, _) => Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Color(0xFFEF4444).withValues(alpha: _pulse.value * 0.5),
                              blurRadius: 60,
                              spreadRadius: 10,
                            ),
                          ],
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                const Color(0xFFEF4444).withValues(alpha: _pulse.value),
                                const Color(0xFF991B1B).withValues(alpha: 0.3),
                                Colors.transparent,
                              ],
                            ),
                          ),
                          child: Icon(
                            Icons.shield_outlined,
                            size: 52,
                            color: Colors.white.withValues(alpha: _pulse.value),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                    Text(
                      'Awaiting Approval',
                      style: GoogleFonts.inter(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Your device has been registered. Please wait for the admin to approve your access.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: Colors.white54,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 32),
                    // Device ID chip
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(40),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.fingerprint, size: 16, color: Color(0xFFEF4444)),
                          const SizedBox(width: 8),
                          Text(
                            'Device ID: …$shortId',
                            style: GoogleFonts.robotoMono(
                              fontSize: 13,
                              color: Colors.white70,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),
                    // Auto-checking indicator
                    _checking
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Color(0xFFEF4444)),
                            ),
                          )
                        : const SizedBox(height: 24),
                    const SizedBox(height: 16),
                    // Manual retry button
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton.icon(
                        onPressed: _checking ? null : _checkStatus,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: Text(
                          'Check Now',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: const BorderSide(color: Colors.white24),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Checking automatically every 15 seconds',
                      style: GoogleFonts.inter(fontSize: 11, color: Colors.white24),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown when the admin has explicitly denied this device.
class DeniedScreen extends StatelessWidget {
  const DeniedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF080808),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                      border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3), width: 2),
                    ),
                    child: const Icon(Icons.block_rounded, size: 44, color: Color(0xFFEF4444)),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    'Access Revoked',
                    style: GoogleFonts.inter(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Your device no longer has access to this app. Contact the admin if you think this is a mistake.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(fontSize: 14, color: Colors.white54, height: 1.6),
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
