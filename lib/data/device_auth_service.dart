import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Enum representing the approval status of this device.
enum DeviceStatus { pending, approved, denied, unknown }

/// Service that registers this device with the admin backend and checks
/// whether access has been granted. No username/password — the device
/// fingerprint (SHA-256) is the identity.
class DeviceAuthService {
  static const String _baseUrl = 'https://ot.goprivate.fun/api/device_auth.php';
  static const String _prefsCacheKey = 'device_auth_status';
  static const String _prefsDeviceIdKey = 'device_auth_device_id';

  // ─── Platform channel to retrieve native device identifiers ──────────────
  // Android: Settings.Secure.ANDROID_ID
  // iOS:     UIDevice.identifierForVendor
  static const MethodChannel _channel = MethodChannel('com.goxio.mobile/device_id');

  // ─── Public API ────────────────────────────────────────────────────────────

  /// Returns the stable SHA-256 device fingerprint.
  static Future<String> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_prefsDeviceIdKey);
    if (cached != null && cached.length == 64) return cached;

    final rawId = await _getRawNativeId();
    final suffix = Platform.isIOS ? '_ios' : '_android';
    final hashed = sha256.convert(utf8.encode('goxio$rawId$suffix')).toString();
    await prefs.setString(_prefsDeviceIdKey, hashed);
    return hashed;
  }

  /// Called on every app launch.
  /// 1. Tries to register / update device info on the server.
  /// 2. Returns the approval [DeviceStatus].
  /// Falls back to cached status if the server is unreachable.
  static Future<DeviceStatus> checkAccess({String? lastContent}) async {
    try {
      final deviceId = await getDeviceId();
      final info = await _getDeviceInfo();

      // Register / update on backend
      final response = await http.post(
        Uri.parse('$_baseUrl?action=register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'device_id'   : deviceId,
          'platform'    : Platform.isIOS ? 'ios' : 'android',
          'device_name' : info['device_name'],
          'device_model': info['device_model'],
          'android_ver' : info['android_ver'],
          'app_version' : '1.0.0',
        }),
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final status = _parseStatus(body['status'] as String?);
        await _cacheStatus(status);
        return status;
      }
    } catch (e) {
      debugPrint('[DeviceAuth] Server unreachable: $e — using cached status');
    }

    // Fallback to cached value
    return await _cachedStatus();
  }

  /// Periodic heartbeat — call every ~5 minutes while app is open.
  /// Returns the latest status so the app can react if access is revoked.
  /// Set [incrementWatched] = true once when a movie finishes to count it.
  static Future<DeviceStatus> heartbeat({
    String? lastContent,
    bool incrementWatched = false,
  }) async {
    try {
      final deviceId = await getDeviceId();
      final response = await http.post(
        Uri.parse('$_baseUrl?action=heartbeat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'device_id'        : deviceId,
          'last_content'     : lastContent ?? '',
          if (incrementWatched) 'increment_watched': true,
        }),
      ).timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        return _parseStatus(body['status'] as String?);
      }
    } catch (_) {}
    return await _cachedStatus();
  }

  /// Call this once when playback reaches >= 95% to increment the
  /// movies-watched counter on the backend for this device.
  static Future<void> reportWatched(String contentTitle) async {
    await heartbeat(lastContent: contentTitle, incrementWatched: true);
  }

  // ─── Internals ─────────────────────────────────────────────────────────────

  /// Retrieves the raw native device identifier via platform channel.
  static Future<String> _getRawNativeId() async {
    try {
      final id = await _channel.invokeMethod<String>('getDeviceId');
      if (id != null && id.isNotEmpty) return id;
    } catch (e) {
      debugPrint('[DeviceAuth] Platform channel error: $e');
    }
    // Fallback: generate and persist a random UUID-like string
    final prefs = await SharedPreferences.getInstance();
    var fallback = prefs.getString('__device_raw_id');
    if (fallback == null) {
      fallback = DateTime.now().millisecondsSinceEpoch.toString() +
          Random.secure().nextInt(0xffffff).toString();
      await prefs.setString('__device_raw_id', fallback);
    }
    return fallback;
  }

  /// Reads device name/model/version from platform channel.
  static Future<Map<String, String>> _getDeviceInfo() async {
    try {
      final info = await _channel.invokeMapMethod<String, String>('getDeviceInfo');
      return info ?? {};
    } catch (_) {}
    return {};
  }

  static DeviceStatus _parseStatus(String? s) {
    return switch (s) {
      'approved' => DeviceStatus.approved,
      'pending'  => DeviceStatus.pending,
      'denied'   => DeviceStatus.denied,
      _          => DeviceStatus.unknown,
    };
  }

  static Future<void> _cacheStatus(DeviceStatus status) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsCacheKey, status.name);
  }

  static Future<DeviceStatus> _cachedStatus() async {
    final prefs = await SharedPreferences.getInstance();
    return _parseStatus(prefs.getString(_prefsCacheKey));
  }
}
