import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:http/http.dart' as http;
import '../models/cloud_account_model.dart';
import '../models/browser_tab_model.dart';
import 'cloud_auth_service.dart';

class DownloadExporterService {
  static final Dio _dio = Dio();

  // --- 1. Client-Side: Local Storage Download ---

  static Future<String?> downloadToLocal({
    required SniffedMediaItem item,
    required String customFilename,
    Function(int received, int total)? onProgress,
  }) async {
    try {
      Directory? dir;
      if (Platform.isAndroid) {
        dir = Directory('/storage/emulated/0/Download');
        if (!dir.existsSync()) {
          dir = await getExternalStorageDirectory();
        }
      } else {
        dir = await getApplicationDocumentsDirectory();
      }

      if (dir == null) return null;

      final extension = _getExtension(item);
      final filename = customFilename.endsWith(extension) ? customFilename : '$customFilename$extension';
      final savePath = p.join(dir.path, filename);

      final headers = <String, dynamic>{
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      };
      if (item.headers != null) {
        headers.addAll(item.headers!);
      }

      await _dio.download(
        item.url,
        savePath,
        options: Options(headers: headers),
        onReceiveProgress: onProgress,
      );

      return savePath;
    } catch (e) {
      debugPrint('downloadToLocal error: $e');
      return null;
    }
  }

  // --- 2. Client-Side: Google Drive Upload ---

  static Future<bool> uploadToGoogleDrive({
    required CloudAccount account,
    required SniffedMediaItem item,
    required String customFilename,
    String? folderId,
    String? localFilePath,
    Function(double progress)? onProgress,
  }) async {
    try {
      File uploadFile;
      bool isTemp = false;

      if (localFilePath != null && File(localFilePath).existsSync()) {
        uploadFile = File(localFilePath);
      } else {
        final tempDir = await getTemporaryDirectory();
        final extension = _getExtension(item);
        final filename = customFilename.endsWith(extension) ? customFilename : '$customFilename$extension';
        uploadFile = File(p.join(tempDir.path, 'upload_${DateTime.now().millisecondsSinceEpoch}$extension'));
        await _dio.download(item.url, uploadFile.path, options: Options(headers: item.headers));
        isTemp = true;
      }

      final fileSize = await uploadFile.length();
      final token = account.accessToken;
      if (token == null || token.isEmpty) {
        debugPrint('uploadToGoogleDrive: token is empty');
        return false;
      }

      // 1. Direct Multipart upload for small files (<= 5MB)
      if (fileSize <= 5 * 1024 * 1024) {
        final metadata = {
          'name': customFilename,
          if (folderId != null && folderId.isNotEmpty) 'parents': [folderId],
        };

        final uri = Uri.parse('https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart');
        final request = http.MultipartRequest('POST', uri);
        request.headers['Authorization'] = 'Bearer $token';

        request.files.add(http.MultipartFile.fromString(
          'metadata',
          jsonEncode(metadata),
          contentType: http.MediaType('application', 'json; charset=UTF-8'),
        ));

        request.files.add(await http.MultipartFile.fromPath(
          'file',
          uploadFile.path,
          filename: customFilename,
        ));

        final streamedRes = await request.send();
        final res = await http.Response.fromStream(streamedRes);
        debugPrint('Google Drive small upload result: ${res.statusCode} - ${res.body}');

        if (isTemp) {
          try { await uploadFile.delete(); } catch (_) {}
        }
        return res.statusCode == 200 || res.statusCode == 201;
      }

      // 2. Resumable Upload for large files (> 5MB)
      final metadata = {
        'name': customFilename,
        if (folderId != null && folderId.isNotEmpty) 'parents': [folderId],
      };

      final initRes = await http.post(
        Uri.parse('https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json; charset=UTF-8',
          'X-Upload-Content-Length': fileSize.toString(),
        },
        body: jsonEncode(metadata),
      );

      if (initRes.statusCode == 200) {
        final uploadUri = initRes.headers['location'];
        if (uploadUri != null) {
          const chunkSize = 2 * 1024 * 1024; // 2 MB chunks
          int uploaded = 0;
          final raf = await uploadFile.open();

          while (uploaded < fileSize) {
            final curSize = (fileSize - uploaded > chunkSize) ? chunkSize : (fileSize - uploaded);
            final chunkBytes = await raf.read(curSize);
            final endByte = uploaded + chunkBytes.length - 1;

            final putRes = await http.put(
              Uri.parse(uploadUri),
              headers: {
                'Content-Length': chunkBytes.length.toString(),
                'Content-Range': 'bytes $uploaded-$endByte/$fileSize',
              },
              body: chunkBytes,
            );

            uploaded += chunkBytes.length;
            if (onProgress != null && fileSize > 0) {
              onProgress(uploaded / fileSize);
            }

            if (putRes.statusCode == 200 || putRes.statusCode == 201) {
              await raf.close();
              if (isTemp) {
                try { await uploadFile.delete(); } catch (_) {}
              }
              return true;
            } else if (putRes.statusCode != 308) {
              debugPrint('Google Drive chunk upload unexpected code: ${putRes.statusCode} - ${putRes.body}');
              await raf.close();
              return false;
            }
          }
          await raf.close();
          return true;
        }
      } else {
        debugPrint('Google Drive resumable init failed: ${initRes.statusCode} - ${initRes.body}');
      }
    } catch (e) {
      debugPrint('uploadToGoogleDrive error: $e');
    }
    return false;
  }

