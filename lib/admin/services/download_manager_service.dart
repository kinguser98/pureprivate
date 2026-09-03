import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../models/browser_tab_model.dart';
import '../models/cloud_account_model.dart';
import '../models/download_task_model.dart';
import 'cloud_auth_service.dart';
import 'download_exporter_service.dart';

class DownloadManagerService extends ChangeNotifier {
  static final DownloadManagerService _instance = DownloadManagerService._internal();
  factory DownloadManagerService() => _instance;
  DownloadManagerService._internal() {
    _loadTasks();
  }

  static const String _storageKey = 'goxio_download_tasks_v1';
  final List<DownloadTask> _tasks = [];
  final Map<String, CancelToken> _cancelTokens = {};
  final Map<String, int> _lastReceivedMap = {};
  final Map<String, DateTime> _lastTimeMap = {};
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(minutes: 30),
  ));

  List<DownloadTask> get tasks => List.unmodifiable(_tasks);

  int get activeDownloadCount => _tasks.where((t) => t.status == DownloadStatus.downloading).length;

  Future<void> _loadTasks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List<dynamic>;
        _tasks.clear();
        for (final item in list) {
          final task = DownloadTask.fromJson(item as Map<String, dynamic>);
          // If task was downloading when closed, mark it paused
          if (task.status == DownloadStatus.downloading || task.status == DownloadStatus.queued) {
            task.status = DownloadStatus.paused;
          }
          _tasks.add(task);
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('DownloadManagerService._loadTasks error: $e');
    }
  }

  Future<void> _saveTasks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode(_tasks.map((t) => t.toJson()).toList());
      await prefs.setString(_storageKey, raw);
    } catch (e) {
      debugPrint('DownloadManagerService._saveTasks error: $e');
    }
  }

  Future<DownloadTask> startDownload({
    required String url,
    required String filename,
    Map<String, String>? headers,
    String? autoUploadCloudAccountId,
    String? autoUploadCloudAccountName,
    bool isServerSide = false,
  }) async {
    final id = 'dl_${DateTime.now().millisecondsSinceEpoch}_${url.hashCode.abs()}';
    final task = DownloadTask(
      id: id,
      url: url,
      filename: filename,
      headers: headers,
      autoUploadCloudAccountId: autoUploadCloudAccountId,
      autoUploadCloudAccountName: autoUploadCloudAccountName,
      isServerSide: isServerSide,
      status: DownloadStatus.queued,
      createdAt: DateTime.now(),
    );

    _tasks.insert(0, task);
    notifyListeners();
    await _saveTasks();

    _executeDownload(task);
    return task;
  }

  Future<void> _executeDownload(DownloadTask task) async {
    final serverWorkerUrl = await CloudAuthService.getServerWorkerUrl();
    if (task.isServerSide && serverWorkerUrl != null && serverWorkerUrl.isNotEmpty && task.autoUploadCloudAccountId != null) {
      _executeServerWorkerDownload(task, serverWorkerUrl);
      return;
    }

    // Direct RAM Streaming Pipe straight to Cloud (0 Phone Storage)
    if (task.autoUploadCloudAccountId != null) {
      _executeDirectCloudStream(task);
      return;
    }

    task.status = DownloadStatus.downloading;
    task.errorMessage = null;
    notifyListeners();

    final cancelToken = CancelToken();
    _cancelTokens[task.id] = cancelToken;

    try {
      // Determine save file location
      Directory? baseDir;
      if (Platform.isAndroid) {
        baseDir = Directory('/storage/emulated/0/Download');
        if (!baseDir.existsSync()) {
          baseDir = await getExternalStorageDirectory();
        }
      } else {
        baseDir = await getApplicationDocumentsDirectory();
      }

      if (baseDir == null) throw Exception('Storage directory not available');

      final safeFilename = task.filename.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final targetPath = p.join(baseDir.path, safeFilename);
      task.savePath = targetPath;

      final file = File(targetPath);
      int startByte = 0;
      if (file.existsSync()) {
        startByte = file.lengthSync();
      }
      task.receivedBytes = startByte;

      final reqHeaders = <String, dynamic>{
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36',
        'Accept': '*/*',
        'Accept-Encoding': 'identity',
        'Accept-Language': 'en-US,en;q=0.9',
        'Connection': 'keep-alive',
        'Sec-Fetch-Dest': 'video',
        'Sec-Fetch-Mode': 'no-cors',
        'Sec-Fetch-Site': 'cross-site',
      };
      if (task.headers != null) {
        reqHeaders.addAll(task.headers!);
      }

      // Auto-inject anti-throttling referer for streamtape and video CDNs if missing
      if (!reqHeaders.containsKey('Referer') && !reqHeaders.containsKey('referer')) {
        try {
          final uri = Uri.parse(task.url);
          if (uri.host.contains('streamtape') || uri.host.contains('tapecontent') || uri.host.contains('strcloud')) {
            reqHeaders['Referer'] = 'https://streamtape.com/';
          } else {
            reqHeaders['Referer'] = '${uri.scheme}://${uri.host}/';
          }
        } catch (_) {}
      }

      if (startByte > 0) {
        reqHeaders['Range'] = 'bytes=$startByte-';
      }

      _lastReceivedMap[task.id] = startByte;
      _lastTimeMap[task.id] = DateTime.now();

      final response = await _dio.get<ResponseBody>(
        task.url,
        cancelToken: cancelToken,
        options: Options(
          headers: reqHeaders,
          responseType: ResponseType.stream,
          receiveTimeout: const Duration(hours: 2),
          sendTimeout: const Duration(minutes: 5),
          validateStatus: (s) => s != null && (s == 200 || s == 206),
        ),
      );

      final contentLength = response.data?.headers['content-length']?.firstOrNull;
      if (contentLength != null) {
        final totalLength = int.tryParse(contentLength) ?? 0;
        if (response.statusCode == 206) {
          task.totalBytes = startByte + totalLength;
        } else {
          task.totalBytes = totalLength;
          startByte = 0; // Server doesn't support Range, starts from 0
        }
      }

      final sink = file.openWrite(mode: startByte > 0 ? FileMode.append : FileMode.write);
      int received = startByte;

      await for (final chunk in response.data!.stream) {
        sink.add(chunk);
        received += chunk.length;
        task.receivedBytes = received;

        // Speed & ETA calculation every 500ms
        final now = DateTime.now();
        final lastTime = _lastTimeMap[task.id] ?? now;
        final elapsedMs = now.difference(lastTime).inMilliseconds;

        if (elapsedMs >= 500) {
          final lastReceived = _lastReceivedMap[task.id] ?? startByte;
          final bytesDelta = received - lastReceived;
          final currentSpeed = (bytesDelta / (elapsedMs / 1000.0));

          // Smooth speed
          task.speedBytesPerSec = (task.speedBytesPerSec * 0.7) + (currentSpeed * 0.3);

          if (task.totalBytes > received && task.speedBytesPerSec > 0) {
            task.etaSeconds = ((task.totalBytes - received) / task.speedBytesPerSec).round();
          }

          _lastReceivedMap[task.id] = received;
          _lastTimeMap[task.id] = now;
          notifyListeners();
        }
      }

      await sink.flush();
      await sink.close();

      task.status = DownloadStatus.completed;
      task.completedAt = DateTime.now();
      task.speedBytesPerSec = 0;
      task.etaSeconds = null;
      notifyListeners();
      await _saveTasks();

      if (task.autoUploadCloudAccountId != null && task.savePath != null) {
        _triggerAutoUpload(task);
      }
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        task.status = DownloadStatus.paused;
      } else {
        task.status = DownloadStatus.failed;
        task.errorMessage = e.message ?? 'Network error';
      }
      task.speedBytesPerSec = 0;
      task.etaSeconds = null;
      notifyListeners();
      await _saveTasks();
    } catch (e) {
      task.status = DownloadStatus.failed;
      task.errorMessage = e.toString();
      task.speedBytesPerSec = 0;
      task.etaSeconds = null;
      notifyListeners();
      await _saveTasks();
    } finally {
      _cancelTokens.remove(task.id);
    }
  }

  void pauseTask(String taskId) {
    final task = _tasks.firstWhere((t) => t.id == taskId);
    _cancelTokens[taskId]?.cancel();
    task.status = DownloadStatus.paused;
    task.speedBytesPerSec = 0;
    task.etaSeconds = null;
    notifyListeners();
    _saveTasks();
  }

  void resumeTask(String taskId) {
    final task = _tasks.firstWhere((t) => t.id == taskId);
    if (task.status != DownloadStatus.downloading) {
      _executeDownload(task);
    }
  }

  void refreshTaskUrl(String taskId, String newUrl) {
    final task = _tasks.firstWhere((t) => t.id == taskId);
    task.url = newUrl;
    notifyListeners();
    _saveTasks();
    resumeTask(taskId);
  }

  Future<void> deleteTask(String taskId, {bool deleteFile = false}) async {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index >= 0) {
      final task = _tasks[index];
      _cancelTokens[taskId]?.cancel();
      if (deleteFile && task.savePath != null) {
        try {
          final f = File(task.savePath!);
          if (f.existsSync()) f.deleteSync();
        } catch (_) {}
      }
      _tasks.removeAt(index);
      notifyListeners();
      await _saveTasks();
    }
  }

  Future<String?> saveToGalleryOrPublicDownloads(DownloadTask task) async {
    if (task.savePath == null) return null;
    try {
      final sourceFile = File(task.savePath!);
      if (!sourceFile.existsSync()) return null;

      final isVideo = task.filename.endsWith('.mp4') || task.filename.endsWith('.mkv') || task.filename.endsWith('.webm') || task.filename.endsWith('.ts');
      final isImage = task.filename.endsWith('.jpg') || task.filename.endsWith('.jpeg') || task.filename.endsWith('.png') || task.filename.endsWith('.webp');

      if (Platform.isAndroid) {
        const channel = MethodChannel('com.goxio.mob/media_saver');
        final success = await channel.invokeMethod<bool>('saveToGallery', {
          'filePath': sourceFile.absolute.path,
          'filename': task.filename,
          'isVideo': isVideo || !isImage,
        });

        if (success == true) {
          return '/storage/emulated/0/Movies/GoXio/${task.filename}';
        }
      }

      // Fallback for non-Android / older versions
      final dir = await getApplicationDocumentsDirectory();
      final destPath = p.join(dir.path, task.filename);
      await sourceFile.copy(destPath);
      return destPath;
    } catch (e) {
      debugPrint('saveToGalleryOrPublicDownloads error: $e');
      return null;
    }
  }

  Future<void> _triggerAutoUpload(DownloadTask task) async {
    try {
      final accounts = await CloudAuthService.getAccounts();
      final account = accounts.where((a) => a.id == task.autoUploadCloudAccountId).firstOrNull;
      if (account != null && task.savePath != null) {
        final mediaItem = SniffedMediaItem(
          id: task.id,
          url: task.url,
          title: task.filename,
          type: SniffedMediaType.genericVideo,
          detectedAt: task.createdAt,
        );

        bool success = false;
        if (account.provider == CloudProvider.gdrive) {
          success = await DownloadExporterService.uploadToGoogleDrive(
            account: account,
            item: mediaItem,
            customFilename: task.filename,
            localFilePath: task.savePath,
          );
        } else if (account.provider == CloudProvider.onedrivePersonal || account.provider == CloudProvider.onedriveBusiness) {
          success = await DownloadExporterService.uploadToOneDrive(
            account: account,
            item: mediaItem,
            customFilename: task.filename,
            localFilePath: task.savePath,
          );
        } else if (account.provider == CloudProvider.telegramBot || account.provider == CloudProvider.telegramMtproto) {
          success = await DownloadExporterService.uploadToTelegram(
            account: account,
            item: mediaItem,
            customFilename: task.filename,
            localFilePath: task.savePath,
          );
        }

        if (success && task.isServerSide) {
          try {
            final f = File(task.savePath!);
            if (f.existsSync()) f.deleteSync();
            task.savePath = null;
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('Auto-upload error: $e');
    }
  }

  Future<void> _executeServerWorkerDownload(DownloadTask task, String workerUrl) async {
    task.status = DownloadStatus.downloading;
    task.errorMessage = null;
    notifyListeners();

    try {
      final accounts = await CloudAuthService.getAccounts();
      final account = accounts.where((a) => a.id == task.autoUploadCloudAccountId).firstOrNull;
      if (account == null) {
        throw Exception('Cloud account not found');
      }

      String providerStr = 'gdrive';
      if (account.provider == CloudProvider.onedrivePersonal || account.provider == CloudProvider.onedriveBusiness) {
        providerStr = 'onedrive';
      } else if (account.provider == CloudProvider.telegramBot || account.provider == CloudProvider.telegramMtproto) {
        providerStr = 'telegram';
      }

      final startUri = Uri.parse(workerUrl.contains('?') ? '$workerUrl&action=start' : '$workerUrl?action=start');
      final startRes = await http.post(
        startUri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'url': task.url,
          'provider': providerStr,
          'access_token': account.accessToken ?? account.telegramBotToken,
          'filename': task.filename,
          'headers': task.headers,
          'telegram_chat_id': account.telegramChatId,
        }),
      );

      if (startRes.statusCode != 200) {
        throw Exception('Server worker failed: ${startRes.statusCode} - ${startRes.body}');
      }

      final startData = jsonDecode(startRes.body) as Map<String, dynamic>;
      final serverTaskId = startData['task_id'] as String?;
      if (serverTaskId == null) {
        throw Exception('Server worker did not return a task_id');
      }

      // Poll server progress
      final statusUriBase = workerUrl.contains('?') ? '$workerUrl&action=status&task_id=$serverTaskId' : '$workerUrl?action=status&task_id=$serverTaskId';
      bool isFinished = false;

      while (!isFinished) {
        await Future.delayed(const Duration(milliseconds: 1500));
        if (task.status == DownloadStatus.canceled || task.status == DownloadStatus.paused) {
          break;
        }

        try {
          final statusRes = await http.get(Uri.parse(statusUriBase));
          if (statusRes.statusCode == 200) {
            final sData = jsonDecode(statusRes.body) as Map<String, dynamic>;
            final serverStatus = sData['status'] as String?;
            task.receivedBytes = (sData['received_bytes'] as num?)?.toInt() ?? 0;
            task.totalBytes = (sData['total_bytes'] as num?)?.toInt() ?? 0;
            task.speedBytesPerSec = (sData['speed_bytes_sec'] as num?)?.toDouble() ?? 0.0;

            if (task.totalBytes > task.receivedBytes && task.speedBytesPerSec > 0) {
              task.etaSeconds = ((task.totalBytes - task.receivedBytes) / task.speedBytesPerSec).round();
            }

            if (serverStatus == 'completed') {
              task.status = DownloadStatus.completed;
              task.completedAt = DateTime.now();
              task.speedBytesPerSec = 0;
              task.etaSeconds = null;
              isFinished = true;
              notifyListeners();
              await _saveTasks();
              break;
            } else if (serverStatus == 'failed') {
              task.status = DownloadStatus.failed;
              task.errorMessage = sData['error'] as String? ?? 'Server worker failed';
              task.speedBytesPerSec = 0;
              task.etaSeconds = null;
              isFinished = true;
              notifyListeners();
              await _saveTasks();
              break;
            }

            notifyListeners();
          }
        } catch (e) {
          debugPrint('Server worker poll error: $e');
        }
      }
    } catch (e) {
      task.status = DownloadStatus.failed;
      task.errorMessage = e.toString();
      task.speedBytesPerSec = 0;
      task.etaSeconds = null;
      notifyListeners();
      await _saveTasks();
    }
  }

  Future<void> _executeDirectCloudStream(DownloadTask task) async {
    task.status = DownloadStatus.downloading;
    task.errorMessage = null;
    notifyListeners();

    final cancelToken = CancelToken();
    _cancelTokens[task.id] = cancelToken;

    try {
      final accounts = await CloudAuthService.getAccounts();
      final account = accounts.where((a) => a.id == task.autoUploadCloudAccountId).firstOrNull;
      if (account == null) throw Exception('Target cloud account not found');

      bool success = false;

      if (account.provider == CloudProvider.gdrive) {
        success = await DownloadExporterService.streamDirectToGoogleDrive(
          account: account,
          sourceUrl: task.url,
          customFilename: task.filename,
          customHeaders: task.headers,
          cancelToken: cancelToken,
          onProgress: (rec, total, speed) {
            task.receivedBytes = rec;
            task.totalBytes = total;
            task.speedBytesPerSec = speed;
            if (total > rec && speed > 0) {
              task.etaSeconds = ((total - rec) / speed).round();
            }
            notifyListeners();
          },
        );
      } else if (account.provider == CloudProvider.onedrivePersonal || account.provider == CloudProvider.onedriveBusiness) {
        success = await DownloadExporterService.streamDirectToOneDrive(
          account: account,
          sourceUrl: task.url,
          customFilename: task.filename,
          customHeaders: task.headers,
          cancelToken: cancelToken,
          onProgress: (rec, total, speed) {
            task.receivedBytes = rec;
            task.totalBytes = total;
            task.speedBytesPerSec = speed;
            if (total > rec && speed > 0) {
              task.etaSeconds = ((total - rec) / speed).round();
            }
            notifyListeners();
          },
        );
      }

      if (success) {
        task.status = DownloadStatus.completed;
        task.completedAt = DateTime.now();
        task.speedBytesPerSec = 0;
        task.etaSeconds = null;
        notifyListeners();
        await _saveTasks();
      } else {
        throw Exception('Cloud streaming transfer failed or was cancelled');
      }
    } catch (e) {
      if (cancelToken.isCancelled) {
        task.status = DownloadStatus.paused;
      } else {
        task.status = DownloadStatus.failed;
        task.errorMessage = e.toString();
      }
      task.speedBytesPerSec = 0;
      task.etaSeconds = null;
      notifyListeners();
      await _saveTasks();
    } finally {
      _cancelTokens.remove(task.id);
    }
  }
}
