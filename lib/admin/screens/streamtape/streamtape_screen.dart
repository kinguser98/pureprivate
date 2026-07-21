import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../utils/admin_api_client.dart';
import '../../utils/drawer_helper.dart';
import '../../widgets/common/glass_card.dart';

class StreamtapeScreen extends ConsumerStatefulWidget {
  const StreamtapeScreen({super.key});
  @override
  ConsumerState<StreamtapeScreen> createState() => _StreamtapeScreenState();
}

class _StreamtapeScreenState extends ConsumerState<StreamtapeScreen> {
  final _loginCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  final _touchCtrl = TextEditingController(text: '5');
  final _downloadCtrl = TextEditingController(text: '1048576');
  final _adminApi = AdminApiClient();
  
  bool _loading = true;
  bool _saving = false;
  bool _running = false;

  Map<String, dynamic>? _accountInfo;
  String? _accountError;
  int _filesCount = 0;
  String? _cachedTime;
  int _offset = 0;
  List<dynamic> _logs = [];

  @override
  void initState() {
    super.initState();
    _fetchDetails();
  }

  @override
  void dispose() {
    _loginCtrl.dispose();
    _keyCtrl.dispose();
    _touchCtrl.dispose();
    _downloadCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchDetails() async {
    setState(() => _loading = true);
    final data = await _adminApi.fetchStreamtapeDetails();
    if (mounted) {
      setState(() {
        if (data['success'] == true) {
          final config = data['config'] as Map?;
          if (config != null) {
            _loginCtrl.text = config['api_login']?.toString() ?? '';
            _keyCtrl.text = config['api_key']?.toString() ?? '';
            _touchCtrl.text = config['touch_per_run']?.toString() ?? '5';
            _downloadCtrl.text = config['download_bytes']?.toString() ?? '1048576';
          }
          _accountInfo = data['account_info'] != null ? Map<String, dynamic>.from(data['account_info']) : null;
          _accountError = data['account_error']?.toString();
          _filesCount = int.tryParse(data['files_count']?.toString() ?? '0') ?? 0;
          _cachedTime = data['cached_time']?.toString();
          _offset = int.tryParse(data['offset']?.toString() ?? '0') ?? 0;
          _logs = data['logs'] is List ? List.from(data['logs']) : [];
        }
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final r = await _adminApi.saveStreamtapeConfig({
      'api_login': _loginCtrl.text.trim(),
      'api_key': _keyCtrl.text.trim(),
      'touch_per_run': _touchCtrl.text.trim(),
      'download_bytes': _downloadCtrl.text.trim(),
    });
    if (mounted) {
      setState(() => _saving = false);
      if (r['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(r['message'] ?? 'Config saved successfully'), backgroundColor: const Color(0xFF22C55E)));
        _fetchDetails();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(r['message'] ?? 'Failed to save config'), backgroundColor: const Color(0xFFEF4444)));
      }
    }
  }

  Future<void> _runKeepalive() async {
    setState(() => _running = true);
    final r = await _adminApi.triggerKeepalive();
    if (mounted) {
      setState(() => _running = false);
      if (r['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(r['message'] ?? 'Keepalive run triggered successfully'),
          backgroundColor: const Color(0xFF22C55E),
        ));
        _fetchDetails();
        
        // Show trigger execution output if any
        if (r['output'] != null && r['output'].toString().isNotEmpty) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF1A1F2E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text('Batch Output', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              content: Container(
                constraints: const BoxConstraints(maxHeight: 200),
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Text(r['output'].toString(), style: const TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'monospace')),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close', style: TextStyle(color: Color(0xFFEF4444)))),
              ],
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(r['message'] ?? 'Failed to run keepalive'), backgroundColor: const Color(0xFFEF4444)));
      }
    }
  }

