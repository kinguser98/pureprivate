import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:private_cinema_mobile/theme/app_colors.dart';
import 'package:private_cinema_mobile/screens/video_player_screen.dart';

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

  // Automatic Device Discovery
  bool _isScanningDevices = false;
  List<Map<String, dynamic>> _discoveredDevices = [];

  // Receive Mode state
  HttpServer? _server;
  int _port = 0;
  String _localIp = '';
  bool _isServerRunning = false;
  List<Map<String, dynamic>> _receivedFiles = [];
  List<String> _allIps = [];
  String? _serverStatusMessage;

  @override
  void initState() {
    super.initState();
    _ipController.text = '192.168.1.100:58526';
    _loadHistory();
    _loadReceivedFiles();
    _startServer();
    _scanForNearbyDevices();
  }

  @override
  void dispose() {
    _server?.close(force: true);
    _ipController.dispose();
    super.dispose();
  }

  // --- Automatic Nearby Device Scanner ---

  Future<void> _scanForNearbyDevices() async {
    if (!mounted) return;
    setState(() => _isScanningDevices = true);

    final List<Map<String, dynamic>> found = [];

    try {
      final interfaces = await NetworkInterface.list();
      String? localIp;
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            final ip = addr.address;
            if (ip.startsWith('192.168.') || ip.startsWith('10.') || ip.startsWith('172.')) {
              localIp = ip;
              break;
            }
          }
        }
      }

      if (localIp != null) {
        final subnet = localIp.substring(0, localIp.lastIndexOf('.'));
        final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 350);

        final futures = <Future<void>>[];
        for (int i = 1; i <= 254; i++) {
          final targetIp = '$subnet.$i';
          futures.add(() async {
            try {
              final req = await client.getUrl(Uri.parse('http://$targetIp:58526/ping'));
              final resp = await req.close();
              if (resp.statusCode == 200) {
                final body = await resp.transform(utf8.decoder).join();
                String name = 'TV Device ($targetIp)';
                if (body.contains('{')) {
                  try {
                    final jsonMap = json.decode(body);
                    name = jsonMap['device_name']?.toString() ?? name;
                  } catch (_) {}
                }
                found.add({
                  'name': name,
                  'ip': targetIp,
                  'port': 58526,
                  'host': '$targetIp:58526',
                });
              }
            } catch (_) {}
          }());
        }
        await Future.wait(futures);
        client.close();
      }
    } catch (e) {
      debugPrint('Device scan failed: $e');
    }

    if (mounted) {
      setState(() {
        _discoveredDevices = found;
        if (found.isNotEmpty) {
          _ipController.text = found.first['host'];
        }
        _isScanningDevices = false;
      });
    }
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
      // Rescan devices when a file is selected
      _scanForNearbyDevices();
    }
  }

  Future<void> _sendFileToDevice(String hostPort) async {
    _ipController.text = hostPort;
    await _sendFile();
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
      final port = uri.port == 0 ? 58526 : uri.port;

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
        _status = '✓ Sent successfully to TV!';
        _history.insert(0, {'ip': _ipController.text, 'file': fileName, 'time': DateTime.now().toIso8601String()});
        _saveHistory();
      } else {
        _status = 'Server error: ${responseStr.substring(0, responseStr.length.clamp(0, 150))}';
      }
    } catch (e) {
      _status = 'Error: $e';
    }

    if (mounted) setState(() => _isSending = false);
  }

  void _scanQrCode() async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black,
        contentPadding: EdgeInsets.zero,
        content: SizedBox(
          width: 300,
          height: 300,
          child: MobileScanner(
            onDetect: (capture) {
              final barcodes = capture.barcodes;
              if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
                Navigator.of(context).pop(barcodes.first.rawValue);
              }
            },
          ),
        ),
      ),
    );

    if (result != null && result.isNotEmpty) {
      var cleaned = result.replaceAll('http://', '').replaceAll('https://', '');
      setState(() {
        _ipController.text = cleaned;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Target set to: $cleaned')),
      );
    }
  }

  // --- Receive Mode Logic ---

  Future<void> _loadReceivedFiles() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('send_to_tv_received_files');
    if (raw != null) {
      try {
        _receivedFiles = (json.decode(raw) as List).cast<Map<String, dynamic>>();
      } catch (_) {}
    }
  }

  Future<void> _saveReceivedFilesIndex() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('send_to_tv_received_files', json.encode(_receivedFiles));
  }

  Future<void> _startServer() async {
    try {
      _allIps = <String>[];
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

      _server = await HttpServer.bind(InternetAddress.anyIPv4, 58526);
      _port = 58526;
      _isServerRunning = true;
      setState(() {});

      _server!.listen((HttpRequest request) async {
        final path = request.uri.path;
        if (request.method == 'POST' && path == '/upload') {
          await _handleUpload(request);
        } else if (path == '/ping') {
          request.response.headers.contentType = ContentType.json;
          request.response.write(json.encode({'status': 'ok', 'app': 'PrivateCinema', 'device_name': 'Mobile App', 'port': _port}));
          await request.response.close();
        } else {
          request.response.statusCode = 404;
          request.response.write('Not found');
          await request.response.close();
        }
      });
    } catch (e) {
      debugPrint('Mobile Server start error: $e');
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

      final savePath = '${saveDir.path}/$fileName';
      await File(savePath).writeAsBytes(fileBytes);
      final fileSize = fileBytes.length;

      setState(() {
        _receivedFiles.insert(0, {
          'name': fileName,
          'path': savePath,
          'size': fileSize,
          'time': DateTime.now().toIso8601String(),
        });
      });
      await _saveReceivedFilesIndex();

      request.response.statusCode = 200;
      request.response.headers.contentType = ContentType.json;
      request.response.write(json.encode({'success': true, 'name': fileName, 'size': fileSize}));
      await request.response.close();
    } catch (e) {
      request.response.statusCode = 500;
      request.response.write('Error: $e');
      await request.response.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Send to TV / Sharing', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
        leading: IconButton(icon: const Icon(Icons.close_rounded, color: Colors.white), onPressed: () => Navigator.of(context).pop()),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                Expanded(child: _buildTabButton(0, 'Send to TV', Icons.tv_rounded)),
                const SizedBox(width: 12),
                Expanded(child: _buildTabButton(1, 'Receive Files', Icons.download_rounded)),
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
          // Discovered TV Devices Section
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.03),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.accentBright.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.tv_rounded, color: AppColors.accentBright, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'DISCOVERED TV DEVICES',
                          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.8),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: _isScanningDevices
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70))
                          : const Icon(Icons.refresh_rounded, color: Colors.white70, size: 20),
                      onPressed: _isScanningDevices ? null : _scanForNearbyDevices,
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                if (_isScanningDevices && _discoveredDevices.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentBright),
                          const SizedBox(width: 12),
                          Text('Scanning local Wi-Fi for TV devices...', style: GoogleFonts.outfit(color: Colors.white60, fontSize: 13)),
                        ],
                      ),
                    ),
                  )
                else if (_discoveredDevices.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12)),
                    child: Text(
                      'No TV app detected on local Wi-Fi. Make sure the app is open on your TV and connected to the same Wi-Fi.',
                      style: GoogleFonts.outfit(color: Colors.white38, fontSize: 12),
                    ),
                  )
                else
                  Column(
                    children: _discoveredDevices.map((device) {
                      final isSelected = _ipController.text == device['host'];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.accentBright.withOpacity(0.15) : Colors.white.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isSelected ? AppColors.accentBright : Colors.white10),
                        ),
                        child: ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.accentBright.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.tv_rounded, color: AppColors.accentBright, size: 20),
                          ),
                          title: Text(
                            device['name'],
                            style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          subtitle: Text(
                            'IP: ${device['host']}',
                            style: GoogleFonts.outfit(color: Colors.white54, fontSize: 12),
                          ),
                          trailing: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isSelected ? AppColors.accentBright : Colors.white12,
                              foregroundColor: isSelected ? Colors.black : Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () => _sendFileToDevice(device['host']),
                            icon: const Icon(Icons.send_rounded, size: 14),
                            label: Text(isSelected ? 'SEND HERE' : 'SELECT', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // File Picker Box
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.02), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white10)),
            child: Column(
              children: [
                GestureDetector(
                  onTap: _isSending ? null : _pickFile,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white10, width: 1.5),
                      borderRadius: BorderRadius.circular(16),
                      color: _selectedFile != null ? Colors.white.withOpacity(0.03) : null,
                    ),
                    child: _selectedFile != null
                        ? Column(children: [
                            const Icon(Icons.insert_drive_file_rounded, color: Colors.tealAccent, size: 40),
                            const SizedBox(height: 8),
                            Text(_selectedFile!.name, style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14), textAlign: TextAlign.center, maxLines: 2),
                            Text('${(_selectedFile!.size ~/ 1048576)} MB', style: GoogleFonts.outfit(color: Colors.white38, fontSize: 12)),
                          ])
                        : Column(children: [
                            const Icon(Icons.cloud_upload_rounded, color: Colors.white38, size: 40),
                            const SizedBox(height: 8),
                            Text('Tap to select a video / file to send to TV', style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                            Text('Supports MP4, MKV, AVI, ZIP, etc.', style: GoogleFonts.outfit(color: Colors.white38, fontSize: 11)),
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
                    ),
                    onPressed: (_selectedFile != null && !_isSending) ? _sendFile : null,
                    icon: Icon(_isSending ? Icons.hourglass_top_rounded : Icons.send_rounded, size: 18),
                    label: Text(_isSending ? 'Sending...' : 'Send Selected File to TV', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                  ),
                ),
                if (_isSending) ...[
                  const SizedBox(height: 12),
                  LinearProgressIndicator(value: _progress > 0 ? _progress : null, backgroundColor: Colors.white10, color: AppColors.accentBright),
                ],
                if (_status != null) ...[
                  const SizedBox(height: 12),
                  Text(_status!, style: GoogleFonts.outfit(color: AppColors.accentBright, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Manual IP & QR Code Fallback
          ExpansionTile(
            title: Text('Manual Target IP / QR Scanner', style: GoogleFonts.outfit(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold)),
            iconColor: Colors.white54,
            collapsedIconColor: Colors.white38,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ipController,
                      style: GoogleFonts.outfit(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: '192.168.1.100:58526',
                        hintStyle: const TextStyle(color: Colors.white30),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.03),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.qr_code_scanner_rounded, color: Colors.tealAccent),
                    onPressed: _scanQrCode,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReceiveView() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Local Server IP: http://$_localIp:$_port', style: GoogleFonts.outfit(color: AppColors.accentBright, fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 16),
          Expanded(
            child: _receivedFiles.isEmpty
                ? Center(child: Text('No received files on Mobile.', style: GoogleFonts.outfit(color: Colors.white38)))
                : ListView.separated(
                    itemCount: _receivedFiles.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (ctx, idx) {
                      final f = _receivedFiles[idx];
                      return ListTile(
                        leading: const Icon(Icons.insert_drive_file_rounded, color: Colors.white70),
                        title: Text(f['name'] ?? '', style: GoogleFonts.outfit(color: Colors.white, fontSize: 13)),
                        subtitle: Text('${((f['size'] ?? 0) ~/ 1048576)} MB', style: GoogleFonts.outfit(color: Colors.white38, fontSize: 11)),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
