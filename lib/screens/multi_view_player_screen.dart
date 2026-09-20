import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:http/http.dart' as http;
import '../theme/app_colors.dart';
import '../data/api_service.dart';
import '../data/stalker_resolver.dart';
import '../data/dns_proxy.dart';

class MultiViewPlayerScreen extends StatefulWidget {
  final List<dynamic>? initialChannels;
  const MultiViewPlayerScreen({super.key, this.initialChannels});

  @override
  State<MultiViewPlayerScreen> createState() => _MultiViewPlayerScreenState();
}

class _MultiViewPlayerScreenState extends State<MultiViewPlayerScreen> {
  // Mobile supports up to 4 split screens
  static const int numPlayers = 4;
  
  final List<Player?> _players = List.generate(numPlayers, (_) => null);
  final List<VideoController?> _controllers = List.generate(numPlayers, (_) => null);
  final List<Map<String, dynamic>?> _activeChannels = List.generate(numPlayers, (_) => null);
  final List<bool> _isLoading = List.generate(numPlayers, (_) => false);
  final List<String?> _errorMessages = List.generate(numPlayers, (_) => null);

  List<dynamic> _channels = [];
  bool _loadingChannels = false;
  int _activeAudioIndex = 0;

  @override
  void initState() {
    super.initState();
    _fetchChannelsList();
    
    // Initialize media kit players
    for (int i = 0; i < numPlayers; i++) {
      _players[i] = Player();
      _controllers[i] = VideoController(_players[i]!);
    }
  }