  // --- 3. Client-Side: OneDrive (Personal & Business) Upload ---

  static Future<bool> uploadToOneDrive({
    required CloudAccount account,
    required SniffedMediaItem item,
    required String customFilename,
    String? folderPath,
    String? localFilePath,
    Function(double progress)? onProgress,
  }) async {
    try {
      String? token = account.accessToken;
      if (account.isExpired) {
        token = await CloudAuthService.refreshOneDriveToken(account);
      }
      if (token == null || token.isEmpty) {
        debugPrint('uploadToOneDrive: token is empty');
        return false;
      }

      File uploadFile;
      bool isTemp = false;

      if (localFilePath != null && File(localFilePath).existsSync()) {
        uploadFile = File(localFilePath);
      } else {
        final tempDir = await getTemporaryDirectory();
        final extension = _getExtension(item);
        final filename = customFilename.endsWith(extension) ? customFilename : '$customFilename$extension';
        uploadFile = File(p.join(tempDir.path, 'onedrive_${DateTime.now().millisecondsSinceEpoch}$extension'));
        await _dio.download(item.url, uploadFile.path, options: Options(headers: item.headers));
        isTemp = true;
      }

      final fileSize = await uploadFile.length();
      final cleanPath = (folderPath != null && folderPath.isNotEmpty) ? '$folderPath/$customFilename' : customFilename;
      final encodedName = Uri.encodeComponent(cleanPath);

      // A. Direct PUT Upload for files <= 4MB (Photos, Small Clips)
      if (fileSize <= 4 * 1024 * 1024) {
        final directUrl = 'https://graph.microsoft.com/v1.0/me/drive/root:/$encodedName:/content';
        debugPrint('OneDrive Direct PUT: $directUrl (Size: $fileSize bytes)');

        final putRes = await http.put(
          Uri.parse(directUrl),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/octet-stream',
          },
          body: await uploadFile.readAsBytes(),
        );

        if (onProgress != null) onProgress(1.0);
        debugPrint('OneDrive direct upload result: ${putRes.statusCode} - ${putRes.body}');
        if (isTemp) {
          try { await uploadFile.delete(); } catch (_) {}
        }
        return putRes.statusCode == 200 || putRes.statusCode == 201;
      }

      // B. Resumable Upload Session for large files (> 4MB)
      final sessionUrl = 'https://graph.microsoft.com/v1.0/me/drive/root:/$encodedName:/createUploadSession';
      final sessionRes = await http.post(
        Uri.parse(sessionUrl),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'item': {
            '@microsoft.graph.conflictBehavior': 'rename',
          }
        }),
      );

      debugPrint('OneDrive createUploadSession: ${sessionRes.statusCode} - ${sessionRes.body}');

      if (sessionRes.statusCode == 200) {
        final sessionData = jsonDecode(sessionRes.body) as Map<String, dynamic>;
        final uploadUrl = sessionData['uploadUrl'] as String;

        // Chunk upload with 320 KiB multiples
        const chunkSize = 320 * 1024 * 10; // 3.2 MB chunks
        int uploadedBytes = 0;
        final raf = await uploadFile.open();

        while (uploadedBytes < fileSize) {
          final currentChunkSize = (fileSize - uploadedBytes > chunkSize) ? chunkSize : (fileSize - uploadedBytes);
          final chunkBytes = await raf.read(currentChunkSize);
          final endByte = uploadedBytes + chunkBytes.length - 1;

          final chunkRes = await http.put(
            Uri.parse(uploadUrl),
            headers: {
              'Content-Length': chunkBytes.length.toString(),
              'Content-Range': 'bytes $uploadedBytes-$endByte/$fileSize',
            },
            body: chunkBytes,
          );

          uploadedBytes += chunkBytes.length;
          if (onProgress != null && fileSize > 0) {
            onProgress(uploadedBytes / fileSize);
          }

          debugPrint('OneDrive chunk uploaded: $uploadedBytes / $fileSize (${chunkRes.statusCode})');

          if (chunkRes.statusCode != 200 && chunkRes.statusCode != 201 && chunkRes.statusCode != 202) {
            debugPrint('OneDrive chunk upload failed: ${chunkRes.statusCode} - ${chunkRes.body}');
            await raf.close();
            return false;
          }
        }
        await raf.close();

        if (isTemp) {
          try { await uploadFile.delete(); } catch (_) {}
        }
        return true;
      }
    } catch (e) {
      debugPrint('uploadToOneDrive error: $e');
    }
    return false;
  }

  // --- 4. Client-Side: Telegram Storage Upload ---

  static Future<bool> uploadToTelegram({
    required CloudAccount account,
    required SniffedMediaItem item,
    required String customFilename,
    String? localFilePath,
  }) async {
    try {
      final token = account.telegramBotToken;
      final chatId = account.telegramChatId ?? 'me';

      if (token != null && token.isNotEmpty) {
        File uploadFile;
        bool isTemp = false;

        if (localFilePath != null && File(localFilePath).existsSync()) {
          uploadFile = File(localFilePath);
        } else {
          final tempDir = await getTemporaryDirectory();
          final extension = _getExtension(item);
          final filename = customFilename.endsWith(extension) ? customFilename : '$customFilename$extension';
          uploadFile = File(p.join(tempDir.path, 'tg_${DateTime.now().millisecondsSinceEpoch}$extension'));
          await _dio.download(item.url, uploadFile.path, options: Options(headers: item.headers));
          isTemp = true;
        }

        final request = http.MultipartRequest(
          'POST',
          Uri.parse('https://api.telegram.org/bot$token/sendDocument'),
        );
        request.fields['chat_id'] = chatId;
        request.files.add(await http.MultipartFile.fromPath('document', uploadFile.path, filename: customFilename));

        final response = await request.send();
        if (isTemp) {
          try {
            await uploadFile.delete();
          } catch (_) {}
        }

        return response.statusCode == 200;
      }
    } catch (e) {
      debugPrint('uploadToTelegram error: $e');
    }
    return false;
  }

  // --- 5. Server-Side: Fast Cloud Worker Offload Relay ---

  static Future<bool> dispatchServerSideJob({
    required CloudAccount account,
    required SniffedMediaItem item,
    required String customFilename,
    String? folderId,
  }) async {
    try {
      final payload = {
        'source_url': item.url,
        'headers': item.headers,
        'filename': customFilename,
        'target_provider': account.provider.name,
        'target_access_token': account.accessToken,
        'target_folder_id': folderId ?? account.defaultFolderId,
        'telegram_bot_token': account.telegramBotToken,
        'telegram_chat_id': account.telegramChatId,
      };

      final res = await http.post(
        Uri.parse('https://ot.goprivate.fun/api/cloud_transfer.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      return res.statusCode == 200;
    } catch (e) {
      debugPrint('dispatchServerSideJob error: $e');
      return false;
    }
  }

  // --- 6. Direct RAM Streaming Pipe: Stream Web to Cloud with 0 Phone Storage ---

  static Future<bool> streamDirectToGoogleDrive({
    required CloudAccount account,
    required String sourceUrl,
    required String customFilename,
    Map<String, dynamic>? customHeaders,
    String? folderId,
    Function(int receivedBytes, int totalBytes, double speedBytesSec)? onProgress,
    CancelToken? cancelToken,
  }) async {
    try {
      final token = account.accessToken;
      if (token == null || token.isEmpty) return false;

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
      if (customHeaders != null) reqHeaders.addAll(customHeaders);
      if (!reqHeaders.containsKey('Referer') && !reqHeaders.containsKey('referer')) {
        try {
          final u = Uri.parse(sourceUrl);
          if (u.host.contains('streamtape') || u.host.contains('tapecontent') || u.host.contains('strcloud')) {
            reqHeaders['Referer'] = 'https://streamtape.com/';
          } else {
            reqHeaders['Referer'] = '${u.scheme}://${u.host}/';
          }
        } catch (_) {}
      }

      final sourceRes = await _dio.get<ResponseBody>(
        sourceUrl,
        cancelToken: cancelToken,
        options: Options(
          headers: reqHeaders,
          responseType: ResponseType.stream,
          receiveTimeout: const Duration(hours: 2),
        ),
      );

      int totalBytes = 0;
      final clHeader = sourceRes.data?.headers['content-length']?.firstOrNull;
      if (clHeader != null) {
        totalBytes = int.tryParse(clHeader) ?? 0;
      }

      final metadata = {
        'name': customFilename,
        if (folderId != null && folderId.isNotEmpty) 'parents': [folderId],
      };

      final initHeaders = <String, String>{
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json; charset=UTF-8',
      };
      if (totalBytes > 0) {
        initHeaders['X-Upload-Content-Length'] = totalBytes.toString();
      }

      final initRes = await http.post(
        Uri.parse('https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable'),
        headers: initHeaders,
        body: jsonEncode(metadata),
      );

      if (initRes.statusCode != 200) {
        debugPrint('Google Drive stream init failed: ${initRes.statusCode} - ${initRes.body}');
        return false;
      }

      final uploadUri = initRes.headers['location'];
      if (uploadUri == null) return false;

      const chunkSize = 2 * 1024 * 1024; // 2 MB RAM buffer
      final buffer = BytesBuilder(copy: false);
      int uploadedBytes = 0;
      DateTime lastTime = DateTime.now();
      int lastBytes = 0;

      await for (final chunk in sourceRes.data!.stream) {
        if (cancelToken?.isCancelled == true) return false;
        buffer.add(chunk);

        if (buffer.length >= chunkSize) {
          final chunkData = buffer.takeBytes();
          final endByte = uploadedBytes + chunkData.length - 1;
          final totalStr = totalBytes > 0 ? totalBytes.toString() : '*';

          final putRes = await http.put(
            Uri.parse(uploadUri),
            headers: {
              'Content-Length': chunkData.length.toString(),
              'Content-Range': 'bytes $uploadedBytes-$endByte/$totalStr',
            },
            body: chunkData,
          );

          uploadedBytes += chunkData.length;

          final now = DateTime.now();
          final elapsedMs = now.difference(lastTime).inMilliseconds;
          if (elapsedMs >= 500 && onProgress != null) {
            final delta = uploadedBytes - lastBytes;
            final speed = delta / (elapsedMs / 1000.0);
            onProgress(uploadedBytes, totalBytes, speed);
            lastTime = now;
            lastBytes = uploadedBytes;
          }

          if (putRes.statusCode == 200 || putRes.statusCode == 201) {
            if (onProgress != null) onProgress(uploadedBytes, totalBytes, 0);
            return true;
          } else if (putRes.statusCode != 308) {
            debugPrint('Google Drive stream unexpected code: ${putRes.statusCode} - ${putRes.body}');
            return false;
          }
        }
      }

      if (buffer.length > 0) {
        final chunkData = buffer.takeBytes();
        final endByte = uploadedBytes + chunkData.length - 1;
        final totalStr = totalBytes > 0 ? totalBytes.toString() : (uploadedBytes + chunkData.length).toString();

        final finalRes = await http.put(
          Uri.parse(uploadUri),
          headers: {
            'Content-Length': chunkData.length.toString(),
            'Content-Range': 'bytes $uploadedBytes-$endByte/$totalStr',
          },
          body: chunkData,
        );

        uploadedBytes += chunkData.length;
        if (onProgress != null) onProgress(uploadedBytes, totalBytes > 0 ? totalBytes : uploadedBytes, 0);

        return (finalRes.statusCode == 200 || finalRes.statusCode == 201);
      }

      return true;
    } catch (e) {
      debugPrint('streamDirectToGoogleDrive error: $e');
      return false;
    }
  }

  static Future<bool> streamDirectToOneDrive({
    required CloudAccount account,
    required String sourceUrl,
    required String customFilename,
    Map<String, dynamic>? customHeaders,
    String? folderPath,
    Function(int receivedBytes, int totalBytes, double speedBytesSec)? onProgress,
    CancelToken? cancelToken,
  }) async {
    try {
      String? token = account.accessToken;
      if (account.isExpired) {
        token = await CloudAuthService.refreshOneDriveToken(account);
      }
      if (token == null || token.isEmpty) return false;

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
      if (customHeaders != null) reqHeaders.addAll(customHeaders);
      if (!reqHeaders.containsKey('Referer') && !reqHeaders.containsKey('referer')) {
        try {
          final u = Uri.parse(sourceUrl);
          if (u.host.contains('streamtape') || u.host.contains('tapecontent') || u.host.contains('strcloud')) {
            reqHeaders['Referer'] = 'https://streamtape.com/';
          } else {
            reqHeaders['Referer'] = '${u.scheme}://${u.host}/';
          }
        } catch (_) {}
      }

      final sourceRes = await _dio.get<ResponseBody>(
        sourceUrl,
        cancelToken: cancelToken,
        options: Options(
          headers: reqHeaders,
          responseType: ResponseType.stream,
          receiveTimeout: const Duration(hours: 2),
        ),
      );

      int totalBytes = 0;
      final clHeader = sourceRes.data?.headers['content-length']?.firstOrNull;
      if (clHeader != null) {
        totalBytes = int.tryParse(clHeader) ?? 0;
      }

      final cleanPath = (folderPath != null && folderPath.isNotEmpty) ? '$folderPath/$customFilename' : customFilename;
      final encodedName = Uri.encodeComponent(cleanPath);
      final sessionUrl = 'https://graph.microsoft.com/v1.0/me/drive/root:/$encodedName:/createUploadSession';

      final sessionRes = await http.post(
        Uri.parse(sessionUrl),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'item': {'@microsoft.graph.conflictBehavior': 'rename'}
        }),
      );

      if (sessionRes.statusCode != 200) {
        debugPrint('OneDrive createUploadSession failed: ${sessionRes.statusCode} - ${sessionRes.body}');
        return false;
      }

      final sessionData = jsonDecode(sessionRes.body) as Map<String, dynamic>;
      final uploadUrl = sessionData['uploadUrl'] as String?;
      if (uploadUrl == null) return false;

      const chunkSize = 320 * 1024 * 10; // 3.2 MB chunks
      final buffer = BytesBuilder(copy: false);
      int uploadedBytes = 0;
      DateTime lastTime = DateTime.now();
      int lastBytes = 0;

      await for (final chunk in sourceRes.data!.stream) {
        if (cancelToken?.isCancelled == true) return false;
        buffer.add(chunk);

        if (buffer.length >= chunkSize) {
          final chunkData = buffer.takeBytes();
          final endByte = uploadedBytes + chunkData.length - 1;
          final totalStr = totalBytes > 0 ? totalBytes.toString() : '*';

          final chunkRes = await http.put(
            Uri.parse(uploadUrl),
            headers: {
              'Content-Length': chunkData.length.toString(),
              'Content-Range': 'bytes $uploadedBytes-$endByte/$totalStr',
            },
            body: chunkData,
          );

          uploadedBytes += chunkData.length;

          final now = DateTime.now();
          final elapsedMs = now.difference(lastTime).inMilliseconds;
          if (elapsedMs >= 500 && onProgress != null) {
            final delta = uploadedBytes - lastBytes;
            final speed = delta / (elapsedMs / 1000.0);
            onProgress(uploadedBytes, totalBytes, speed);
            lastTime = now;
            lastBytes = uploadedBytes;
          }

          if (chunkRes.statusCode != 200 && chunkRes.statusCode != 201 && chunkRes.statusCode != 202) {
            debugPrint('OneDrive chunk upload failed: ${chunkRes.statusCode} - ${chunkRes.body}');
            return false;
          }
        }
      }

      if (buffer.length > 0) {
        final chunkData = buffer.takeBytes();
        final endByte = uploadedBytes + chunkData.length - 1;
        final totalStr = totalBytes > 0 ? totalBytes.toString() : (uploadedBytes + chunkData.length).toString();

        final chunkRes = await http.put(
          Uri.parse(uploadUrl),
          headers: {
            'Content-Length': chunkData.length.toString(),
            'Content-Range': 'bytes $uploadedBytes-$endByte/$totalStr',
          },
          body: chunkData,
        );

        uploadedBytes += chunkData.length;
        if (onProgress != null) onProgress(uploadedBytes, totalBytes > 0 ? totalBytes : uploadedBytes, 0);

        return (chunkRes.statusCode == 200 || chunkRes.statusCode == 201 || chunkRes.statusCode == 202);
      }

      return true;
    } catch (e) {
      debugPrint('streamDirectToOneDrive error: $e');
      return false;
    }
  }

  static String _getExtension(SniffedMediaItem item) {
    switch (item.type) {
      case SniffedMediaType.hlsStream:
        return '.m3u8';
      case SniffedMediaType.mpdStream:
        return '.mpd';
      case SniffedMediaType.mp4Video:
        return '.mp4';
      case SniffedMediaType.genericVideo:
        return '.mp4';
      case SniffedMediaType.audio:
        return '.mp3';
      case SniffedMediaType.image:
        return '.jpg';
    }
  }
}
