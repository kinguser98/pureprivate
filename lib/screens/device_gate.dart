import 'dart:async';
import 'package:flutter/material.dart';
import 'package:private_cinema_mobile/data/device_auth_service.dart';
import 'package:private_cinema_mobile/screens/device_access_screen.dart';
import 'package:private_cinema_mobile/screens/navigation_holder.dart';

/// Wraps the app root. On first frame it checks device approval status
/// and routes to the correct screen (home / pending / denied).
/// After approval, sends a heartbeat every 5 minutes.
class DeviceGate extends StatefulWidget {
  const DeviceGate({super.key});

  @override
  State<DeviceGate> createState() => _DeviceGateState();
}

class _DeviceGateState extends State<DeviceGate> {
  DeviceStatus? _status;
  Timer? _heartbeatTimer;

  @override
  void initState() {
    super.initState();
    _checkAccess();
  }

  Future<void> _checkAccess() async {
    final status = await DeviceAuthService.checkAccess();
    if (!mounted) return;
    setState(() => _status = status);

    if (status == DeviceStatus.approved) {
      // Start heartbeat every 5 minutes
      _heartbeatTimer?.cancel();
      _heartbeatTimer = Timer.periodic(const Duration(minutes: 5), (_) async {
        final latest = await DeviceAuthService.heartbeat();
        if (latest == DeviceStatus.denied && mounted) {
          // Revoked mid-session — show denied screen immediately
          _heartbeatTimer?.cancel();
          setState(() => _status = DeviceStatus.denied);
        }
      });
    }
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // While checking: show a minimal branded splash
    if (_status == null) return const _SplashLoader();

    return switch (_status!) {
      DeviceStatus.approved => const NavigationHolder(),
      DeviceStatus.pending  => const PendingApprovalScreen(),
      DeviceStatus.denied   => const DeniedScreen(),
      DeviceStatus.unknown  => const PendingApprovalScreen(), // treat unknown as pending
    };
  }
}

/// Minimal loading splash shown during the initial auth check.
class _SplashLoader extends StatelessWidget {
  const _SplashLoader();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF080808),
      body: Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation(Color(0xFFEF4444)),
          ),
        ),
      ),
    );
  }
}
