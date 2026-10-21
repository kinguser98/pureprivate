import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// High-performance local Wi-Fi Cast Service for Private Cinema Mobile (Android & iOS).
///
/// Features:
/// 1. Instant UDP Beacon & Subnet Discovery of Android TVs on port 41234 & 8888.
/// 2. Offline Local File Range Server (HTTP 206 Partial Content) — allows TV to stream
///    and seek downloaded movies directly from Mobile without any internet connection.
/// 3. Online Stream Proxy Server — bridges external streams to offline TV over local Wi-Fi.
/// 4. Bi-directional Remote Control RPC (Play, Pause, Seek, Stop, Status Polling).
class WifiCastService {
  static const int tvHttpPort = 8888;
  static const int tvUdpPort = 41234;
  static const int mobileHttpPort = 58526;
  static const int mobileUdpPort = 41235;

  static HttpServer? _server;
  static http.Client? _client;
  static File? _currentLocalFile;
  static String? _targetUrl;
  static Map<String, String>? _targetHeaders;

  static bool get isRunning => _server != null;

  // ---------------------------------------------------------------------------
  // DEVICE DISCOVERY (Dual UDP Beacon + Batched Fast Subnet Ping)
  // ---------------------------------------------------------------------------

  /// Discovers Android TV and Mobile (Android & iOS) devices on the local Wi-Fi network.
  /// Combines dual UDP broadcast probes (TV: 41234, Mobile: 41235) with batched HTTP /ping subnet scan.
  static Future<List<Map<String, dynamic>>> discoverTvDevices({
    Duration timeout = const Duration(milliseconds: 2000),
  }) async {
    final Map<String, Map<String, dynamic>> discovered = {};

    // 1. Dual UDP Broadcast Discovery Probe (TV + Mobile)
    RawDatagramSocket? udpSocket;
    try {
      udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      udpSocket.broadcastEnabled = true;

      final probe = utf8.encode(json.encode({'cmd': 'discover', 'client': 'goxio'}));
      final broadcastAddress = InternetAddress('255.255.255.255');
      // Probe Android TV receiver on 41234 and Mobile phone receiver on 41235
      udpSocket.send(probe, broadcastAddress, tvUdpPort);
      udpSocket.send(probe, broadcastAddress, mobileUdpPort);

      udpSocket.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = udpSocket?.receive();
          if (datagram != null) {
            try {
              final text = utf8.decode(datagram.data);
              final map = json.decode(text) as Map<String, dynamic>;
              final ip = map['ip']?.toString() ?? datagram.address.address;
              final type = map['type']?.toString().toLowerCase() ?? 'tv';
              final isTv = type.contains('tv');
              final port = (map['port'] as num?)?.toInt() ?? (isTv ? tvHttpPort : mobileHttpPort);
              final name = map['name']?.toString() ?? (isTv ? 'Goxio TV ($ip)' : 'Mobile Phone ($ip)');
              discovered[ip] = {
                'name': name,
                'ip': ip,
                'port': port,
                'host': '$ip:$port',
                'type': isTv ? 'tv' : 'mobile',
                'source': 'udp',
              };
            } catch (_) {}
          }
        }
      });
    } catch (e) {
      debugPrint('UDP discovery probe error: $e');
    }

    // 2. Batched HTTP Subnet Scan on port 8888 (TV) and port 58526 (Mobile Android/iOS)
    // Batching 25 concurrent connections prevents socket exhaustion (too many open files) on mobile OS
    try {
      final localIp = await getLocalIp();
      if (localIp != '127.0.0.1' && localIp.contains('.')) {
        final subnet = localIp.substring(0, localIp.lastIndexOf('.'));
        final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 350);

        final ips = List.generate(254, (i) => '$subnet.${i + 1}').where((ip) => ip != localIp).toList();
        const batchSize = 25;

        for (int i = 0; i < ips.length; i += batchSize) {
          final batch = ips.sublist(i, (i + batchSize > ips.length) ? ips.length : i + batchSize);
          await Future.wait(batch.map((targetIp) => _probeIp(client, targetIp, discovered)));
        }
        client.close();
      }
    } catch (e) {
      debugPrint('Subnet discovery scan error: $e');
    }

    // Short yield to allow any trailing UDP broadcast responses to arrive
    await Future.delayed(const Duration(milliseconds: 250));
    try {
      udpSocket?.close();
    } catch (_) {}

    return discovered.values.toList();
  }

  static Future<void> _probeIp(
    HttpClient client,
    String targetIp,
    Map<String, Map<String, dynamic>> discovered,
  ) async {
    // 1. Probe TV on port 8888
    try {
      final req = await client.getUrl(Uri.parse('http://$targetIp:$tvHttpPort/ping'));
      final resp = await req.close().timeout(const Duration(milliseconds: 300));
      if (resp.statusCode == 200) {
        final body = await resp.transform(utf8.decoder).join();
        String name = 'Goxio TV ($targetIp)';
        if (body.contains('{')) {
          try {
            final jsonMap = json.decode(body);
            name = jsonMap['name']?.toString() ?? name;
          } catch (_) {}
        }
        discovered['tv_$targetIp'] = {
          'name': name,
          'ip': targetIp,
          'port': tvHttpPort,
          'host': '$targetIp:$tvHttpPort',
          'type': 'tv',
          'source': 'http',
        };
        return;
      }
    } catch (_) {}

    // 2. Probe Mobile device on port 58526
    try {
      final req = await client.getUrl(Uri.parse('http://$targetIp:$mobileHttpPort/ping'));
      final resp = await req.close().timeout(const Duration(milliseconds: 300));
      if (resp.statusCode == 200) {
        final body = await resp.transform(utf8.decoder).join();
        String name = 'Mobile Phone ($targetIp)';
        if (body.contains('{')) {
          try {
            final jsonMap = json.decode(body);
            name = jsonMap['device_name']?.toString() ?? name;
          } catch (_) {}
        }
        discovered['mobile_$targetIp'] = {
          'name': name,
          'ip': targetIp,
          'port': mobileHttpPort,
          'host': '$targetIp:$mobileHttpPort',
          'type': 'mobile',
          'source': 'http',
        };
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // LOCAL FILE STREAM SERVER (HTTP 206 Range - 100% Offline, Zero Internet)
  // ---------------------------------------------------------------------------

  /// Starts an embedded HTTP server serving a locally downloaded file with
  /// HTTP 206 Partial Content (Range) support. ExoPlayer on TV can seek anywhere smoothly.
  static Future<String?> startLocalFileServer(File file) async {
    await stopAll();

    if (!await file.exists()) {
      debugPrint('WifiCastService: Local file does not exist: ${file.path}');
      return null;
    }

    _currentLocalFile = file;

    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      final port = _server!.port;
      final localIp = await getLocalIp();
      final streamUrl = 'http://$localIp:$port/cast/video.mp4';

      debugPrint('WifiCastService: Local offline file server listening at $streamUrl');

      _server!.listen((HttpRequest request) async {
        await _handleLocalFileRequest(request, file);
      });

      return streamUrl;
    } catch (e) {
      debugPrint('WifiCastService: Failed to start local file server: $e');
      await stopAll();
      return null;
    }
  }

  static Future<void> _handleLocalFileRequest(HttpRequest request, File file) async {
    try {
      final fileLength = await file.length();
      final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);

      final extension = file.path.split('.').last.toLowerCase();
      final contentType = (extension == 'mkv')
          ? ContentType('video', 'x-matroska')
          : (extension == 'webm')
              ? ContentType('video', 'webm')
              : ContentType('video', 'mp4');

      request.response.headers.contentType = contentType;
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      request.response.headers.set('Access-Control-Allow-Origin', '*');

      if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
        // Parse HTTP Range: bytes=start-end
        final rangeValue = rangeHeader.substring(6).trim();
        final parts = rangeValue.split('-');
        int start = int.tryParse(parts[0]) ?? 0;
        int? end = parts.length > 1 && parts[1].isNotEmpty ? int.tryParse(parts[1]) : null;

        if (end == null || end >= fileLength) {
          end = fileLength - 1;
        }

        if (start > end || start >= fileLength) {
          request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          request.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$fileLength');
          await request.response.close();
          return;
        }

        final contentLength = end - start + 1;
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers.set(HttpHeaders.contentLengthHeader, contentLength);
        request.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$fileLength');

        await file.openRead(start, end + 1).pipe(request.response);
      } else {
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.set(HttpHeaders.contentLengthHeader, fileLength);
        await file.openRead().pipe(request.response);
      }
    } catch (e) {
      debugPrint('WifiCastService: File stream error: $e');
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {}
    }
  }

  // ---------------------------------------------------------------------------
  // ONLINE STREAM PROXY (Bridges external internet streams to TV via Wi-Fi)
  // ---------------------------------------------------------------------------

  static Future<String?> startProxyServer(String streamUrl, {Map<String, String>? headers}) async {
    await stopAll();

    _targetUrl = streamUrl;
    _targetHeaders = headers;
    _client = http.Client();

    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      final port = _server!.port;
      final localIp = await getLocalIp();
      final proxyUrl = 'http://$localIp:$port/stream';

      debugPrint('WifiCastService: Online proxy server listening at $proxyUrl');

      _server!.listen((HttpRequest request) async {
        if (request.uri.path == '/stream') {
          await _handleProxyRequest(request);
        } else {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        }
      });

      return proxyUrl;
    } catch (e) {
      debugPrint('WifiCastService: Failed to start stream proxy: $e');
      await stopAll();
      return null;
    }
  }

  static Future<void> _handleProxyRequest(HttpRequest request) async {
    if (_targetUrl == null || _client == null) {
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
      return;
    }

    try {
      final proxyReq = http.StreamedRequest(request.method, Uri.parse(_targetUrl!));
      request.headers.forEach((name, values) {
        if (name.toLowerCase() != 'host') {
          proxyReq.headers[name] = values.join(', ');
        }
      });
      if (_targetHeaders != null) {
        proxyReq.headers.addAll(_targetHeaders!);
      }

      final response = await _client!.send(proxyReq);
      request.response.statusCode = response.statusCode;
      response.headers.forEach((name, value) {
        request.response.headers.set(name, value);
      });
      request.response.headers.set('Access-Control-Allow-Origin', '*');

      await response.stream.pipe(request.response);
    } catch (e) {
      debugPrint('WifiCastService: Proxy error: $e');
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {}
    }
  }

  // ---------------------------------------------------------------------------
  // CAST REMOTE CONTROL & DISPATCH RPC
  // ---------------------------------------------------------------------------

  /// Dispatches media playback command to Android TV via LAN.
  static Future<bool> castToTv({
    required String tvHost,
    required String title,
    required String streamUrl,
    Map<String, String>? headers,
    int startPositionMs = 0,
    String? posterUrl,
    String? subtitle,
  }) async {
    final uri = Uri.parse('http://$tvHost/api/cast/play');
    final payload = {
      'title': title,
      'url': streamUrl,
      'media_url': streamUrl,
      'start_position_ms': startPositionMs,
      'headers': headers ?? {},
      'poster_url': posterUrl ?? '',
      'subtitle': subtitle ?? '',
    };

    try {
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(payload),
      ).timeout(const Duration(seconds: 5));
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('WifiCastService: Failed castToTv request: $e');
      return false;
    }
  }

  /// Sends playback control command (play, pause, seek, stop) to Android TV.
  static Future<bool> sendControl({
    required String tvHost,
    required String command,
    int? positionMs,
  }) async {
    final uri = Uri.parse('http://$tvHost/api/cast/control');
    final payload = {
      'command': command,
      'position_ms': positionMs ?? 0,
    };

    try {
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(payload),
      ).timeout(const Duration(seconds: 3));
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('WifiCastService: Failed sendControl request: $e');
      return false;
    }
  }

  /// Polls TV for real-time playback state (position, duration, isPlaying).
  static Future<Map<String, dynamic>?> fetchPlaybackStatus({
    required String tvHost,
  }) async {
    final uri = Uri.parse('http://$tvHost/api/cast/status');
    try {
      final res = await http.get(uri).timeout(const Duration(milliseconds: 1500));
      if (res.statusCode == 200) {
        return json.decode(res.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  // ---------------------------------------------------------------------------
  // LIFECYCLE & HELPERS
  // ---------------------------------------------------------------------------

  static Future<void> stopAll() async {
    _client?.close();
    _client = null;
    await _server?.close(force: true);
    _server = null;
    _currentLocalFile = null;
    _targetUrl = null;
    _targetHeaders = null;
  }

  static Future<void> stopProxyServer() => stopAll();

  static Future<String> getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );

      // 1. Wi-Fi / Ethernet interfaces first (wlan, en, ap, eth)
      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();
        final isWifiOrEth = name.startsWith('wlan') ||
            name.startsWith('en') ||
            name.startsWith('eth') ||
            name.startsWith('ap');
        if (isWifiOrEth) {
          for (final addr in iface.addresses) {
            if (!addr.isLoopback &&
                (addr.address.startsWith('192.168.') ||
                 addr.address.startsWith('10.') ||
                 addr.address.startsWith('172.'))) {
              return addr.address;
            }
          }
        }
      }

      // 2. Non-cellular interfaces with standard 192.168.* IP
      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();
        final isCellular = name.startsWith('rmnet') ||
            name.startsWith('ccmni') ||
            name.startsWith('pdp') ||
            name.startsWith('radio') ||
            name.startsWith('dummy') ||
            name.startsWith('tun');
        if (!isCellular) {
          for (final addr in iface.addresses) {
            if (!addr.isLoopback && addr.address.startsWith('192.168.')) {
              return addr.address;
            }
          }
        }
      }

      // 3. Any non-cellular private IP
      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();
        final isCellular = name.startsWith('rmnet') ||
            name.startsWith('ccmni') ||
            name.startsWith('pdp') ||
            name.startsWith('radio') ||
            name.startsWith('dummy') ||
            name.startsWith('tun');
        if (!isCellular) {
          for (final addr in iface.addresses) {
            if (!addr.isLoopback) return addr.address;
          }
        }
      }

      // 4. Fallback to any non-loopback address
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (_) {}
    return '127.0.0.1';
  }
}