  Widget _field(String label, TextEditingController ctrl, IconData icon, {bool obscure = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            label.toUpperCase(),
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF0B0F19),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 16, color: Colors.white38),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: ctrl,
                  obscureText: obscure,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.menu), onPressed: DrawerProvider.openDrawer),
        title: const Text('Streamtape Keepalive'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchDetails),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildAnalyticsOverview(),
                  const SizedBox(height: 16),
                  _buildControlPanel(),
                  const SizedBox(height: 16),
                  _buildLogsSection(),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  Widget _buildAnalyticsOverview() {
    return GridView.count(
      crossAxisCount: 1,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      childAspectRatio: 2.8,
      children: [
        // Account Info Card
        GlassCard(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.person, color: Color(0xFFEF4444), size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'STREAMTAPE ACCOUNT',
                      style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _accountInfo != null ? (_accountInfo!['email']?.toString() ?? 'Configured') : 'Not Configured',
                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (_accountInfo != null && _accountInfo!['signup_at'] != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Member since: ${_accountInfo!['signup_at']}',
                        style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 10),
                      ),
                    ] else if (_accountError != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        _accountError!,
                        style: const TextStyle(color: Color(0xFFEF4444), fontSize: 10),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        
        // Monitored & Progress Layout
        Row(
          children: [
            Expanded(
              child: GlassCard(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'VIDEOS MONITORED',
                      style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$_filesCount',
                      style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900),
                    ),
                    if (_cachedTime != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Synced $_cachedTime',
                        style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 9),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Expanded(
              child: GlassCard(
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'BATCH OFFSET PROGRESS',
                      style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1),
                    ),
                    const SizedBox(height: 4),
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(text: '$_offset', style: const TextStyle(color: Color(0xFF10B981), fontSize: 28, fontWeight: FontWeight.w900)),
                          TextSpan(text: ' / $_filesCount', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 16, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _filesCount > 0 ? (_offset / _filesCount) : 0.0,
                        backgroundColor: Colors.white.withOpacity(0.05),
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
                        minHeight: 4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildControlPanel() {
    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: const Color(0xFFEF4444).withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.settings, color: Color(0xFFEF4444), size: 18),
              ),
              const SizedBox(width: 12),
              const Text('Keepalive Settings', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 18),
          _field('Streamtape API Login', _loginCtrl, Icons.person_outline),
          const SizedBox(height: 14),
          _field('Streamtape API Key', _keyCtrl, Icons.lock_outline, obscure: true),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _field('Touch Per Run', _touchCtrl, Icons.touch_app_outlined)),
              const SizedBox(width: 14),
              Expanded(child: _field('Download Bytes', _downloadCtrl, Icons.data_usage_outlined)),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save_outlined, size: 18),
                    label: const Text('Save Config', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(color: Colors.white.withOpacity(0.2)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: const LinearGradient(colors: [Color(0xFFEF4444), Color(0xFFDC2626)]),
                  ),
                  child: ElevatedButton.icon(
                    onPressed: _running ? null : _runKeepalive,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: _running
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.play_arrow, size: 18),
                    label: const Text('Run Batch', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLogsSection() {
    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: const Color(0xFF3B82F6).withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.analytics_outlined, color: Color(0xFF3B82F6), size: 18),
              ),
              const SizedBox(width: 12),
              const Text('Keepalive Activity Log', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 16),
          if (_logs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.receipt_long_outlined, size: 40, color: Colors.white.withOpacity(0.15)),
                    const SizedBox(height: 12),
                    Text('No keepalive logs recorded yet', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 13)),
                  ],
                ),
              ),
            )
          else
            Container(
              constraints: const BoxConstraints(maxHeight: 350),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _logs.length,
                separatorBuilder: (_, __) => Divider(color: Colors.white.withOpacity(0.04), height: 1),
                itemBuilder: (context, idx) {
                  final log = _logs[idx];
                  final filename = log['filename']?.toString() ?? '';
                  final time = log['time']?.toString() ?? '';
                  final codeStr = log['code']?.toString() ?? '';
                  final int? codeVal = int.tryParse(codeStr);
                  final isSuccess = codeVal == 200 || codeVal == 206;
                  
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(color: Colors.white.withOpacity(0.04), borderRadius: BorderRadius.circular(8)),
                          child: const Icon(Icons.video_file_outlined, color: Colors.white54, size: 16),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(filename, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold), maxLines: 2, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 3),
                              Text(time, style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 9)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isSuccess ? const Color(0xFF10B981).withOpacity(0.1) : const Color(0xFFEF4444).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: isSuccess ? const Color(0xFF10B981).withOpacity(0.2) : const Color(0xFFEF4444).withOpacity(0.2)),
                          ),
                          child: Text(
                            isSuccess ? 'HTTP $codeStr OK' : 'FAIL ($codeStr)',
                            style: TextStyle(color: isSuccess ? const Color(0xFF10B981) : const Color(0xFFEF4444), fontSize: 9, fontWeight: FontWeight.bold),
                          ),
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
