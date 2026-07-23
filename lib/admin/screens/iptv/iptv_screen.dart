import 'dart:convert';
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../providers/iptv_provider.dart';
import '../../providers/settings_provider.dart';
import '../../models/iptv_channel.dart';
import '../../utils/drawer_helper.dart';
import '../../utils/admin_api_client.dart';
import '../../widgets/common/glass_card.dart';
import '../../../data/stalker_resolver.dart';
import '../../utils/master_channel_repository.dart';
import '../../models/master_channel.dart';
import '../../../widgets/epg_picker_dialog.dart';
import '../../../widgets/master_channel_picker_dialog.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

class IptvScreen extends ConsumerStatefulWidget {
  const IptvScreen({super.key});

  @override
  ConsumerState<IptvScreen> createState() => _IptvScreenState();
}

class _IptvScreenState extends ConsumerState<IptvScreen> {
  final _searchController = TextEditingController();
  final _adminApi = AdminApiClient();
  String _searchQuery = '';
  String? _selectedCategory;
  bool _isGlobalSaving = false;

  final Map<String, bool> _isReorderingChannels = {};
  final Map<String, List<IptvChannel>> _tempCategoryChannels = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(iptvProvider.notifier).fetchChannels();
      ref.read(settingsProvider.notifier).fetchSettings();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showLoadingOverlay() {
    setState(() => _isGlobalSaving = true);
  }

  void _hideLoadingOverlay() {
    setState(() => _isGlobalSaving = false);
  }

