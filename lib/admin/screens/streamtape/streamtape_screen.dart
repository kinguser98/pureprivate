import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/streamtape_service.dart';
import '../../utils/admin_api_client.dart';
import '../../utils/drawer_helper.dart';
import '../../widgets/common/glass_card.dart';
import '../../../screens/video_player_screen.dart';

class StreamtapeScreen extends ConsumerStatefulWidget {
  const StreamtapeScreen({super.key});

  @override
  ConsumerState<StreamtapeScreen> createState() => _StreamtapeScreenState();
}

class _StreamtapeScreenState extends ConsumerState<StreamtapeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _streamtapeService = StreamtapeService();
  final _adminApi = AdminApiClient();

  // Settings controllers
  final _loginCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  final _touchCtrl = TextEditingController(text: '5');
  final _downloadCtrl = TextEditingController(text: '1048576');
  final _customDomainCtrl = TextEditingController();

  // State
  bool _loading = true;
  bool _saving = false;
  bool _running = false;
  bool _testingConnection = false;

  // File Manager State
  List<StreamtapeFolder> _folders = [];
  List<StreamtapeFile> _files = [];
  bool _loadingFiles = false;
  String? _fileManagerError;
  final List<Map<String, String>> _navBreadcrumbs = [{'id': '', 'name': 'Root'}];
  String _fileSearchQuery = '';
  final _searchCtrl = TextEditingController();

  // Remote DL State
  List<StreamtapeRemoteTask> _remoteTasks = [];
  bool _loadingRemote = false;
  Timer? _remotePollTimer;

  // Keepalive State
  Map<String, dynamic>? _accountInfo;
  int _filesCount = 0;
  String? _cachedTime;
  int _offset = 0;
  List<dynamic> _logs = [];

  // Domain Config
  String _selectedPresetApi = 'api.streamtape.com';
  bool _useCustomDomain = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_handleTabChange);
    _initData();
  }

  void _handleTabChange() {
    if (_tabController.index == 1) {
      _startRemotePolling();
    } else {
      _stopRemotePolling();
    }
  }

  void _startRemotePolling() {
    _fetchRemoteTasks();
    _remotePollTimer?.cancel();
    _remotePollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _fetchRemoteTasks(silent: true));
  }

  void _stopRemotePolling() {
    _remotePollTimer?.cancel();
    _remotePollTimer = null;
  }

  @override
  void dispose() {
    _remotePollTimer?.cancel();
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    _loginCtrl.dispose();
    _keyCtrl.dispose();
    _touchCtrl.dispose();
    _downloadCtrl.dispose();
    _customDomainCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _initData() async {
    setState(() => _loading = true);
    await _streamtapeService.init();

    _loginCtrl.text = _streamtapeService.apiLogin;
    _keyCtrl.text = _streamtapeService.apiKey;
    _selectedPresetApi = _streamtapeService.activeApiDomain;
    _useCustomDomain = _streamtapeService.isCustomDomain;
    _customDomainCtrl.text = _streamtapeService.customDomain;

    await Future.wait([
      _fetchBackendDetails(),
      _loadFolder(),
    ]);

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _fetchBackendDetails() async {
    final data = await _adminApi.fetchStreamtapeDetails();
    if (mounted && data['success'] == true) {
      final config = data['config'] as Map?;
      if (config != null) {
        if (_loginCtrl.text.isEmpty) _loginCtrl.text = config['api_login']?.toString() ?? '';
        if (_keyCtrl.text.isEmpty) _keyCtrl.text = config['api_key']?.toString() ?? '';
        _touchCtrl.text = config['touch_per_run']?.toString() ?? '5';
        _downloadCtrl.text = config['download_bytes']?.toString() ?? '1048576';
        
        // Sync service credentials if empty
        if (_streamtapeService.apiLogin.isEmpty && _loginCtrl.text.isNotEmpty) {
          await _streamtapeService.updateCredentials(login: _loginCtrl.text, key: _keyCtrl.text);
        }
      }
      _accountInfo = data['account_info'] != null ? Map<String, dynamic>.from(data['account_info']) : null;
      _filesCount = int.tryParse(data['files_count']?.toString() ?? '0') ?? 0;
      _cachedTime = data['cached_time']?.toString();
      _offset = int.tryParse(data['offset']?.toString() ?? '0') ?? 0;
      _logs = data['logs'] is List ? List.from(data['logs']) : [];
    }
  }

  String get _currentFolderId => _navBreadcrumbs.last['id'] ?? '';

  Future<void> _loadFolder([String? folderId]) async {
    setState(() {
      _loadingFiles = true;
      _fileManagerError = null;
    });

    final targetId = folderId ?? _currentFolderId;
    final res = await _streamtapeService.listFolder(folderId: targetId);

    if (mounted) {
      setState(() {
        _loadingFiles = false;
        if (res['success'] == true) {
          _folders = res['folders'] is List<StreamtapeFolder> ? res['folders'] : [];
          _files = res['files'] is List<StreamtapeFile> ? res['files'] : [];
        } else {
          _fileManagerError = res['message']?.toString() ?? 'Failed to load folder';
        }
      });
    }
  }

  Future<void> _fetchRemoteTasks({bool silent = false}) async {
    if (!silent) setState(() => _loadingRemote = true);
    final res = await _streamtapeService.getRemoteUploadsStatus();
    if (mounted) {
      setState(() {
        if (!silent) _loadingRemote = false;
        if (res['success'] == true && res['tasks'] is List<StreamtapeRemoteTask>) {
          _remoteTasks = res['tasks'];
        }
      });
    }
  }

  void _navigateToFolder(String id, String name) {
    setState(() {
      _navBreadcrumbs.add({'id': id, 'name': name});
    });
    _loadFolder(id);
  }

  void _navigateBackToBreadcrumb(int index) {
    if (index >= _navBreadcrumbs.length - 1) return;
    setState(() {
      _navBreadcrumbs.removeRange(index + 1, _navBreadcrumbs.length);
    });
    _loadFolder(_currentFolderId);
  }

  Future<void> _playVideo(StreamtapeFile file) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 20)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Color(0xFFEF4444)),
              const SizedBox(height: 16),
              Text(
                'Resolving Streamtape video...',
                style: GoogleFonts.outfit(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                file.name,
                style: const TextStyle(color: Colors.white60, fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );

    final res = await _streamtapeService.resolveStreamingUrl(file.linkid.isNotEmpty ? file.linkid : file.id);

    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop(); // dismiss loading dialog

      if (res['success'] == true && res['url'] != null) {
        final streamUrl = res['url'].toString();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => VideoPlayerScreen(
              videoSource: streamUrl,
              title: file.name,
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to play: ${res['message'] ?? 'Could not resolve streaming link'}'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  void _copyToClipboard(String text, String message) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF22C55E),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showCopyLinksModal(StreamtapeFile file) {
    final fileId = file.linkid.isNotEmpty ? file.linkid : file.id;
    final domains = _streamtapeService.getAllWebDomains();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Container(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
              decoration: const BoxDecoration(
                color: Color(0xFF0F172A),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [BoxShadow(color: Colors.black87, blurRadius: 30, spreadRadius: 5)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 12, bottom: 8),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [Color(0xFFEF4444), Color(0xFFDC2626)]),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.share_rounded, color: Colors.white, size: 22),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Copy Stream Links & Mirrors',
                                style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                file.name,
                                style: const TextStyle(color: Colors.white60, fontSize: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white54),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  const Divider(color: Colors.white10, height: 1),
                  Flexible(
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [const Color(0xFF38BDF8).withOpacity(0.12), const Color(0xFF0F172A)],
                            ),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF38BDF8).withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.flash_on_rounded, color: Color(0xFF38BDF8), size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: const [
                                    Text('Direct Video Stream', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                                    SizedBox(height: 2),
                                    Text('Raw stream (.tapecontent.net)', style: TextStyle(color: Colors.white54, fontSize: 11)),
                                  ],
                                ),
                              ),
                              ElevatedButton.icon(
                                onPressed: () async {
                                  Navigator.pop(ctx);
                                  final res = await _streamtapeService.resolveStreamingUrl(fileId);
                                  if (res['success'] == true && res['url'] != null) {
                                    _copyToClipboard(res['url'].toString(), 'Direct Streaming URL copied!');
                                  } else {
                                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: ${res['message']}'), backgroundColor: const Color(0xFFEF4444)));
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF38BDF8),
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                icon: const Icon(Icons.copy, size: 14),
                                label: const Text('Copy URL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('AVAILABLE DOMAIN MIRRORS', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
                            TextButton.icon(
                              onPressed: () {
                                final allLinks = domains.map((d) => '${d['label']} (Watch): https://${d['domain']}/v/$fileId\n${d['label']} (Embed): https://${d['domain']}/e/$fileId').join('\n\n');
                                _copyToClipboard(allLinks, 'All domain mirror links copied to clipboard!');
                              },
                              icon: const Icon(Icons.copy_all_rounded, size: 14, color: Color(0xFFEF4444)),
                              label: const Text('Copy All Mirrors', style: TextStyle(color: Color(0xFFEF4444), fontSize: 11, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ...domains.map((d) {
                          final domain = d['domain']!;
                          final label = d['label']!;
                          final watchUrl = 'https://$domain/v/$fileId';
                          final embedUrl = 'https://$domain/e/$fileId';
                          final iframe = '<iframe src="https://$domain/e/$fileId" width="100%" height="100%" allowfullscreen allowtransparency referrerpolicy="no-referrer"></iframe>';
                          final isDefault = domain == _streamtapeService.activeWebDomain;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isDefault ? const Color(0xFFEF4444).withOpacity(0.5) : Colors.white.withOpacity(0.06),
                                width: isDefault ? 1.5 : 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.public, color: isDefault ? const Color(0xFFEF4444) : const Color(0xFF38BDF8), size: 16),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Row(
                                        children: [
                                          Text(domain, style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                                          if (isDefault) ...[
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFEF4444).withOpacity(0.18),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: const Text('DEFAULT', style: TextStyle(color: Color(0xFFEF4444), fontSize: 9, fontWeight: FontWeight.bold)),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    Text(label, style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11)),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _buildCopyChip(
                                      icon: Icons.link,
                                      label: 'Watch Link (/v/)',
                                      onTap: () => _copyToClipboard(watchUrl, '$domain Watch Link copied!'),
                                    ),
                                    _buildCopyChip(
                                      icon: Icons.smart_display_outlined,
                                      label: 'Embed Link (/e/)',
                                      onTap: () => _copyToClipboard(embedUrl, '$domain Embed Link copied!'),
                                    ),
                                    _buildCopyChip(
                                      icon: Icons.code,
                                      label: '<iframe> HTML',
                                      onTap: () => _copyToClipboard(iframe, '$domain Iframe Embed Code copied!'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCopyChip({required IconData icon, required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: const Color(0xFF38BDF8)),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }


  Future<void> _showCreateFolderDialog() async {
    final ctrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1F2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Create New Folder', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Folder Name',
            hintStyle: TextStyle(color: Colors.white38),
            filled: true,
            fillColor: Color(0xFF0B0F19),
            border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            onPressed: () async {
              final name = ctrl.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              final res = await _streamtapeService.createFolder(name, parentId: _currentFolderId.isNotEmpty ? _currentFolderId : null);
              if (res['success'] == true) {
                _loadFolder();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Folder created successfully'), backgroundColor: Color(0xFF22C55E)),
                  );
                }
              } else {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed: ${res['message']}'), backgroundColor: const Color(0xFFEF4444)),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _showRenameFolderDialog(StreamtapeFolder folder) async {
    final ctrl = TextEditingController(text: folder.name);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1F2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Rename Folder', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'New Folder Name',
            hintStyle: TextStyle(color: Colors.white38),
            filled: true,
            fillColor: Color(0xFF0B0F19),
            border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            onPressed: () async {
              final name = ctrl.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              final res = await _streamtapeService.renameFolder(folder.id, name);
              if (res['success'] == true) {
                _loadFolder();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Folder renamed'), backgroundColor: Color(0xFF22C55E)),
                  );
                }
              } else {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed: ${res['message']}'), backgroundColor: const Color(0xFFEF4444)),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteFolder(StreamtapeFolder folder) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1F2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Folder', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to delete "${folder.name}"? This action cannot be undone.', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final res = await _streamtapeService.deleteFolder(folder.id);
      if (res['success'] == true) {
        _loadFolder();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Folder deleted'), backgroundColor: Color(0xFF22C55E)),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed: ${res['message']}'), backgroundColor: const Color(0xFFEF4444)),
          );
        }
      }
    }
  }

  Future<void> _showRenameFileDialog(StreamtapeFile file) async {
    final ctrl = TextEditingController(text: file.name);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1F2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Rename File', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'New File Name',
            hintStyle: TextStyle(color: Colors.white38),
            filled: true,
            fillColor: Color(0xFF0B0F19),
            border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            onPressed: () async {
              final name = ctrl.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              final res = await _streamtapeService.renameFile(file.id, name);
              if (res['success'] == true) {
                _loadFolder();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('File renamed'), backgroundColor: Color(0xFF22C55E)),
                  );
                }
              } else {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed: ${res['message']}'), backgroundColor: const Color(0xFFEF4444)),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteFile(StreamtapeFile file) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1F2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete File', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to delete "${file.name}"?', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final res = await _streamtapeService.deleteFile(file.id);
      if (res['success'] == true) {
        _loadFolder();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('File deleted'), backgroundColor: Color(0xFF22C55E)),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed: ${res['message']}'), backgroundColor: const Color(0xFFEF4444)),
          );
        }
      }
    }
  }

  Future<void> _showMoveFileDialog(StreamtapeFile file) async {
    // Show destination folder picker
    final rootRes = await _streamtapeService.listFolder(folderId: '');
    final allFolders = <StreamtapeFolder>[];
    if (rootRes['success'] == true && rootRes['folders'] is List<StreamtapeFolder>) {
      allFolders.addAll(rootRes['folders']);
    }

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1F2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Move File To...', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.folder_special, color: Color(0xFFEF4444)),
                title: const Text('Root Directory', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final res = await _streamtapeService.moveFile(file.id, '');
                  if (res['success'] == true) {
                    _loadFolder();
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File moved to Root'), backgroundColor: Color(0xFF22C55E)));
                  }
                },
              ),
              const Divider(color: Colors.white12),
              if (allFolders.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No subfolders found', style: TextStyle(color: Colors.white38)),
                )
              else
                ...allFolders.map(
                  (f) => ListTile(
                    leading: const Icon(Icons.folder, color: Color(0xFF38BDF8)),
                    title: Text(f.name, style: const TextStyle(color: Colors.white)),
                    onTap: () async {
                      Navigator.pop(ctx);
                      final res = await _streamtapeService.moveFile(file.id, f.id);
                      if (res['success'] == true) {
                        _loadFolder();
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('File moved to ${f.name}'), backgroundColor: const Color(0xFF22C55E)));
                      }
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _cloneFile(StreamtapeFile file) async {
    final res = await _streamtapeService.cloneFile(file.id, targetFolderId: _currentFolderId.isNotEmpty ? _currentFolderId : null);
    if (res['success'] == true) {
      _loadFolder();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File duplicated / cloned to current folder'), backgroundColor: Color(0xFF22C55E)),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: ${res['message']}'), backgroundColor: const Color(0xFFEF4444)),
        );
      }
    }
  }

  Future<void> _showAddRemoteUrlDialog() async {
    final urlCtrl = TextEditingController();
    final nameCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1F2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: const Color(0xFFEF4444).withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.cloud_upload_rounded, color: Color(0xFFEF4444), size: 18),
            ),
            const SizedBox(width: 10),
            const Text('Remote URL Upload', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: urlCtrl,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'DIRECT VIDEO URL (MP4 / MKV / STREAM)',
                  labelStyle: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold),
                  hintText: 'https://example.com/video.mp4',
                  hintStyle: TextStyle(color: Colors.white24, fontSize: 12),
                  filled: true,
                  fillColor: Color(0xFF0B0F19),
                  border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'CUSTOM FILE NAME (OPTIONAL)',
                  labelStyle: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold),
                  hintText: 'Movie Title (2024).mp4',
                  hintStyle: TextStyle(color: Colors.white24, fontSize: 12),
                  filled: true,
                  fillColor: Color(0xFF0B0F19),
                  border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.folder_open, size: 16, color: Color(0xFF38BDF8)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Target Folder: ${_navBreadcrumbs.last['name']}',
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          ElevatedButton.icon(
            onPressed: () async {
              final url = urlCtrl.text.trim();
              if (url.isEmpty) return;
              Navigator.pop(ctx);

              final res = await _streamtapeService.addRemoteUpload(
                url,
                name: nameCtrl.text.trim().isNotEmpty ? nameCtrl.text.trim() : null,
                folderId: _currentFolderId.isNotEmpty ? _currentFolderId : null,
              );

              if (res['success'] == true) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Remote upload queued successfully!'), backgroundColor: Color(0xFF22C55E)),
                  );
                  _tabController.animateTo(1); // switch to Remote Uploads tab
                  _fetchRemoteTasks();
                }
              } else {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed: ${res['message']}'), backgroundColor: const Color(0xFFEF4444)),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Start Upload'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveSettings() async {
    setState(() => _saving = true);

    // 1. Update local service
    await _streamtapeService.updateCredentials(login: _loginCtrl.text, key: _keyCtrl.text);

    if (_useCustomDomain) {
      await _streamtapeService.setCustomDomain(_customDomainCtrl.text);
    } else {
      final matchPreset = StreamtapeService.domainPresets.firstWhere(
        (p) => p['api'] == _selectedPresetApi,
        orElse: () => StreamtapeService.domainPresets.first,
      );
      await _streamtapeService.setDomainPreset(matchPreset['api']!, matchPreset['web']!);
    }

    // 2. Sync to backend
    final r = await _adminApi.saveStreamtapeConfig({
      'api_login': _loginCtrl.text.trim(),
      'api_key': _keyCtrl.text.trim(),
      'touch_per_run': _touchCtrl.text.trim(),
      'download_bytes': _downloadCtrl.text.trim(),
    });

    if (mounted) {
      setState(() => _saving = false);
      if (r['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Configuration saved successfully!'), backgroundColor: Color(0xFF22C55E)),
        );
        _fetchBackendDetails();
        _loadFolder();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(r['message'] ?? 'Failed to save config'), backgroundColor: const Color(0xFFEF4444)),
        );
      }
    }
  }

  Future<void> _testConnection() async {
    setState(() => _testingConnection = true);
    await _streamtapeService.updateCredentials(login: _loginCtrl.text, key: _keyCtrl.text);
    if (_useCustomDomain) {
      await _streamtapeService.setCustomDomain(_customDomainCtrl.text);
    } else {
      final matchPreset = StreamtapeService.domainPresets.firstWhere(
        (p) => p['api'] == _selectedPresetApi,
        orElse: () => StreamtapeService.domainPresets.first,
      );
      await _streamtapeService.setDomainPreset(matchPreset['api']!, matchPreset['web']!);
    }

    final res = await _streamtapeService.testConnection();

    if (mounted) {
      setState(() => _testingConnection = false);
      if (res['success'] == true) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1A1F2E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: const [
                Icon(Icons.check_circle, color: Color(0xFF22C55E)),
                SizedBox(width: 10),
                Text('Connection Successful', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Active Domain: ${_streamtapeService.activeApiDomain}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 6),
                if (res['account'] is Map) ...[
                  Text('Account Email: ${res['account']['email'] ?? 'N/A'}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text('Signed Up: ${res['account']['signup_at'] ?? 'N/A'}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                ],
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK', style: TextStyle(color: Color(0xFFEF4444)))),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connection Failed: ${res['message']}'), backgroundColor: const Color(0xFFEF4444)),
        );
      }
    }
  }

  Future<void> _runKeepalive() async {
    setState(() => _running = true);
    final r = await _adminApi.triggerKeepalive();
    if (mounted) {
      setState(() => _running = false);
      if (r['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(r['message'] ?? 'Keepalive run triggered successfully'), backgroundColor: const Color(0xFF22C55E)),
        );
        _fetchBackendDetails();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(r['message'] ?? 'Failed to run keepalive'), backgroundColor: const Color(0xFFEF4444)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07090E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0F19),
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.menu), onPressed: DrawerProvider.openDrawer),
        title: Text('Streamtape Hub', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _fetchBackendDetails();
              _loadFolder();
              _fetchRemoteTasks();
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFEF4444),
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white38,
          labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: const [
            Tab(icon: Icon(Icons.folder_open_rounded, size: 20), text: 'Files'),
            Tab(icon: Icon(Icons.cloud_upload_outlined, size: 20), text: 'Remote DL'),
            Tab(icon: Icon(Icons.sync_rounded, size: 20), text: 'Keepalive'),
            Tab(icon: Icon(Icons.settings_suggest_rounded, size: 20), text: 'Settings'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFEF4444)))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildFileManagerTab(),
                _buildRemoteUploadsTab(),
                _buildKeepaliveTab(),
                _buildSettingsTab(),
              ],
            ),
    );
  }

  // -------------------------------------------------------------
  // TAB 1: FILE MANAGER
  // -------------------------------------------------------------
  Widget _buildFileManagerTab() {
    final filteredFiles = _files.where((f) {
      if (_fileSearchQuery.isEmpty) return true;
      return f.name.toLowerCase().contains(_fileSearchQuery.toLowerCase());
    }).toList();

    return RefreshIndicator(
      color: const Color(0xFFEF4444),
      backgroundColor: const Color(0xFF1A1F2E),
      onRefresh: _loadFolder,
      child: Column(
        children: [
          // Breadcrumb Navigation & Top Action Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: const Color(0xFF0E1322),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: List.generate(_navBreadcrumbs.length, (idx) {
                        final isLast = idx == _navBreadcrumbs.length - 1;
                        return Row(
                          children: [
                            InkWell(
                              onTap: isLast ? null : () => _navigateBackToBreadcrumb(idx),
                              borderRadius: BorderRadius.circular(6),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                child: Text(
                                  _navBreadcrumbs[idx]['name']!,
                                  style: GoogleFonts.outfit(
                                    color: isLast ? const Color(0xFFEF4444) : Colors.white70,
                                    fontWeight: isLast ? FontWeight.bold : FontWeight.normal,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                            if (!isLast) const Icon(Icons.chevron_right, size: 16, color: Colors.white24),
                          ],
                        );
                      }),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.create_new_folder_outlined, color: Color(0xFF38BDF8), size: 22),
                  tooltip: 'New Folder',
                  onPressed: _showCreateFolderDialog,
                ),
                IconButton(
                  icon: const Icon(Icons.cloud_upload_outlined, color: Color(0xFFEF4444), size: 22),
                  tooltip: 'Remote Upload URL',
                  onPressed: _showAddRemoteUrlDialog,
                ),
              ],
            ),
          ),

          // Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF141927),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withOpacity(0.06)),
              ),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _fileSearchQuery = v),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search files in current folder...',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12),
                  prefixIcon: const Icon(Icons.search, size: 18, color: Colors.white38),
                  suffixIcon: _fileSearchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 16, color: Colors.white38),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _fileSearchQuery = '');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),

          // Files and Folders List
          Expanded(
            child: _loadingFiles
                ? const Center(child: CircularProgressIndicator(color: Color(0xFFEF4444)))
                : _fileManagerError != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.error_outline, size: 48, color: Color(0xFFEF4444)),
                              const SizedBox(height: 12),
                              Text(_fileManagerError!, style: const TextStyle(color: Colors.white70, fontSize: 13), textAlign: TextAlign.center),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: _loadFolder,
                                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
                                icon: const Icon(Icons.refresh, size: 16),
                                label: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : (_folders.isEmpty && filteredFiles.isEmpty)
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.folder_open_outlined, size: 56, color: Colors.white.withOpacity(0.15)),
                                const SizedBox(height: 12),
                                Text('This folder is empty', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 14)),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: _showAddRemoteUrlDialog,
                                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
                                  icon: const Icon(Icons.cloud_upload_outlined, size: 16),
                                  label: const Text('Upload Remote URL'),
                                ),
                              ],
                            ),
                          )
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                            children: [
                              // Subfolders
                              if (_folders.isNotEmpty) ...[
                                Padding(
                                  padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
                                  child: Text('FOLDERS (${_folders.length})', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                                ),
                                ..._folders.map(_buildFolderTile),
                                const SizedBox(height: 16),
                              ],

                              // Files
                              if (filteredFiles.isNotEmpty) ...[
                                Padding(
                                  padding: const EdgeInsets.only(left: 4, bottom: 8),
                                  child: Text('FILES (${filteredFiles.length})', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                                ),
                                ...filteredFiles.map(_buildFileTile),
                              ],
                            ],
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildFolderTile(StreamtapeFolder folder) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF111728),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: ListTile(
        onTap: () => _navigateToFolder(folder.id, folder.name),
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: const Color(0xFF38BDF8).withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.folder_rounded, color: Color(0xFF38BDF8), size: 20),
        ),
        title: Text(folder.name, style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: Colors.white38, size: 20),
          color: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          onSelected: (val) {
            if (val == 'rename') _showRenameFolderDialog(folder);
            if (val == 'delete') _deleteFolder(folder);
          },
          itemBuilder: (ctx) => [
            const PopupMenuItem(value: 'rename', child: Row(children: [Icon(Icons.edit, size: 16, color: Colors.white70), SizedBox(width: 8), Text('Rename', style: TextStyle(color: Colors.white))])),
            const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, size: 16, color: Color(0xFFEF4444)), SizedBox(width: 8), Text('Delete', style: TextStyle(color: Color(0xFFEF4444)))])),
          ],
        ),
      ),
    );
  }

  Widget _buildFileTile(StreamtapeFile file) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF111728),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFFEF4444), Color(0xFFDC2626)]),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.movie_creation_outlined, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.name,
                      style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(file.formattedSize, style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                        Text('•  ${file.downloads} DLs', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10)),
                        if (file.convert != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF22C55E).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(file.convert!.toUpperCase(), style: const TextStyle(color: Color(0xFF22C55E), fontSize: 9, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Colors.white38, size: 20),
                color: const Color(0xFF1E293B),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onSelected: (val) async {
                  if (val == 'play') _playVideo(file);
                  if (val == 'copy_mirrors') _showCopyLinksModal(file);
                  if (val == 'copy_link') _copyToClipboard(_streamtapeService.getPublicWebLink(file.linkid.isNotEmpty ? file.linkid : file.id), 'Streamtape Link copied!');
                  if (val == 'copy_direct') {
                    final res = await _streamtapeService.resolveStreamingUrl(file.linkid.isNotEmpty ? file.linkid : file.id);
                    if (res['success'] == true && res['url'] != null) {
                      _copyToClipboard(res['url'].toString(), 'Direct Streaming URL copied!');
                    } else {
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: ${res['message']}'), backgroundColor: const Color(0xFFEF4444)));
                    }
                  }
                  if (val == 'clone') _cloneFile(file);
                  if (val == 'move') _showMoveFileDialog(file);
                  if (val == 'rename') _showRenameFileDialog(file);
                  if (val == 'delete') _deleteFile(file);
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(value: 'play', child: Row(children: [Icon(Icons.play_circle_fill, size: 16, color: Color(0xFFEF4444)), SizedBox(width: 8), Text('Play Video', style: TextStyle(color: Colors.white))])),
                  const PopupMenuItem(value: 'copy_mirrors', child: Row(children: [Icon(Icons.share_rounded, size: 16, color: Color(0xFF38BDF8)), SizedBox(width: 8), Text('Links & Mirrors (All Domains)', style: TextStyle(color: Colors.white))])),
                  const PopupMenuItem(value: 'copy_link', child: Row(children: [Icon(Icons.link, size: 16, color: Colors.white70), SizedBox(width: 8), Text('Copy Page Link', style: TextStyle(color: Colors.white))])),
                  const PopupMenuItem(value: 'copy_direct', child: Row(children: [Icon(Icons.flash_on, size: 16, color: Color(0xFF38BDF8)), SizedBox(width: 8), Text('Copy Direct Stream URL', style: TextStyle(color: Colors.white))])),
                  const PopupMenuItem(value: 'clone', child: Row(children: [Icon(Icons.copy, size: 16, color: Colors.white70), SizedBox(width: 8), Text('Duplicate / Clone', style: TextStyle(color: Colors.white))])),
                  const PopupMenuItem(value: 'move', child: Row(children: [Icon(Icons.drive_file_move_outlined, size: 16, color: Colors.white70), SizedBox(width: 8), Text('Move to Folder...', style: TextStyle(color: Colors.white))])),
                  const PopupMenuItem(value: 'rename', child: Row(children: [Icon(Icons.edit, size: 16, color: Colors.white70), SizedBox(width: 8), Text('Rename', style: TextStyle(color: Colors.white))])),
                  const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, size: 16, color: Color(0xFFEF4444)), SizedBox(width: 8), Text('Delete', style: TextStyle(color: Color(0xFFEF4444)))])),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 34,
                  child: ElevatedButton.icon(
                    onPressed: () => _playVideo(file),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4444),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: const Text('Play', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 34,
                child: ElevatedButton.icon(
                  onPressed: () => _showCopyLinksModal(file),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E293B),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    side: BorderSide(color: Colors.white.withOpacity(0.12)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  icon: const Icon(Icons.share_rounded, size: 14, color: Color(0xFF38BDF8)),
                  label: const Text('Links & Mirrors', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // TAB 2: REMOTE UPLOADS MONITOR
  // -------------------------------------------------------------
  Widget _buildRemoteUploadsTab() {
    return RefreshIndicator(
      color: const Color(0xFFEF4444),
      backgroundColor: const Color(0xFF1A1F2E),
      onRefresh: () => _fetchRemoteTasks(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [const Color(0xFFEF4444).withOpacity(0.2), const Color(0xFF0E1322)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: const Color(0xFFEF4444), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.cloud_download_rounded, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Remote URL Uploader', style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text('Download any direct video URL to Streamtape cloud in background.', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle, color: Color(0xFFEF4444), size: 32),
                  onPressed: _showAddRemoteUrlDialog,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Active tasks list
          if (_loadingRemote)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator(color: Color(0xFFEF4444))))
          else if (_remoteTasks.isEmpty)
            Padding(
              padding: const EdgeInsets.all(48),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.cloud_done_outlined, size: 48, color: Colors.white.withOpacity(0.2)),
                    const SizedBox(height: 12),
                    Text('No Remote Upload Tasks', style: GoogleFonts.outfit(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('Tap + above to start a background direct download.', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12), textAlign: TextAlign.center),
                  ],
                ),
              ),
            )
          else
            ..._remoteTasks.map(_buildRemoteTaskTile),
        ],
      ),
    );
  }

  Widget _buildRemoteTaskTile(StreamtapeRemoteTask task) {
    final isDone = task.isCompleted;
    final isError = task.isFailed;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111728),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDone ? const Color(0xFF22C55E).withOpacity(0.25) : isError ? const Color(0xFFEF4444).withOpacity(0.25) : Colors.white.withOpacity(0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  task.name ?? 'Streamtape Remote Task',
                  style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isDone ? const Color(0xFF22C55E).withOpacity(0.15) : isError ? const Color(0xFFEF4444).withOpacity(0.15) : const Color(0xFF38BDF8).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  task.status.toUpperCase(),
                  style: TextStyle(
                    color: isDone ? const Color(0xFF22C55E) : isError ? const Color(0xFFEF4444) : const Color(0xFF38BDF8),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(task.remoteUrl, style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: isDone ? 1.0 : task.progress,
            backgroundColor: Colors.white.withOpacity(0.06),
            valueColor: AlwaysStoppedAnimation(isDone ? const Color(0xFF22C55E) : const Color(0xFFEF4444)),
            borderRadius: BorderRadius.circular(4),
            minHeight: 6,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(task.formattedProgress, style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11, fontWeight: FontWeight.w600)),
              Row(
                children: [
                  if (task.resultUrl != null)
                    TextButton.icon(
                      onPressed: () {
                        final uri = Uri.tryParse(task.resultUrl!);
                        final segments = uri?.pathSegments ?? [];
                        final fileId = segments.isNotEmpty ? segments.last : task.id;
                        _showCopyLinksModal(StreamtapeFile(
                          id: fileId,
                          name: task.name ?? 'Streamtape Video',
                          size: 0,
                          link: task.resultUrl!,
                          linkid: fileId,
                        ));
                      },
                      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), visualDensity: VisualDensity.compact),
                      icon: const Icon(Icons.share_rounded, size: 14, color: Color(0xFF38BDF8)),
                      label: const Text('Links & Mirrors', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.w600)),
                    ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.white38, size: 18),
                    onPressed: () async {
                      final res = await _streamtapeService.removeRemoteUpload(task.id);
                      if (res['success'] == true) _fetchRemoteTasks(silent: true);
                    },
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // TAB 3: KEEPALIVE & SYNC AUTOMATION
  // -------------------------------------------------------------
  Widget _buildKeepaliveTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildAnalyticsOverview(),
          const SizedBox(height: 16),
          _buildKeepaliveControlCard(),
          const SizedBox(height: 16),
          _buildLogsSection(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildAnalyticsOverview() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.45,
      children: [
        GlassCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(color: const Color(0xFFEF4444).withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.person, color: Color(0xFFEF4444), size: 16),
                  ),
                  const SizedBox(width: 8),
                  Text('ACCOUNT', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _accountInfo != null ? (_accountInfo!['email']?.toString() ?? 'Configured') : 'Not Configured',
                style: GoogleFonts.outfit(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (_accountInfo != null && _accountInfo!['signup_at'] != null)
                Text('Since: ${_accountInfo!['signup_at']}', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 9)),
            ],
          ),
        ),
        GlassCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(color: const Color(0xFF38BDF8).withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.cloud_done_rounded, color: Color(0xFF38BDF8), size: 16),
                  ),
                  const SizedBox(width: 8),
                  Text('STATUS', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _accountInfo != null ? 'Connected' : 'Offline',
                style: GoogleFonts.outfit(color: _accountInfo != null ? const Color(0xFF10B981) : Colors.orangeAccent, fontSize: 13, fontWeight: FontWeight.bold),
              ),
              Text('API: ${_streamtapeService.activeApiDomain}', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 9), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        GlassCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('MONITORED VIDEOS', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1)),
              const SizedBox(height: 4),
              Text('$_filesCount', style: GoogleFonts.outfit(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
              if (_cachedTime != null)
                Text('Synced $_cachedTime', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 8)),
            ],
          ),
        ),
        GlassCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('BATCH OFFSET', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1)),
              const SizedBox(height: 4),
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(text: '$_offset', style: GoogleFonts.outfit(color: const Color(0xFF10B981), fontSize: 22, fontWeight: FontWeight.w900)),
                    TextSpan(text: ' / $_filesCount', style: GoogleFonts.outfit(color: Colors.white.withOpacity(0.3), fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildKeepaliveControlCard() {
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: const Color(0xFFEF4444).withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.play_circle_fill_rounded, color: Color(0xFFEF4444), size: 18),
              ),
              const SizedBox(width: 12),
              const Text('Trigger Keepalive Run', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Touches and streams bytes for the next batch of videos from Streamtape to prevent inactive file deletion.',
            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _field('Touch Per Run', _touchCtrl, Icons.touch_app_outlined)),
              const SizedBox(width: 12),
              Expanded(child: _field('Download Bytes', _downloadCtrl, Icons.data_usage_outlined)),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            height: 46,
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
              label: const Text('Run Batch Now', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogsSection() {
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: const Color(0xFF3B82F6).withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.analytics_outlined, color: Color(0xFF3B82F6), size: 18),
              ),
              const SizedBox(width: 12),
              const Text('Keepalive Activity Log', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 14),
          if (_logs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('No keepalive logs recorded yet', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12)),
              ),
            )
          else
            Container(
              constraints: const BoxConstraints(maxHeight: 280),
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
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(filename, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                              Text(time, style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 9)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isSuccess ? const Color(0xFF10B981).withOpacity(0.1) : const Color(0xFFEF4444).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
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

  // -------------------------------------------------------------
  // TAB 4: DOMAIN MASTER SWITCH & SETTINGS
  // -------------------------------------------------------------
  Widget _buildSettingsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Domain Master Switch Card
          GlassCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(color: const Color(0xFF38BDF8).withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.language_rounded, color: Color(0xFF38BDF8), size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Master Domain Switcher', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                          Text('Switch API & Web mirrors when Streamtape updates domain', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text('STANDARD PRESETS', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: StreamtapeService.domainPresets.map((preset) {
                    final isSelected = !_useCustomDomain && _selectedPresetApi == preset['api'];
                    return ChoiceChip(
                      label: Text(preset['label']!, style: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
                      selected: isSelected,
                      selectedColor: const Color(0xFFEF4444),
                      backgroundColor: const Color(0xFF0B0F19),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: isSelected ? const Color(0xFFEF4444) : Colors.white12)),
                      onSelected: (val) {
                        if (val) {
                          setState(() {
                            _useCustomDomain = false;
                            _selectedPresetApi = preset['api']!;
                          });
                        }
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Switch(
                      value: _useCustomDomain,
                      activeColor: const Color(0xFFEF4444),
                      onChanged: (v) => setState(() => _useCustomDomain = v),
                    ),
                    const SizedBox(width: 8),
                    const Text('Use Custom Domain Override', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
                if (_useCustomDomain) ...[
                  const SizedBox(height: 10),
                  _field('Custom Streamtape Domain', _customDomainCtrl, Icons.dns_rounded),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Credentials Card
          GlassCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(color: const Color(0xFFEF4444).withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.key_rounded, color: Color(0xFFEF4444), size: 18),
                    ),
                    const SizedBox(width: 12),
                    const Text('API Credentials', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 16),
                _field('Streamtape API Login', _loginCtrl, Icons.person_outline),
                const SizedBox(height: 12),
                _field('Streamtape API Key', _keyCtrl, Icons.lock_outline, obscure: true),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 46,
                        child: OutlinedButton.icon(
                          onPressed: _testingConnection ? null : _testConnection,
                          icon: _testingConnection
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.bolt, size: 16),
                          label: const Text('Test Connection', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(color: Colors.white.withOpacity(0.2)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 46,
                        child: ElevatedButton.icon(
                          onPressed: _saving ? null : _saveSettings,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFEF4444),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: _saving
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.save_outlined, size: 16),
                          label: const Text('Save Settings', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl, IconData icon, {bool obscure = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            label.toUpperCase(),
            style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF0B0F19),
            borderRadius: BorderRadius.circular(12),
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
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
