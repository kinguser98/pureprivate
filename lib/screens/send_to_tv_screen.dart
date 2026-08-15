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
    // Auto refresh discovered TV devices every 5 seconds
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
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

  // --- Fast Subnet Scanner for TV Devices ---

  Future<void> _scanForNearbyTvs({bool showLoader = true}) async {
    if (!mounted) return;
    if (showLoader) setState(() => _isScanningDevices = true);

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
          // Check ports 58526 and 58527
          for (final testPort in [58526, 58527]) {
            futures.add(() async {
              try {
                final req = await client.getUrl(Uri.parse('http://$targetIp:$testPort/ping'));
                final resp = await req.close();
                if (resp.statusCode == 200) {
                  final body = await resp.transform(utf8.decoder).join();
                  String name = 'Smart TV ($targetIp)';
                  if (body.contains('{')) {
                    try {
                      final jsonMap = json.decode(body);
                      name = jsonMap['device_name']?.toString() ?? name;
                    } catch (_) {}
                  }
                  if (!found.any((d) => d['ip'] == targetIp)) {
                    found.add({
                      'name': name,
                      'ip': targetIp,
                      'port': testPort,
                      'host': '$targetIp:$testPort',
                    });
                  }
                }
              } catch (_) {}
            }());
          }
        }
        await Future.wait(futures);
        client.close();
      }
    } catch (e) {
      debugPrint('TV discovery error: $e');
    }

    if (mounted) {
      setState(() {
        _discoveredTvDevices = found;
        _isScanningDevices = false;
      });
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
      _sendingToDeviceName = deviceName;
      _status = 'Connecting to $deviceName...';
    });

    try {
      final fileName = _selectedFile!.name;
      final file = File(_selectedFile!.path!);
      final fileSize = await file.length();
      final uri = Uri.parse('http://$targetHost');
      final host = uri.host;
      final port = uri.port;

      _status = 'Sending $fileName (${fileSize ~/ 1048576} MB) to $deviceName...';

      final socket = await Socket.connect(host, port, timeout: const Duration(seconds: 15));

      final requestLine = 'POST /upload?name=${Uri.encodeComponent(fileName)} HTTP/1.1\r\n';
      final hostHeader = 'Host: $targetHost\r\n';
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
        _status = '✓ Sent successfully to $deviceName!';
        _history.insert(0, {'ip': targetHost, 'file': fileName, 'time': DateTime.now().toIso8601String()});
        _saveHistory();
      } else {
        _status = 'TV Error: ${responseStr.substring(0, responseStr.length.clamp(0, 150))}';
      }
    } catch (e) {
      _status = 'Transfer failed: $e';
    }

    if (mounted) setState(() => _isSending = false);
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
        if (request.uri.path == '/ping') {
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
                      Text('${(_progress * 100).toInt()}%', style: GoogleFonts.outfit(color: AppColors.accentBright, fontWeight: FontWeight.bold, fontSize: 13)),
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

          // STEP 2: Choose TV Device List
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'STEP 2: CHOOSE TARGET TV',
                style: GoogleFonts.outfit(color: Colors.white38, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1),
              ),
              IconButton(
                icon: _isScanningDevices
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70))
                    : const Icon(Icons.refresh_rounded, color: Colors.white70, size: 18),
                onPressed: _isScanningDevices ? null : () => _scanForNearbyTvs(),
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
                  Text('Scanning Wi-Fi for TV devices...', style: GoogleFonts.outfit(color: Colors.white60, fontSize: 13)),
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
                  const Icon(Icons.tv_off_rounded, color: Colors.white24, size: 36),
                  const SizedBox(height: 8),
                  Text(
                    'No TV App Found on Local Wi-Fi',
                    style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Make sure the app is open on your TV and connected to the same Wi-Fi network.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(color: Colors.white38, fontSize: 11),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white12,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => _scanForNearbyTvs(),
                    icon: const Icon(Icons.search_rounded, size: 16),
                    label: Text('SEARCH AGAIN', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            )
          else
            Column(
              children: _discoveredTvDevices.map((device) {
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
                      child: Icon(Icons.tv_rounded, color: AppColors.accentBright, size: 24),
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
                      label: Text('SEND TO TV', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12)),
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
