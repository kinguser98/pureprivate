import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:private_cinema_mobile/theme/app_colors.dart';

class SendToTvScreen extends StatefulWidget {
  const SendToTvScreen({super.key});
  @override
  State<SendToTvScreen> createState() => _SendToTvScreenState();
}

class _SendToTvScreenState extends State<SendToTvScreen> {
  final TextEditingController _ipController = TextEditingController();
  PlatformFile? _selectedFile;
  bool _isSending = false;
  double _progress = 0;
  String? _status;
  List<Map<String, String>> _history = [];

  @override
  void initState() {
    super.initState();
    _ipController.text = '192.168.43.1:8080';
    _loadHistory();
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

    setState(() { _isSending = true; _progress = 0; _status = 'Connecting...'; });

    try {
      final bytes = await File(_selectedFile!.path!).readAsBytes();
      final fileName = _selectedFile!.name;
      final uri = Uri.parse('http://${_ipController.text}/upload?name=${Uri.encodeComponent(fileName)}');

      _status = 'Sending $fileName (${_selectedFile!.size ~/ 1048576} MB)...';

      final request = http.MultipartRequest('POST', uri);
      request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: fileName));

      final streamedRes = await request.send().timeout(const Duration(minutes: 10));

      if (streamedRes.statusCode == 200) {
        _status = '✓ Sent successfully!';
        _history.insert(0, {'ip': _ipController.text, 'file': fileName, 'time': DateTime.now().toIso8601String()});
        _saveHistory();
      } else {
        final body = await streamedRes.stream.bytesToString();
        _status = 'Server error: ${streamedRes.statusCode} $body';
      }
    } catch (e) {
      _status = 'Error: $e';
    }

    setState(() => _isSending = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Send to TV', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
        leading: IconButton(icon: const Icon(Icons.close_rounded, color: Colors.white), onPressed: () => Navigator.of(context).pop()),
      ),
      body: SingleChildScrollView(
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
                  Text('TV IP ADDRESS', style: GoogleFonts.outfit(color: Colors.white38, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _ipController,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          decoration: InputDecoration(
                            hintText: '192.168.1.5:8080',
                            hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
                            filled: true, fillColor: Colors.white.withOpacity(0.03),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white10)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.04), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white10)),
                        child: const Icon(Icons.wifi_rounded, color: Colors.white54, size: 20),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('Enter the IP shown on your TV (same WiFi/hotspot)', style: TextStyle(color: Colors.white30, fontSize: 10)),
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
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        disabledBackgroundColor: Colors.grey,
                      ),
                      onPressed: (_selectedFile != null && !_isSending) ? _sendFile : null,
                      icon: Icon(_isSending ? Icons.hourglass_top_rounded : Icons.send_rounded, size: 18),
                      label: Text(_isSending ? 'Sending...' : 'Send to TV', style: const TextStyle(fontWeight: FontWeight.bold)),
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
      ),
    );
  }
}
