import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class StreamtapeFolder {
  final String id;
  final String name;

  const StreamtapeFolder({required this.id, required this.name});

  factory StreamtapeFolder.fromJson(Map<String, dynamic> json) {
    return StreamtapeFolder(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Unnamed Folder',
    );
  }
}

class StreamtapeFile {
  final String id;
  final String name;
  final int size;
  final String link;
  final String linkid;
  final String? createdAt;
  final int downloads;
  final String? convert;

  const StreamtapeFile({
    required this.id,
    required this.name,
    required this.size,
    required this.link,
    required this.linkid,
    this.createdAt,
    this.downloads = 0,
    this.convert,
  });

  factory StreamtapeFile.fromJson(Map<String, dynamic> json) {
    return StreamtapeFile(
      id: json['id']?.toString() ?? json['linkid']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Unnamed File',
      size: int.tryParse(json['size']?.toString() ?? '0') ?? 0,
      link: json['link']?.toString() ?? '',
      linkid: json['linkid']?.toString() ?? json['id']?.toString() ?? '',
      createdAt: json['created_at']?.toString(),
      downloads: int.tryParse(json['downloads']?.toString() ?? '0') ?? 0,
      convert: json['convert']?.toString(),
    );
  }

  String get formattedSize {
    if (size <= 0) return '0 B';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

class StreamtapeRemoteTask {
  final String id;
  final String remoteUrl;
  final String status;
  final int bytesLoaded;
  final int bytesTotal;
  final String? resultUrl;
  final String? name;

  const StreamtapeRemoteTask({
    required this.id,
    required this.remoteUrl,
    required this.status,
    required this.bytesLoaded,
    required this.bytesTotal,
    this.resultUrl,
    this.name,
  });

  factory StreamtapeRemoteTask.fromJson(String id, Map<String, dynamic> json) {
    return StreamtapeRemoteTask(
      id: id,
      remoteUrl: json['remoteurl']?.toString() ?? json['url']?.toString() ?? '',
      status: json['status']?.toString() ?? 'unknown',
      bytesLoaded: int.tryParse(json['bytes_loaded']?.toString() ?? '0') ?? 0,
      bytesTotal: int.tryParse(json['bytes_total']?.toString() ?? '0') ?? 0,
      resultUrl: json['url']?.toString(),
      name: json['name']?.toString(),
    );
  }

  double get progress {
    if (bytesTotal <= 0) return 0.0;
    return (bytesLoaded / bytesTotal).clamp(0.0, 1.0);
  }

  bool get isCompleted => status.toLowerCase() == 'completed' || status.toLowerCase() == 'finished' || (bytesTotal > 0 && bytesLoaded >= bytesTotal);
  bool get isFailed => status.toLowerCase() == 'failed' || status.toLowerCase() == 'error' || status.toLowerCase() == 'aborted';

  String get formattedProgress {
    if (bytesTotal <= 0) return '${(bytesLoaded / (1024 * 1024)).toStringAsFixed(1)} MB';
    final currentMB = (bytesLoaded / (1024 * 1024)).toStringAsFixed(1);
    final totalMB = (bytesTotal / (1024 * 1024)).toStringAsFixed(1);
    return '$currentMB / $totalMB MB (${(progress * 100).toStringAsFixed(0)}%)';
  }
}

class StreamtapeService {
  static final StreamtapeService _instance = StreamtapeService._internal();
  factory StreamtapeService() => _instance;
  StreamtapeService._internal();

  static const List<Map<String, String>> domainPresets = [
    {'label': 'Streamtape (Default)', 'api': 'api.streamtape.com', 'web': 'streamtape.com'},
    {'label': 'Strcloud Club', 'api': 'api.strcloud.club', 'web': 'strcloud.club'},
    {'label': 'Streamtape TO', 'api': 'api.streamtape.to', 'web': 'streamtape.to'},
    {'label': 'Streamtape NET', 'api': 'api.streamtape.net', 'web': 'streamtape.net'},
    {'label': 'Stape FUN', 'api': 'api.stape.fun', 'web': 'stape.fun'},
    {'label': 'Streamtape PE', 'api': 'api.streamta.pe', 'web': 'streamta.pe'},
  ];

  String _apiLogin = '';
  String _apiKey = '';
  String _apiDomain = 'api.streamtape.com';
  String _webDomain = 'streamtape.com';
  bool _customDomainEnabled = false;
  String _customDomain = '';

  String get apiLogin => _apiLogin;
  String get apiKey => _apiKey;
  String get activeApiDomain => _customDomainEnabled && _customDomain.isNotEmpty ? _customDomain : _apiDomain;
  String get activeWebDomain => _webDomain;
  bool get isCustomDomain => _customDomainEnabled;
  String get customDomain => _customDomain;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _apiLogin = prefs.getString('streamtape_api_login') ?? '';
    _apiKey = prefs.getString('streamtape_api_key') ?? '';
    _apiDomain = prefs.getString('streamtape_api_domain') ?? 'api.streamtape.com';
    _webDomain = prefs.getString('streamtape_web_domain') ?? 'streamtape.com';
    _customDomainEnabled = prefs.getBool('streamtape_custom_domain_enabled') ?? false;
    _customDomain = prefs.getString('streamtape_custom_domain') ?? '';
  }

  Future<void> updateCredentials({required String login, required String key}) async {
    _apiLogin = login.trim();
    _apiKey = key.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('streamtape_api_login', _apiLogin);
    await prefs.setString('streamtape_api_key', _apiKey);
  }

  Future<void> setDomainPreset(String apiDomain, String webDomain) async {
    _apiDomain = apiDomain.trim();
    _webDomain = webDomain.trim();
    _customDomainEnabled = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('streamtape_api_domain', _apiDomain);
    await prefs.setString('streamtape_web_domain', _webDomain);
    await prefs.setBool('streamtape_custom_domain_enabled', false);
  }

  Future<void> setCustomDomain(String domain) async {
    _customDomain = domain.trim().replaceAll('https://', '').replaceAll('http://', '').replaceAll('/', '');
    _customDomainEnabled = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('streamtape_custom_domain', _customDomain);
    await prefs.setBool('streamtape_custom_domain_enabled', true);
  }

  Map<String, String> _buildHeaders() {
    return {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      'Connection': 'close',
      'Accept': 'application/json',
    };
  }

  Future<Map<String, dynamic>> _get(String path, [Map<String, String>? extraParams]) async {
    final queryParams = {
      'login': _apiLogin,
      'key': _apiKey,
      if (extraParams != null) ...extraParams,
    };

    final domainsToTry = <String>[activeApiDomain];
    for (final p in domainPresets) {
      if (!domainsToTry.contains(p['api']!)) {
        domainsToTry.add(p['api']!);
      }
    }

    String lastError = 'Unknown error';

    for (final domain in domainsToTry) {
      try {
        final uri = Uri.https(domain, path, queryParams);
        final response = await http.get(uri, headers: _buildHeaders()).timeout(const Duration(seconds: 12));
        
        if (response.statusCode == 200) {
          final decoded = json.decode(response.body);
          if (decoded is Map<String, dynamic>) {
            if (decoded['status'] == 200) {
              return {'success': true, 'data': decoded['result']};
            } else {
              return {'success': false, 'message': decoded['msg']?.toString() ?? 'Streamtape API returned non-200 status'};
            }
          }
        } else {
          lastError = 'HTTP ${response.statusCode}: ${response.body}';
        }
      } catch (e) {
        lastError = e.toString();
      }
    }

    return {'success': false, 'message': lastError};
  }

  /// Test connection and credentials against active domain
  Future<Map<String, dynamic>> testConnection() async {
    if (_apiLogin.isEmpty || _apiKey.isEmpty) {
      return {'success': false, 'message': 'API Login and API Key cannot be empty.'};
    }
    final res = await _get('/account/info');
    if (res['success'] == true) {
      return {
        'success': true,
        'message': 'Connected successfully to $activeApiDomain!',
        'account': res['data'],
      };
    }
    return res;
  }

  /// Get Account details (email, signup date)
  Future<Map<String, dynamic>> getAccountInfo() async {
    return await _get('/account/info');
  }

  /// List folder contents (subfolders and files)
  Future<Map<String, dynamic>> listFolder({String? folderId}) async {
    final params = <String, String>{};
    if (folderId != null && folderId.isNotEmpty) {
      params['folder'] = folderId;
    }
    final res = await _get('/file/listfolder', params);
    if (res['success'] == true && res['data'] is Map) {
      final data = res['data'] as Map;
      final folders = <StreamtapeFolder>[];
      final files = <StreamtapeFile>[];

      if (data['folders'] is List) {
        for (final f in data['folders'] as List) {
          if (f is Map) folders.add(StreamtapeFolder.fromJson(Map<String, dynamic>.from(f)));
        }
      }

      if (data['files'] is List) {
        for (final f in data['files'] as List) {
          if (f is Map) files.add(StreamtapeFile.fromJson(Map<String, dynamic>.from(f)));
        }
      }

      return {
        'success': true,
        'folders': folders,
        'files': files,
      };
    }
    return res;
  }

  /// Create new subfolder
  Future<Map<String, dynamic>> createFolder(String name, {String? parentId}) async {
    final params = {'name': name.trim()};
    if (parentId != null && parentId.isNotEmpty) {
      params['parent'] = parentId;
    }
    return await _get('/file/createfolder', params);
  }

  /// Rename existing folder
  Future<Map<String, dynamic>> renameFolder(String folderId, String newName) async {
    return await _get('/file/renamefolder', {
      'folder': folderId,
      'name': newName.trim(),
    });
  }

  /// Delete folder
  Future<Map<String, dynamic>> deleteFolder(String folderId) async {
    return await _get('/file/deletefolder', {'folder': folderId});
  }

  /// Rename file
  Future<Map<String, dynamic>> renameFile(String fileId, String newName) async {
    return await _get('/file/rename', {
      'file': fileId,
      'name': newName.trim(),
    });
  }

  /// Delete file
  Future<Map<String, dynamic>> deleteFile(String fileId) async {
    return await _get('/file/delete', {'file': fileId});
  }

  /// Move file to folder
  Future<Map<String, dynamic>> moveFile(String fileId, String targetFolderId) async {
    return await _get('/file/move', {
      'file': fileId,
      'folder': targetFolderId,
    });
  }

  /// Clone / Copy file to folder
  Future<Map<String, dynamic>> cloneFile(String fileId, {String? targetFolderId}) async {
    final params = {'file': fileId};
    if (targetFolderId != null && targetFolderId.isNotEmpty) {
      params['folder'] = targetFolderId;
    }
    return await _get('/file/clone', params);
  }

  /// Add Remote URL Download task
  Future<Map<String, dynamic>> addRemoteUpload(String url, {String? name, String? folderId}) async {
    final params = {'url': url.trim()};
    if (name != null && name.trim().isNotEmpty) {
      params['name'] = name.trim();
    }
    if (folderId != null && folderId.isNotEmpty) {
      params['folder'] = folderId;
    }
    return await _get('/remotedl/add', params);
  }

  /// Get status of all remote downloads or a specific download task
  Future<Map<String, dynamic>> getRemoteUploadsStatus({String? id}) async {
    final params = <String, String>{};
    if (id != null && id.isNotEmpty) {
      params['id'] = id;
    }
    final res = await _get('/remotedl/status', params);
    if (res['success'] == true && res['data'] != null) {
      final tasks = <StreamtapeRemoteTask>[];
      final dynamic rawData = res['data'];

      if (rawData is Map) {
        rawData.forEach((taskId, val) {
          if (val is Map) {
            tasks.add(StreamtapeRemoteTask.fromJson(taskId.toString(), Map<String, dynamic>.from(val)));
          }
        });
      }
      return {'success': true, 'tasks': tasks};
    }
    return res;
  }

  /// Remove / Cancel remote upload task
  Future<Map<String, dynamic>> removeRemoteUpload(String id) async {
    return await _get('/remotedl/remove', {'id': id});
  }

  /// Resolve direct streaming URL from Streamtape File ID or Stream Link
  Future<Map<String, dynamic>> resolveStreamingUrl(String fileIdOrUrl) async {
    String fileId = fileIdOrUrl.trim();
    if (fileId.contains('/v/')) {
      final uri = Uri.tryParse(fileId);
      if (uri != null && uri.pathSegments.length >= 2) {
        fileId = uri.pathSegments[1];
      }
    } else if (fileId.contains('/e/')) {
      final uri = Uri.tryParse(fileId);
      if (uri != null && uri.pathSegments.length >= 2) {
        fileId = uri.pathSegments[1];
      }
    }

    // 1. Get download ticket
    final ticketRes = await _get('/file/dlticket', {'file': fileId});
    if (ticketRes['success'] != true || ticketRes['data'] == null) {
      return {'success': false, 'message': ticketRes['message'] ?? 'Failed to obtain download ticket'};
    }

    final ticketData = ticketRes['data'] as Map;
    final ticket = ticketData['ticket']?.toString() ?? '';
    final waitTime = int.tryParse(ticketData['wait_time']?.toString() ?? '0') ?? 0;

    if (ticket.isEmpty) {
      return {'success': false, 'message': 'Invalid ticket received from Streamtape'};
    }

    // 2. Wait for ticket cooldown if required
    if (waitTime > 0) {
      await Future.delayed(Duration(seconds: waitTime + 1));
    }

    // 3. Request direct download link
    final dlRes = await _get('/file/dl', {'file': fileId, 'ticket': ticket});
    if (dlRes['success'] == true && dlRes['data'] is Map) {
      final directUrl = dlRes['data']['url']?.toString();
      if (directUrl != null && directUrl.isNotEmpty) {
        return {'success': true, 'url': directUrl};
      }
    }

    return {'success': false, 'message': dlRes['message'] ?? 'Failed to get direct stream link'};
  }

  /// Format public share link
  String getPublicWebLink(String fileId) {
    return 'https://$activeWebDomain/v/$fileId';
  }

  /// Get list of all available web mirror domains
  List<Map<String, String>> getAllWebDomains() {
    final list = <Map<String, String>>[];
    for (final p in domainPresets) {
      list.add({
        'label': p['label']!,
        'domain': p['web']!,
      });
    }
    if (_customDomainEnabled && _customDomain.isNotEmpty) {
      list.insert(0, {
        'label': 'Custom Domain',
        'domain': _customDomain,
      });
    }
    return list;
  }

  /// Format watch link for a given domain
  String getWatchUrl(String fileId, [String? domain]) {
    final d = domain ?? activeWebDomain;
    return 'https://$d/v/$fileId';
  }

  /// Format embed player link for a given domain
  String getEmbedUrl(String fileId, [String? domain]) {
    final d = domain ?? activeWebDomain;
    return 'https://$d/e/$fileId';
  }

  /// Format HTML iframe embed code for a given domain
  String getIframeCode(String fileId, [String? domain]) {
    final d = domain ?? activeWebDomain;
    return '<iframe src="https://$d/e/$fileId" width="100%" height="100%" allowfullscreen allowtransparency referrerpolicy="no-referrer"></iframe>';
  }
}

