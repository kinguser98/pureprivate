import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ExternalPlayerService {
  static const _channel = MethodChannel('com.goxio.mob/external_player');

  static const List<Map<String, String>> playerTypes = [
    {'id': 'vlc', 'name': 'VLC Media Player', 'package': 'org.videolan.vlc'},
    {'id': 'mx', 'name': 'MX Player', 'package': 'com.mxtech.videoplayer.ad'},
    {'id': 'system', 'name': 'System Chooser (Ask Every Time)', 'package': ''},
  ];

  static const List<Map<String, String>> sourceTypes = [
    {'id': 'telegram', 'name': 'Telegram Streams', 'desc': 'Play Telegram video links externally'},
    {'id': 'stalker', 'name': 'Stalker IPTV & Portals', 'desc': 'Play Stalker live & VOD externally'},
    {'id': 'torrentio', 'name': 'Torrentio & Debrid', 'desc': 'Play RealDebrid/Seedr externally'},
    {'id': 'netmirror', 'name': 'NetMirror & Stravo', 'desc': 'Play NetMirror streams externally'},
    {'id': 'streamtape', 'name': 'Streamtape Streams', 'desc': 'Play Streamtape links externally'},
    {'id': 'vegamovies', 'name': 'Vegamovies.se Streams', 'desc': 'Play Vegamovies links externally'},
    {'id': 'cinejoy', 'name': 'Cinejoy.to Embed Streams', 'desc': 'Play Cinejoy links externally'},
    {'id': 'direct_link', 'name': 'Direct Link Streams', 'desc': 'Play direct video URLs externally'},
    {'id': 'local', 'name': 'Local Storage Files', 'desc': 'Play local video files externally'},
  ];

  static Future<String> getDefaultPlayer() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('default_external_player') ?? 'vlc';
  }

  static Future<void> setDefaultPlayer(String player) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('default_external_player', player);
  }

  static Future<String> getPlayerDisplayName([String? player]) async {
    final p = player ?? await getDefaultPlayer();
    switch (p) {
      case 'mx':
        return 'MX Player';
      case 'system':
        return 'External Player (Chooser)';
      case 'vlc':
      default:
        return 'VLC Media Player';
    }
  }

  static Future<bool> isGlobalEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('use_external_player') ?? false;
  }

  static Future<void> setGlobalEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('use_external_player', enabled);
  }

  static Future<Set<String>> getEnabledSources() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('external_player_sources');
    if (list != null) {
      return list.toSet();
    }
    return {};
  }

  static Future<void> setSourceEnabled(String sourceId, bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    final current = (prefs.getStringList('external_player_sources') ?? []).toSet();
    if (enabled) {
      current.add(sourceId);
    } else {
      current.remove(sourceId);
    }
    await prefs.setStringList('external_player_sources', current.toList());
  }

  static Future<bool> shouldPlayInExternalPlayer({
    required String url,
    String? sourceName,
  }) async {
    if (await isGlobalEnabled()) return true;

    final enabledSources = await getEnabledSources();
    if (enabledSources.isEmpty) return false;

    final lowerUrl = url.toLowerCase();
    final lowerName = sourceName?.toLowerCase() ?? '';

    if (enabledSources.contains('telegram') && (
        lowerName.contains('telegram') ||
        lowerName.contains('tg') ||
        lowerUrl.contains('/tg/') ||
        lowerUrl.contains('/f/') ||
        lowerUrl.contains('telegram') ||
        (lowerUrl.contains('127.0.0.1') && lowerUrl.contains('/f/'))
    )) {
      return true;
    }
    if (enabledSources.contains('stalker') && (
        lowerName.contains('stalker') ||
        lowerName.contains('vod') ||
        lowerUrl.contains('mac=') ||
        lowerUrl.contains('/server/load.php') ||
        lowerUrl.startsWith('stalker://') ||
        lowerUrl.contains('stalker') ||
        lowerUrl.contains('/vod/')
    )) {
      return true;
    }
    if (enabledSources.contains('torrentio') && (lowerName.contains('torrentio') || lowerName.contains('debrid') || lowerName.contains('seedr') || lowerUrl.contains('seedr'))) {
      return true;
    }
    if (enabledSources.contains('netmirror') && (lowerName.contains('netmirror') || lowerName.contains('stravo'))) {
      return true;
    }
    if (enabledSources.contains('streamtape') && (lowerName.contains('streamtape') || lowerUrl.contains('streamtape') || lowerUrl.contains('strcloud'))) {
      return true;
    }
    if (enabledSources.contains('local') && (lowerName.contains('local') || lowerUrl.startsWith('file:') || lowerUrl.startsWith('/storage/'))) {
      return true;
    }

    return false;
  }

  static Future<bool> launch({
    required String url,
    String? title,
    Map<String, String>? headers,
    String? overridePlayerPackage,
  }) async {
    try {
      final playerPackage = overridePlayerPackage ?? await getDefaultPlayer();
      final success = await _channel.invokeMethod<bool>('launchExternalPlayer', {
        'url': url,
        'title': title,
        'headers': headers,
        'playerPackage': playerPackage,
      });
      return success ?? false;
    } catch (e) {
      return false;
    }
  }

  static void showLaunchDialog(BuildContext context, [String? playerDisplayName]) {
    final name = playerDisplayName ?? 'External Player';
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        Future.delayed(const Duration(milliseconds: 3500), () {
          if (context.mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        });
        return AlertDialog(
          backgroundColor: const Color(0xFF16161A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Colors.white12),
          ),
          content: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(color: Color(0xFFFF2D55), strokeWidth: 3),
                ),
                const SizedBox(height: 20),
                Text(
                  'Opening in $name soon...',
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Please wait while the stream is handed over.',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

