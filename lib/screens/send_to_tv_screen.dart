import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:private_cinema_mobile/theme/app_colors.dart';
import 'package:private_cinema_mobile/data/wifi_cast_service.dart';
import 'package:private_cinema_mobile/screens/video_player_screen.dart';
import 'package:share_plus/share_plus.dart';

class SendToTvScreen extends StatefulWidget {
  const SendToTvScreen({super.key});
  @override
  State<SendToTvScreen> createState() => _SendToTvScreenState();
}

class _SendToTvScreenState extends State<SendToTvScreen> {
  int _activeTab = 0; // 0: Send to TV Mode, 1: Receive Files Mode

  // File state
  PlatformFile? _selectedFile;
  bool _isSending = false;
  double _progress = 0;
  String? _status;
  String? _sendingToDeviceName;
  String? _transferSpeed;
  String? _transferEta;
  String? _transferredMb;
  List<Map<String, String>> _history = [];

  // Local Wi-Fi Device Discovery state
  bool _isScanningDevices = false;
  List<Map<String, dynamic>> _discoveredTvDevices = [];
  Timer? _autoRefreshTimer;

  // Receive Mode state
  HttpServer? _server;
  RawDatagramSocket? _udpSocket;
  int _port = 58526;
  String _localIp = '';
  List<Map<String, dynamic>> _receivedFiles = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _loadReceivedFiles();
    _startServer();
    _scanForNearbyTvs();
    // Auto refresh discovered TV devices every 4 seconds
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted && !_isSending && _activeTab == 0) {
        _scanForNearbyTvs(showLoader: false);
      }
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _server?.close(force: true);
    try {
      _udpSocket?.close();
    } catch (_) {}
    super.dispose();
  }

  // --- Fast UDP & Subnet Discovery for TV Devices ---

  Future<void> _scanForNearbyTvs({bool showLoader = true}) async {
    if (!mounted) return;
    if (showLoader) setState(() => _isScanningDevices = true);

    try {
      final found = await WifiCastService.discoverTvDevices(
        timeout: const Duration(milliseconds: 1800),
      );
      if (mounted) {
        setState(() {
          _discoveredTvDevices = found;
          _isScanningDevices = false;
        });
      }
    } catch (e) {
      debugPrint('TV discovery error: $e');
      if (mounted) setState(() => _isScanningDevices = false);
    }
  }

  // --- Send File to Selected TV ---

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _selectedFile = result.files.first;
        _status = null;
      });
      // Scan for TVs immediately after picking file
      _scanForNearbyTvs();
    }
  }

  Future<void> _sendFileToTv(Map<String, dynamic> device) async {
    if (_selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a file first above!')),
      );
      return;
    }

    final targetHost = device['host'] as String;
    final deviceName = device['name'] as String;

    setState(() {
      _isSending = true;
      _progress = 0;
      _transferSpeed = null;
      _transferEta = null;
      _transferredMb = null;
      _sendingToDeviceName = deviceName;
      _status = 'Connecting to $deviceName...';
    });

    Socket? socket;
    try {
      final fileName = _selectedFile!.name;
      final file = File(_selectedFile!.path!);
      final fileSize = await file.length();
      final uri = Uri.parse('http://$targetHost');
      final host = uri.host;
      final port = uri.port;

      _status = 'Sending $fileName...';

      socket = await Socket.connect(host, port, timeout: const Duration(seconds: 10));

      final requestLine = 'POST /upload?name=${Uri.encodeComponent(fileName)} HTTP/1.1\r\n';
      final hostHeader = 'Host: $targetHost\r\n';
      final contentType = 'Content-Type: application/octet-stream\r\n';
      final contentLength = 'Content-Length: $fileSize\r\n';
      final connection = 'Connection: close\r\n';
      final headersEnd = '\r\n';

      socket.add(utf8.encode(requestLine));
      socket.add(utf8.encode(hostHeader));
      socket.add(utf8.encode(contentType));
      socket.add(utf8.encode(contentLength));
      socket.add(utf8.encode(connection));
      socket.add(utf8.encode(headersEnd));
      await socket.flush();

      final stopwatch = Stopwatch()..start();
      int sentBytes = 0;
      int lastUpdate = 0;
      const int chunkSize = 65536; // 64 KB chunk size for accurate TCP pacing

      final raf = await file.open(mode: FileMode.read);
      try {
        while (sentBytes < fileSize) {
          final toRead = (fileSize - sentBytes) > chunkSize ? chunkSize : (fileSize - sentBytes);
          final chunk = await raf.read(toRead);
          if (chunk.isEmpty) break;

          socket.add(chunk);
          await socket.flush(); // Waits for TCP socket buffer to actually push bytes over Wi-Fi
          sentBytes += chunk.length;

          final now = stopwatch.elapsedMilliseconds;
          if (now - lastUpdate > 120 || sentBytes == fileSize) {
            lastUpdate = now;
            final elapsedSec = now / 1000.0;
            final speedMBs = elapsedSec > 0 ? (sentBytes / (1024 * 1024)) / elapsedSec : 0.0;
            final remainingBytes = fileSize - sentBytes;
            final etaSec = speedMBs > 0 ? (remainingBytes / (1024 * 1024 * speedMBs)).round() : 0;

            if (mounted) {
              setState(() {
                _progress = (sentBytes / fileSize).clamp(0.0, 1.0);
                _transferSpeed = '${speedMBs.toStringAsFixed(1)} MB/s';
                _transferEta = etaSec > 0 ? '${etaSec}s remaining' : '';
                _transferredMb = '${(sentBytes / 1048576).toStringAsFixed(1)} / ${(fileSize / 1048576).toStringAsFixed(1)} MB';
              });
            }
          }
        }
      } finally {
        await raf.close();
      }

      // Read HTTP response with 15s timeout
      final responseBytes = <int>[];
      await socket.listen((data) => responseBytes.addAll(data)).asFuture().timeout(const Duration(seconds: 15));
      final responseStr = utf8.decode(responseBytes);
      try { await socket.close(); } catch (_) {}

      if (responseStr.contains('200') || responseStr.contains('"status":"success"')) {
        _status = '✓ Sent successfully to $deviceName!';
        _history.insert(0, {'ip': targetHost, 'file': fileName, 'time': DateTime.now().toIso8601String()});
        _saveHistory();
      } else {
        _status = 'TV Error: ${responseStr.substring(0, responseStr.length.clamp(0, 150))}';
      }
    } catch (e) {
      _status = 'Transfer failed: $e';
    } finally {
      try { socket?.destroy(); } catch (_) {}
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('send_to_tv_history');
    if (raw != null) {
      _history = raw.map((e) {
        final parts = e.split('|');
        return {'ip': parts[0], 'file': parts[1], 'time': parts.length > 2 ? parts[2] : ''};
      }).toList();
      if (mounted) setState(() {});
    }
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('send_to_tv_history', _history.map((e) => '${e['ip']}|${e['file']}|${e['time']}').toList());
  }

  // --- Receive Mode Logic ---

  Future<void> _loadReceivedFiles() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('send_to_tv_received_files');
    if (raw != null) {
      try { _receivedFiles = (json.decode(raw) as List).cast<Map<String, dynamic>>(); } catch (_) {}
    }
  }

  Future<void> _saveFileIndex() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('send_to_tv_received_files', json.encode(_receivedFiles));
  }

  void _deleteFile(int index) {
    final f = _receivedFiles[index];
    try { File(f['path']).deleteSync(); } catch (_) {}
    setState(() => _receivedFiles.removeAt(index));
    _saveFileIndex();
  }

  Future<void> _handleUpload(HttpRequest request) async {
    try {
      final fileName = request.uri.queryParameters['name'] ?? 'file_${DateTime.now().millisecondsSinceEpoch}';
      final dir = await getApplicationDocumentsDirectory();
      final saveDir = Directory('${dir.path}/ReceivedFiles');
      if (!await saveDir.exists()) await saveDir.create(recursive: true);

      final savePath = '${saveDir.path}/$fileName';
      final file = File(savePath);
      final sink = file.openWrite();

      int fileSize = 0;
      await for (final chunk in request) {
        sink.add(chunk);
        fileSize += chunk.length;
      }
      await sink.flush();
      await sink.close();

      if (fileSize == 0) {
        request.response.statusCode = 400;
        request.response.write('Empty file');
        await request.response.close();
        return;
      }

      final ext = fileName.split('.').last.toLowerCase();
      final videoExts = ['mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'webm', 'm4v', 'ts', '3gp'];
      final imageExts = ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'];
      final isVideo = videoExts.contains(ext);
      final isImage = imageExts.contains(ext);

      final newItem = {
        'name': fileName,
        'path': savePath,
        'size': fileSize,
        'type': isVideo ? 'video' : (isImage ? 'image' : 'file'),
        'ext': ext,
        'time': DateTime.now().toIso8601String(),
      };

      if (mounted) {
        setState(() {
          _receivedFiles.insert(0, newItem);
        });
      }
      await _saveFileIndex();

      request.response.statusCode = 200;
      request.response.headers.contentType = ContentType.json;
      request.response.write(json.encode({'status': 'ok', 'path': savePath}));
      await request.response.close();
    } catch (e) {
      debugPrint('Mobile Receiver upload error: $e');
      request.response.statusCode = 500;
      await request.response.close();
    }
  }

  void _openOrPlayFile(Map<String, dynamic> item) {
    final String? srcPath = item['path'];
    final String fileName = item['name'] ?? 'File';

    if (srcPath == null || !File(srcPath).existsSync()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File not found on device storage.'), backgroundColor: Colors.redAccent),
        );
      }
      return;
    }

    final ext = (item['ext'] ?? fileName.split('.').last).toString().toLowerCase();
    final videoExts = ['mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'webm', 'm4v', 'ts', '3gp'];
    final imageExts = ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'];
    final audioExts = ['mp3', 'm4a', 'aac', 'flac', 'wav', 'ogg'];

    if (videoExts.contains(ext) || audioExts.contains(ext)) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VideoPlayerScreen(
            videoSource: srcPath,
            title: fileName,
            isLive: false,
          ),
        ),
      );
    } else if (imageExts.contains(ext)) {
      _showImageViewer(srcPath, fileName);
    } else {
      Share.shareXFiles([XFile(srcPath, name: fileName)], text: fileName);
    }
  }

  void _showImageViewer(String imagePath, String fileName) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black.withValues(alpha: 0.95),
        insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      fileName,
                      style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.share_rounded, color: Colors.white70, size: 20),
                    onPressed: () => Share.shareXFiles([XFile(imagePath, name: fileName)], text: fileName),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 22),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 4.0,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    File(imagePath),
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => const Padding(
                      padding: EdgeInsets.all(40),
                      child: Text('Unable to render image preview', style: TextStyle(color: Colors.white54)),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],
        ),
      ),
    );
  }

  Future<void> _saveFileToDownloads(Map<String, dynamic> item) async {
    final String? srcPath = item['path'];
    final String fileName = item['name'] ?? 'received_file';

    if (srcPath == null || !File(srcPath).existsSync()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File not found on device storage.'), backgroundColor: Colors.redAccent),
        );
      }
      return;
    }

    try {
      if (Platform.isIOS) {
        // On iOS: Share Sheet provides native "Save Video", "Save Image", "Save to Files"
        await Share.shareXFiles(
          [XFile(srcPath, name: fileName)],
          text: 'Save $fileName',
        );
        return;
      }

      // Android: Copy to public Downloads/GoXio/
      Directory? downloadsDir;
      final pubDownload = Directory('/storage/emulated/0/Download');
      if (await pubDownload.exists()) {
        downloadsDir = pubDownload;
      } else {
        downloadsDir = await getExternalStorageDirectory();
      }

      if (downloadsDir != null) {
        final goxioDownloads = Directory('${downloadsDir.path}/GoXio');
        if (!await goxioDownloads.exists()) await goxioDownloads.create(recursive: true);
        final targetPath = '${goxioDownloads.path}/$fileName';
        await File(srcPath).copy(targetPath);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.download_done_rounded, color: Colors.greenAccent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Saved to Downloads/GoXio/$fileName',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF1E293B),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error saving file to downloads: $e');
      try {
        await Share.shareXFiles([XFile(srcPath, name: fileName)], text: fileName);
      } catch (err) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error saving: $err'), backgroundColor: Colors.redAccent),
          );
        }
      }
    }
  }

  Future<void> _startServer() async {
    try {
      _localIp = await WifiCastService.getLocalIp();
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 58526);
      _port = 58526;
      if (mounted) setState(() {});

      _server!.listen((HttpRequest request) async {
        if (request.method == 'POST' && request.uri.path == '/upload') {
          await _handleUpload(request);
        } else if (request.uri.path == '/ping') {
          request.response.headers.contentType = ContentType.json;
          final modelName = Platform.isIOS ? 'iPhone' : 'Android Mobile';
          request.response.write(json.encode({'status': 'ok', 'device_name': modelName, 'port': _port}));
          await request.response.close();
        }
      });

      // Start UDP Discovery Listener on port 41235 for zero-latency peer discovery
      try {
        _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, WifiCastService.mobileUdpPort);
        _udpSocket!.broadcastEnabled = true;
        _udpSocket!.listen((RawSocketEvent event) {
          if (event == RawSocketEvent.read) {
            final datagram = _udpSocket?.receive();
            if (datagram != null) {
              try {
                final msg = utf8.decode(datagram.data);
                if (msg.contains('discover') || msg.contains('goxio')) {
                  final resp = json.encode({
                    'type': 'mobile',
                    'name': Platform.isIOS ? 'iPhone (GoXio)' : 'Android Phone (GoXio)',
                    'ip': _localIp,
                    'port': _port,
                  });
                  _udpSocket?.send(utf8.encode(resp), datagram.address, datagram.port);
                }
              } catch (_) {}
            }
          }
        });
      } catch (e) {
        debugPrint('Mobile UDP discovery responder error: $e');
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Send File to TV', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
        leading: IconButton(icon: const Icon(Icons.close_rounded, color: Colors.white), onPressed: () => Navigator.of(context).pop()),
      ),
      body: Column(
        children: [
          // Top Tab Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                Expanded(child: _buildTabChip(0, 'Send to TV', Icons.tv_rounded)),
                const SizedBox(width: 12),
                Expanded(child: _buildTabChip(1, 'Received Files', Icons.download_rounded)),
              ],
            ),
          ),
          const SizedBox(height: 10),

          Expanded(
            child: _activeTab == 0 ? _buildSendToTvView() : _buildReceivedFilesView(),
          ),
        ],
      ),
    );
  }

  Widget _buildTabChip(int index, String label, IconData icon) {
    final active = _activeTab == index;
    return GestureDetector(
      onTap: () => setState(() => _activeTab = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: active ? AppColors.accentBright : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: active ? Colors.transparent : Colors.white10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: active ? Colors.black : Colors.white60, size: 18),
            const SizedBox(width: 8),
            Text(label, style: GoogleFonts.outfit(color: active ? Colors.black : Colors.white70, fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  void _showManualIpDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Direct IP Transfer (Mobile / TV)',
          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter the receiver IP shown on the other phone (Android / iOS) or TV screen:',
              style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                hintText: 'e.g. 192.168.1.15 or 192.168.1.15:58526',
                hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white12),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('CANCEL', style: GoogleFonts.outfit(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentBright,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              final raw = controller.text.trim();
              if (raw.isEmpty) return;
              Navigator.of(ctx).pop();
              final host = raw.contains(':') ? raw : '$raw:58526';
              final ip = raw.contains(':') ? raw.split(':').first : raw;
              _sendFileToTv({
                'name': 'Device ($host)',
                'ip': ip,
                'port': raw.contains(':') ? (int.tryParse(raw.split(':').last) ?? 58526) : 58526,
                'host': host,
                'type': 'direct',
              });
            },
            child: Text('SEND FILE', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildSendToTvView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // STEP 1: Select File Box
          Text(
            'STEP 1: SELECT FILE TO SEND',
            style: GoogleFonts.outfit(color: Colors.white38, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _isSending ? null : _pickFile,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _selectedFile != null ? AppColors.accentBright.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _selectedFile != null ? AppColors.accentBright : Colors.white12,
                  width: _selectedFile != null ? 1.5 : 1.0,
                ),
              ),
              child: _selectedFile != null
                  ? Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.accentBright.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.insert_drive_file_rounded, color: AppColors.accentBright, size: 28),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _selectedFile!.name,
                                style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${(_selectedFile!.size ~/ 1048576)} MB • Ready to send',
                                style: GoogleFonts.outfit(color: AppColors.accentBright, fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: _isSending ? null : _pickFile,
                          child: Text('CHANGE', style: GoogleFonts.outfit(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        const Icon(Icons.cloud_upload_rounded, color: Colors.white38, size: 44),
                        const SizedBox(height: 10),
                        Text('Tap here to select a movie or file', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 4),
                        Text('MP4, MKV, AVI, APK, etc.', style: GoogleFonts.outfit(color: Colors.white38, fontSize: 11)),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 24),

          // Transfer Progress Bar (if sending)
          if (_isSending) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.accentBright.withValues(alpha: 0.4)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _sendingToDeviceName != null ? 'Sending to $_sendingToDeviceName...' : 'Sending file...',
                        style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      Text(
                        '${(_progress * 100).toInt()}%${_transferSpeed != null ? ' • $_transferSpeed' : ''}',
                        style: GoogleFonts.outfit(color: AppColors.accentBright, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  LinearProgressIndicator(
                    value: _progress > 0 ? _progress : null,
                    backgroundColor: Colors.white10,
                    color: AppColors.accentBright,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  if (_transferredMb != null || _transferEta != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_transferredMb ?? '', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                        Text(_transferEta ?? '', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          if (_status != null && !_isSending) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _status!.startsWith('✓') ? Colors.green.withValues(alpha: 0.15) : Colors.red.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _status!.startsWith('✓') ? Colors.greenAccent : Colors.redAccent),
              ),
              child: Text(
                _status!,
                style: GoogleFonts.outfit(color: _status!.startsWith('✓') ? Colors.greenAccent : Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 20),
          ],

          // STEP 2: Choose TV / Mobile Device List
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'STEP 2: CHOOSE TARGET (TV / MOBILE)',
                style: GoogleFonts.outfit(color: Colors.white38, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Direct IP Transfer',
                    icon: const Icon(Icons.dialpad_rounded, color: Colors.white70, size: 20),
                    onPressed: () => _showManualIpDialog(),
                  ),
                  IconButton(
                    icon: _isScanningDevices
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70))
                        : const Icon(Icons.refresh_rounded, color: Colors.white70, size: 18),
                    onPressed: _isScanningDevices ? null : () => _scanForNearbyTvs(),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (_isScanningDevices && _discoveredTvDevices.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.02), borderRadius: BorderRadius.circular(16)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentBright),
                  const SizedBox(width: 14),
                  Text('Scanning Wi-Fi for TV & Mobile devices...', style: GoogleFonts.outfit(color: Colors.white60, fontSize: 13)),
                ],
              ),
            )
          else if (_discoveredTvDevices.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.02),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                children: [
                  const Icon(Icons.devices_other_rounded, color: Colors.white24, size: 36),
                  const SizedBox(height: 8),
                  Text(
                    'No Receiver Found on Local Wi-Fi',
                    style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Open the app on your TV, Android phone, or iPhone (tab "Received Files") on the same Wi-Fi.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(color: Colors.white38, fontSize: 11),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white12,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () => _scanForNearbyTvs(),
                        icon: const Icon(Icons.search_rounded, size: 16),
                        label: Text('SCAN AGAIN', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accentBright.withValues(alpha: 0.2),
                          foregroundColor: AppColors.accentBright,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () => _showManualIpDialog(),
                        icon: const Icon(Icons.edit_note_rounded, size: 16),
                        label: Text('ENTER IP', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ],
              ),
            )
          else
            Column(
              children: _discoveredTvDevices.map((device) {
                final isMobile = device['type'] == 'mobile';
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.accentBright.withValues(alpha: 0.4)),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.accentBright.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isMobile ? Icons.smartphone_rounded : Icons.tv_rounded,
                        color: AppColors.accentBright,
                        size: 24,
                      ),
                    ),
                    title: Text(
                      device['name'],
                      style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    subtitle: Text(
                      'Connected on ${device['ip']}',
                      style: GoogleFonts.outfit(color: Colors.white54, fontSize: 12),
                    ),
                    trailing: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accentBright,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _isSending ? null : () => _sendFileToTv(device),
                      icon: const Icon(Icons.send_rounded, size: 16),
                      label: Text(
                        isMobile ? 'SEND TO PHONE' : 'SEND TO TV',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildReceivedFilesView() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.accentBright.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.accentBright.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.wifi_tethering_rounded, color: AppColors.accentBright, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Device Receiver Active',
                        style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      Text(
                        'Direct IP: ${_localIp.isNotEmpty ? _localIp : "Detecting..."}:$_port',
                        style: GoogleFonts.outfit(color: AppColors.accentBright, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _receivedFiles.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.folder_open_rounded, color: Colors.white24, size: 48),
                        const SizedBox(height: 10),
                        Text('No files received yet', style: GoogleFonts.outfit(color: Colors.white60, fontSize: 14)),
                        const SizedBox(height: 4),
                        Text('Send files from another device or TV to see them here', style: GoogleFonts.outfit(color: Colors.white38, fontSize: 11)),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: _receivedFiles.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 10),
                    itemBuilder: (ctx, idx) {
                      final f = _receivedFiles[idx];
                      final isVideo = f['type'] == 'video';
                      final isImage = f['type'] == 'image';
                      return InkWell(
                        onTap: () => _openOrPlayFile(f),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: isVideo
                                          ? AppColors.accentBright.withValues(alpha: 0.15)
                                          : (isImage ? Colors.purpleAccent.withValues(alpha: 0.15) : Colors.white10),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      isVideo
                                          ? Icons.movie_rounded
                                          : (isImage ? Icons.image_rounded : Icons.insert_drive_file_rounded),
                                      color: isVideo
                                          ? AppColors.accentBright
                                          : (isImage ? Colors.purpleAccent : Colors.white70),
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          f['name'] ?? '',
                                          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${((f['size'] ?? 0) / 1048576).toStringAsFixed(1)} MB',
                                          style: GoogleFonts.outfit(color: Colors.white38, fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  if (isVideo)
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.accentBright,
                                        foregroundColor: Colors.black,
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      onPressed: () => _openOrPlayFile(f),
                                      icon: const Icon(Icons.play_arrow_rounded, size: 16),
                                      label: Text('PLAY', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold)),
                                    )
                                  else if (isImage)
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.purpleAccent,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      onPressed: () => _openOrPlayFile(f),
                                      icon: const Icon(Icons.visibility_rounded, size: 16),
                                      label: Text('VIEW', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold)),
                                    )
                                  else
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.white24,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      onPressed: () => _openOrPlayFile(f),
                                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                                      label: Text('OPEN', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold)),
                                    ),
                                  const SizedBox(width: 8),
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      side: const BorderSide(color: Colors.white24),
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    onPressed: () => _saveFileToDownloads(f),
                                    icon: const Icon(Icons.download_rounded, size: 14),
                                    label: Text('SAVE', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold)),
                                  ),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    tooltip: 'Share',
                                    icon: const Icon(Icons.share_rounded, color: Colors.white60, size: 18),
                                    onPressed: () {
                                      final path = f['path'];
                                      final name = f['name'] ?? 'file';
                                      if (path != null && File(path).existsSync()) {
                                        Share.shareXFiles([XFile(path, name: name)], text: name);
                                      }
                                    },
                                  ),
                                  IconButton(
                                    tooltip: 'Delete',
                                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                                    onPressed: () => _deleteFile(idx),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