  Future<void> _fetchChannelsList() async {
    if (widget.initialChannels != null && widget.initialChannels!.isNotEmpty) {
      setState(() => _channels = widget.initialChannels!);
      return;
    }

    setState(() => _loadingChannels = true);
    try {
      final uri = Uri.parse('${ApiService.apiUrl}?action=get_live_channels');
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final List<dynamic> list = json.decode(utf8.decode(response.bodyBytes));
        if (mounted) {
          setState(() {
            _channels = list;
            _loadingChannels = false;
          });
        }
      }
    } catch (e) {
      debugPrint('MultiViewPlayerScreen: Error fetching channels: $e');
      if (mounted) {
        setState(() => _loadingChannels = false);
      }
    }
  }

  Future<void> _resolveAndPlayChannel(int index, Map<String, dynamic> channel) async {
    final player = _players[index];
    if (player == null) return;

    setState(() {
      _isLoading[index] = true;
      _errorMessages[index] = null;
      _activeChannels[index] = channel;
    });

    try {
      final cmd = channel['cmd']?.toString() ?? '';
      final portalId = int.tryParse(channel['portal_id']?.toString() ?? '') ?? 1;
      
      final resolved = await StalkerResolver.resolveStream(cmd, portalId);
      
      if (mounted) {
        var resolvedSource = resolved.url;
        final dnsProxy = CustomDnsProxy();
        if (resolvedSource.startsWith('http') && dnsProxy.port != null) {
          final uri = Uri.parse(resolvedSource);
          final hostWithPort = uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
          
          final newParams = Map<String, String>.from(uri.queryParameters);
          newParams['local_proxy_headers'] = jsonEncode(resolved.headers);
          final cleanUri = uri.replace(queryParameters: newParams);

          resolvedSource = 'http://127.0.0.1:${dnsProxy.port}/proxy/${cleanUri.scheme}/$hostWithPort${cleanUri.path}${cleanUri.hasQuery ? "?" + cleanUri.query : ""}';
        }

        if (player.platform is NativePlayer) {
          final nativePlayer = player.platform as NativePlayer;
          await nativePlayer.setProperty('cache', 'yes');
          await nativePlayer.setProperty('demuxer-readahead-secs', '15');
          await nativePlayer.setProperty('cache-secs', '15');
          await nativePlayer.setProperty('demuxer-max-bytes', '33554432');
          await nativePlayer.setProperty('cache-pause-wait', '1');
          await nativePlayer.setProperty('network-timeout', '30');
        }

        await player.open(
          Media(
            resolvedSource,
            httpHeaders: resolved.headers,
          ),
          play: true,
        );

        // Switch volume based on audio focus index
        await player.setVolume(index == _activeAudioIndex ? 100 : 0);

        setState(() {
          _isLoading[index] = false;
        });
      }
    } catch (e) {
      debugPrint('MultiView: Error playing slot $index -> $e');
      if (mounted) {
        setState(() {
          _isLoading[index] = false;
          _errorMessages[index] = e.toString();
        });
      }
    }
  }

  void _switchAudioFocus(int index) {
    setState(() => _activeAudioIndex = index);
    for (int i = 0; i < numPlayers; i++) {
      _players[i]?.setVolume(i == index ? 100 : 0);
    }
  }

  void _showChannelPickerDialog(int index) {
    if (_channels.isEmpty) {
      _fetchChannelsList();
    }

    final searchCtrl = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final query = searchCtrl.text.toLowerCase().trim();
            final filtered = query.isEmpty
                ? _channels
                : _channels.where((ch) {
                    final name = (ch['name']?.toString() ?? '').toLowerCase();
                    final cat = (ch['category_name']?.toString() ?? '').toLowerCase();
                    return name.contains(query) || cat.contains(query);
                  }).toList();

            return Dialog(
              backgroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Container(
                width: MediaQuery.of(context).size.width * 0.9,
                height: 540,
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.deepPurpleAccent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.tv_rounded, color: Colors.deepPurpleAccent, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Select Channel for Slot ${index + 1}',
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '${filtered.length} of ${_channels.length} channels',
                                style: const TextStyle(color: Colors.white38, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 20),
                          onPressed: () => Navigator.of(ctx).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // Search bar
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          const Icon(Icons.search_rounded, color: Colors.white54, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: searchCtrl,
                              autofocus: false,
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                              decoration: const InputDecoration(
                                hintText: 'Search channel name or category...',
                                hintStyle: TextStyle(color: Colors.white30, fontSize: 13),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(vertical: 12),
                              ),
                              onChanged: (_) => setModalState(() {}),
                            ),
                          ),
                          if (searchCtrl.text.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.clear_rounded, color: Colors.white54, size: 18),
                              onPressed: () {
                                searchCtrl.clear();
                                setModalState(() {});
                              },
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: _loadingChannels
                          ? const Center(child: CircularProgressIndicator(color: Colors.deepPurpleAccent))
                          : filtered.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.search_off_rounded, color: Colors.white30, size: 40),
                                      const SizedBox(height: 8),
                                      Text(
                                        query.isEmpty ? 'No channels available' : 'No channels matching "$query"',
                                        style: const TextStyle(color: Colors.white54, fontSize: 13),
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.separated(
                                  itemCount: filtered.length,
                                  separatorBuilder: (_, __) => Divider(color: Colors.white.withValues(alpha: 0.05), height: 1),
                                  itemBuilder: (context, idx) {
                                    final ch = filtered[idx];
                                    final name = ch['name']?.toString() ?? 'Channel';
                                    final category = ch['category_name']?.toString() ?? 'Live';
                                    final logo = ch['logo_url']?.toString() ?? ch['logo']?.toString() ?? '';
                                    final isCurrentlyPlaying = _activeChannels[index]?['id'] == ch['id'] ||
                                        _activeChannels[index]?['cmd'] == ch['cmd'];

                                    return ListTile(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      leading: Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.05),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(10),
                                          child: logo.startsWith('http')
                                              ? CachedNetworkImage(
                                                  imageUrl: logo,
                                                  fit: BoxFit.cover,
                                                  errorWidget: (_, __, ___) => const Icon(Icons.tv_rounded, color: Colors.white38, size: 20),
                                                )
                                              : const Icon(Icons.tv_rounded, color: Colors.white38, size: 20),
                                        ),
                                      ),
                                      title: Text(
                                        name,
                                        style: TextStyle(
                                          color: isCurrentlyPlaying ? Colors.deepPurpleAccent : Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      subtitle: Text(
                                        category,
                                        style: const TextStyle(color: Colors.white38, fontSize: 11),
                                      ),
                                      trailing: isCurrentlyPlaying
                                          ? Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: Colors.deepPurpleAccent.withValues(alpha: 0.2),
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: Colors.deepPurpleAccent.withValues(alpha: 0.5)),
                                              ),
                                              child: const Text(
                                                'PLAYING',
                                                style: TextStyle(
                                                  color: Colors.deepPurpleAccent,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            )
                                          : const Icon(Icons.play_circle_outline_rounded, color: Colors.white38, size: 22),
                                      onTap: () {
                                        Navigator.of(ctx).pop();
                                        _resolveAndPlayChannel(index, ch);
                                      },
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    for (int i = 0; i < numPlayers; i++) {
      _players[i]?.stop();
      _players[i]?.dispose();
    }
    // Allow orientation to freely rotate or restore default
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return OrientationBuilder(
      builder: (context, orientation) {
        final isPortrait = orientation == Orientation.portrait;

        return Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Column(
              children: [
                // Top Toolbar Row
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: isPortrait ? 12 : 6),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 24),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'GRID MULTI-VIEW',
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.2,
                              ),
                            ),
                            Text(
                              isPortrait
                                  ? 'Portrait: One after another • Tap for audio'
                                  : 'Landscape: 2x2 Grid • Tap for audio',
                              style: GoogleFonts.outfit(
                                color: Colors.white54,
                                fontSize: 10.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Quick Orientation Toggle Button
                      IconButton(
                        icon: Icon(
                          isPortrait ? Icons.screen_lock_landscape_rounded : Icons.screen_lock_portrait_rounded,
                          color: AppColors.accentBright,
                          size: 22,
                        ),
                        tooltip: isPortrait ? 'Switch to 2x2 Landscape' : 'Switch to Portrait Stack',
                        onPressed: () {
                          if (isPortrait) {
                            SystemChrome.setPreferredOrientations([
                              DeviceOrientation.landscapeLeft,
                              DeviceOrientation.landscapeRight,
                            ]);
                          } else {
                            SystemChrome.setPreferredOrientations([
                              DeviceOrientation.portraitUp,
                            ]);
                          }
                        },
                      ),
                    ],
                  ),
                ),

                // Video Players: Vertical list in portrait, 2x2 grid in landscape
                Expanded(
                  child: isPortrait
                      ? ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                          itemCount: numPlayers,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, i) {
                            return AspectRatio(
                              aspectRatio: 16 / 9,
                              child: _buildPlayerSlot(i, isPortrait: true),
                            );
                          },
                        )
                      : Padding(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                          child: GridView.count(
                            crossAxisCount: 2,
                            childAspectRatio: 16 / 9,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                            children: List.generate(numPlayers, (i) => _buildPlayerSlot(i, isPortrait: false)),
                          ),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlayerSlot(int i, {required bool isPortrait}) {
    final hasAudio = _activeAudioIndex == i;
    final ch = _activeChannels[i];
    final controller = _controllers[i];
    final err = _errorMessages[i];

    return GestureDetector(
      onTap: () {
        if (ch == null) {
          _showChannelPickerDialog(i);
        } else {
          _switchAudioFocus(i);
        }
      },
      onLongPress: () {
        _showChannelPickerDialog(i);
      },
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0F111E),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hasAudio ? AppColors.accentBright : Colors.white.withOpacity(0.08),
            width: hasAudio ? 2.2 : 1.0,
          ),
          boxShadow: hasAudio
              ? [
                  BoxShadow(
                    color: AppColors.accentBright.withOpacity(0.35),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Video Widget
            if (controller != null && ch != null && err == null)
              Video(controller: controller),
            
            // Placeholder (Unselected Slot)
            if (ch == null)
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.add_to_queue_rounded, color: Colors.white54, size: 28),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'SCREEN ${i + 1} • TAP TO SELECT',
                    style: GoogleFonts.outfit(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              )
            else if (_isLoading[i])
              const Center(
                child: CircularProgressIndicator(color: Colors.deepPurpleAccent),
              )
            else if (err != null)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 26),
                    const SizedBox(height: 4),
                    Text(
                      err,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70, fontSize: 9.5),
                    ),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: () => _resolveAndPlayChannel(i, ch),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('Retry', style: TextStyle(color: Colors.white, fontSize: 10)),
                      ),
                    ),
                  ],
                ),
              ),

            // Top Overlay: Screen Label & Audio Focus Badge
            Positioned(
              top: 8,
              left: 8,
              right: 8,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Channel / Screen Title Pill
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Text(
                      ch != null ? (ch['name']?.toString() ?? 'Screen ${i + 1}') : 'Screen ${i + 1}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  // Audio Badge (Tap to switch audio)
                  GestureDetector(
                    onTap: () => _switchAudioFocus(i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                      decoration: BoxDecoration(
                        color: hasAudio ? const Color(0xFF10B981) : Colors.black87,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: hasAudio ? Colors.greenAccent : Colors.white12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            hasAudio ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                            color: hasAudio ? Colors.black : Colors.white60,
                            size: 13,
                          ),
                          const SizedBox(width: 3.5),
                          Text(
                            hasAudio ? 'AUDIO' : 'MUTED',
                            style: GoogleFonts.outfit(
                              color: hasAudio ? Colors.black : Colors.white60,
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Bottom Right: Change Channel Icon Button
            if (ch != null)
              Positioned(
                bottom: 8,
                right: 8,
                child: GestureDetector(
                  onTap: () => _showChannelPickerDialog(i),
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Icon(Icons.swap_horiz_rounded, color: Colors.white, size: 15),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
