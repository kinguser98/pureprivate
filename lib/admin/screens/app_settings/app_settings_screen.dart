import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../utils/admin_api_client.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/common/glass_card.dart';

class AppSettingsScreen extends ConsumerStatefulWidget {
  const AppSettingsScreen({super.key});

  @override
  ConsumerState<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends ConsumerState<AppSettingsScreen> {
  final _adminApi = AdminApiClient();
  bool _isLoading = true;
  bool _isSaving = false;
  
  List<Map<String, dynamic>> _sources = [];
  String _maxSourceSize = '0';
  List<Map<String, dynamic>> _portals = [];
  
  bool _stremioEnabled = true;
  List<Map<String, dynamic>> _stremioAddons = [];
  bool _importingStremio = false;
  final _stremioInputCtrl = TextEditingController();

  bool _nuveoEnabled = true;
  List<Map<String, dynamic>> _nuveoAddons = [];
  bool _importingNuveo = false;
  final _nuveoInputCtrl = TextEditingController();

  bool _telegramEnabled = true;
  final _tgApiIdCtrl = TextEditingController();
  final _tgApiHashCtrl = TextEditingController();

  final _blockedGroupsCtrl = TextEditingController();

  final _torrentioUrlCtrl = TextEditingController();
  final _stravoUrlCtrl = TextEditingController();
  final _netmirrorDomainsCtrl = TextEditingController();
  final _seedrTokenCtrl = TextEditingController();
  
  // Track expanded addon states
  final Set<String> _expandedAddons = {};

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _loadData());
  }

  @override
  void dispose() {
    _stremioInputCtrl.dispose();
    _nuveoInputCtrl.dispose();
    _tgApiIdCtrl.dispose();
    _tgApiHashCtrl.dispose();
    _blockedGroupsCtrl.dispose();
    _torrentioUrlCtrl.dispose();
    _stravoUrlCtrl.dispose();
    _netmirrorDomainsCtrl.dispose();
    _seedrTokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    try {
      // 1. Fetch global settings
      await ref.read(settingsProvider.notifier).fetchSettings();
      final settingsMap = ref.read(settingsProvider).settings;
      
      // 2. Fetch Stalker Portals configured in admin panel
      final allPortals = await _adminApi.getStalkerSettings();
      
      // 3. Parse Source Priority & Visibility
      final allSources = ['vidlink', 'netmirror', 'cinemm', 'stalker', 'stravo', 'castle', 'torrent', 'stremioAddon', 'telegram'];
      final List<String> enabledSources = [];
      if (settingsMap.containsKey('source_order')) {
        try {
          final List<dynamic> parsed = jsonDecode(settingsMap['source_order']!);
          for (final s in parsed) {
            if (allSources.contains(s)) {
              enabledSources.add(s.toString());
            }
          }
        } catch (_) {}
      }
      
      final List<Map<String, dynamic>> parsedSources = [];
      for (final s in enabledSources) {
        parsedSources.add({'key': s, 'name': _getSourceLabel(s), 'enabled': true});
      }
      for (final s in allSources) {
        if (!enabledSources.contains(s)) {
          parsedSources.add({'key': s, 'name': _getSourceLabel(s), 'enabled': false});
        }
      }
      
      // 4. Parse Max Stream Size
      _maxSourceSize = settingsMap['max_source_size_mb'] ?? '0';
      
      // 5. Parse Active Stalker Portals
      List<int> activePortalIds = [];
      if (settingsMap.containsKey('active_stalker_portals')) {
        try {
          activePortalIds = List<int>.from(jsonDecode(settingsMap['active_stalker_portals']!));
        } catch (_) {}
      }
      
      final List<Map<String, dynamic>> parsedPortals = allPortals.map((p) {
        final id = int.tryParse(p['id'].toString()) ?? 0;
        return {
          'id': id,
          'name': p['name']?.toString() ?? 'Portal $id',
          'url': p['portal_url']?.toString() ?? '',
          'enabled': activePortalIds.contains(id),
        };
      }).toList();
      
      // 6. Parse Stremio Addons
      _stremioEnabled = (settingsMap['stremio_addons_enabled'] ?? 'true') == 'true';
      List<Map<String, dynamic>> parsedStremio = [];
      if (settingsMap.containsKey('global_stremio_addons')) {
        try {
          final list = jsonDecode(settingsMap['global_stremio_addons']!);
          if (list is List) {
            parsedStremio = list.map((item) {
              if (item is String) {
                return {'url': item, 'name': Uri.parse(item).host, 'enabled': true, 'manifestLoaded': false};
              }
              return Map<String, dynamic>.from(item);
            }).toList();
          }
        } catch (_) {}
      }
      
      // 7. Parse Nuveo Addons
      _nuveoEnabled = (settingsMap['nuveo_addons_enabled'] ?? 'true') == 'true';
      List<Map<String, dynamic>> parsedNuveo = [];
      if (settingsMap.containsKey('global_nuveo_addons')) {
        try {
          final list = jsonDecode(settingsMap['global_nuveo_addons']!);
          if (list is List) {
            parsedNuveo = list.map((item) => Map<String, dynamic>.from(item)).toList();
          }
        } catch (_) {}
      }
      
      // 8. Parse Blocked Groups
      _blockedGroupsCtrl.text = settingsMap['blocked_addon_groups'] ?? '';

      // 9. Parse Telegram Integration
      final hasTgId = (settingsMap['telegram_api_id'] ?? '').isNotEmpty;
      final hasTgHash = (settingsMap['telegram_api_hash'] ?? '').isNotEmpty;
      _telegramEnabled = settingsMap.containsKey('source_show_telegram')
          ? (settingsMap['source_show_telegram'] == 'true')
          : (hasTgId || hasTgHash); // default ON when creds already saved
      _tgApiIdCtrl.text = settingsMap['telegram_api_id'] ?? '';
      _tgApiHashCtrl.text = settingsMap['telegram_api_hash'] ?? '';

      // 10. Parse Provider Addons & Seedr Token
      _torrentioUrlCtrl.text = settingsMap['torrentio_addon_url'] ?? '';
      _stravoUrlCtrl.text = settingsMap['stravo_addon_url'] ?? '';
      _netmirrorDomainsCtrl.text = settingsMap['netmirror_domains'] ?? '';
      _seedrTokenCtrl.text = settingsMap['seedr_token'] ?? '';

      if (mounted) {
        setState(() {
          _sources = parsedSources;
          _portals = parsedPortals;
          _stremioAddons = parsedStremio;
          _nuveoAddons = parsedNuveo;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load settings from server'), backgroundColor: Color(0xFFEF4444)),
        );
      }
    }
  }

  String _getSourceLabel(String key) {
    switch (key) {
      case 'vidlink': return 'VidLink Server';
      case 'netmirror': return 'NetMirror Server';
      case 'cinemm': return 'CineMM Server';
      case 'stalker': return 'Stalker VOD Server';
      case 'stravo': return 'Stravo Server';
      case 'castle': return 'Castle TV';
      case 'torrent': return 'Torrent Server';
      case 'stremioAddon': return 'Stremio Addons';
      case 'telegram': return 'Telegram Server';
      default: return key;
    }
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final item = _sources.removeAt(oldIndex);
      _sources.insert(newIndex, item);
    });
  }

  void _toggleSourceVisibility(int index) {
    setState(() {
      _sources[index]['enabled'] = !(_sources[index]['enabled'] as bool);
    });
  }

  void _togglePortal(int index) {
    setState(() {
      _portals[index]['enabled'] = !(_portals[index]['enabled'] as bool);
    });
  }

  Future<void> _importStremioManifest() async {
    final url = _stremioInputCtrl.text.trim();
    if (url.isEmpty || !url.startsWith('http')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid URL starting with http/https'), backgroundColor: Color(0xFFEF4444)),
      );
      return;
    }
    
    setState(() => _importingStremio = true);
    final res = await _adminApi.fetchStremioManifest(url);
    setState(() => _importingStremio = false);
    if (!mounted) return;
    
    if (res['success'] == true && res['addon'] != null) {
      final addon = Map<String, dynamic>.from(res['addon']);
      addon['enabled'] = true;
      
      setState(() {
        _stremioAddons.removeWhere((a) => a['url'] == url);
        _stremioAddons.add(addon);
        _stremioInputCtrl.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported addon: ${addon['name']}'), backgroundColor: const Color(0xFF22C55E)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to import: ${res['error'] ?? 'Unknown error'}'), backgroundColor: const Color(0xFFEF4444)),
      );
    }
  }

  Future<void> _importNuveoManifest() async {
    final url = _nuveoInputCtrl.text.trim();
    if (url.isEmpty || !url.startsWith('http')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid URL starting with http/https'), backgroundColor: Color(0xFFEF4444)),
      );
      return;
    }
    
    setState(() => _importingNuveo = true);
    final res = await _adminApi.fetchNuveoManifest(url);
    setState(() => _importingNuveo = false);
    if (!mounted) return;
    
    if (res['success'] == true && res['addon'] != null) {
      final addon = Map<String, dynamic>.from(res['addon']);
      addon['enabled'] = true;
      
      setState(() {
        _nuveoAddons.removeWhere((a) => a['url'] == url);
        _nuveoAddons.add(addon);
        _nuveoInputCtrl.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported Nuveo addon: ${addon['name']}'), backgroundColor: const Color(0xFF22C55E)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to import: ${res['error'] ?? 'Unknown error'}'), backgroundColor: const Color(0xFFEF4444)),
      );
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    
    try {
      final enabledKeys = _sources.where((s) => s['enabled'] == true).map((s) => s['key'].toString()).toList();
      final sourceOrderJson = jsonEncode(enabledKeys);
      
      final activePortalIds = _portals.where((p) => p['enabled'] == true).map((p) => p['id'] as int).toList();
      final activePortalsJson = jsonEncode(activePortalIds);
      
      final newSettings = {
        'source_order': sourceOrderJson,
        'source_visibility': sourceOrderJson,
        'max_source_size_mb': _maxSourceSize,
        'active_stalker_portals': activePortalsJson,
        'stremio_addons_enabled': _stremioEnabled ? 'true' : 'false',
        'nuveo_addons_enabled': _nuveoEnabled ? 'true' : 'false',
        'global_stremio_addons': jsonEncode(_stremioAddons),
        'global_nuveo_addons': jsonEncode(_nuveoAddons),
        'blocked_addon_groups': _blockedGroupsCtrl.text.trim(),
        'source_show_telegram': _telegramEnabled ? 'true' : 'false',
        'telegram_api_id': _tgApiIdCtrl.text.trim(),
        'telegram_api_hash': _tgApiHashCtrl.text.trim(),
        'torrentio_addon_url': _torrentioUrlCtrl.text.trim(),
        'stravo_addon_url': _stravoUrlCtrl.text.trim(),
        'netmirror_domains': _netmirrorDomainsCtrl.text.trim(),
        'seedr_token': _seedrTokenCtrl.text.trim(),
      };
      
      for (final s in _sources) {
        newSettings['source_show_${s['key']}'] = s['enabled'] == true ? 'true' : 'false';
      }
      
      await ref.read(settingsProvider.notifier).bulkSaveSettings(newSettings);
      
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings saved successfully'), backgroundColor: Color(0xFF22C55E)),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save settings'), backgroundColor: Color(0xFFEF4444)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('App Settings'),
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildSourcePrioritySection(),
                      const SizedBox(height: 16),
                       _buildMaxStreamSizeSection(),
                       const SizedBox(height: 16),
                       _buildAddonUrlsAndTorrentsSection(),
                       const SizedBox(height: 16),
                       _buildStalkerPortalsSection(),
                      const SizedBox(height: 16),
                      _buildStremioAddonsSection(),
                      const SizedBox(height: 16),
                      _buildNuveoAddonsSection(),
                      const SizedBox(height: 16),
                      _buildTelegramSection(),
                      const SizedBox(height: 16),
                      _buildBlockedGroupsSection(),
                      const SizedBox(height: 32),
                      _buildSaveButton(),
                      const SizedBox(height: 48),
                    ],
                  ),
                ),
                if (_isSaving)
                  Container(
                    color: Colors.black.withOpacity(0.5),
                    child: const Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
    );
  }

  Widget _buildSectionTitle(String title, {String? subtitle}) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8, top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                color: Colors.white.withOpacity(0.4),
                fontSize: 11,
              ),
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildSourcePrioritySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Source Priority & Visibility', subtitle: 'Drag to reorder priority. Switch off to hide from apps.'),
        GlassCard(
          padding: const EdgeInsets.all(8),
          child: ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _sources.length,
            onReorder: _onReorder,
            itemBuilder: (context, index) {
              final source = _sources[index];
              final isEnabled = source['enabled'] as bool;
              return Container(
                key: ValueKey(source['key']),
                margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                decoration: BoxDecoration(
                  color: isEnabled ? Colors.white.withOpacity(0.04) : Colors.white.withOpacity(0.01),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(isEnabled ? 0.05 : 0.01)),
                ),
                child: ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  leading: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ReorderableDragStartListener(
                        index: index,
                        child: Icon(
                          Icons.drag_handle_rounded,
                          color: Colors.white.withOpacity(0.4),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isEnabled ? const Color(0xFFEF4444).withOpacity(0.1) : Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            color: isEnabled ? const Color(0xFFEF4444) : Colors.white60,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  title: Text(
                    source['name'] as String,
                    style: TextStyle(
                      color: isEnabled ? Colors.white : Colors.white.withOpacity(0.35),
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      decoration: isEnabled ? TextDecoration.none : TextDecoration.lineThrough,
                    ),
                  ),
                  trailing: Switch(
                    value: isEnabled,
                    onChanged: (_) => _toggleSourceVisibility(index),
                    activeThumbColor: const Color(0xFFEF4444),
                    activeTrackColor: const Color(0xFFEF4444).withOpacity(0.4),
                    inactiveThumbColor: Colors.white60,
                    inactiveTrackColor: Colors.white10,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMaxStreamSizeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Max Stream Size Limit', subtitle: 'Streams larger than this size in MB will be hidden. 0 = no limit.'),
        GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.storage, color: Colors.white60, size: 20),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  keyboardType: TextInputType.number,
                  controller: TextEditingController(text: _maxSourceSize)
                    ..selection = TextSelection.fromPosition(TextPosition(offset: _maxSourceSize.length)),
                  onChanged: (val) => _maxSourceSize = val,
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                  decoration: const InputDecoration(
                    hintText: '0 (No Limit)',
                    hintStyle: TextStyle(color: Colors.white30),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              const Text('MB', style: TextStyle(color: Colors.white30, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStalkerPortalsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Active Stalker Portals', subtitle: 'Only VOD movies from selected portals will show in apps.'),
        if (_portals.isEmpty)
          const GlassCard(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('No configured Stalker Portals found', style: TextStyle(color: Colors.white54, fontSize: 13))),
          )
        else
          GlassCard(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _portals.length,
              separatorBuilder: (_, __) => Divider(color: Colors.white.withOpacity(0.05), height: 1),
              itemBuilder: (context, index) {
                final portal = _portals[index];
                return CheckboxListTile(
                  value: portal['enabled'] as bool,
                  onChanged: (_) => _togglePortal(index),
                  activeColor: const Color(0xFFEF4444),
                  checkColor: Colors.white,
                  title: Text(portal['name'] as String, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                  subtitle: Text(portal['url'] as String, style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11)),
                  controlAffinity: ListTileControlAffinity.leading,
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildStremioAddonsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionTitle('Stremio Addons', subtitle: 'Global manifests loaded for search queries.'),
            Switch(
              value: _stremioEnabled,
              onChanged: (val) => setState(() => _stremioEnabled = val),
              activeThumbColor: const Color(0xFFEF4444),
              activeTrackColor: const Color(0xFFEF4444).withOpacity(0.4),
              inactiveThumbColor: Colors.white60,
              inactiveTrackColor: Colors.white10,
            ),
          ],
        ),
        if (_stremioEnabled) ...[
          GlassCard(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _stremioInputCtrl,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'https://raw.githubusercontent.com/.../manifest.json',
                          hintStyle: TextStyle(color: Colors.white.withOpacity(0.25)),
                          filled: true,
                          fillColor: const Color(0xFF0B0F19),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _importingStremio ? null : _importStremioManifest,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFEF4444),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _importingStremio
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Import', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                    ),
                  ],
                ),
                if (_stremioAddons.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _stremioAddons.length,
                    itemBuilder: (context, idx) {
                      final addon = _stremioAddons[idx];
                      final url = addon['url']?.toString() ?? '';
                      final name = addon['name']?.toString() ?? 'Stremio Addon';
                      final ver = addon['version']?.toString() ?? '';
                      final isEnabled = addon['enabled'] != false;
                      final isExpanded = _expandedAddons.contains('stremio_$url');
                      final List<String> resources = [];
                      if (addon['resources'] is List) {
                        for (final r in addon['resources']) {
                          if (r is String) {
                            resources.add(r);
                          } else if (r is Map) {
                            final rName = r['name']?.toString() ?? '';
                            if (rName.isNotEmpty) resources.add(rName);
                          }
                        }
                      }
                      
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(isEnabled ? 0.03 : 0.01),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white.withOpacity(0.05)),
                        ),
                        child: Column(
                          children: [
                            ListTile(
                              onTap: () {
                                setState(() {
                                  if (isExpanded) {
                                    _expandedAddons.remove('stremio_$url');
                                  } else {
                                    _expandedAddons.add('stremio_$url');
                                  }
                                });
                              },
                              leading: Opacity(
                                opacity: isEnabled ? 1.0 : 0.4,
                                child: const Text('🧩', style: TextStyle(fontSize: 18)),
                              ),
                              title: Text(name, style: TextStyle(color: isEnabled ? Colors.white : Colors.white54, fontWeight: FontWeight.bold, fontSize: 13)),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (ver.isNotEmpty) Text('v$ver', style: const TextStyle(color: Colors.white38, fontSize: 10)),
                                  Text(url, style: TextStyle(color: Colors.white.withOpacity(0.25), fontSize: 9), maxLines: 1, overflow: TextOverflow.ellipsis),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(isEnabled ? Icons.check_circle : Icons.cancel, color: isEnabled ? const Color(0xFF22C55E) : Colors.white30, size: 20),
                                    onPressed: () {
                                      setState(() {
                                        _stremioAddons[idx]['enabled'] = !isEnabled;
                                      });
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444), size: 20),
                                    onPressed: () {
                                      setState(() {
                                        _stremioAddons.removeAt(idx);
                                      });
                                    },
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                    color: Colors.white38,
                                    size: 20,
                                  ),
                                ],
                              ),
                            ),
                            if (isExpanded && resources.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('CAPABILITIES', style: TextStyle(color: Colors.white30, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1)),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: resources.map((r) => Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFEF4444).withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.25)),
                                        ),
                                        child: Text(r, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 10, fontWeight: FontWeight.bold)),
                                      )).toList(),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildNuveoAddonsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionTitle('Nuveo Addons', subtitle: 'JSON scrapers loaded for source crawling.'),
            Switch(
              value: _nuveoEnabled,
              onChanged: (val) => setState(() => _nuveoEnabled = val),
              activeThumbColor: const Color(0xFFEF4444),
              activeTrackColor: const Color(0xFFEF4444).withOpacity(0.4),
              inactiveThumbColor: Colors.white60,
              inactiveTrackColor: Colors.white10,
            ),
          ],
        ),
        if (_nuveoEnabled) ...[
          GlassCard(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _nuveoInputCtrl,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'https://raw.githubusercontent.com/.../manifest.json',
                          hintStyle: TextStyle(color: Colors.white.withOpacity(0.25)),
                          filled: true,
                          fillColor: const Color(0xFF0B0F19),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _importingNuveo ? null : _importNuveoManifest,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFEF4444),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _importingNuveo
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Import', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                    ),
                  ],
                ),
                if (_nuveoAddons.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _nuveoAddons.length,
                    itemBuilder: (context, idx) {
                      final addon = _nuveoAddons[idx];
                      final url = addon['url']?.toString() ?? '';
                      final name = addon['name']?.toString() ?? 'Nuveo Addon';
                      final ver = addon['version']?.toString() ?? '';
                      final isEnabled = addon['enabled'] != false;
                      final isExpanded = _expandedAddons.contains('nuveo_$url');
                      final scrapers = addon['scrapers'] is List ? List<dynamic>.from(addon['scrapers']) : [];
                      
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(isEnabled ? 0.03 : 0.01),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white.withOpacity(0.05)),
                        ),
                        child: Column(
                          children: [
                            ListTile(
                              onTap: () {
                                setState(() {
                                  if (isExpanded) {
                                    _expandedAddons.remove('nuveo_$url');
                                  } else {
                                    _expandedAddons.add('nuveo_$url');
                                  }
                                });
                              },
                              leading: Opacity(
                                opacity: isEnabled ? 1.0 : 0.4,
                                child: const Text('⚡', style: TextStyle(fontSize: 18)),
                              ),
                              title: Text(name, style: TextStyle(color: isEnabled ? Colors.white : Colors.white54, fontWeight: FontWeight.bold, fontSize: 13)),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (ver.isNotEmpty) Text('v$ver', style: const TextStyle(color: Colors.white38, fontSize: 10)),
                                  Text(url, style: TextStyle(color: Colors.white.withOpacity(0.25), fontSize: 9), maxLines: 1, overflow: TextOverflow.ellipsis),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(isEnabled ? Icons.check_circle : Icons.cancel, color: isEnabled ? const Color(0xFF22C55E) : Colors.white30, size: 20),
                                    onPressed: () {
                                      setState(() {
                                        _nuveoAddons[idx]['enabled'] = !isEnabled;
                                      });
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444), size: 20),
                                    onPressed: () {
                                      setState(() {
                                        _nuveoAddons.removeAt(idx);
                                      });
                                    },
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                    color: Colors.white38,
                                    size: 20,
                                  ),
                                ],
                              ),
                            ),
                            if (isExpanded && scrapers.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('SCRAPERS', style: TextStyle(color: Colors.white30, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1)),
                                    const SizedBox(height: 6),
                                    ...scrapers.asMap().entries.map((entry) {
                                      final sIdx = entry.key;
                                      final scraper = entry.value is Map ? Map<String, dynamic>.from(entry.value as Map) : <String, dynamic>{};
                                      final sName = scraper['name']?.toString() ?? 'Scraper';
                                      final sEnabled = scraper['enabled'] != false;
                                      
                                      final List<String> formats = [];
                                      if (scraper['formats'] is List) {
                                        for (final f in scraper['formats']) {
                                          if (f != null) formats.add(f.toString());
                                        }
                                      }
                                      
                                      return Container(
                                        margin: const EdgeInsets.only(bottom: 4),
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withOpacity(0.25),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(sName, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                                                  if (formats.isNotEmpty)
                                                    Text(formats.join(', '), style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 10)),
                                                ],
                                              ),
                                            ),
                                            Transform.scale(
                                              scale: 0.8,
                                              child: Switch(
                                                value: sEnabled,
                                                onChanged: (val) {
                                                  setState(() {
                                                    _nuveoAddons[idx]['scrapers'][sIdx]['enabled'] = val;
                                                  });
                                                },
                                                activeThumbColor: const Color(0xFFEF4444),
                                                activeTrackColor: const Color(0xFFEF4444).withOpacity(0.4),
                                                inactiveThumbColor: Colors.white60,
                                                inactiveTrackColor: Colors.white10,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBlockedGroupsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Addon Group Filter (Hide Categories)', subtitle: 'Enter addon groups or categories to hide, one per line.'),
        GlassCard(
          padding: const EdgeInsets.all(12),
          child: TextField(
            maxLines: 4,
            controller: _blockedGroupsCtrl,
            style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
            decoration: InputDecoration(
              hintText: 'Penguplay - MovieBlast\nAnother Addon',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.25)),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(4),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTelegramSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(
          'Telegram Integration (Telegram Server)',
          subtitle:
              'Users forward movie files to their Telegram Server. The app indexes those files and surfaces them as stream sources.',
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF12151F),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Enable Telegram source for users',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'You can keep this off while entering credentials; users only see sources when this is ON.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.45),
                            fontSize: 11,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _telegramEnabled,
                    onChanged: (val) => setState(() => _telegramEnabled = val),
                    activeThumbColor: const Color(0xFFEF4444),
                    activeTrackColor: const Color(0xFFEF4444)
                        .withValues(alpha: 0.4),
                    inactiveThumbColor: Colors.white60,
                    inactiveTrackColor: Colors.white10,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                height: 1,
                color: Colors.white.withValues(alpha: 0.07),
              ),
              const SizedBox(height: 16),
              const Row(
                children: [
                  Text('📨 ', style: TextStyle(fontSize: 18)),
                  Expanded(
                    child: Text(
                      'Get api_id / api_hash from my.telegram.org under your app. They are shared across all devices of every user.',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'API ID',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _tgApiIdCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontFamily: 'Consolas',
                ),
                decoration: InputDecoration(
                  hintText: 'e.g. 12345678',
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.25),
                  ),
                  filled: true,
                  fillColor: const Color(0xFF0B0F19),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'API HASH',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _tgApiHashCtrl,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontFamily: 'Consolas',
                ),
                decoration: InputDecoration(
                  hintText: 'e.g. a1b2c3d4e5f6...',
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.25),
                  ),
                  filled: true,
                  fillColor: const Color(0xFF0B0F19),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    color: Colors.white38,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Each end-user still signs in with their own phone + OTP inside the app. These credentials only identify the app on Telegram\'s side.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSaveButton() {
    return Container(
      width: double.infinity,
      height: 52,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFEF4444).withOpacity(0.25),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _saveSettings,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: const Text(
          'Save All Settings',
          style: TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildAddonUrlsAndTorrentsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Provider Addon URLs & Torrents', subtitle: 'Manage Torrentio, Stravo, NetMirror domains, and Seedr tokens.'),
        GlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildInputRow(
                icon: Icons.link,
                label: 'Torrentio Addon URL',
                controller: _torrentioUrlCtrl,
                hint: 'https://torrentio.strem.fun',
              ),
              const SizedBox(height: 16),
              _buildInputRow(
                icon: Icons.link,
                label: 'Stravo Addon URL',
                controller: _stravoUrlCtrl,
                hint: 'https://stravo-clfk.onrender.com/default',
              ),
              const SizedBox(height: 16),
              _buildInputRow(
                icon: Icons.dns,
                label: 'NetMirror Domains (comma-separated)',
                controller: _netmirrorDomainsCtrl,
                hint: 'domain1.com,domain2.com',
              ),
              const SizedBox(height: 16),
              _buildInputRow(
                icon: Icons.cloud_done,
                label: 'Seedr.cc Auth Token (shared)',
                controller: _seedrTokenCtrl,
                hint: 'Paste Seedr.cc auth token',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInputRow({
    required IconData icon,
    required String label,
    required TextEditingController controller,
    required String hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0B0F19),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Row(
            children: [
              const SizedBox(width: 12),
              Icon(icon, color: Colors.white30, size: 18),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: controller,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
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
