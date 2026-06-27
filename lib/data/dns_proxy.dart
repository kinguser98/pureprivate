import 'dart:convert';
import 'dart:io';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class CustomDnsProxy {
  static final CustomDnsProxy _instance = CustomDnsProxy._internal();
  factory CustomDnsProxy() => _instance;
  CustomDnsProxy._internal();

  HttpServer? _server;
  int? port;
  final Map<String, String> _dnsCache = {};

  Future<void> start() async {
    if (_server != null) return;

    try {
      // Bind to localhost on a random available port
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      port = _server!.port;
      debugPrint('CustomDnsProxy: Started local proxy on port $port');

      _server!.listen((HttpRequest request) async {
        debugPrint('CustomDnsProxy: Incoming request ${request.method} ${request.uri.toString()}');
        if (request.method == 'CONNECT') {
          await _handleConnect(request);
        } else {
          await _handleHttp(request);
        }
      }, onError: (e) {
        debugPrint('CustomDnsProxy server level error: $e');
      });
    } catch (e) {
      debugPrint('CustomDnsProxy failed to start: $e');
    }
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    port = null;
    debugPrint('CustomDnsProxy: Stopped');
  }

  Future<String> _resolveHost(String host) async {
    if (_dnsCache.containsKey(host)) {
      return _dnsCache[host]!;
    }

    // 1. Try Cloudflare DNS over HTTPS (DoH) JSON API first
    try {
      final uri = Uri.parse('https://1.1.1.1/dns-query?name=$host&type=A');
      final res = await http.get(uri, headers: {
        'Accept': 'application/dns-json',
      }).timeout(const Duration(seconds: 4));
      
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final answers = data['Answer'] as List?;
        if (answers != null && answers.isNotEmpty) {
          for (final ans in answers) {
            if (ans['type'] == 1) { // Type 1 is A record
              final ip = ans['data'] as String;
              if (ip.isNotEmpty && ip != '0.0.0.0') {
                debugPrint('CustomDnsProxy: Cloudflare DoH resolved $host -> $ip');
                _dnsCache[host] = ip;
                return ip;
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('CustomDnsProxy: Cloudflare DoH error for $host: $e');
    }

    // 2. Try Google DNS over HTTPS (DoH) JSON API
    try {
      final uri = Uri.parse('https://8.8.8.8/resolve?name=$host&type=A');
      final res = await http.get(uri).timeout(const Duration(seconds: 4));
      
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final answers = data['Answer'] as List?;
        if (answers != null && answers.isNotEmpty) {
          for (final ans in answers) {
            if (ans['type'] == 1) { // Type 1 is A record
              final ip = ans['data'] as String;
              if (ip.isNotEmpty && ip != '0.0.0.0') {
                debugPrint('CustomDnsProxy: Google DoH resolved $host -> $ip');
                _dnsCache[host] = ip;
                return ip;
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('CustomDnsProxy: Google DoH error for $host: $e');
    }

    // 3. Fallback to standard system DNS resolution only as a last resort
    try {
      final list = await InternetAddress.lookup(host);
      if (list.isNotEmpty) {
        final ip = list.first.address;
        if (ip != '0.0.0.0' && ip != '::' && !ip.startsWith('218.248.')) {
          _dnsCache[host] = ip;
          return ip;
        }
      }
    } catch (_) {}

    throw Exception('Failed to resolve host $host via system or secure DNS overrides.');
  }

  Future<String> resolveHostForNative(String host) async {
    try {
      return await _resolveHost(host);
    } catch (e) {
      debugPrint('CustomDnsProxy resolveHostForNative error for $host: $e');
      return host;
    }
  }

  Future<void> _handleConnect(HttpRequest request) async {
    var authority = '';
    final uriStr = request.uri.toString();
    if (request.uri.host.isNotEmpty) {
      authority = request.uri.authority;
    } else if (uriStr.contains(':')) {
      authority = uriStr;
    } else {
      authority = request.headers.value('host') ?? '';
    }
    
    if (authority.isEmpty) {
      debugPrint('CustomDnsProxy CONNECT error: Authority/Host is empty');
      request.response.statusCode = 400;
      request.response.write('Bad Request: Missing Host');
      await request.response.close();
      return;
    }

    final parts = authority.split(':');
    final host = parts[0];
    final portVal = parts.length > 1 ? int.parse(parts[1]) : 443;

    // Prevent loop: do not connect to the proxy port on localhost/127.0.0.1
    if ((host == '127.0.0.1' || host == 'localhost') && portVal == port) {
      debugPrint('CustomDnsProxy CONNECT error: Loop detected trying to connect back to proxy itself at $authority');
      request.response.statusCode = 400;
      request.response.write('Bad Request: Loop Detected');
      await request.response.close();
      return;
    }

    debugPrint('CustomDnsProxy: Incoming CONNECT tunnel request for $authority');

    Socket? targetSocket;
    Socket? clientSocket;

    try {
      debugPrint('CustomDnsProxy CONNECT: Resolving host $host');
      final ip = await _resolveHost(host);
      debugPrint('CustomDnsProxy CONNECT: Connecting TCP socket to $ip:$portVal');
      targetSocket = await Socket.connect(ip, portVal, timeout: const Duration(seconds: 10));
      
      debugPrint('CustomDnsProxy CONNECT: Established TCP to $ip:$portVal. Detaching client socket.');
      clientSocket = await request.response.detachSocket();
      clientSocket.write('HTTP/1.1 200 Connection Established\r\nProxy-agent: CustomDnsProxy\r\n\r\n');
      await clientSocket.flush();

      debugPrint('CustomDnsProxy CONNECT: Piping bi-directional tunnel between client and $ip:$portVal');
      // Setup bi-directional tunnel piping
      clientSocket.listen(
        (data) {
          try {
            targetSocket?.add(data);
          } catch (_) {
            _cleanup(clientSocket, targetSocket);
          }
        },
        onDone: () {
          debugPrint('CustomDnsProxy CONNECT: Client socket closed for $authority');
          _cleanup(clientSocket, targetSocket);
        },
        onError: (e) {
          debugPrint('CustomDnsProxy CONNECT: Client socket error for $authority: $e');
          _cleanup(clientSocket, targetSocket);
        },
        cancelOnError: true,
      );

      targetSocket.listen(
        (data) {
          try {
            clientSocket?.add(data);
          } catch (_) {
            _cleanup(clientSocket, targetSocket);
          }
        },
        onDone: () {
          debugPrint('CustomDnsProxy CONNECT: Target socket closed for $authority');
          _cleanup(clientSocket, targetSocket);
        },
        onError: (e) {
          debugPrint('CustomDnsProxy CONNECT: Target socket error for $authority: $e');
          _cleanup(clientSocket, targetSocket);
        },
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('CustomDnsProxy CONNECT tunnel error for $authority: $e');
      try {
        request.response.statusCode = 502;
        request.response.write('Bad Gateway: $e');
        await request.response.close();
      } catch (_) {}
      _cleanup(clientSocket, targetSocket);
    }
  }

  Future<void> _handleHttp(HttpRequest request) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    client.autoUncompress = false;
    client.findProxy = (uri) => 'DIRECT';
    client.connectionFactory = (Uri uri, String? proxyHost, int? proxyPort) async {
      final targetHost = uri.host;
      final targetPort = uri.port;
      final ip = await _resolveHost(targetHost);
      final socket = await Socket.connect(ip, targetPort).timeout(const Duration(seconds: 8));
      if (uri.scheme == 'https') {
        final secureSocket = await SecureSocket.secure(
          socket,
          host: targetHost,
          context: SecurityContext.defaultContext,
          onBadCertificate: (cert) => true,
        );
        return ConnectionTask.fromSocket(Future.value(secureSocket), () {});
      }
      return ConnectionTask.fromSocket(Future.value(socket), () {});
    };
    
    try {
      final pathSegments = request.uri.pathSegments;
      if (pathSegments.length >= 3 && pathSegments[0] == 'proxy') {
        final targetScheme = pathSegments[1];
        final targetHostRaw = pathSegments[2];
        final hostParts = targetHostRaw.split(':');
        final targetHost = hostParts[0];
        final targetPort = hostParts.length > 1 ? int.parse(hostParts[1]) : (targetScheme == 'https' ? 443 : 80);
        final remainingPath = '/' + pathSegments.sublist(3).join('/');
        final query = request.uri.hasQuery ? '?' + request.uri.query : '';
        final targetUrl = '$targetScheme://$targetHostRaw$remainingPath$query';
        
        debugPrint('CustomDnsProxy HTTP Relay: Fetching $targetUrl');
        
        final req = await client.openUrl(request.method, Uri.parse(targetUrl));
        req.followRedirects = false;
        
        // Copy headers, inject Host
        request.headers.forEach((name, values) {
          final nameLower = name.toLowerCase();
          if (nameLower != 'host' && nameLower != 'connection' && nameLower != 'keep-alive') {
            for (final value in values) {
              req.headers.add(name, value);
            }
          }
        });
        req.headers.set('Host', targetHostRaw);
        
        if (request.contentLength > 0 || request.headers.value('transfer-encoding') == 'chunked') {
          await req.addStream(request);
        }
        
        final resp = await req.close();
        request.response.statusCode = resp.statusCode;
        
        resp.headers.forEach((name, values) {
          final nameLower = name.toLowerCase();
          if (nameLower != 'connection' && nameLower != 'keep-alive' && nameLower != 'transfer-encoding') {
            for (final value in values) {
              request.response.headers.add(name, value);
            }
          }
        });
        
        // If it's HLS playlist, rewrite absolute stream URLs to go through our proxy
        if (targetUrl.contains('.m3u8')) {
          final bodyBytes = await resp.fold<List<int>>([], (p, e) => p..addAll(e));
          var bodyStr = utf8.decode(bodyBytes);
          
          final urlRegExp = RegExp(r'(https?://[^\s"\r\n]+)');
          bodyStr = bodyStr.replaceAllMapped(urlRegExp, (match) {
            final absoluteUrl = match.group(1)!;
            if (absoluteUrl.contains('127.0.0.1') || absoluteUrl.contains('localhost')) {
              return absoluteUrl;
            }
            try {
              final absUri = Uri.parse(absoluteUrl);
              final hostWithPort = absUri.hasPort ? '${absUri.host}:${absUri.port}' : absUri.host;
              return 'http://127.0.0.1:$port/proxy/${absUri.scheme}/$hostWithPort${absUri.path}${absUri.hasQuery ? "?" + absUri.query : ""}';
            } catch (_) {
              return absoluteUrl;
            }
          });
          
          final rewrittenBytes = utf8.encode(bodyStr);
          request.response.headers.set('content-length', rewrittenBytes.length.toString());
          request.response.add(rewrittenBytes);
        } else {
          await request.response.addStream(resp);
        }
        
        await request.response.close();
        return;
      }

      var host = request.uri.host;
      if (host.isEmpty) {
        final hostHeader = request.headers.value('host') ?? '';
        host = hostHeader.split(':')[0];
      }
      
      if (host.isEmpty) {
        debugPrint('CustomDnsProxy HTTP error: Host header is empty');
        request.response.statusCode = 400;
        request.response.write('Bad Request: Missing Host');
        await request.response.close();
        return;
      }

      // Prevent loop: do not proxy HTTP requests back to the proxy port on localhost/127.0.0.1
      final targetPort = request.uri.port == 0 ? 80 : request.uri.port;
      if ((host == '127.0.0.1' || host == 'localhost') && targetPort == port) {
        debugPrint('CustomDnsProxy HTTP error: Loop detected trying to proxy HTTP request to itself: ${request.uri}');
        request.response.statusCode = 400;
        request.response.write('Bad Request: Loop Detected');
        await request.response.close();
        return;
      }

      debugPrint('CustomDnsProxy: Resolving host $host');
      final ip = await _resolveHost(host);
      final resolvedUri = request.uri.replace(host: ip);
      debugPrint('CustomDnsProxy: Forwarding ${request.method} to $resolvedUri (Host: $host)');

      final req = await client.openUrl(request.method, resolvedUri);
      req.followRedirects = false;
      
      // Standard hop-by-hop headers to strip to avoid connection reset and transfer encoding issues
      const hopByHopHeaders = [
        'connection',
        'keep-alive',
        'proxy-authenticate',
        'proxy-authorization',
        'te',
        'trailers',
        'transfer-encoding',
        'upgrade',
      ];

      // Copy all headers except host and hop-by-hop headers
      request.headers.forEach((name, values) {
        final nameLower = name.toLowerCase();
        if (nameLower != 'host' && !hopByHopHeaders.contains(nameLower)) {
          for (final value in values) {
            req.headers.add(name, value);
          }
        }
      });
      req.headers.set('Host', host);

      // Copy request body only if request has content
      if (request.contentLength > 0 || request.headers.value('transfer-encoding') == 'chunked') {
        debugPrint('CustomDnsProxy: Copying body stream (contentLength: ${request.contentLength})');
        await req.addStream(request);
      }
      debugPrint('CustomDnsProxy: Closing request stream to backend');
      final resp = await req.close();

      debugPrint('CustomDnsProxy: Received response status: ${resp.statusCode}');
      request.response.statusCode = resp.statusCode;
      
      // Copy response headers, excluding hop-by-hop headers
      resp.headers.forEach((name, values) {
        final nameLower = name.toLowerCase();
        if (!hopByHopHeaders.contains(nameLower)) {
          for (final value in values) {
            request.response.headers.add(name, value);
          }
        }
      });

      debugPrint('CustomDnsProxy: Piping response stream back to client');
      await request.response.addStream(resp);
      await request.response.close();
      debugPrint('CustomDnsProxy: Completed HTTP transaction successfully');
    } catch (e) {
      debugPrint('CustomDnsProxy HTTP error: $e');
      try {
        request.response.statusCode = 502;
        request.response.write('Bad Gateway: $e');
        await request.response.close();
      } catch (_) {}
    } finally {
      client.close();
    }
  }

  void _cleanup(Socket? s1, Socket? s2) {
    try {
      s1?.close();
    } catch (_) {}
    try {
      s2?.close();
    } catch (_) {}
  }
}

class MyHttpOverrides extends HttpOverrides {
  final int port;
  MyHttpOverrides(this.port);

  @override
  String findProxyFromEnvironment(Uri uri, Map<String, String>? environment) {
    final host = uri.host.toLowerCase();
    if (host.contains('remoteconsultinggroup') ||
        host.contains('streamimdb') ||
        host.contains('vidsrc')) {
      return 'PROXY 127.0.0.1:$port';
    }
    return 'DIRECT';
  }
}