  Future<void> _toggleChannel(IptvChannel channel) async {
    final newStatus = channel.enabled ? 0 : 1;
    try {
      await _adminApi.toggleChannel(channel.id, newStatus);
      if (mounted) {
        ref.read(iptvProvider.notifier).fetchChannels();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Toggle failed: $e')),
        );
      }
    }
  }

  String _getCategoryDisplayName(String category, int portalId, Map<String, String> settings) {
    if (settings.containsKey('live_tv_category_renames')) {
      try {
        final Map<String, dynamic> renames = jsonDecode(settings['live_tv_category_renames']!);
        final key = '$category|$portalId';
        if (renames.containsKey(key) && renames[key].toString().trim().isNotEmpty) {
          return renames[key].toString();
        }
      } catch (_) {}
    }
    return category;
  }

  bool _isCategoryHidden(String category, int portalId, Map<String, String> settings) {
    if (settings.containsKey('live_tv_hidden_categories')) {
      try {
        final List<dynamic> hidden = jsonDecode(settings['live_tv_hidden_categories']!);
        final key = '$category|$portalId';
        return hidden.contains(key);
      } catch (_) {}
    }
    return false;
  }

  List<String> _getOrderedCategories(List<String> categories, Map<String, String> settings) {
    List<dynamic> catOrder = [];
    if (settings.containsKey('live_tv_category_order')) {
      try {
        catOrder = jsonDecode(settings['live_tv_category_order']!);
      } catch (_) {}
    }
    
    final sorted = List<String>.from(categories);
    sorted.sort((a, b) {
      final idxA = catOrder.indexOf(a);
      final idxB = catOrder.indexOf(b);
      final posA = idxA == -1 ? 999999 : idxA;
      final posB = idxB == -1 ? 999999 : idxB;
      if (posA != posB) return posA.compareTo(posB);
      return a.compareTo(b);
    });
    return sorted;
  }

  bool _isSelectionMode = false;
  final Set<int> _selectedChannelIds = {};

  void _toggleChannelSelection(int channelId) {
    setState(() {
      if (_selectedChannelIds.contains(channelId)) {
        _selectedChannelIds.remove(channelId);
        if (_selectedChannelIds.isEmpty) _isSelectionMode = false;
      } else {
        _selectedChannelIds.add(channelId);
        _isSelectionMode = true;
      }
    });
  }

  void _selectAllChannels(List<IptvChannel> channels) {
    setState(() {
      _isSelectionMode = true;
      for (final ch in channels) {
        _selectedChannelIds.add(ch.id);
      }
    });
  }

  void _deselectAllChannels() {
    setState(() {
      _selectedChannelIds.clear();
      _isSelectionMode = false;
    });
  }

  void _confirmBulkDeleteChannels() {
    if (_selectedChannelIds.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF131722),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.white.withOpacity(0.1))),
        title: Row(
          children: [
            const Icon(Icons.delete_sweep_rounded, color: Color(0xFFEF4444), size: 22),
            const SizedBox(width: 8),
            Text('Bulk Delete Channels', style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text('Are you sure you want to delete ${_selectedChannelIds.length} selected stream channels?', style: const TextStyle(color: Colors.white70, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.5)))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              final idsToDelete = List<int>.from(_selectedChannelIds);
              _deselectAllChannels();
              _showLoadingOverlay();
              for (final id in idsToDelete) {
                await _adminApi.deleteChannel(id);
              }
              _hideLoadingOverlay();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${idsToDelete.length} channels deleted successfully'), backgroundColor: const Color(0xFF22C55E)),
                );
                ref.read(iptvProvider.notifier).fetchChannels();
              }
            },
            child: Text('Delete (${_selectedChannelIds.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final iptvState = ref.watch(iptvProvider);
    final settingsMap = ref.watch(settingsProvider).settings;
    final filteredChannels = _getFilteredChannels(iptvState);

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(_isSelectionMode ? Icons.close : Icons.menu),
          onPressed: () {
            if (_isSelectionMode) {
              _deselectAllChannels();
            } else {
              DrawerProvider.openDrawer();
            }
          },
        ),
        title: Text(_isSelectionMode ? '${_selectedChannelIds.length} Selected' : 'IPTV Channels'),
        backgroundColor: const Color(0xFF0D1117).withOpacity(0.7),
        elevation: 0,
        actions: [
          if (_isSelectionMode) ...[
            TextButton(
              onPressed: () {
                if (_selectedChannelIds.length >= filteredChannels.length) {
                  _deselectAllChannels();
                } else {
                  _selectAllChannels(filteredChannels);
                }
              },
              child: Text(
                _selectedChannelIds.length >= filteredChannels.length ? 'Deselect' : 'Select All',
                style: const TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_forever_rounded, color: Color(0xFFEF4444)),
              onPressed: _confirmBulkDeleteChannels,
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.select_all_rounded, color: Colors.white70),
              onPressed: () => _selectAllChannels(filteredChannels),
            ),
            IconButton(
              tooltip: 'Master Channel Registry',
              icon: const Icon(Icons.playlist_add_check_circle_rounded, color: Color(0xFF8B5CF6)),
              onPressed: () => context.push('/master-channels'),
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                ref.read(iptvProvider.notifier).fetchChannels();
                ref.read(settingsProvider.notifier).fetchSettings();
              },
            ),
          ],
        ],
      ),
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0D1117), Color(0xFF161B22), Color(0xFF0D1117)],
              ),
            ),
            child: _buildBody(iptvState, settingsMap),
          ),
          if (_isGlobalSaving)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(
                child: CircularProgressIndicator(color: Color(0xFFEF4444)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody(IptvState iptvState, Map<String, String> settings) {
    if (iptvState.isLoading && iptvState.channels.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Color(0xFFEF4444)),
            const SizedBox(height: 16),
            Text(
              'Loading channels...',
              style: TextStyle(color: Colors.white.withOpacity(0.5)),
            ),
          ],
        ),
      );
    }

    if (iptvState.error != null && iptvState.channels.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.withOpacity(0.7)),
            const SizedBox(height: 16),
            Text(
              iptvState.error!,
              style: TextStyle(color: Colors.white.withOpacity(0.7)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            _buildGlassButton(
              onPressed: () {
                ref.read(iptvProvider.notifier).fetchChannels();
                ref.read(settingsProvider.notifier).fetchSettings();
              },
              child: const Text('Retry', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }

    final filteredChannels = _getFilteredChannels(iptvState);
    final grouped = _groupByCategory(filteredChannels);
    final categories = _getOrderedCategories(grouped.keys.toList(), settings);

    return SafeArea(
      child: Column(
        children: [
          _buildSearchBar(),
          const SizedBox(height: 8),
          _buildCategoryDropdown(categories, settings),
          const SizedBox(height: 4),
          _buildStatsBar(iptvState, categories, settings),
          const SizedBox(height: 4),
          Expanded(
            child: filteredChannels.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.tv, size: 64, color: Colors.white.withOpacity(0.2)),
                        const SizedBox(height: 16),
                        Text(
                          'No channels found',
                          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 16),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    itemCount: categories.length,
                    itemBuilder: (context, index) {
                      final category = categories[index];
                      final channels = grouped[category] ?? [];
                      return _buildCategorySection(category, channels, settings);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  List<IptvChannel> _getFilteredChannels(IptvState state) {
    var channels = state.channels;
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      channels = channels.where((c) =>
        c.displayName.toLowerCase().contains(query) ||
        c.categoryName.toLowerCase().contains(query)
      ).toList();
    }
    if (_selectedCategory != null) {
      channels = channels.where((c) => c.categoryName == _selectedCategory).toList();
    }
    return channels;
  }

  Map<String, List<IptvChannel>> _groupByCategory(List<IptvChannel> channels) {
    final map = <String, List<IptvChannel>>{};
    for (final channel in channels) {
      map.putIfAbsent(channel.categoryName, () => []);
      map[channel.categoryName]!.add(channel);
    }
    for (final list in map.values) {
      list.sort((a, b) => a.position.compareTo(b.position));
    }
    return map;
  }

  Widget _buildGlassContainer({required Widget child, double opacity = 0.4}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF161B26),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: child,
    );
  }

  Widget _buildGlassButton({required VoidCallback onPressed, required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFEF4444).withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.3)),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: _buildGlassContainer(
        opacity: 0.3,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: TextField(
            controller: _searchController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Search channels...',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.35)),
              prefixIcon: Icon(Icons.search, color: Colors.white.withOpacity(0.4), size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.close, color: Colors.white.withOpacity(0.4), size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            ),
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryDropdown(List<String> categories, Map<String, String> settings) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: _buildGlassContainer(
        opacity: 0.3,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedCategory,
              isExpanded: true,
              hint: Row(
                children: [
                  Icon(Icons.category, size: 16, color: Colors.white.withOpacity(0.4)),
                  const SizedBox(width: 8),
                  Text(
                    'All Categories',
                    style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
                  ),
                ],
              ),
              dropdownColor: const Color(0xFF1A1F2E),
              icon: Icon(Icons.keyboard_arrow_down, color: Colors.white.withOpacity(0.5)),
              items: [
                DropdownMenuItem<String>(
                  value: null,
                  child: Row(
                    children: [
                      Icon(Icons.all_inclusive, size: 16, color: Colors.white.withOpacity(0.5)),
                      const SizedBox(width: 8),
                      Text('All Categories', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13)),
                    ],
                  ),
                ),
                ...categories.map((cat) {
                  final portalId = cat.contains('(') ? int.tryParse(cat.split('(').last.replaceAll(')', '')) ?? 1 : 1;
                  final dispName = _getCategoryDisplayName(cat, portalId, settings);
                  return DropdownMenuItem<String>(
                    value: cat,
                    child: Text(
                      dispName,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }),
              ],
              onChanged: (val) => setState(() => _selectedCategory = val),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatsBar(IptvState state, List<String> categories, Map<String, String> settings) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(Icons.live_tv, size: 14, color: Colors.white.withOpacity(0.35)),
              const SizedBox(width: 6),
              Text(
                '${state.enabledChannels.length}/${state.channels.length} active',
                style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
              ),
              const SizedBox(width: 6),
              Container(width: 1, height: 12, color: Colors.white.withOpacity(0.1)),
              const SizedBox(width: 6),
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle),
              ),
              const SizedBox(width: 4),
              Text(
                '${categories.length} categories',
                style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
              ),
            ],
          ),
          InkWell(
            onTap: () => _openCategoryReorderDialog(categories, settings),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.sort_rounded, color: Color(0xFFEF4444), size: 14),
                  const SizedBox(width: 4),
                  const Text('Sort Folders', style: TextStyle(color: Color(0xFFEF4444), fontSize: 11, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategorySection(String category, List<IptvChannel> channels, Map<String, String> settings) {
    final portalId = category.contains('(') ? int.tryParse(category.split('(').last.replaceAll(')', '')) ?? 1 : 1;
    final displayName = _getCategoryDisplayName(category, portalId, settings);
    final isHidden = _isCategoryHidden(category, portalId, settings);
    final isReordering = _isReorderingChannels[category] ?? false;

    if (isReordering && !_tempCategoryChannels.containsKey(category)) {
      _tempCategoryChannels[category] = List<IptvChannel>.from(channels);
    }
    final renderChannels = isReordering ? (_tempCategoryChannels[category] ?? []) : channels;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: isHidden 
              ? const Color(0xFFEF4444).withOpacity(0.08) 
              : const Color(0xFF1A1F2E).withOpacity(0.7),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isHidden 
                ? const Color(0xFFEF4444).withOpacity(0.15) 
                : Colors.white.withOpacity(0.05)
          ),
        ),
        child: Theme(
              data: Theme.of(context).copyWith(
                dividerColor: Colors.transparent,
                unselectedWidgetColor: Colors.white.withOpacity(0.3),
              ),
              child: ExpansionTile(
                initiallyExpanded: false,
                tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                collapsedBackgroundColor: Colors.transparent,
                backgroundColor: Colors.transparent,
                leading: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isHidden 
                          ? [const Color(0xFF64748B), const Color(0xFF475569)]
                          : [const Color(0xFF8B5CF6), const Color(0xFF6366F1)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: (isHidden ? const Color(0xFF64748B) : const Color(0xFF8B5CF6)).withOpacity(0.3),
                        blurRadius: 8,
                        spreadRadius: 0,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(
                      isHidden ? Icons.visibility_off_outlined : Icons.folder, 
                      size: 16, 
                      color: Colors.white
                    ),
                  ),
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            style: TextStyle(
                              color: isHidden ? Colors.white60 : Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              decoration: isHidden ? TextDecoration.lineThrough : TextDecoration.none,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (isHidden)
                            const Text(
                              'HIDDEN FROM USERS',
                              style: TextStyle(color: Color(0xFFEF4444), fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                            )
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: (isHidden ? const Color(0xFF64748B) : const Color(0xFF8B5CF6)).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: (isHidden ? const Color(0xFF64748B) : const Color(0xFF8B5CF6)).withOpacity(0.2)),
                      ),
                      child: Text(
                        '${channels.length}',
                        style: TextStyle(
                          color: isHidden ? const Color(0xFF94A3B8) : const Color(0xFF8B5CF6),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.settings_outlined, size: 18, color: Colors.white38),
                      onPressed: () => _openCategorySettingsSheet(category, displayName, isHidden, portalId),
                    ),
                  ],
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isReordering ? '⚠️ Drag handles to set priority ordering' : 'Category channels listing',
                          style: TextStyle(color: isReordering ? const Color(0xFFF59E0B) : Colors.white30, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                        if (!isReordering)
                          InkWell(
                            onTap: () {
                              setState(() {
                                _isReorderingChannels[category] = true;
                              });
                            },
                            borderRadius: BorderRadius.circular(6),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              child: Row(
                                children: [
                                  Icon(Icons.swap_vert_rounded, color: Color(0xFFEF4444), size: 12),
                                  SizedBox(width: 4),
                                  Text('Reorder list', style: TextStyle(color: Color(0xFFEF4444), fontSize: 10, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          )
                        else
                          Row(
                            children: [
                              TextButton(
                                onPressed: () {
                                  setState(() {
                                    _isReorderingChannels[category] = false;
                                    _tempCategoryChannels.remove(category);
                                  });
                                },
                                child: const Text('Cancel', style: TextStyle(color: Colors.white38, fontSize: 11)),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF22C55E),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  minimumSize: Size.zero,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                ),
                                onPressed: () async {
                                  final temp = _tempCategoryChannels[category] ?? [];
                                  final Map<int, int> positions = {};
                                  for (int i = 0; i < temp.length; i++) {
                                    positions[temp[i].id] = i + 1;
                                  }
                                  setState(() {
                                    _isReorderingChannels[category] = false;
                                    _tempCategoryChannels.remove(category);
                                  });
                                  _showLoadingOverlay();
                                  final res = await _adminApi.saveChannelPositions(positions);
                                  _hideLoadingOverlay();
                                  if (mounted) {
                                    if (res['success'] == true) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Positions updated successfully'), backgroundColor: Color(0xFF22C55E)),
                                      );
                                      ref.read(iptvProvider.notifier).fetchChannels();
                                    } else {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Save failed: ${res['error']}'), backgroundColor: const Color(0xFFEF4444)),
                                      );
                                    }
                                  }
                                },
                                child: const Text('Save Order', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  if (isReordering)
                    ReorderableListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: renderChannels.length,
                      onReorder: (oldIndex, newIndex) {
                        setState(() {
                          if (newIndex > oldIndex) newIndex--;
                          final list = _tempCategoryChannels[category]!;
                          final item = list.removeAt(oldIndex);
                          list.insert(newIndex, item);
                        });
                      },
                      itemBuilder: (context, idx) {
                        final channel = renderChannels[idx];
                        return _buildChannelItem(channel, key: ValueKey(channel.id), isReorderMode: true, reorderIndex: idx);
                      },
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: renderChannels.length,
                      itemBuilder: (context, idx) {
                        final channel = renderChannels[idx];
                        return _buildChannelItem(channel, key: ValueKey(channel.id));
                      },
                    ),
                ],
              ),
            ),
          ),
    );
  }

  Widget _buildChannelItem(IptvChannel channel, {required Key key, bool isReorderMode = false, int reorderIndex = 0}) {
    final isSelected = _selectedChannelIds.contains(channel.id);

    return Padding(
      key: key,
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onLongPress: () => _toggleChannelSelection(channel.id),
        onTap: _isSelectionMode ? () => _toggleChannelSelection(channel.id) : null,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFFEF4444).withOpacity(0.2)
                : (channel.enabled
                    ? const Color(0xFF1A1F2E).withOpacity(0.85)
                    : Colors.red.withOpacity(0.12)),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFFEF4444)
                  : (channel.enabled
                      ? Colors.white.withOpacity(0.06)
                      : Colors.red.withOpacity(0.15)),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                if (_isSelectionMode)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(
                      isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                      color: isSelected ? const Color(0xFFEF4444) : Colors.white38,
                      size: 20,
                    ),
                  ),
                if (isReorderMode) ...[
                    ReorderableDragStartListener(
                      index: reorderIndex,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(Icons.drag_handle_rounded, color: Colors.white30, size: 18),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ] else ...[
                    IconButton(
                      icon: const Icon(Icons.play_circle_fill_rounded, color: Color(0xFFEF4444), size: 24),
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (_) => ChannelPlayerDialog(
                            channelName: channel.displayName,
                            streamUrl: channel.cmd,
                            portalId: channel.portalId,
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 2),
                  ],
                  const SizedBox(width: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: channel.logoUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: channel.logoUrl,
                            width: 38,
                            height: 38,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(
                              width: 38,
                              height: 38,
                              color: Colors.white.withOpacity(0.05),
                              child: const Center(
                                child: SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                            ),
                            errorWidget: (context, url, error) => Container(
                              width: 38,
                              height: 38,
                              color: Colors.white.withOpacity(0.05),
                              child: Icon(Icons.tv, size: 18, color: Colors.white.withOpacity(0.2)),
                            ),
                          )
                        : Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(Icons.tv, size: 18, color: Colors.white.withOpacity(0.2)),
                          ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: InkWell(
                      onTap: isReorderMode ? null : () => _openChannelEditDialog(channel),
                      borderRadius: BorderRadius.circular(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            height: 20,
                            child: AutoScrollEpgText(
                              text: channel.displayName,
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF8B5CF6).withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: const Color(0xFF8B5CF6).withOpacity(0.15)),
                                ),
                                child: Text(
                                  channel.categoryName.contains('(') ? channel.categoryName.split('(').first.trim() : channel.categoryName,
                                  style: const TextStyle(
                                    color: Color(0xFF8B5CF6),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                channel.portalName ?? 'Portal ${channel.portalId}',
                                style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 10),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (!isReorderMode) ...[
                    Transform.scale(
                      scale: 0.8,
                      child: Switch(
                        value: channel.enabled,
                        onChanged: (_) => _toggleChannel(channel),
                        activeColor: const Color(0xFF10B981),
                        activeTrackColor: const Color(0xFF10B981).withOpacity(0.3),
                        inactiveThumbColor: Colors.red.withOpacity(0.6),
                        inactiveTrackColor: Colors.red.withOpacity(0.15),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 20),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => _confirmDeleteChannel(channel),
                    ),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
  }

  void _openCategorySettingsSheet(String categoryName, String currentDispName, bool isCurrentlyHidden, int portalId) {
    final renameCtrl = TextEditingController(text: currentDispName);
    bool isHidden = isCurrentlyHidden;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF161B22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Category settings',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white60),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('RENAME CATEGORY', style: TextStyle(color: Colors.white30, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withOpacity(0.06)),
                    ),
                    child: TextField(
                      controller: renameCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: const InputDecoration(
                        hintText: 'Enter new category name',
                        hintStyle: TextStyle(color: Colors.white30),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Hide category from users', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                          SizedBox(height: 2),
                          Text('Hiding will disable all its channels', style: TextStyle(color: Colors.white38, fontSize: 10)),
                        ],
                      ),
                      Switch(
                        value: isHidden,
                        onChanged: (val) {
                          setSheetState(() {
                            isHidden = val;
                          });
                        },
                        activeColor: const Color(0xFFEF4444),
                        activeTrackColor: const Color(0xFFEF4444).withOpacity(0.3),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: Colors.white.withOpacity(0.08)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: () async {
                            Navigator.pop(ctx);
                            _showLoadingOverlay();
                            final res = await _adminApi.toggleCategoryVisibility(categoryName, portalId, true);
                            _hideLoadingOverlay();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(res['success'] == true ? 'Disabled all channels under category' : 'Failed bulk toggle'),
                                  backgroundColor: res['success'] == true ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
                                ),
                              );
                              ref.read(iptvProvider.notifier).fetchChannels();
                            }
                          },
                          child: const Text('DISABLE ALL', style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFEF4444),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: () async {
                            Navigator.pop(ctx);
                            _showLoadingOverlay();
                            
                            final hideRes = await _adminApi.toggleCategoryVisibility(categoryName, portalId, !isHidden);
                            final renameRes = await _adminApi.renameCategory(categoryName, portalId, renameCtrl.text.trim());
                            
                            _hideLoadingOverlay();
                            
                            if (mounted) {
                              if (hideRes['success'] == true && renameRes['success'] == true) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Category settings saved successfully'), backgroundColor: Color(0xFF22C55E)),
                                );
                                ref.read(iptvProvider.notifier).fetchChannels();
                                ref.read(settingsProvider.notifier).fetchSettings();
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Failed to update category settings'), backgroundColor: Color(0xFFEF4444)),
                                );
                              }
                            }
                          },
                          child: const Text('SAVE SETTINGS', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFEF4444),
                      side: const BorderSide(color: Color(0xFFEF4444)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _confirmDeleteCategory(categoryName, portalId, currentDispName);
                    },
                    icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                    label: const Text('DELETE FOLDER & ALL CHANNELS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _confirmDeleteChannel(IptvChannel channel) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF131722),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.white.withOpacity(0.1))),
        title: Row(
          children: [
            const Icon(Icons.delete_forever_rounded, color: Color(0xFFEF4444), size: 22),
            const SizedBox(width: 8),
            Text('Delete Stream Channel', style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text('Are you sure you want to delete "${channel.displayName}" from IPTV channels?', style: const TextStyle(color: Colors.white70, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.5)))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              _showLoadingOverlay();
              final res = await _adminApi.deleteChannel(channel.id);
              _hideLoadingOverlay();
              if (mounted) {
                if (res['success'] == true) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Channel deleted successfully'), backgroundColor: Color(0xFF22C55E)),
                  );
                  ref.read(iptvProvider.notifier).fetchChannels();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Delete failed: ${res['error']}'), backgroundColor: const Color(0xFFEF4444)),
                  );
                }
              }
            },
            child: const Text('Delete Channel', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteCategory(String categoryName, int portalId, String dispName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF131722),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.white.withOpacity(0.1))),
        title: Row(
          children: [
            const Icon(Icons.folder_delete_rounded, color: Color(0xFFEF4444), size: 22),
            const SizedBox(width: 8),
            Text('Delete Category Folder', style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text('Are you sure you want to delete category "$dispName" and ALL channels inside it from your IPTV list?', style: const TextStyle(color: Colors.white70, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.5)))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              _showLoadingOverlay();
              final res = await _adminApi.deleteCategory(categoryName, portalId);
              _hideLoadingOverlay();
              if (mounted) {
                if (res['success'] == true) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Category folder & channels deleted'), backgroundColor: Color(0xFF22C55E)),
                  );
                  ref.read(iptvProvider.notifier).fetchChannels();
                  ref.read(settingsProvider.notifier).fetchSettings();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Delete failed: ${res['error']}'), backgroundColor: const Color(0xFFEF4444)),
                  );
                }
              }
            },
            child: const Text('Delete Folder', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _openCategoryReorderDialog(List<String> categories, Map<String, String> settings) {
    List<dynamic> catOrder = [];
    if (settings.containsKey('live_tv_category_order')) {
      try {
        catOrder = jsonDecode(settings['live_tv_category_order']!);
      } catch (_) {}
    }
    
    final orderedCats = List<String>.from(categories);
    orderedCats.sort((a, b) {
      final idxA = catOrder.indexOf(a);
      final idxB = catOrder.indexOf(b);
      final posA = idxA == -1 ? 999999 : idxA;
      final posB = idxB == -1 ? 999999 : idxB;
      if (posA != posB) return posA.compareTo(posB);
      return a.compareTo(b);
    });

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Dialog.fullscreen(
              backgroundColor: const Color(0xFF0D1117),
              child: Scaffold(
                backgroundColor: Colors.transparent,
                appBar: AppBar(
                  backgroundColor: const Color(0xFF161B22),
                  title: const Text('Folder priority order', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  leading: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        _showLoadingOverlay();
                        final res = await _adminApi.saveCategoryOrder(orderedCats);
                        _hideLoadingOverlay();
                        if (mounted) {
                          if (res['success'] == true) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Folder priorities saved successfully'), backgroundColor: Color(0xFF22C55E)),
                            );
                            ref.read(settingsProvider.notifier).fetchSettings();
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Failed: ${res['error'] ?? 'Unknown Error'}'), backgroundColor: const Color(0xFFEF4444)),
                            );
                          }
                        }
                      },
                      child: const Text('SAVE', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                body: ReorderableListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  onReorder: (oldIdx, newIdx) {
                    setModalState(() {
                      if (newIdx > oldIdx) newIdx--;
                      final item = orderedCats.removeAt(oldIdx);
                      orderedCats.insert(newIdx, item);
                    });
                  },
                  children: orderedCats.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final catName = entry.value;
                    final portalId = catName.contains('(') ? int.tryParse(catName.split('(').last.replaceAll(')', '')) ?? 1 : 1;
                    final dispName = _getCategoryDisplayName(catName, portalId, settings);
                    final isHidden = _isCategoryHidden(catName, portalId, settings);

                    return Container(
                      key: ValueKey(catName),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: isHidden ? const Color(0xFFEF4444).withOpacity(0.02) : Colors.white.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: isHidden ? const Color(0xFFEF4444).withOpacity(0.12) : Colors.white.withOpacity(0.05)),
                      ),
                      child: ListTile(
                        dense: true,
                        leading: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('${idx + 1}', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 11)),
                        ),
                        title: Text(dispName, style: TextStyle(color: isHidden ? Colors.white54 : Colors.white, fontWeight: FontWeight.bold, fontSize: 13, decoration: isHidden ? TextDecoration.lineThrough : TextDecoration.none)),
                        trailing: const Icon(Icons.drag_handle, color: Colors.white30),
                      ),
                    );
                  }).toList(),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _openChannelEditDialog(IptvChannel channel) {
    final nameCtrl = TextEditingController(text: channel.displayName);
    final logoCtrl = TextEditingController(text: channel.logoUrl);
    final epgCtrl = TextEditingController(text: channel.stalkerId ?? channel.name);
    String selectedLanguage = 'Malayalam';

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final logoUrlText = logoCtrl.text.trim();
            return Dialog(
              backgroundColor: const Color(0xFF131722),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(color: Colors.white.withOpacity(0.1)),
              ),
              child: Container(
                width: MediaQuery.of(context).size.width * 0.88,
                padding: const EdgeInsets.all(20),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFEF4444), Color(0xFFF59E0B)],
                              ),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(color: const Color(0xFFEF4444).withOpacity(0.3), blurRadius: 10, spreadRadius: 1),
                              ],
                            ),
                            child: const Icon(Icons.tune_rounded, color: Colors.white, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Edit Stream Channel',
                                  style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
                                ),
                                Text(
                                  'Channel #${channel.position} • Portal Stream',
                                  style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white38, size: 20),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      InkWell(
                        onTap: () async {
                          final pickedMaster = await MasterChannelPickerDialog.show(ctx);
                          if (pickedMaster != null) {
                            setDialogState(() {
                              nameCtrl.text = pickedMaster.displayName;
                              if (pickedMaster.logoUrl.isNotEmpty) logoCtrl.text = pickedMaster.logoUrl;
                              if (pickedMaster.epgId.isNotEmpty) epgCtrl.text = pickedMaster.epgId;
                              if (pickedMaster.language != null) selectedLanguage = pickedMaster.language!;
                            });
                          }
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [const Color(0xFF8B5CF6).withOpacity(0.2), const Color(0xFF6366F1).withOpacity(0.1)],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFF8B5CF6).withOpacity(0.4)),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.playlist_add_check_rounded, color: Color(0xFFA855F7), size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Link to Master Channel Catalog',
                                style: TextStyle(color: Color(0xFFA855F7), fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text('CUSTOM CHANNEL NAME', style: TextStyle(color: Color(0xFFEF4444), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white.withOpacity(0.08)),
                        ),
                        child: TextField(
                          controller: nameCtrl,
                          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                          decoration: const InputDecoration(
                            hintText: 'Enter channel name override',
                            hintStyle: TextStyle(color: Colors.white30),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text('LOGO URL', style: TextStyle(color: Color(0xFFEF4444), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.04),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Colors.white.withOpacity(0.08)),
                              ),
                              child: TextField(
                                controller: logoCtrl,
                                maxLines: 2,
                                style: const TextStyle(color: Colors.white, fontSize: 12),
                                decoration: const InputDecoration(
                                  hintText: 'http://...',
                                  hintStyle: TextStyle(color: Colors.white30),
                                  border: InputBorder.none,
                                ),
                                onChanged: (_) => setDialogState(() {}),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white.withOpacity(0.08)),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: logoUrlText.startsWith('http')
                                  ? CachedNetworkImage(
                                      imageUrl: logoUrlText,
                                      fit: BoxFit.cover,
                                      errorWidget: (_, __, ___) => const Icon(Icons.tv, size: 20, color: Colors.white30),
                                    )
                                  : const Icon(Icons.tv, size: 20, color: Colors.white30),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text('LINKED EPG CHANNEL ID', style: TextStyle(color: Color(0xFFEF4444), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white.withOpacity(0.08)),
                        ),
                        child: TextField(
                          controller: epgCtrl,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: const InputDecoration(
                            hintText: 'EPG channel ID...',
                            hintStyle: TextStyle(color: Colors.white30),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text('LANGUAGE CATEGORY', style: TextStyle(color: Color(0xFFEF4444), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white.withOpacity(0.08)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: selectedLanguage,
                            dropdownColor: const Color(0xFF131722),
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                            isExpanded: true,
                            items: ['Malayalam', 'Tamil', 'Hindi', 'English', 'Telugu', 'Kannada', 'Sports', 'News', 'Kids']
                                .map((lang) => DropdownMenuItem(value: lang, child: Text(lang)))
                                .toList(),
                            onChanged: (val) {
                              if (val != null) setDialogState(() => selectedLanguage = val);
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.5))),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFEF4444),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                              elevation: 4,
                            ),
                            onPressed: () async {
                              Navigator.pop(ctx);
                              _showLoadingOverlay();
                              
                              final res = await _adminApi.updateChannelDetails(
                                channel.id,
                                nameCtrl.text.trim(),
                                logoCtrl.text.trim(),
                              );
                              
                              // Sync to Master Registry MySQL database
                              final master = MasterChannel(
                                id: 'master_${channel.id}',
                                displayName: nameCtrl.text.trim().isNotEmpty ? nameCtrl.text.trim() : channel.name,
                                logoUrl: logoCtrl.text.trim().isNotEmpty ? logoCtrl.text.trim() : channel.logoUrl,
                                epgId: epgCtrl.text.trim(),
                                categoryName: channel.categoryName,
                                language: selectedLanguage,
                                aliases: [channel.name.toLowerCase().trim()],
                              );
                              await MasterChannelRepository.save(master);

                              _hideLoadingOverlay();
                              
                              if (mounted) {
                                if (res['success'] == true) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Channel details & Master EPG synced successfully!'), backgroundColor: Color(0xFF22C55E)),
                                  );
                                  ref.read(iptvProvider.notifier).fetchChannels();
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Failed to edit channel'), backgroundColor: Color(0xFFEF4444)),
                                  );
                                }
                              }
                            },
                            child: const Text('Update Channel Details', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class ChannelPlayerDialog extends StatefulWidget {
  final String channelName;
  final String streamUrl;
  final int portalId;

  const ChannelPlayerDialog({
    super.key,
    required this.channelName,
    required this.streamUrl,
    required this.portalId,
  });

  @override
  State<ChannelPlayerDialog> createState() => _ChannelPlayerDialogState();
}

class _ChannelPlayerDialogState extends State<ChannelPlayerDialog> {
  Player? _player;
  VideoController? _videoController;
  Timer? _keepAliveTimer;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _videoController = VideoController(_player!);
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    var cleanUrl = widget.streamUrl.trim();
    while (true) {
      if (cleanUrl.startsWith('ffmpeg ')) {
        cleanUrl = cleanUrl.substring(7);
      } else if (cleanUrl.startsWith('auto ')) {
        cleanUrl = cleanUrl.substring(5);
      } else if (cleanUrl.startsWith('ffrt ')) {
        cleanUrl = cleanUrl.substring(5);
      } else if (cleanUrl.startsWith('hls ')) {
        cleanUrl = cleanUrl.substring(4);
      } else {
        break;
      }
    }
    cleanUrl = cleanUrl.trim();
        
    try {
      String playUrl = cleanUrl;
      Map<String, String> headers = {};
      
      if (widget.portalId > 0) {
        try {
          final resolved = await StalkerResolver.resolveStream(cleanUrl, widget.portalId);
          playUrl = resolved.url;
          headers = resolved.headers;
        } catch (e) {
          debugPrint('ChannelPlayerDialog failed to resolve stalker stream: $e');
        }
      }

      final dynamic platform = _player!.platform;
      try {
        await platform.setProperty('hwdec', 'auto-safe');
        await platform.setProperty('framedrop', 'vo');
        await platform.setProperty('autosync', '0');
        await platform.setProperty('correct-pts', 'yes');
        await platform.setProperty('audio-pitch-correction', 'yes');
        await platform.setProperty('cache', 'yes');
        await platform.setProperty('cache-on-disk', 'no');
        await platform.setProperty('demuxer-max-bytes', '33554432');
        await platform.setProperty('demuxer-readahead-secs', '15');
        await platform.setProperty('cache-secs', '15');
        await platform.setProperty('network-timeout', '15');
        await platform.setProperty('hr-seek', 'no');
      } catch (_) {}

      await _player!.open(
        Media(playUrl, httpHeaders: headers),
        play: true,
      );

      if (widget.portalId > 0) {
        _keepAliveTimer?.cancel();
        _keepAliveTimer = Timer.periodic(const Duration(seconds: 8), (_) {
          StalkerResolver.keepAlive(widget.portalId);
        });
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    _keepAliveTimer?.cancel();
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF0D1117),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: Colors.white.withOpacity(0.08)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: SizedBox(
          width: MediaQuery.of(context).size.width * 0.9,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        widget.channelName,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white60, size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Container(
                  color: Colors.black,
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator(color: Color(0xFFEF4444)))
                      : _errorMessage != null
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 36),
                                    const SizedBox(height: 8),
                                    Text(
                                      _errorMessage!,
                                      style: const TextStyle(color: Colors.white60, fontSize: 11),
                                      textAlign: TextAlign.center,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : Video(controller: _videoController!),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class AutoScrollEpgText extends StatefulWidget {
  final String text;
  final TextStyle style;

  const AutoScrollEpgText({super.key, required this.text, required this.style});

  @override
  State<AutoScrollEpgText> createState() => _AutoScrollEpgTextState();
}

class _AutoScrollEpgTextState extends State<AutoScrollEpgText> {
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startScroll());
  }

  void _startScroll() async {
    if (!mounted || !_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    if (maxScroll > 0) {
      await Future.delayed(const Duration(seconds: 1));
      while (mounted && _scrollController.hasClients) {
        await _scrollController.animateTo(
          maxScroll,
          duration: Duration(milliseconds: (maxScroll * 45).toInt().clamp(2000, 8000)),
          curve: Curves.linear,
        );
        await Future.delayed(const Duration(seconds: 1));
        if (!mounted || !_scrollController.hasClients) break;
        await _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOut,
        );
        await Future.delayed(const Duration(seconds: 1));
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      child: Text(widget.text, style: widget.style),
    );
  }
}
