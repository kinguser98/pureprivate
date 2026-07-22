import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class WifiCastService {
  static HttpServer? _server;
  static http.Client? _client;
  static String? _targetUrl;
  static Map<String, String>? _targetHeaders;

  static bool get isRunning => _server != null;

  /// Starts a local HTTP server on the mobile device to proxy requests from the TV.
  static Future<String?> startProxyServer(String streamUrl, {Map<String, String>? headers}) async {
    await stopProxyServer();

    _targetUrl = streamUrl;
    _targetHeaders = headers;
    _client = http.Client();

    try {
      // Bind to any available port on all interfaces (port 0 selects a random free port)
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      final port = _server!.port;

      // Find local IP address
      final localIp = await _getLocalIp();
      final proxyUrl = 'http://$localIp:$port/stream';

      debugPrint('WifiCastService: Local proxy server listening at $proxyUrl');

      // Listen for TV requests in background
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
      debugPrint('WifiCastService: Failed to start proxy server: $e');
      await stopProxyServer();
      return null;
    }
  }

  static Future<void> stopProxyServer() async {
    _client?.close();
    _client = null;
    await _server?.close(force: true);
    _server = null;
    _targetUrl = null;
    _targetHeaders = null;
  }

  static Future<String> _getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback && addr.address.startsWith('192.168.')) {
            return addr.address;
          }
        }
      }
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (_) {}
    return '127.0.0.1';
  }

  static Future<void> _handleProxyRequest(HttpRequest request) async {
    if (_targetUrl == null || _client == null) {
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
      return;
    }

    try {
      final proxyReq = http.StreamedRequest(request.method, Uri.parse(_targetUrl!));
      
      // Copy incoming request headers (except host)
      request.headers.forEach((name, values) {
        if (name.toLowerCase() != 'host') {
          proxyReq.headers[name] = values.join(', ');
        }
      });

      // Add original target headers if present
      if (_targetHeaders != null) {
        proxyReq.headers.addAll(_targetHeaders!);
      }

      final response = await _client!.send(proxyReq);

      // Copy response status code & headers
      request.response.statusCode = response.statusCode;
      response.headers.forEach((name, value) {
        request.response.headers.set(name, value);
      });

      // Pipe the body stream directly to the TV client
      await response.stream.pipe(request.response);
      debugPrint('WifiCastService: Stream proxy finished.');
    } catch (e) {
      debugPrint('WifiCastService: Stream proxy error: $e');
      request.response.statusCode = HttpStatus.internalServerError;
      try {
        await request.response.close();
      } catch (_) {}
    }
  }
}
