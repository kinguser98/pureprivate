import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:private_cinema_ios/theme/app_colors.dart';
import 'package:private_cinema_ios/screens/video_player_screen.dart';

class SendToTvScreen extends StatefulWidget {
  const SendToTvScreen({super.key});
  @override
  State<SendToTvScreen> createState() => _SendToTvScreenState();
}

class _SendToTvScreenState extends State<SendToTvScreen> {
  int _activeTab = 0; // 0: Send Mode, 1: Receive Mode

  // Send Mode state
  final TextEditingController _ipController = TextEditingController();
  PlatformFile? _selectedFile;
  bool _isSending = false;
  double _progress = 0;
  String? _status;
  List<Map<String, String>> _history = [];

  // Receive Mode state
  HttpServer? _server;
  int _port = 0;
  String _localIp = '';
  bool _isServerRunning = false;
  List<Map<String, dynamic>> _receivedFiles = [];
  List<String> _allIps = [];
  String? _serverStatusMessage;
  bool _isFilesLoading = true;

  @override
  void initState() {
    super.initState();
    _ipController.text = '192.168.1.100:58526';
    _loadHistory();
    _loadReceivedFiles();
    _startServer();
  }

  @override
  void dispose() {
    _server?.close(force: true);
    _ipController.dispose();
    super.dispose();
  }

  // --- Send Mode Logic ---

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

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _selectedFile = result.files.first;
        _status = null;
      });
    }
  }

