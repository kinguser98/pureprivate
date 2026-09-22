import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

const _kApiBase = 'https://ot.goprivate.fun/api/device_auth.php';

class AdminDeviceAccessScreen extends StatefulWidget {
  const AdminDeviceAccessScreen({super.key});

  @override
  State<AdminDeviceAccessScreen> createState() => _AdminDeviceAccessScreenState();
}

class _AdminDeviceAccessScreenState extends State<AdminDeviceAccessScreen>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _devices = [];
  bool _loading = true;
  String? _error;
  String _filter = 'all'; // all | pending | approved | denied
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _filter = ['all', 'pending', 'approved', 'denied'][_tabController.index];
        });
      }
    });
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await http
          .get(Uri.parse('$_kApiBase?action=list_devices'))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final list = (body['devices'] as List? ?? [])
            .cast<Map<String, dynamic>>();
        if (mounted) setState(() { _devices = list; _loading = false; });
      } else {
        throw Exception('HTTP ${res.statusCode}');
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _setStatus(String deviceId, String status) async {
    try {
      final res = await http.post(
        Uri.parse('$_kApiBase?action=set_status'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'target_device_id': deviceId, 'status': status}),
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_filter == 'all') return _devices;
    return _devices.where((d) => d['status'] == _filter).toList();
  }

  int _count(String status) =>
      _devices.where((d) => d['status'] == status).length;
  int get _onlineCount =>
      _devices.where((d) => d['is_online'] == true).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0F19),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.menu, color: Colors.white70),
          onPressed: () => Scaffold.of(context).openDrawer(),
        ),
        title: Text('Device Access',
            style: GoogleFonts.inter(
                color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            onPressed: _load,
            tooltip: 'Refresh',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFEF4444),
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white38,
          labelStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
          tabs: [
            Tab(text: 'All (${_devices.length})'),
            Tab(text: 'Pending (${_count('pending')})'),
            Tab(text: 'Approved (${_count('approved')})'),
            Tab(text: 'Denied (${_count('denied')})'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Stats bar
          _StatsBar(
            total: _devices.length,
            online: _onlineCount,
            pending: _count('pending'),
            approved: _count('approved'),
          ),
          // Content
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFFEF4444)))
                : _error != null
                    ? _ErrorView(error: _error!, onRetry: _load)
                    : _filtered.isEmpty
                        ? _EmptyView(filter: _filter)
                        : RefreshIndicator(
                            color: const Color(0xFFEF4444),
                            onRefresh: _load,
                            child: ListView.builder(
                              padding: const EdgeInsets.all(12),
                              itemCount: _filtered.length,
                              itemBuilder: (ctx, i) => _DeviceCard(
                                device: _filtered[i],
                                onApprove: () => _setStatus(_filtered[i]['device_id'], 'approved'),
                                onDeny: () => _setStatus(_filtered[i]['device_id'], 'denied'),
                                onPending: () => _setStatus(_filtered[i]['device_id'], 'pending'),
                              ),
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

// ─── Stats bar ───────────────────────────────────────────────────────────────

class _StatsBar extends StatelessWidget {
  final int total, online, pending, approved;
  const _StatsBar({required this.total, required this.online, required this.pending, required this.approved});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF111827),
        border: Border(bottom: BorderSide(color: Color(0xFF1F2937))),
      ),
      child: Row(
        children: [
          _Stat(label: 'Total', value: '$total', color: Colors.white70),
          _Stat(label: 'Online', value: '$online', color: const Color(0xFF10B981)),
          _Stat(label: 'Pending', value: '$pending', color: const Color(0xFFF59E0B)),
          _Stat(label: 'Approved', value: '$approved', color: const Color(0xFF34D399)),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label, value;
  final Color color;
  const _Stat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: GoogleFonts.inter(
                  color: color, fontSize: 20, fontWeight: FontWeight.bold)),
          Text(label,
              style: GoogleFonts.inter(color: Colors.white38, fontSize: 10)),
        ],
      ),
    );
  }
}

// ─── Device card ─────────────────────────────────────────────────────────────

class _DeviceCard extends StatelessWidget {
  final Map<String, dynamic> device;
  final VoidCallback onApprove, onDeny, onPending;

  const _DeviceCard({
    required this.device,
    required this.onApprove,
    required this.onDeny,
    required this.onPending,
  });

  Color get _statusColor => switch (device['status']) {
    'approved' => const Color(0xFF10B981),
    'denied'   => const Color(0xFFEF4444),
    _          => const Color(0xFFF59E0B),
  };

  IconData get _statusIcon => switch (device['status']) {
    'approved' => Icons.check_circle_rounded,
    'denied'   => Icons.cancel_rounded,
    _          => Icons.hourglass_top_rounded,
  };

