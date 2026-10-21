import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:private_cinema_mobile/theme/app_colors.dart';
import 'package:private_cinema_mobile/data/wifi_cast_service.dart';

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

      await for (final chunk in file.openRead()) {
        socket.add(chunk);
        sentBytes += chunk.length;

        final now = stopwatch.elapsedMilliseconds;
        if (now - lastUpdate > 100 || sentBytes == fileSize) {
          lastUpdate = now;
          final elapsedSec = now / 1000.0;
          final speedMBs = elapsedSec > 0 ? (sentBytes / (1024 * 1024)) / elapsedSec : 0.0;
          final remainingBytes = fileSize - sentBytes;
          final etaSec = speedMBs > 0 ? (remainingBytes / (1024 * 1024 * speedMBs)).round() : 0;

          if (mounted) {
            setState(() {
              _progress = sentBytes / fileSize;
              _transferSpeed = '${speedMBs.toStringAsFixed(1)} MB/s';
              _transferEta = etaSec > 0 ? '${etaSec}s remaining' : '';
              _transferredMb = '${(sentBytes / 1048576).toStringAsFixed(1)} / ${(fileSize / 1048576).toStringAsFixed(1)} MB';
            });
          }
        }
      }
      await socket.flush();

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
      final videoExts = ['mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'webm', 'm4v'];
      final isVideo = videoExts.contains(ext);

      final newItem = {
        'name': fileName,
        'path': savePath,
        'size': fileSize,
        'type': isVideo ? 'video' : 'file',
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

  Future<void> _saveFileToDownloads(Map<String, dynamic> item) async {
    final String? srcPath = item['path'];
    final String fileName = item['name'] ?? 'received_file';

    if (srcPath == null || !File(srcPath).existsSync()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('File not found on device storage.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    try {
      Directory? downloadsDir;
      if (Platform.isAndroid) {
        final pubDownload = Directory('/storage/emulated/0/Download');
        if (await pubDownload.exists()) {
          downloadsDir = pubDownload;
        } else {
          try {
            await pubDownload.create(recursive: true);
            downloadsDir = pubDownload;
          } catch (_) {}
        }
      }

      if (downloadsDir == null) {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          downloadsDir = Directory('${extDir.path}/Download');
          if (!await downloadsDir.exists()) await downloadsDir.create(recursive: true);
        } else {
          final docDir = await getApplicationDocumentsDirectory();
          downloadsDir = Directory('${docDir.path}/Download');
          if (!await downloadsDir.exists()) await downloadsDir.create(recursive: true);
        }
      }

      final targetPath = '${downloadsDir.path}/$fileName';
      final srcFile = File(srcPath);
      await srcFile.copy(targetPath);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.download_done_rounded, color: Colors.greenAccent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Saved to Downloads: $fileName',
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
    } catch (e) {
      debugPrint('Error saving file to downloads: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving to downloads: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _startServer() async {
    try {
      final interfaces = await NetworkInterface.list();
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            _localIp = addr.address;
            break;
          }
        }
      }
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 58526);
      _port = 58526;
      setState(() {});

      _server!.listen((HttpRequest request) async {
        if (request.method == 'POST' && request.uri.path == '/upload') {
          await _handleUpload(request);
        } else if (request.uri.path == '/ping') {
          request.response.headers.contentType = ContentType.json;
          request.response.write(json.encode({'status': 'ok', 'device_name': 'Mobile Phone', 'port': _port}));
          await request.response.close();
        }
      });
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
                      Text('Sending file...', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
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
          Text(
            'Local Mobile Receiver: $_localIp:$_port',
            style: GoogleFonts.outfit(color: AppColors.accentBright, fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _receivedFiles.isEmpty
                ? Center(child: Text('No files received yet.', style: GoogleFonts.outfit(color: Colors.white38)))
                : ListView.separated(
                    itemCount: _receivedFiles.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (ctx, idx) {
                      final f = _receivedFiles[idx];
                      final isVideo = f['type'] == 'video';
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: isVideo ? AppColors.accentBright.withValues(alpha: 0.15) : Colors.white10,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                isVideo ? Icons.movie_rounded : Icons.insert_drive_file_rounded,
                                color: isVideo ? AppColors.accentBright : Colors.white70,
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
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Colors.white24),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: () => _saveFileToDownloads(f),
                              icon: const Icon(Icons.download_rounded, size: 14),
                              label: Text('SAVE', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                              onPressed: () => _deleteFile(idx),
                            ),
                          ],
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