Future<void> _sendFile() async {
  if (_selectedFile == null || _ipController.text.isEmpty) return;

  setState(() {
    _isSending = true;
    _progress = 0;
    _status = 'Connecting...';
  });

  try {
    final fileName = _selectedFile!.name;
    final file = File(_selectedFile!.path!);
    final fileSize = await file.length();
    var targetHost = _ipController.text.trim();
    final uri = Uri.parse(targetHost.startsWith('http') ? targetHost : 'http://$targetHost');
    final host = uri.host;
    final port = uri.port == 0 ? 80 : uri.port;

    _status = 'Sending $fileName (${fileSize ~/ 1048576} MB)...';

    final socket = await Socket.connect(host, port, timeout: const Duration(seconds: 15));

    final requestLine = 'POST /upload?name=${Uri.encodeComponent(fileName)} HTTP/1.1\r\n';
    final hostHeader = 'Host: $host:$port\r\n';
    final contentType = 'Content-Type: application/octet-stream\r\n';
    final contentLength = 'Content-Length: $fileSize\r\n';
    final headersEnd = '\r\n';

    socket.add(requestLine.codeUnits);
    socket.add(hostHeader.codeUnits);
    socket.add(contentType.codeUnits);
    socket.add(contentLength.codeUnits);
    socket.add(headersEnd.codeUnits);
    await socket.flush();

    int sentBytes = 0;
    await for (final chunk in file.openRead()) {
      socket.add(chunk);
      sentBytes += chunk.length;
      if (mounted) {
        setState(() {
          _progress = sentBytes / fileSize;
        });
      }
    }
    await socket.flush();
  final responseStr = await socket.map(utf8.decode).join();
  await socket.close();

  if (responseStr.contains('200') || responseStr.contains('"success":true')) {
      _status = '✓ Sent successfully!';
      _history.insert(0, {'ip': _ipController.text, 'file': fileName, 'time': DateTime.now().toIso8601String()});
      _saveHistory();
    } else {
      _status = 'Server error: ${responseStr.substring(0, responseStr.length.clamp(0, 200))}';
    }
  } catch (e) {
    _status = 'Error: $e';
  }

  setState(() => _isSending = false);
}

  Future<void> _scanQrCode() async {
    final status = await Permission.camera.request();
    if (status.isGranted) {
      if (!mounted) return;
      final scannedIp = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        backgroundColor: const Color(0xFF0F111E),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (ctx) {
          final scanController = MobileScannerController();
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.7,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Scan Receiver QR Code',
                          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: Colors.white60),
                          onPressed: () {
                            scanController.dispose();
                            Navigator.pop(ctx);
                          },
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 24),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: MobileScanner(
                          controller: scanController,
                          onDetect: (capture) {
                            final barcodes = capture.barcodes;
                            if (barcodes.isNotEmpty) {
                              final code = barcodes.first.rawValue;
                              if (code != null && code.isNotEmpty) {
                                String parsed = code.trim();
                                if (parsed.startsWith('http://')) {
                                  parsed = parsed.replaceFirst('http://', '');
                                }
                                if (parsed.contains('/')) {
                                  parsed = parsed.split('/').first;
                                }
                                scanController.dispose();
                                Navigator.pop(ctx, parsed);
                              }
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Point camera at the QR code displayed on the TV or phone',
                      style: GoogleFonts.outfit(color: Colors.white38, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );

      if (scannedIp != null && scannedIp.isNotEmpty) {
        setState(() {
          _ipController.text = scannedIp;
          _status = '✓ Scanned IP: $scannedIp';
        });
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Camera permission is required to scan QR code.')),
        );
      }
    }
  }

  // --- Receive Mode Logic ---

  Future<void> _loadReceivedFiles() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('mobile_received_files');
    if (raw != null) {
      try {
        _receivedFiles = (json.decode(raw) as List).cast<Map<String, dynamic>>();
      } catch (_) {}
    }
    setState(() => _isFilesLoading = false);
  }

  Future<void> _saveReceivedFilesIndex() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('mobile_received_files', json.encode(_receivedFiles));
  }

  Future<void> _startServer() async {
    try {
      _allIps = [];
      final interfaces = await NetworkInterface.list();
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            _allIps.add(addr.address);
          }
        }
      }

      _localIp = _allIps.firstWhere((ip) => ip.startsWith('192.168.'),
          orElse: () => _allIps.firstWhere((ip) => ip.startsWith('10.'),
              orElse: () => _allIps.isNotEmpty ? _allIps.first : '192.168.1.100'));

      _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      _port = _server!.port;
      _isServerRunning = true;
      setState(() {});

      _server!.listen((HttpRequest request) async {
        final path = request.uri.path;

        if (request.method == 'POST' && path == '/upload') {
          await _handleUpload(request);
        } else if (path == '/files') {
          request.response.headers.contentType = ContentType.json;
          request.response.write(json.encode(_receivedFiles));
          await request.response.close();
        } else if (path == '/ping') {
          request.response.write('OK');
          await request.response.close();
        } else {
          request.response.statusCode = 404;
          request.response.write('Not found');
          await request.response.close();
        }
      });

      debugPrint('Mobile Server: Running on $_localIp:$_port');
    } catch (e) {
      setState(() => _serverStatusMessage = 'Server error: $e');
    }
  }

  Future<void> _handleUpload(HttpRequest request) async {
    try {
      final fileName = request.uri.queryParameters['name'] ?? 'file_${DateTime.now().millisecondsSinceEpoch}';
      final fileBytes = await request.fold<List<int>>([], (prev, chunk) => [...prev, ...chunk]);

      if (fileBytes.isEmpty) {
        request.response.statusCode = 400;
        request.response.write('Empty file');
        await request.response.close();
        return;
      }

      final dir = await getApplicationDocumentsDirectory();
      final saveDir = Directory('${dir.path}/ReceivedFiles');
      if (!await saveDir.exists()) await saveDir.create(recursive: true);

      final ext = fileName.split('.').last.toLowerCase();
      final videoExts = ['mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'webm', 'm4v'];
      final isVideo = videoExts.contains(ext);

      final savePath = '${saveDir.path}/$fileName';
      await File(savePath).writeAsBytes(fileBytes);
      final fileSize = fileBytes.length;

      setState(() {
        _receivedFiles.insert(0, {
          'name': fileName,
          'path': savePath,
          'size': fileSize,
          'type': isVideo ? 'video' : 'file',
          'ext': ext,
          'time': DateTime.now().toIso8601String(),
        });
        _serverStatusMessage = 'Received: $fileName';
      });
      await _saveReceivedFilesIndex();

      request.response.statusCode = 200;
      request.response.headers.contentType = ContentType.json;
      request.response.write(json.encode({
        'success': true, 'name': fileName, 'size': fileSize, 'isVideo': isVideo
      }));
      await request.response.close();
    } catch (e) {
      request.response.statusCode = 500;
      request.response.write('Error: $e');
      await request.response.close();
    }
  }

  void _playReceivedFile(String path) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => VideoPlayerScreen(
        videoSource: path,
        title: path.split('/').last,
        subtitle: 'Local Received File',
      ),
    ));
  }

  void _deleteReceivedFile(int index) {
    final f = _receivedFiles[index];
    try {
      File(f['path']).deleteSync();
    } catch (_) {}
    setState(() {
      _receivedFiles.removeAt(index);
    });
    _saveReceivedFilesIndex();
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  }

  // --- UI Builders ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Cross-Platform Sharing', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
        leading: IconButton(icon: const Icon(Icons.close_rounded, color: Colors.white), onPressed: () => Navigator.of(context).pop()),
      ),
      body: Column(
        children: [
          // Tab bar selector
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                Expanded(child: _buildTabButton(0, 'Send File', Icons.cloud_upload_rounded)),
                const SizedBox(width: 12),
                Expanded(child: _buildTabButton(1, 'Receive File', Icons.install_mobile_rounded)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _activeTab == 0 ? _buildSendView() : _buildReceiveView(),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton(int index, String label, IconData icon) {
    final active = _activeTab == index;
    return GestureDetector(
      onTap: () => setState(() => _activeTab = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: active ? AppColors.accentBright : Colors.white.withOpacity(0.02),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: active ? Colors.transparent : Colors.white10),
          boxShadow: active ? [BoxShadow(color: AppColors.accentBright.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 4))] : null,
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

  Widget _buildSendView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.02), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white10)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('RECEIVER IP ADDRESS', style: GoogleFonts.outfit(color: Colors.white38, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _ipController,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: '192.168.1.100:58526',
                          hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.03),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // QR Scanner trigger button
                    IconButton(
                      icon: const Icon(Icons.qr_code_scanner_rounded, color: Colors.tealAccent),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withOpacity(0.04),
                        padding: const EdgeInsets.all(12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Colors.white10)),
                      ),
                      onPressed: _scanQrCode,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text('Enter target IP address directly or tap scanner icon to scan QR', style: TextStyle(color: Colors.white30, fontSize: 10)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.02), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white10)),
            child: Column(
              children: [
                GestureDetector(
                  onTap: _isSending ? null : _pickFile,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white10, width: 1.5),
                      borderRadius: BorderRadius.circular(16),
                      color: _selectedFile != null ? Colors.white.withOpacity(0.03) : null,
                    ),
                    child: _selectedFile != null
                        ? Column(children: [
                            const Icon(Icons.insert_drive_file_rounded, color: Colors.white54, size: 36),
                            const SizedBox(height: 8),
                            Text(_selectedFile!.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13), textAlign: TextAlign.center, maxLines: 2),
                            Text('${(_selectedFile!.size ~/ 1048576)} MB', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                          ])
                        : Column(children: [
                            const Icon(Icons.cloud_upload_rounded, color: Colors.white38, size: 40),
                            const SizedBox(height: 8),
                            Text('Tap to select a file', style: TextStyle(color: Colors.white38, fontSize: 13)),
                            Text('MP4, MKV, APK, ZIP, etc.', style: TextStyle(color: Colors.white24, fontSize: 11)),
                          ]),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isSending ? Colors.grey : AppColors.accentBright,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      disabledBackgroundColor: Colors.grey,
                    ),
                    onPressed: (_selectedFile != null && !_isSending) ? _sendFile : null,
                    icon: Icon(_isSending ? Icons.hourglass_top_rounded : Icons.send_rounded, size: 18),
                    label: Text(_isSending ? 'Sending...' : 'Send File', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                if (_isSending) ...[
                  const SizedBox(height: 12),
                  LinearProgressIndicator(value: _progress > 0 ? _progress : null, backgroundColor: Colors.white10, color: AppColors.accentBright),
                ],
                if (_status != null) ...[
                  const SizedBox(height: 12),
                  Text(_status!, style: TextStyle(color: _status!.startsWith('✓') ? const Color(0xFF00E676) : (_status!.startsWith('Error') ? Colors.redAccent : Colors.white70), fontSize: 12)),
                ],
              ],
            ),
          ),
          if (_history.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('RECENT TRANSFERS', style: GoogleFonts.outfit(color: Colors.white38, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1)),
            const SizedBox(height: 8),
            ..._history.take(10).map((h) => Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.02), borderRadius: BorderRadius.circular(10)),
                  child: Row(children: [
                    const Icon(Icons.history_rounded, color: Colors.white24, size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Text(h['file'] ?? '', style: const TextStyle(color: Colors.white60, fontSize: 11), maxLines: 1)),
                    Text(h['ip'] ?? '', style: const TextStyle(color: Colors.white24, fontSize: 10)),
                  ]),
                )),
          ],
        ],
      ),
    );
  }

  Widget _buildReceiveView() {
    return Column(
      children: [
        // Top Card: Server info & QR
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.02),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white10),
          ),
          child: Row(
            children: [
              // QR Code container
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                child: _localIp.isNotEmpty && _port > 0
                    ? QrImageView(
                        data: '$_localIp:$_port',
                        version: QrVersions.auto,
                        size: 120,
                        eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
                        dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Colors.black),
                      )
                    : const SizedBox(width: 120, height: 120, child: Center(child: CircularProgressIndicator())),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('RECEIVE ON THIS DEVICE', style: GoogleFonts.outfit(color: Colors.tealAccent, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                    const SizedBox(height: 8),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(color: const Color(0xFF8B5CF6).withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                        child: Text(
                          '$_localIp:$_port',
                          style: GoogleFonts.outfit(color: const Color(0xFFC084FC), fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text('Scan QR or enter this IP on the sending device.', style: TextStyle(color: Colors.white38, fontSize: 10)),
                    if (_serverStatusMessage != null) ...[
                      const SizedBox(height: 8),
                      Text(_serverStatusMessage!, style: const TextStyle(color: Color(0xFF00E676), fontSize: 10, fontWeight: FontWeight.bold)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),

        // Bottom List: Received files
        Expanded(
          child: Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.01),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
              border: const Border(top: BorderSide(color: Colors.white10)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('RECEIVED FILES', style: GoogleFonts.outfit(color: Colors.white54, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1)),
                    Text('${_receivedFiles.length} files', style: const TextStyle(color: Colors.white24, fontSize: 10)),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: _isFilesLoading
                      ? const Center(child: CircularProgressIndicator())
                      : (_receivedFiles.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.folder_open_rounded, color: Colors.white12, size: 48),
                                  const SizedBox(height: 8),
                                  Text('No files received yet', style: TextStyle(color: Colors.white24, fontSize: 13)),
                                ],
                              ),
                            )
                          : ListView.separated(
                              itemCount: _receivedFiles.length,
                              separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
                              itemBuilder: (context, index) {
                                final f = _receivedFiles[index];
                                final isVideo = f['type'] == 'video';
                                return ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: CircleAvatar(
                                    backgroundColor: isVideo ? const Color(0xFF0284C7).withOpacity(0.15) : const Color(0xFF475569).withOpacity(0.15),
                                    child: Icon(isVideo ? Icons.movie_creation_rounded : Icons.insert_drive_file_rounded, color: isVideo ? const Color(0xFF38BDF8) : Colors.white60, size: 20),
                                  ),
                                  title: Text(f['name'] ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  subtitle: Text(
                                    '${_formatFileSize(f['size'] ?? 0)} • ${f['time'] != null ? f['time'].toString().substring(11, 19) : ''}',
                                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (isVideo)
                                        IconButton(
                                          icon: const Icon(Icons.play_circle_fill_rounded, color: Colors.tealAccent, size: 24),
                                          onPressed: () => _playReceivedFile(f['path']),
                                        ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                                        onPressed: () => _deleteReceivedFile(index),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            )),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
