import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:http/http.dart' as http;
import 'package:private_cinema_mobile/theme/app_colors.dart';
import 'package:private_cinema_mobile/data/api_service.dart';
import 'package:private_cinema_mobile/data/stalker_resolver.dart';
import 'package:private_cinema_mobile/data/dns_proxy.dart';

class MultiViewPlayerScreen extends StatefulWidget {
  final List<dynamic>? initialChannels;
  const MultiViewPlayerScreen({super.key, this.initialChannels});

  @override
  State<MultiViewPlayerScreen> createState() => _MultiViewPlayerScreenState();
}

class _MultiViewPlayerScreenState extends State<MultiViewPlayerScreen> {
  // Mobile supports up to 4 split screens in a 2x2 grid
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
          newParams['local_proxy_headers'] = jsonEncode(resolved.headers ?? {});
          final cleanUri = uri.replace(queryParameters: newParams);

          resolvedSource = 'http://127.0.0.1:${dnsProxy.port}/proxy/${cleanUri.scheme}/$hostWithPort${cleanUri.path}${cleanUri.hasQuery ? "?" + cleanUri.query : ""}';
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

    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Colors.white10),
          ),
          title: Text(
            'Select Channel for Screen ${index + 1}',
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 450,
            child: _loadingChannels
                ? const Center(child: CircularProgressIndicator(color: Colors.deepPurpleAccent))
                : _channels.isEmpty
                    ? const Center(child: Text('No channels synced to portal', style: TextStyle(color: Colors.white60)))
                    : ListView.builder(
                        itemCount: _channels.length,
                        itemBuilder: (context, idx) {
                          final ch = _channels[idx];
                          final name = ch['name']?.toString() ?? 'Channel';
                          final category = ch['category_name']?.toString() ?? 'Live';
                          return ListTile(
                            title: Text(name, style: const TextStyle(color: Colors.white, fontSize: 14)),
                            subtitle: Text(category, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                            leading: const Icon(Icons.tv_rounded, color: Colors.deepPurpleAccent),
                            onTap: () {
                              Navigator.of(context).pop();
                              _resolveAndPlayChannel(index, ch);
                            },
                          );
                        },
                      ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    for (int i = 0; i < numPlayers; i++) {
      _players[i]?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Top Toolbar Row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 28),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'GRID MULTI-VIEW',
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Tap screen to select channel. Double-tap to focus audio.',
                          style: GoogleFonts.outfit(
                            color: Colors.white54,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // 2x2 Video Player Grid
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                child: GridView.count(
                  crossAxisCount: 2,
                  childAspectRatio: 16 / 9,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  children: List.generate(numPlayers, (i) {
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
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: hasAudio ? AppColors.accent : Colors.white.withOpacity(0.05),
                            width: hasAudio ? 2.5 : 1.0,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // Video Widget
                            if (controller != null && ch != null && err == null)
                              Video(controller: controller),
                            
                            // Placeholder
                            if (ch == null)
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.add_to_queue_rounded, color: Colors.white38, size: 36),
                                  const SizedBox(height: 8),
                                  Text(
                                    'SELECT CHANNEL',
                                    style: GoogleFonts.outfit(
                                      color: Colors.white70,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
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
                                    const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 28),
                                    const SizedBox(height: 4),
                                    Text(
                                      err,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(color: Colors.white70, fontSize: 9),
                                    ),
                                  ],
                                ),
                              ),

                            // Overlay audio/channel badge
                            if (ch != null)
                              Positioned(
                                left: 8,
                                bottom: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.black87,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.white12),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        hasAudio ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                                        color: hasAudio ? Colors.greenAccent : Colors.white54,
                                        size: 11,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        ch['name']?.toString() ?? 'Live',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 9,
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
                    );
                  }),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
