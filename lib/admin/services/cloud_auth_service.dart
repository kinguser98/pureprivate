import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/cloud_account_model.dart';

class CloudAuthService {
  static const String _storageKey = 'goxio_cloud_accounts_v1';
  static const String _defaultExecutionModeKey = 'goxio_download_exec_mode';

  // Microsoft OAuth App Constants (Standard common multi-tenant Azure App)
  static const String msClientId = '9e034e32-2d1d-40cf-b6a9-46747b01d36d'; // Sample public client / configurable
  static const String msRedirectUri = 'https://login.microsoftonline.com/common/oauth2/nativeclient';
  
  // Google OAuth App Constants
  static const String googleClientId = '407408718192.apps.googleusercontent.com'; // Standard GDrive Web/Installed Client

  static Future<List<CloudAccount>> getAccounts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => CloudAccount.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('CloudAuthService.getAccounts error: $e');
      return [];
    }
  }

  static Future<void> saveAccounts(List<CloudAccount> accounts) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode(accounts.map((e) => e.toJson()).toList());
      await prefs.setString(_storageKey, raw);
    } catch (e) {
      debugPrint('CloudAuthService.saveAccounts error: $e');
    }
  }

  static Future<void> addOrUpdateAccount(CloudAccount account) async {
    final accounts = await getAccounts();
    final index = accounts.indexWhere((a) => a.id == account.id);
    if (index >= 0) {
      accounts[index] = account;
    } else {
      accounts.add(account);
    }
    await saveAccounts(accounts);
  }

  static Future<void> removeAccount(String accountId) async {
    final accounts = await getAccounts();
    accounts.removeWhere((a) => a.id == accountId);
    await saveAccounts(accounts);
  }

  static const String _serverWorkerUrlKey = 'goxio_server_worker_url';

  static Future<String> getExecutionMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_defaultExecutionModeKey) ?? 'client'; // 'client' or 'server'
  }

  static Future<void> setExecutionMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_defaultExecutionModeKey, mode);
  }

  static Future<String?> getServerWorkerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_serverWorkerUrlKey);
  }

  static Future<void> setServerWorkerUrl(String? url) async {
    final prefs = await SharedPreferences.getInstance();
    if (url == null || url.trim().isEmpty) {
      await prefs.remove(_serverWorkerUrlKey);
    } else {
      await prefs.setString(_serverWorkerUrlKey, url.trim());
    }
  }

  // --- OneDrive (Personal & Business) OAuth Helpers ---

  static String getOneDriveAuthUrl({required bool isBusiness, String? customTenant, String? customClientId}) {
    final tenant = isBusiness ? (customTenant ?? 'organizations') : 'consumers';
    final clientId = customClientId ?? msClientId;
    final scopes = Uri.encodeComponent('Files.ReadWrite.All offline_access User.Read');
    final redirect = Uri.encodeComponent(msRedirectUri);
    return 'https://login.microsoftonline.com/$tenant/oauth2/v2.0/authorize?'
        'client_id=$clientId&response_type=code&redirect_uri=$redirect'
        '&response_mode=query&scope=$scopes&prompt=select_account';
  }

  static Future<CloudAccount?> handleOneDriveAuthCode({
    required String code,
    required bool isBusiness,
    String? customTenant,
    String? customClientId,
  }) async {
    final tenant = isBusiness ? (customTenant ?? 'organizations') : 'consumers';
    final clientId = customClientId ?? msClientId;
    final url = Uri.parse('https://login.microsoftonline.com/$tenant/oauth2/v2.0/token');

    try {
      final res = await http.post(
        url,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'client_id': clientId,
          'grant_type': 'authorization_code',
          'code': code,
          'redirect_uri': msRedirectUri,
        },
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final accessToken = data['access_token'] as String;
        final refreshToken = data['refresh_token'] as String?;
        final expiresIn = data['expires_in'] as int? ?? 3600;
        final expiryMs = DateTime.now().millisecondsSinceEpoch + (expiresIn * 1000);

        // Fetch User profile & drive info from MS Graph
        final profileRes = await http.get(
          Uri.parse('https://graph.microsoft.com/v1.0/me'),
          headers: {'Authorization': 'Bearer $accessToken'},
        );

        String email = '';
        String displayName = isBusiness ? 'OneDrive Business' : 'OneDrive Personal';
        if (profileRes.statusCode == 200) {
          final profileData = jsonDecode(profileRes.body) as Map<String, dynamic>;
          email = profileData['userPrincipalName'] ?? profileData['mail'] ?? '';
          displayName = profileData['displayName'] ?? displayName;
        }

        // Fetch Drive quota
        int? totalStorage;
        int? usedStorage;
        try {
          final driveRes = await http.get(
            Uri.parse('https://graph.microsoft.com/v1.0/me/drive'),
            headers: {'Authorization': 'Bearer $accessToken'},
          );
          if (driveRes.statusCode == 200) {
            final driveData = jsonDecode(driveRes.body) as Map<String, dynamic>;
            final quota = driveData['quota'] as Map<String, dynamic>?;
            if (quota != null) {
              totalStorage = quota['total'] as int?;
              usedStorage = quota['used'] as int?;
            }
          }
        } catch (_) {}

        final id = 'onedrive_${DateTime.now().millisecondsSinceEpoch}';
        final account = CloudAccount(
          id: id,
          provider: isBusiness ? CloudProvider.onedriveBusiness : CloudProvider.onedrivePersonal,
          accountName: displayName,
          email: email,
          accessToken: accessToken,
          refreshToken: refreshToken,
          tokenExpiryMs: expiryMs,
          tenantId: tenant,
          totalStorageBytes: totalStorage,
          usedStorageBytes: usedStorage,
          connectedAt: DateTime.now(),
        );

        await addOrUpdateAccount(account);
        return account;
      }
    } catch (e) {
      debugPrint('handleOneDriveAuthCode error: $e');
    }
    return null;
  }

  static Future<String?> refreshOneDriveToken(CloudAccount account) async {
    if (account.refreshToken == null) return account.accessToken;
    final tenant = account.tenantId ?? (account.provider == CloudProvider.onedriveBusiness ? 'organizations' : 'consumers');
    final url = Uri.parse('https://login.microsoftonline.com/$tenant/oauth2/v2.0/token');

    try {
      final res = await http.post(
        url,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'client_id': msClientId,
          'grant_type': 'refresh_token',
          'refresh_token': account.refreshToken!,
          'redirect_uri': msRedirectUri,
        },
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final newAccessToken = data['access_token'] as String;
        final newRefreshToken = data['refresh_token'] as String? ?? account.refreshToken;
        final expiresIn = data['expires_in'] as int? ?? 3600;
        final newExpiryMs = DateTime.now().millisecondsSinceEpoch + (expiresIn * 1000);

        final updated = account.copyWith(
          accessToken: newAccessToken,
          refreshToken: newRefreshToken,
          tokenExpiryMs: newExpiryMs,
        );
        await addOrUpdateAccount(updated);
        return newAccessToken;
      }
    } catch (e) {
      debugPrint('refreshOneDriveToken error: $e');
    }
    return account.accessToken;
  }

  // --- Google Drive OAuth & Direct Auth Helpers ---

  static String getGoogleDriveAuthUrl() {
    final scopes = Uri.encodeComponent('https://www.googleapis.com/auth/drive.file email profile');
    final redirect = Uri.encodeComponent('urn:ietf:wg:oauth:2.0:oob');
    return 'https://accounts.google.com/o/oauth2/v2/auth?'
        'client_id=$googleClientId&response_type=code&redirect_uri=$redirect'
        '&scope=$scopes&access_type=offline&prompt=consent';
  }

  static Future<CloudAccount?> connectGoogleDriveManual({
    required String accountName,
    required String email,
    required String accessToken,
    String? refreshToken,
  }) async {
    final id = 'gdrive_${DateTime.now().millisecondsSinceEpoch}';
    final account = CloudAccount(
      id: id,
      provider: CloudProvider.gdrive,
      accountName: accountName.isNotEmpty ? accountName : 'Google Drive ($email)',
      email: email,
      accessToken: accessToken,
      refreshToken: refreshToken,
      connectedAt: DateTime.now(),
    );
    await addOrUpdateAccount(account);
    return account;
  }

  // --- Telegram Account / Bot Connect ---

  static Future<CloudAccount?> connectTelegramBot({
    required String botToken,
    required String chatId,
    String? accountName,
  }) async {
    try {
      final res = await http.get(Uri.parse('https://api.telegram.org/bot$botToken/getMe'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final botInfo = data['result'] as Map<String, dynamic>;
        final botUsername = botInfo['username'] ?? 'Telegram Bot';
        final id = 'tg_bot_${DateTime.now().millisecondsSinceEpoch}';

        final account = CloudAccount(
          id: id,
          provider: CloudProvider.telegramBot,
          accountName: accountName?.isNotEmpty == true ? accountName! : '@$botUsername',
          email: 'Chat ID: $chatId',
          telegramBotToken: botToken,
          telegramChatId: chatId,
          connectedAt: DateTime.now(),
        );

        await addOrUpdateAccount(account);
        return account;
      }
    } catch (e) {
      debugPrint('connectTelegramBot error: $e');
    }
    return null;
  }

  static Future<CloudAccount?> connectTelegramUser({
    required String accountName,
    required String phoneOrUsername,
    String? sessionData,
  }) async {
    final id = 'tg_user_${DateTime.now().millisecondsSinceEpoch}';
    final account = CloudAccount(
      id: id,
      provider: CloudProvider.telegramMtproto,
      accountName: accountName.isNotEmpty ? accountName : 'Telegram ($phoneOrUsername)',
      email: phoneOrUsername,
      telegramChatId: 'me', // Saved Messages
      connectedAt: DateTime.now(),
    );
    await addOrUpdateAccount(account);
    return account;
  }
}
