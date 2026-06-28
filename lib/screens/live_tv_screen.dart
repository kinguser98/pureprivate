import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:private_cinema_mobile/data/api_service.dart';
import 'package:private_cinema_mobile/data/stalker_resolver.dart';
import 'package:private_cinema_mobile/screens/video_player_screen.dart';
import 'package:private_cinema_mobile/theme/app_colors.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LiveTvScreen extends StatefulWidget {
  const LiveTvScreen({super.key});

  @override
  State<LiveTvScreen> createState() => _LiveTvScreenState();
}

class _LiveTvScreenState extends State<LiveTvScreen> with SingleTickerProviderStateMixin {
  List<dynamic> _allChannels = [];
  Map<String, List<dynamic>> _groupedChannels = {};
  List<String> _categories = [];
  
  bool _isLoading = true;
  String? _errorMessage;
  TabController? _tabController;
  
  bool _isGridView = true;
  Map<String, String> _logoHeaders = {};

  Future<void> _loadViewPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _isGridView = prefs.getBool('live_tv_grid_view') ?? true;
      });
    } catch (e) {
      debugPrint('Error loading view preference: $e');
    }
  }

  Future<void> _toggleViewPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _isGridView = !_isGridView;
      });
      await prefs.setBool('live_tv_grid_view', _isGridView);
    } catch (e) {
      debugPrint('Error saving view preference: $e');
    }
  }
  
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  List<dynamic> _searchResults = [];

  bool _isResolvingStream = false;
  String _resolvingChannelName = '';
  bool _isSyncing = false;

  Future<void> _syncChannels() async {
    setState(() {
      _isSyncing = true;
    });

    try {
      final res = await StalkerResolver.syncChannelsToServer();
      if (mounted) {
        setState(() {
          _isSyncing = false;
        });
        if (res['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Synced ${res['imported']} channels! Enable them in your admin panel.'),
              backgroundColor: Colors.green,
            ),
          );
          _fetchChannels();
        } else {
          throw Exception(res['error'] ?? 'Unknown error');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSyncing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync failed: $e'),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchChannels();
    _loadViewPreference();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _fetchChannels() async {
    if (mounted) setState(() => _isLoading = true);

    try {
      final headers = await StalkerResolver.getLogoHeaders(1);
      final uri = Uri.parse('${ApiService.apiUrl}?action=get_live_channels');
      final response = await http.get(uri).timeout(const Duration(seconds: 12));
      
      if (response.statusCode == 200) {
        final List<dynamic> channels = json.decode(utf8.decode(response.bodyBytes));
        final Map<String, List<dynamic>> grouped = {};
        
        for (final ch in channels) {
          final cat = ch['category_name']?.toString() ?? 'General';
          grouped.putIfAbsent(cat, () => []).add(ch);
        }

        final sortedCategories = grouped.keys.toList()..sort();
        
        if (mounted) {
          _tabController?.dispose();
          if (sortedCategories.isNotEmpty) {
            _tabController = TabController(length: sortedCategories.length, vsync: this);
            _tabController!.addListener(() {
              if (mounted) setState(() {});
            });
          } else {
            _tabController = null;
          }
          
          setState(() {
            _allChannels = channels;
            _groupedChannels = grouped;
            _categories = sortedCategories;
            _logoHeaders = headers;
            _isLoading = false;
            _errorMessage = null;
          });
        }
      } else {
        throw Exception('HTTP Error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error loading live TV channels on mobile: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load Live TV catalog. Run a sync in your admin panel.';
        });
      }
    }
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase().trim();
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
      });
      return;
    }

    final results = _allChannels.where((ch) {
      final name = (ch['name']?.toString() ?? '').toLowerCase();
      final cat = (ch['category_name']?.toString() ?? '').toLowerCase();
      return name.contains(query) || cat.contains(query);
    }).toList();

    setState(() {
      _searchResults = results;
    });
  }

  Future<void> _playChannel(Map<String, dynamic> channel) async {
    final name = channel['name']?.toString() ?? 'Live Channel';
    final cmd = channel['cmd']?.toString() ?? '';

    if (cmd.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid channel link cmd.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() {
      _isResolvingStream = true;
      _resolvingChannelName = name;
    });

    try {
      final portalId = int.tryParse(channel['portal_id']?.toString() ?? '') ?? 1;
      // Resolve direct stream link from Stalker Portal
      final resolved = await StalkerResolver.resolveStream(cmd, portalId);
      
      if (mounted) {
        setState(() => _isResolvingStream = false);
        
        // Open Mobile Native Video Player with resolved stream and headers
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => VideoPlayerScreen(
              videoSource: resolved.url,
              title: name,
              subtitle: 'Live TV | ${channel['category_name']}',
              headers: resolved.headers,
              isLive: true,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error resolving Stalker stream: $e');
      if (mounted) {
        setState(() => _isResolvingStream = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load channel: $e'),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () => _playChannel(channel),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final showSearch = _isSearching || _searchController.text.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.4),
        elevation: 0,
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: const InputDecoration(
                  hintText: 'Search channels...',
                  hintStyle: TextStyle(color: Colors.white38),
                  border: InputBorder.none,
                ),
              )
            : Text(
                'LIVE TELEVISION',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                  letterSpacing: 1,
                ),
              ),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search, color: Colors.white),
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _searchController.clear();
                  _isSearching = false;
                } else {
                  _isSearching = true;
                }
              });
            },
          ),
          if (!_isSearching) ...[
            IconButton(
              icon: const Icon(Icons.sync, color: Colors.white),
              onPressed: _syncChannels,
            ),
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: _fetchChannels,
            ),
          ],
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Content
          if (_isLoading)
            Center(child: CircularProgressIndicator(color: AppColors.accentBright))
          else if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.all(32.0),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.wifi_off_rounded, color: Colors.redAccent, size: 64),
                    const SizedBox(height: 16),
                    Text(
                      'Catalog Connection Failed',
                      style: GoogleFonts.outfit(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.4),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _fetchChannels,
                      child: const Text('Try Again', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            )
          else if (_categories.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32.0),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.tv_off_rounded, color: Colors.white30, size: 64),
                    const SizedBox(height: 16),
                    Text(
                      'No Live Channels',
                      style: GoogleFonts.outfit(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Select and enable IPTV channels in your admin panel to display them here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.4),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _syncChannels,
                      icon: const Icon(Icons.sync, color: Colors.white),
                      label: const Text('Sync Portal Channels', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            )
          else if (showSearch)
            _buildSearchResults()
          else
            _buildTabbedView(),

          // Stream resolution overlay loader
          if (_isResolvingStream)
            Positioned.fill(
              child: Container(
                color: Colors.black87,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: AppColors.accentBright),
                        const SizedBox(height: 20),
                        Text(
                          'RESOLVING LIVE STREAM',
                          style: GoogleFonts.outfit(
                            color: Colors.white24,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _resolvingChannelName,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Connecting to IPTV Stalker Portal...',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          // Full Screen Syncing overlay spinner
          if (_isSyncing)
            Positioned.fill(
              child: Container(
                color: Colors.black87,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: AppColors.accentBright),
                        const SizedBox(height: 20),
                        Text(
                          'SYNCING PORTAL CHANNELS',
                          style: GoogleFonts.outfit(
                            color: Colors.white24,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Fetching channels from portal and uploading to server...',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFallbackLogo(String name, {double size = 50, double fontSize = 20}) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final code = name.hashCode.abs();
    final List<Color> gradientColors = [
      Colors.primaries[code % Colors.primaries.length],
      Colors.primaries[(code + 3) % Colors.primaries.length].withValues(alpha: 0.8),
    ];
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: gradientColors[0].withValues(alpha: 0.35),
            blurRadius: 8,
            spreadRadius: 1,
          )
        ],
      ),
      child: Center(
        child: Text(
          initial,
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildLayoutSelector() {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSelectorPill(
            isSelected: _isGridView,
            icon: Icons.grid_view_rounded,
            label: 'Grid',
            onTap: () {
              if (!_isGridView) _toggleViewPreference();
            },
          ),
          _buildSelectorPill(
            isSelected: !_isGridView,
            icon: Icons.view_list_rounded,
            label: 'List',
            onTap: () {
              if (_isGridView) _toggleViewPreference();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSelectorPill({
    required bool isSelected,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.accent.withValues(alpha: 0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected ? Colors.white : AppColors.textMuted,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderRow(int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '$count CHANNELS',
            style: GoogleFonts.outfit(
              color: AppColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          _buildLayoutSelector(),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_searchResults.isEmpty) {
      return Center(
        child: Text(
          'No channels found for "${_searchController.text}"',
          style: const TextStyle(color: AppColors.textMuted, fontSize: 14),
        ),
      );
    }

    return Column(
      children: [
        _buildHeaderRow(_searchResults.length),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.97, end: 1.0).animate(animation),
                  child: child,
                ),
              );
            },
            child: _isGridView
                ? GridView.builder(
                    key: const ValueKey('search_grid'),
                    padding: const EdgeInsets.all(16),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 0.95,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: _searchResults.length,
                    itemBuilder: (context, index) => _buildChannelItem(_searchResults[index]),
                  )
                : ListView.separated(
                    key: const ValueKey('search_list'),
                    padding: const EdgeInsets.all(16),
                    itemCount: _searchResults.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) => _buildChannelListItem(_searchResults[index]),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildTabbedView() {
    final activeIndex = _tabController?.index ?? 0;
    final activeCategory = _categories.isNotEmpty ? _categories[activeIndex] : '';
    final activeChannels = _groupedChannels[activeCategory] ?? [];
    final activeCount = activeChannels.length;

    return Column(
      children: [
        Container(
          height: 48,
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            labelColor: Colors.white,
            unselectedLabelColor: AppColors.textMuted,
            indicatorSize: TabBarIndicatorSize.tab,
            indicator: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                colors: [
                  AppColors.accent,
                  AppColors.accentBright,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.accent.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13),
            unselectedLabelStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 13),
            dividerColor: Colors.transparent,
            tabAlignment: TabAlignment.start,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            tabs: _categories.map((cat) => Tab(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(cat.toUpperCase()),
              ),
            )).toList(),
          ),
        ),
        _buildHeaderRow(activeCount),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: _categories.map((cat) {
              final catChannels = _groupedChannels[cat] ?? [];
              
              return RefreshIndicator(
                color: AppColors.accent,
                backgroundColor: AppColors.card,
                onRefresh: _fetchChannels,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(
                        scale: Tween<double>(begin: 0.97, end: 1.0).animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: _isGridView
                      ? GridView.builder(
                          key: ValueKey('grid_$cat'),
                          padding: const EdgeInsets.all(16),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            childAspectRatio: 0.95,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                          itemCount: catChannels.length,
                          itemBuilder: (context, index) => _buildChannelItem(catChannels[index]),
                        )
                      : ListView.separated(
                          key: ValueKey('list_$cat'),
                          padding: const EdgeInsets.all(16),
                          itemCount: catChannels.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) => _buildChannelListItem(catChannels[index]),
                        ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildChannelItem(dynamic ch) {
    final name = ch['name']?.toString() ?? 'Live Stream';
    final logoUrl = ch['logo_url']?.toString() ?? '';

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.04),
            Colors.white.withValues(alpha: 0.01),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _playChannel(ch),
            splashColor: AppColors.accent.withValues(alpha: 0.15),
            highlightColor: AppColors.accent.withValues(alpha: 0.08),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    child: Center(
                      child: logoUrl.isNotEmpty
                          ? Image.network(
                              logoUrl,
                              headers: _logoHeaders,
                              fit: BoxFit.contain,
                              loadingBuilder: (context, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return Center(
                                  child: SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.accentBright.withValues(alpha: 0.5),
                                    ),
                                  ),
                                );
                              },
                              errorBuilder: (_, __, ___) => _buildFallbackLogo(name, size: 54, fontSize: 22),
                            )
                          : _buildFallbackLogo(name, size: 54, fontSize: 22),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  color: Colors.black.withValues(alpha: 0.3),
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChannelListItem(dynamic ch) {
    final name = ch['name']?.toString() ?? 'Live Stream';
    final logoUrl = ch['logo_url']?.toString() ?? '';
    final category = ch['category_name']?.toString() ?? 'General';

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.03),
            Colors.white.withValues(alpha: 0.01),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _playChannel(ch),
            splashColor: AppColors.accent.withValues(alpha: 0.15),
            highlightColor: AppColors.accent.withValues(alpha: 0.08),
            child: Row(
              children: [
                // Left accent indicator bar
                Container(
                  width: 4,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(2),
                      bottomRight: Radius.circular(2),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.accent.withValues(alpha: 0.5),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Logo container
                Container(
                  width: 50,
                  height: 50,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.02),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                  ),
                  child: Center(
                    child: logoUrl.isNotEmpty
                        ? Image.network(
                            logoUrl,
                            headers: _logoHeaders,
                            fit: BoxFit.contain,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Center(
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.accentBright.withValues(alpha: 0.5),
                                  ),
                                ),
                              );
                            },
                            errorBuilder: (_, __, ___) => _buildFallbackLogo(name, size: 36, fontSize: 15),
                          )
                        : _buildFallbackLogo(name, size: 36, fontSize: 15),
                  ),
                ),
                const SizedBox(width: 16),
                // Name and Category details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        category.toUpperCase(),
                        style: GoogleFonts.outfit(
                          color: AppColors.textMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                // Play button/indicator icon
                Container(
                  margin: const EdgeInsets.only(right: 16),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
                  ),
                  child: Icon(
                    Icons.play_arrow_rounded,
                    color: AppColors.accentBright,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