  String _timeAgo(int? sec) {
    if (sec == null) return 'Never';
    if (sec < 60)  return '${sec}s ago';
    if (sec < 3600) return '${sec ~/ 60}m ago';
    if (sec < 86400) return '${sec ~/ 3600}h ago';
    return '${sec ~/ 86400}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = device['is_online'] == true;
    final name = (device['nickname']?.toString().isNotEmpty == true)
        ? device['nickname']
        : (device['device_name']?.toString().isNotEmpty == true
            ? device['device_name']
            : 'Unknown Device');
    final model     = device['device_model']?.toString() ?? '';
    final platform  = device['platform']?.toString() ?? 'android';
    final status    = device['status']?.toString() ?? 'pending';
    final openCount = device['open_count']?.toString() ?? '0';
    final watched   = device['movies_watched']?.toString() ?? '0';
    final lastContent = device['last_content']?.toString() ?? '';
    final secAgo    = device['last_seen_ago'] as int?;
    final deviceId  = device['device_id']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isOnline
              ? const Color(0xFF10B981).withValues(alpha: 0.4)
              : const Color(0xFF1F2937),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                // Platform icon
                Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(
                    color: _statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    platform == 'ios' ? Icons.apple_rounded : Icons.android_rounded,
                    color: _statusColor, size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(name,
                                style: GoogleFonts.inter(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14),
                                overflow: TextOverflow.ellipsis),
                          ),
                          if (isOnline) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Container(
                                  width: 5, height: 5,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF10B981),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text('Live', style: GoogleFonts.inter(
                                    color: const Color(0xFF10B981), fontSize: 10,
                                    fontWeight: FontWeight.bold)),
                              ]),
                            ),
                          ],
                        ],
                      ),
                      Text(model,
                          style: GoogleFonts.inter(color: Colors.white38, fontSize: 11)),
                    ],
                  ),
                ),
                // Status badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(_statusIcon, color: _statusColor, size: 12),
                    const SizedBox(width: 4),
                    Text(status[0].toUpperCase() + status.substring(1),
                        style: GoogleFonts.inter(
                            color: _statusColor,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                  ]),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Stats row
            Row(
              children: [
                _InfoChip(icon: Icons.movie_filter_rounded, label: '$watched watched',
                    color: const Color(0xFF818CF8)),
                const SizedBox(width: 6),
                _InfoChip(icon: Icons.launch_rounded, label: '$openCount opens',
                    color: const Color(0xFF60A5FA)),
                const SizedBox(width: 6),
                _InfoChip(icon: Icons.access_time_rounded,
                    label: _timeAgo(secAgo),
                    color: isOnline ? const Color(0xFF10B981) : Colors.white38),
              ],
            ),
            if (lastContent.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.play_circle_outline_rounded,
                      size: 12, color: Colors.white24),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(lastContent,
                        style: GoogleFonts.inter(
                            color: Colors.white24, fontSize: 11),
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 4),
            // Device ID (tap to copy)
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: deviceId));
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Device ID copied'),
                        duration: Duration(seconds: 1)));
              },
              child: Text(
                'ID: ${deviceId.substring(0, 16)}…',
                style: GoogleFonts.robotoMono(
                    color: Colors.white12, fontSize: 10),
              ),
            ),
            const SizedBox(height: 10),
            const Divider(color: Color(0xFF1F2937), height: 1),
            const SizedBox(height: 8),
            // Action buttons
            Row(
              children: [
                if (status != 'approved')
                  _ActionButton(
                    label: 'Approve',
                    icon: Icons.check_rounded,
                    color: const Color(0xFF10B981),
                    onTap: onApprove,
                  ),
                if (status != 'approved') const SizedBox(width: 8),
                if (status != 'denied')
                  _ActionButton(
                    label: 'Deny',
                    icon: Icons.block_rounded,
                    color: const Color(0xFFEF4444),
                    onTap: onDeny,
                  ),
                if (status != 'denied') const SizedBox(width: 8),
                if (status != 'pending')
                  _ActionButton(
                    label: 'Set Pending',
                    icon: Icons.hourglass_empty_rounded,
                    color: const Color(0xFFF59E0B),
                    onTap: onPending,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _InfoChip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 4),
        Text(label, style: GoogleFonts.inter(color: color, fontSize: 11)),
      ]),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _ActionButton({required this.label, required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 5),
              Text(label, style: GoogleFonts.inter(
                  color: color, fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Empty / Error views ─────────────────────────────────────────────────────

class _EmptyView extends StatelessWidget {
  final String filter;
  const _EmptyView({required this.filter});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.devices_rounded, color: Colors.white12, size: 60),
          const SizedBox(height: 16),
          Text('No $filter devices',
              style: GoogleFonts.inter(color: Colors.white38, fontSize: 16)),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.wifi_off_rounded, color: Colors.white24, size: 52),
          const SizedBox(height: 12),
          Text('Failed to load devices', style: GoogleFonts.inter(color: Colors.white54)),
          const SizedBox(height: 4),
          Text(error, style: GoogleFonts.inter(color: Colors.white24, fontSize: 11)),
          const SizedBox(height: 16),
          TextButton(
            onPressed: onRetry,
            child: const Text('Retry', style: TextStyle(color: Color(0xFFEF4444))),
          ),
        ],
      ),
    );
  }
}
