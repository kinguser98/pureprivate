import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';

class AdminApiClient {
  static Dio? _sharedDio;

  final Dio _dio;

  AdminApiClient() : _dio = _getDio();

  static Dio get sharedDio => _getDio();

  static Dio _getDio() {
    if (_sharedDio != null) return _sharedDio!;
    
    final d = Dio();
    d.options = BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      followRedirects: false,
      validateStatus: (status) => status != null && (status >= 200 && status < 400),
    );
    
    try { (d.httpClientAdapter as IOHttpClientAdapter).onHttpClientCreate = (client) { client.badCertificateCallback = (cert, host, port) => true; return client; }; } catch (_) {}
    
    d.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        options.headers['User-Agent'] = 'Mozilla/5.0 (Linux; Android 14; SM-S908E) AppleWebKit/537.36';
        final prefs = await SharedPreferences.getInstance();
        final phpsessid = prefs.getString('phpsessid');
        if (phpsessid != null) options.headers['Cookie'] = 'PHPSESSID=$phpsessid';
        return handler.next(options);
      },
      onResponse: (response, handler) async {
        _saveCookie(response.headers);
        return handler.next(response);
      },
      onError: (error, handler) async {
        if (error.response != null) {
          _saveCookie(error.response!.headers);
        }
        return handler.next(error);
      },
    ));
    
    _sharedDio = d;
    return d;
  }

  static void _saveCookie(Headers headers) async {
    final setCookies = headers['set-cookie'];
    if (setCookies != null) {
      for (final header in setCookies) {
        final match = RegExp(r'PHPSESSID=([^;]+)').firstMatch(header);
        if (match != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('phpsessid', match.group(1)!);
          break;
        }
      }
    }
  }

  bool _isAuthRedirect(Headers headers, int? statusCode) {
    if (statusCode == 302 || statusCode == 301) {
      final location = headers.value('location') ?? '';
      if (location.contains('login.php')) {
        return true;
      }
    }
    return false;
  }

  String _extractMessage(String html) {
    if (html.contains('Movie Added Successfully') || html.contains('✅')) return 'Success';
    if (html.contains('Error') || html.contains('❌')) {
      final errorMatch = RegExp(r'❌\s*([^<.]+)').firstMatch(html);
      if (errorMatch != null) return errorMatch.group(1)?.trim() ?? 'Error occurred';
    }
    final patterns = [
      RegExp(r'class="[^"]*success[^"]*"[^>]*>([^<]+)'),
      RegExp(r'class="[^"]*error[^"]*"[^>]*>([^<]+)'),
    ];
    for (final p in patterns) {
      final match = p.firstMatch(html);
      if (match != null) return match.group(1)?.trim() ?? '';
    }
    return html.contains('Success') ? 'Success' : 'Operation completed';
  }

  Future<Map<String, dynamic>> addMovie(Map<String, dynamic> data) async {
    try {
      final response = await _dio.post(ApiConfig.addMovie, data: FormData.fromMap(data));
      if (_isAuthRedirect(response.headers, response.statusCode)) {
        return {'success': false, 'message': 'Session expired. Please log out and sign in again.'};
      }
      final html = response.data.toString();
      if (html.contains('Movie Added Successfully') || html.contains('✅')) {
        return {'success': true, 'message': 'Movie added to library'};
      }
      final msg = _extractMessage(html);
      return {'success': msg == 'Success', 'message': msg};
    } on DioException catch (e) {
      if (e.response != null && _isAuthRedirect(e.response!.headers, e.response!.statusCode)) {
        return {'success': false, 'message': 'Session expired. Please log out and sign in again.'};
      }
      return {'success': false, 'message': _extractMessage(e.response?.data ?? '')};
    }
  }

  Future<Map<String, dynamic>> updateMovie(int id, Map<String, dynamic> data) async {
    try {
      data['id'] = id.toString();
      final response = await _dio.post('${ApiConfig.editMovie}?id=$id', data: FormData.fromMap(data));
      if (_isAuthRedirect(response.headers, response.statusCode)) {
        return {'success': false, 'message': 'Session expired. Please log out and sign in again.'};
      }
      final html = response.data.toString();
      if (html.contains('Success') || html.contains('✅') || html.contains('Updated')) {
        return {'success': true, 'message': 'Movie updated'};
      }
      return {'success': false, 'message': _extractMessage(html)};
    } on DioException catch (e) {
      if (e.response != null && _isAuthRedirect(e.response!.headers, e.response!.statusCode)) {
        return {'success': false, 'message': 'Session expired. Please log out and sign in again.'};
      }
      return {'success': false, 'message': _extractMessage(e.response?.data ?? '')};
    }
  }

  Future<Map<String, dynamic>> deleteMovie(int id) async {
    try {
      final response = await _dio.get('${ApiConfig.viewAllMovies}?delete=$id');
      if (_isAuthRedirect(response.headers, response.statusCode)) {
        return {'success': false, 'message': 'Session expired. Please log out and sign in again.'};
      }
      return {'success': true, 'message': 'Movie deleted successfully'};
    } on DioException catch (e) {
      if (e.response != null && _isAuthRedirect(e.response!.headers, e.response!.statusCode)) {
        return {'success': false, 'message': 'Session expired. Please log out and sign in again.'};
      }
      return {'success': false, 'message': _extractMessage(e.response?.data ?? '')};
    } catch (e) {
      return {'success': false, 'message': 'Failed to delete movie: $e'};
    }
  }


  Future<Map<String, dynamic>> addLanguage(String name, String imageUrl) async {
    try {
      final response = await _dio.post(ApiConfig.languages, data: FormData.fromMap({'name': name, 'image_url': imageUrl}));
      if (_isAuthRedirect(response.headers, response.statusCode)) {
        return {'success': false, 'message': 'Session expired. Please log out and sign in again.'};
      }
      return {'success': response.data.toString().contains('success'), 'message': 'Language added'};
    } on DioException catch (e) {
      if (e.response != null && _isAuthRedirect(e.response!.headers, e.response!.statusCode)) {
        return {'success': false, 'message': 'Session expired. Please log out and sign in again.'};
      }
      return {'success': false, 'message': _extractMessage(e.response?.data ?? '')};
    }
  }

  Future<Map<String, dynamic>> updateLanguage(int id, String name, String imageUrl) async {
    try {
      final response = await _dio.post(ApiConfig.languages, data: FormData.fromMap({'id': id.toString(), 'name': name, 'image_url': imageUrl}));
      if (_isAuthRedirect(response.headers, response.statusCode)) {
        return {'success': false, 'message': 'Session expired. Please log out and sign in again.'};
      }
      return {'success': response.data.toString().contains('success'), 'message': 'Language updated'};
    } on DioException catch (e) {
      if (e.response != null && _isAuthRedirect(e.response!.headers, e.response!.statusCode)) {
        return {'success': false, 'message': 'Session expired. Please log out and sign in again.'};
      }
      return {'success': false, 'message': _extractMessage(e.response?.data ?? '')};
    }
  }

  Future<Map<String, dynamic>> deleteLanguage(int id) async {
    try { await _dio.get('${ApiConfig.languages}?delete=$id'); return {'success': true, 'message': 'Language deleted'}; } catch (_) { return {'success': true, 'message': 'Language deleted'}; }
  }

  Future<Map<String, dynamic>> savePortal(Map<String, dynamic> data) async {
    try {
      final response = await _dio.post(ApiConfig.iptvSettings, data: FormData.fromMap(data));
      if (_isAuthRedirect(response.headers, response.statusCode)) {
        return {'success': false, 'message': 'Session expired. Please log out and sign in again.'};
      }
      return {'success': response.data.toString().contains('success'), 'message': 'Portal saved'};
    } on DioException catch (e) {
      if (e.response != null && _isAuthRedirect(e.response!.headers, e.response!.statusCode)) {
        return {'success': false, 'message': 'Session expired. Please log out and sign in again.'};
      }
      return {'success': false, 'message': _extractMessage(e.response?.data ?? '')};
    }
  }

  Future<Map<String, dynamic>> deletePortal(int id) async {
    try { await _dio.get('${ApiConfig.iptvSettings}?delete=$id'); return {'success': true, 'message': 'Portal deleted'}; } catch (_) { return {'success': true, 'message': 'Portal deleted'}; }
  }

  Future<Map<String, dynamic>> deleteChannel(int channelId) async {
    try {
      final response = await _dio.get('/api.php?action=delete_channel&id=$channelId');
      return {'success': true, 'message': 'Channel deleted'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> deleteCategory(String categoryName, int portalId) async {
    try {
      final response = await _dio.get('/api.php?action=delete_category&category=${Uri.encodeComponent(categoryName)}&portal_id=$portalId');
      return {'success': true, 'message': 'Category deleted'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> testPortal(String portalUrl, String macAddress) async {
    try {
      final response = await _dio.get('${ApiConfig.iptvSettings}?test=1&portal_url=$portalUrl&mac_address=$macAddress');
      final data = response.data;
      if (data is Map) {
        return {
          'success': data['success'] == true,
          'message': data['message'] ?? (data['success'] == true ? 'Connection successful' : 'Connection failed')
        };
      }
      final html = response.data.toString();
      return {
        'success': html.contains('success') || html.contains('Handshake') || html.contains('Successfully'),
        'message': html.contains('success') || html.contains('Successfully') ? 'Connection successful' : 'Connection failed'
      };
    } catch (e) { return {'success': false, 'message': 'Connection failed: $e'}; }
  }

  Future<Map<String, dynamic>> saveOttProvider(String name, String logoUrl, {int? id}) async {
    try {
      final response = await _dio.post(
        ApiConfig.ottProviders,
        queryParameters: {'api': '1'},
        data: FormData.fromMap(id != null
            ? {'action': 'edit', 'id': id.toString(), 'name': name, 'logo_url': logoUrl}
            : {'action': 'add', 'name': name, 'logo_url': logoUrl}),
      );
      if (response.data is Map) {
        return Map<String, dynamic>.from(response.data);
      }
      return {'success': true, 'message': 'Provider saved'};
    } catch (e) {
      return {'success': false, 'message': 'Failed to save provider: $e'};
    }
  }

  Future<Map<String, dynamic>> deleteOttProvider(int id) async {
    try {
      final response = await _dio.post(
        ApiConfig.ottProviders,
        queryParameters: {'api': '1'},
        data: FormData.fromMap({'action': 'delete', 'id': id.toString()}),
      );
      if (response.data is Map) {
        return Map<String, dynamic>.from(response.data);
      }
      return {'success': true, 'message': 'Provider deleted'};
    } catch (e) {
      return {'success': false, 'message': 'Failed to delete provider: $e'};
    }
  }

  Future<String?> uploadLogoFile(List<int> bytes, String filename) async {
    try {
      final formData = FormData.fromMap({
        'action': 'upload_logo',
        'logo_file': MultipartFile.fromBytes(bytes, filename: filename),
      });
      final response = await _dio.post('/api.php?action=upload_logo', data: formData);
      if (response.data != null && response.data is Map && response.data['url'] != null) {
        return response.data['url'].toString();
      }
    } catch (e) {
      debugPrint('Logo upload error: $e');
    }
    return null;
  }

  Future<String?> uploadLogoFromUrl(String remoteUrl) async {
    if (remoteUrl.isEmpty || remoteUrl.contains('ott.redapp.space')) {
      return remoteUrl;
    }
    try {
      final res = await Dio().get<List<int>>(remoteUrl, options: Options(responseType: ResponseType.bytes)).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200 && res.data != null && res.data!.isNotEmpty) {
        final ext = remoteUrl.contains('.png') ? 'png' : (remoteUrl.contains('.webp') ? 'webp' : 'jpg');
        final fileName = 'logo_${DateTime.now().millisecondsSinceEpoch}.$ext';
        final uploaded = await uploadLogoFile(res.data!, fileName);
        if (uploaded != null && uploaded.isNotEmpty) {
          return uploaded;
        }
      }
    } catch (e) {
      debugPrint('Upload logo from URL error: $e');
    }
    return remoteUrl;
  }


  Future<Map<String, dynamic>> bulkUpdate(String find, String replace, bool dryRun) async {
    try {
      final response = await _dio.post(ApiConfig.bulkUpdater, data: FormData.fromMap({'find': find, 'replace': replace, if (dryRun) 'dry_run': 'on'}));
      return {'success': true, 'message': dryRun ? 'Dry run completed' : 'Update completed', 'html': response.data.toString()};
    } on DioException catch (e) { return {'success': false, 'message': _extractMessage(e.response?.data ?? '')}; }
  }

  Future<List<Map<String, dynamic>>> getStalkerSettings() async {
    try {
      final response = await _dio.get(ApiConfig.stalkerSettings);
      final data = response.data;
      if (data is List) return data.cast<Map<String, dynamic>>();
      if (data is Map) return [data.cast<String, dynamic>()];
      return [];
    } catch (_) { return []; }
  }

  Future<List<Map<String, dynamic>>> getLanguages() async {
    try {
      final response = await _dio.get(ApiConfig.movies);
      final data = response.data;
      if (data is Map && data['languages'] is List) return (data['languages'] as List).cast<Map<String, dynamic>>();
      return [];
    } catch (_) { return []; }
  }

  Future<List<Map<String, dynamic>>> getOttProviders() async {
    try {
      final response = await _dio.get(ApiConfig.addMovie);
      final html = response.data.toString();
      final providers = <Map<String, dynamic>>[];
      // Find OTT select section and extract options
      final selectMatch = RegExp(r'<select[^>]*name="ott_id"[^>]*>(.*?)</select>', dotAll: true).firstMatch(html);
      if (selectMatch != null) {
        final selectContent = selectMatch.group(1) ?? '';
        for (final m in RegExp(r"""<option\s+value=['"](\d+)['"][^>]*>([^<]+)</option>""").allMatches(selectContent)) {
          final id = int.tryParse(m.group(1) ?? '');
          final name = m.group(2)?.trim() ?? '';
          if (id != null && name.isNotEmpty && !name.contains('Select') && !name.contains('--')) {
            providers.add({'id': id, 'name': name, 'logo_url': ''});
          }
        }
      }
      if (providers.isNotEmpty) return providers;
    } catch (_) {}
    return [{'id': 1, 'name': 'Netflix', 'logo_url': ''}, {'id': 2, 'name': 'Amazon Prime', 'logo_url': ''}];
  }

  Future<Map<String, dynamic>> updateAccount(String username, String currentPassword, {String? newPassword, String? confirmPassword}) async {
    try {
      final data = <String, dynamic>{'username': username, 'current_password': currentPassword};
      if (newPassword?.isNotEmpty == true) data['new_password'] = newPassword;
      if (confirmPassword?.isNotEmpty == true) data['confirm_password'] = confirmPassword;
      final response = await _dio.post(ApiConfig.accountSettings, data: FormData.fromMap(data));
      return {'success': response.statusCode == 302 || response.data.toString().contains('success'), 'message': 'Account updated'};
    } on DioException catch (e) {
      if (e.response?.statusCode == 302) return {'success': true, 'message': 'Account updated'};
      return {'success': false, 'message': _extractMessage(e.response?.data ?? '')};
    }
  }

  Future<Map<String, dynamic>> saveStreamtapeConfig(Map<String, dynamic> config) async {
    try {
      config['save_config'] = '1';
      final response = await _dio.post(
        ApiConfig.streamtapeManager,
        data: FormData.fromMap(config),
        queryParameters: {'api': '1'},
      );
      if (response.data is Map) {
        return Map<String, dynamic>.from(response.data);
      }
      return {'success': true, 'message': 'Config saved'};
    } catch (e) {
      return {'success': false, 'message': 'Failed to save config: $e'};
    }
  }

  Future<Map<String, dynamic>> triggerKeepalive() async {
    try {
      final response = await _dio.get(
        ApiConfig.streamtapeManager,
        queryParameters: {'trigger_keepalive': '1', 'api': '1'},
      );
      if (response.data is Map) {
        return Map<String, dynamic>.from(response.data);
      }
      return {'success': true, 'message': 'Keepalive triggered'};
    } catch (e) {
      return {'success': false, 'message': 'Failed to trigger keepalive: $e'};
    }
  }

  Future<Map<String, dynamic>> toggleChannel(int channelId, int status) async {
    try { await _dio.post('${ApiConfig.iptvChannels}?ajax_toggle=$channelId&status=$status'); return {'success': true, 'message': status == 1 ? 'Channel enabled' : 'Channel disabled'}; } catch (_) { return {'success': true, 'message': status == 1 ? 'Channel enabled' : 'Channel disabled'}; }
  }

  // Streamtape details fetching (config, account, cache stats, progress, logs)
  Future<Map<String, dynamic>> fetchStreamtapeDetails() async {
    try {
      final response = await _dio.get(ApiConfig.streamtapeManager);
      final dynamic data = response.data;
      
      // If it is already a decoded JSON map (e.g. from new JSON API)
      if (data is Map && (data['success'] == true || data.containsKey('config'))) {
        return Map<String, dynamic>.from(data);
      }
      
      // Fallback: parse original HTML structure
      final html = data.toString();
      
      String apiLogin = '';
      String apiKey = '';
      String touchPerRun = '5';
      String downloadBytes = '1048576';
      
      final loginMatch = RegExp(r'name="api_login"[^>]*value="([^"]*)"').firstMatch(html);
      if (loginMatch != null) apiLogin = loginMatch.group(1)!;

      final keyMatch = RegExp(r'name="api_key"[^>]*value="([^"]*)"').firstMatch(html);
      if (keyMatch != null) apiKey = keyMatch.group(1)!;

      final touchMatch = RegExp(r'name="touch_per_run"[^>]*value="([^"]*)"').firstMatch(html);
      if (touchMatch != null) touchPerRun = touchMatch.group(1)!;

      final bytesMatch = RegExp(r'name="download_bytes"[^>]*value="([^"]*)"').firstMatch(html);
      if (bytesMatch != null) downloadBytes = bytesMatch.group(1)!;
      
      String email = 'Not Configured';
      String signup = '';
      final emailMatch = RegExp(r'class="text-xl font-black text-white break-all"\s*>([^<]+)</h3>').firstMatch(html);
      if (emailMatch != null) {
        email = emailMatch.group(1)!.trim();
      } else {
        if (html.contains('Not Configured')) email = 'Not Configured';
      }

      final signupMatch = RegExp(r'Signed up:\s*([^<]+)</p>').firstMatch(html);
      if (signupMatch != null) signup = signupMatch.group(1)!.trim();
      
      int filesCount = 0;
      final countMatch = RegExp(r'Videos Monitored</p>\s*<h3 class="text-4xl font-black text-white">\s*([\d,]+)\s*</h3>').firstMatch(html);
      if (countMatch != null) {
        filesCount = int.tryParse(countMatch.group(1)!.replaceAll(',', '')) ?? 0;
      }
      
      int offset = 0;
      final offsetMatch = RegExp(r'Batch Offset</p>\s*<h3 class="text-4xl font-black text-green-400">\s*(\d+)').firstMatch(html);
      if (offsetMatch != null) offset = int.tryParse(offsetMatch.group(1)!) ?? 0;
      
      final logs = <Map<String, dynamic>>[];
      final logRows = RegExp(
        r'class="text-sm font-bold text-white truncate group-hover:text-red-500 transition">\s*([^<]+)\s*</p>',
        dotAll: true,
      ).allMatches(html).toList();
      
      final timePattern = RegExp(r'tracking-widest[^>]*>\s*([^<]+)\s*</p>');
      final statusPattern = RegExp(r'tracking-wider[^"]*">\s*([^<]+)\s*</span>');
      
      for (final lr in logRows) {
        final filename = lr.group(1)!.trim();
        final idx = html.indexOf(lr.group(0)!);
        if (idx != -1) {
          final searchSub = html.substring(idx, idx + 1000 > html.length ? html.length : idx + 1000);
          final timeM = timePattern.firstMatch(searchSub);
          final statusM = statusPattern.firstMatch(searchSub);
          
          if (timeM != null && statusM != null) {
            final time = timeM.group(1)!.trim();
            final status = statusM.group(1)!.trim();
            dynamic code = 200;
            if (status.contains('HTTP')) {
              code = int.tryParse(status.replaceAll(RegExp(r'[^\d]'), '')) ?? 200;
            } else {
              code = status;
            }
            logs.add({
              'time': time,
              'filename': filename,
              'code': code,
            });
          }
        }
      }
      
      return {
        'success': true,
        'config': {
          'api_login': apiLogin,
          'api_key': apiKey,
          'touch_per_run': touchPerRun,
          'download_bytes': downloadBytes,
        },
        'account': email != 'Not Configured' ? {
          'email': email,
          'signup_at': signup,
        } : null,
        'files_count': filesCount,
        'offset': offset,
        'logs': logs,
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // Legacy fallback
  Future<Map<String, String>> fetchStreamtapeConfig() async {
    final details = await fetchStreamtapeDetails();
    if (details['success'] == true && details['config'] is Map) {
      final config = details['config'] as Map;
      return {
        'api_login': config['api_login']?.toString() ?? '',
        'api_key': config['api_key']?.toString() ?? '',
        'touch_per_run': config['touch_per_run']?.toString() ?? '5',
        'download_bytes': config['download_bytes']?.toString() ?? '0',
      };
    }
    return {'api_login': '', 'api_key': '', 'touch_per_run': '5', 'download_bytes': '0'};
  }

  // Backup file listing
  Future<List<Map<String, String>>> fetchBackups() async {
    try {
      final response = await _dio.get(ApiConfig.backups);
      final dynamic data = response.data;
      
      if (data is List) {
        return data.map<Map<String, String>>((item) {
          final map = item as Map;
          return {
            'filename': map['filename']?.toString() ?? map['name']?.toString() ?? '',
            'date': map['date']?.toString() ?? '',
            'size': map['size']?.toString() ?? '',
          };
        }).toList();
      } else if (data is Map && data['backups'] is List) {
        final list = data['backups'] as List;
        return list.map<Map<String, String>>((item) {
          final map = item as Map;
          return {
            'filename': map['filename']?.toString() ?? map['name']?.toString() ?? '',
            'date': map['date']?.toString() ?? '',
            'size': map['size']?.toString() ?? '',
          };
        }).toList();
      }
      
      final html = data.toString();
      final backups = <Map<String, String>>[];
      
      final titlePattern = RegExp(r'class="text-sm font-bold text-white truncate[^"]*">\s*(backup_[^<]+)\s*</p>');
      final dateSizeRegex = RegExp(r'Ingested:\s*([^&]+)\s*&bull;\s*Size:\s*([^<\n\r]+)');
      
      final matches = titlePattern.allMatches(html).toList();
      for (final m in matches) {
        final filename = m.group(1)!.trim();
        final idx = html.indexOf(m.group(0)!);
        if (idx != -1) {
          final searchSub = html.substring(idx, idx + 1000 > html.length ? html.length : idx + 1000);
          final dsMatch = dateSizeRegex.firstMatch(searchSub);
          String date = '';
          String size = '';
          if (dsMatch != null) {
            date = dsMatch.group(1)!.trim();
            size = dsMatch.group(2)!.replaceAll(RegExp(r'</?p[^>]*>'), '').trim();
          }
          if (!backups.any((b) => b['filename'] == filename)) {
            backups.add({
              'filename': filename,
              'date': date,
              'size': size,
            });
          }
        }
      }
      return backups;
    } catch (_) {}
    return [];
  }

  Future<Map<String, dynamic>> createBackup() async {
    try {
      final response = await _dio.post(
        ApiConfig.backups,
        data: FormData.fromMap({'create_backup': '1'}),
      );
      final dynamic data = response.data;
      if (data is Map) {
        return Map<String, dynamic>.from(data);
      }
      final location = response.headers.value('location') ?? '';
      if (response.statusCode == 302 || location.contains('created=1') || response.statusCode == 200) {
        return {'success': true, 'message': 'Backup created successfully'};
      }
      return {'success': false, 'message': 'Failed to create backup'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> deleteBackup(String filename) async {
    try {
      final response = await _dio.get(
        ApiConfig.backups,
        queryParameters: {'delete': filename},
      );
      final dynamic data = response.data;
      if (data is Map) {
        return Map<String, dynamic>.from(data);
      }
      final location = response.headers.value('location') ?? '';
      if (response.statusCode == 302 || location.contains('deleted=1') || response.statusCode == 200) {
        return {'success': true, 'message': 'Backup deleted successfully'};
      }
      return {'success': false, 'message': 'Failed to delete backup'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  // Stremio & Nuveo manifest fetch
  Future<Map<String, dynamic>> fetchStremioManifest(String url) async {
    try {
      final response = await _dio.post(
        ApiConfig.appSettingsPhp,
        data: FormData.fromMap({
          'ajax_action': 'fetch_stremio_manifest',
          'url': url,
        }),
      );
      if (response.data is Map) {
        return Map<String, dynamic>.from(response.data);
      }
      return {'success': false, 'error': 'Invalid response format'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> fetchNuveoManifest(String url) async {
    try {
      final response = await _dio.post(
        ApiConfig.appSettingsPhp,
        data: FormData.fromMap({
          'ajax_action': 'fetch_nuveo_manifest',
          'url': url,
        }),
      );
      if (response.data is Map) {
        return Map<String, dynamic>.from(response.data);
      }
      return {'success': false, 'error': 'Invalid response format'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // OTT provider list from ott_admin.php table
  Future<List<Map<String, dynamic>>> fetchOttProviderList() async {
    try {
      final response = await _dio.get(ApiConfig.ottProviders);
      final dynamic data = response.data;
      
      if (data is List) {
        return List<Map<String, dynamic>>.from(
          data.map((x) => Map<String, dynamic>.from(x as Map)),
        );
      }
      
      final html = data.toString();
      final providers = <Map<String, dynamic>>[];
      
      final trRegex = RegExp(r'<tr[^>]*>(.*?)</tr>', dotAll: true);
      final idRegex = RegExp(r'<td[^>]*>\s*(\d+)\s*</td>');
      final nameRegex = RegExp(r'name="name"\s*value="([^"]*)"');
      final logoRegex = RegExp(r'name="logo_url"\s*(?:value="([^"]*)"|placeholder)');
      final logoUrlRegex = RegExp(r'src="([^"]*)"');
      
      for (final trMatch in trRegex.allMatches(html)) {
        final tr = trMatch.group(1) ?? '';
        final idMatch = idRegex.firstMatch(tr);
        if (idMatch == null) continue;
        
        final id = int.tryParse(idMatch.group(1)!) ?? 0;
        if (id == 0) continue;
        
        String name = '';
        final nameMatch = nameRegex.firstMatch(tr);
        if (nameMatch != null) name = nameMatch.group(1)!.trim();
        
        String logoUrl = '';
        final logoUrlMatch = logoUrlRegex.firstMatch(tr);
        if (logoUrlMatch != null) {
          logoUrl = logoUrlMatch.group(1)!.trim();
        } else {
          final logoValMatch = logoRegex.firstMatch(tr);
          if (logoValMatch != null && logoValMatch.group(1) != null) {
            logoUrl = logoValMatch.group(1)!.trim();
          }
        }
        
        providers.add({
          'id': id,
          'name': name,
          'logo_url': logoUrl,
        });
      }
      return providers;
    } catch (_) {}
    return [];
  }

  // IPTV Channels operations:
  Future<Map<String, dynamic>> toggleCategoryVisibility(String categoryName, int portalId, bool visible) async {
    try {
      final status = visible ? 0 : 1; // 1 = hide, 0 = show
      final response = await _dio.get(
        '${ApiConfig.iptvChannels}?ajax_toggle_hide_category=${Uri.encodeComponent(categoryName)}&portal_id=$portalId&hide_status=$status',
      );
      if (response.data is Map) {
        return Map<String, dynamic>.from(response.data);
      }
      return {'success': response.statusCode == 200};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> renameCategory(String oldName, int portalId, String newName) async {
    try {
      final response = await _dio.get(
        '${ApiConfig.iptvChannels}?ajax_rename_category=${Uri.encodeComponent(oldName)}&portal_id=$portalId&new_name=${Uri.encodeComponent(newName)}',
      );
      if (response.data is Map) {
        return Map<String, dynamic>.from(response.data);
      }
      return {'success': response.statusCode == 200};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> updateChannelDetails(int channelId, String displayName, String logoUrl) async {
    try {
      final response = await _dio.post(
        ApiConfig.iptvChannels,
        data: FormData.fromMap({
          'action_edit_channel': '1',
          'channel_id': channelId.toString(),
          'custom_name': displayName,
          'logo_url': logoUrl,
        }),
      );
      return {'success': response.statusCode == 200};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> saveCategoryOrder(List<String> orderedCategories) async {
    try {
      final Map<String, dynamic> formData = {
        'action_reorder_categories': '1',
      };
      for (int i = 0; i < orderedCategories.length; i++) {
        formData['category_orders[${orderedCategories[i]}]'] = i.toString();
      }
      final response = await _dio.post(
        ApiConfig.iptvChannels,
        data: FormData.fromMap(formData),
      );
      return {'success': response.statusCode == 200};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> saveChannelPositions(Map<int, int> positions) async {
    try {
      final Map<String, dynamic> formData = {
        'action_update_positions': '1',
      };
      positions.forEach((id, pos) {
        formData['positions[$id]'] = pos.toString();
      });
      final response = await _dio.post(
        ApiConfig.iptvChannels,
        data: FormData.fromMap(formData),
      );
      return {'success': response.statusCode == 200};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }
}
