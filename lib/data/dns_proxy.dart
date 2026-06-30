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
  HttpClient? _httpClient;

  HttpClient _getHttpClient() {
    if (_httpClient == null) {
      _httpClient = HttpClient();
      _httpClient!.connectionTimeout = const Duration(seconds: 10);
      _httpClient!.autoUncompress = false;
      _httpClient!.maxConnectionsPerHost = 100;
      _httpClient!.findProxy = (uri) => 'DIRECT';
      _httpClient!.connectionFactory = (Uri uri, String? proxyHost, int? proxyPort) async {
        final targetHost = uri.host;
        final targetPort = uri.port;
        final socket = await _connectToHost(targetHost, targetPort);
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
    }
    return _httpClient!;
  }

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
    _httpClient?.close(force: true);
    _httpClient = null;
    debugPrint('CustomDnsProxy: Stopped');
  }

  Future<String?> _getWithCleanClient(Uri uri, Map<String, String>? headers) async {
    // Save the current overrides and temporarily set HttpOverrides.global to null
    // so we can construct a clean native HttpClient without triggering recursive stack overflows.
    final oldOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    final client = HttpClient();
    HttpOverrides.global = oldOverrides; // Restore the global overrides immediately.
    
    try {
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 4));
      headers?.forEach((key, value) {
        request.headers.set(key, value);
      });
      final response = await request.close().timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        return await response.transform(utf8.decoder).join();
      }
    } catch (e) {
      debugPrint('CustomDnsProxy internal network client error: $e');
    } finally {
      client.close();
    }
    return null;
  }

  final Map<String, List<String>> _dnsCacheList = {};

  Future<List<String>> _resolveHostList(String host) async {
    if (_dnsCacheList.containsKey(host)) {
      return _dnsCacheList[host]!;
    }
    
    final List<String> ips = [];
    
    // 1. Try standard system DNS resolution first to ensure CDN edge geo-routing speed
    try {
      final list = await InternetAddress.lookup(host).timeout(const Duration(seconds: 2));
      for (final addr in list) {
        final ip = addr.address;
        if (ip != '0.0.0.0' && ip != '::' && !ip.startsWith('218.248.')) {
          ips.add(ip);
        }
      }
    } catch (_) {}

    // 2. Fallback to Cloudflare DNS over HTTPS (DoH) JSON API if blocked/failed
    if (ips.isEmpty) {
      try {
        final uri = Uri.parse('https://cloudflare-dns.com/dns-query?name=$host&type=A');
        final resBody = await _getWithCleanClient(uri, {
          'Accept': 'application/dns-json',
        });
        
        if (resBody != null) {
          final data = jsonDecode(resBody);
          final answers = data['Answer'] as List?;
          if (answers != null && answers.isNotEmpty) {
            for (final ans in answers) {
              if (ans['type'] == 1) { // Type 1 is A record
                final ip = ans['data'] as String;
                if (ip.isNotEmpty && ip != '0.0.0.0') {
                  ips.add(ip);
                }
              }
            }
          }
        }
      } catch (e) {
        debugPrint('CustomDnsProxy: Cloudflare DoH list error for $host: $e');
      }
    }

    // 3. Fallback to Google DNS over HTTPS (DoH) JSON API
    if (ips.isEmpty) {
      try {
        final uri = Uri.parse('https://dns.google/resolve?name=$host&type=A');
        final resBody = await _getWithCleanClient(uri, null);
        
        if (resBody != null) {
          final data = jsonDecode(resBody);
          final answers = data['Answer'] as List?;
          if (answers != null && answers.isNotEmpty) {
            for (final ans in answers) {
              if (ans['type'] == 1) { // Type 1 is A record
                final ip = ans['data'] as String;
                if (ip.isNotEmpty && ip != '0.0.0.0') {
                  ips.add(ip);
                }
              }
            }
          }
        }
      } catch (e) {
        debugPrint('CustomDnsProxy: Google DoH list error for $host: $e');
      }
    }

    if (ips.isNotEmpty) {
      debugPrint('CustomDnsProxy resolved $host -> $ips');
      _dnsCacheList[host] = ips;
      return ips;
    }
    throw Exception('Failed to resolve host $host via secure or system DNS.');
  }

  Future<Socket> _connectToHost(String host, int port) async {
    final ips = await _resolveHostList(host);
    Object? lastError;
    for (final ip in ips) {
      try {
        return await Socket.connect(ip, port).timeout(const Duration(seconds: 5));
      } catch (e) {
        lastError = e;
        debugPrint('CustomDnsProxy: Failed connecting to $ip:$port — trying next IP. Error: $e');
      }
    }
    throw lastError ?? Exception('Could not connect to any resolved IP for $host');
  }

  Future<String> _resolveHost(String host) async {
    final ips = await _resolveHostList(host);
    return ips.first;
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
      debugPrint('CustomDnsProxy CONNECT: Connecting TCP socket to $host:$portVal');
      targetSocket = await _connectToHost(host, portVal);
      
      debugPrint('CustomDnsProxy CONNECT: Established TCP to $host:$portVal. Detaching client socket.');
      clientSocket = await request.response.detachSocket();
      clientSocket.write('HTTP/1.1 200 Connection Established\r\nProxy-agent: CustomDnsProxy\r\n\r\n');
      await clientSocket.flush();


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
    final client = _getHttpClient();
    
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
        
        // Construct a clean target URL without the 'headers' query parameter
        String cleanTargetUrl = targetUrl;
        final Map<String, String> extraHeaders = {};
        try {
          final targetUri = Uri.parse(targetUrl);
          if (targetUri.queryParameters.containsKey('headers')) {
            final headersParam = targetUri.queryParameters['headers'];
            if (headersParam != null && headersParam.isNotEmpty) {
              final decodedJson = jsonDecode(headersParam);
              if (decodedJson is Map) {
                decodedJson.forEach((key, value) {
                  extraHeaders[key.toString()] = value.toString();
                });
              }
            }
            final cleanParams = Map<String, String>.from(targetUri.queryParameters);
            cleanParams.remove('headers');
            if (cleanParams.isEmpty) {
              cleanTargetUrl = targetUri.replace(query: '').toString();
              if (cleanTargetUrl.endsWith('?')) {
                cleanTargetUrl = cleanTargetUrl.substring(0, cleanTargetUrl.length - 1);
              }
            } else {
              cleanTargetUrl = targetUri.replace(queryParameters: cleanParams).toString();
            }
          }
        } catch (e) {
          debugPrint('CustomDnsProxy: Error extracting query headers: $e');
        }
        
        debugPrint('CustomDnsProxy HTTP Relay: Fetching $cleanTargetUrl with retry loop');
        
        HttpClientResponse? resp;
        Object? lastError;
        for (int attempt = 0; attempt < 3; attempt++) {
          try {
            final req = await client.openUrl(request.method, Uri.parse(cleanTargetUrl))
                .timeout(const Duration(seconds: 8));
            req.followRedirects = false;
            
            // Copy headers, inject Host, enforce Connection: close
            request.headers.forEach((name, values) {
              final nameLower = name.toLowerCase();
              if (nameLower != 'host' && nameLower != 'connection' && nameLower != 'keep-alive' && nameLower != 'user-agent') {
                for (final value in values) {
                  req.headers.add(name, value);
                }
              }
            });
            req.headers.set('Host', targetHostRaw);
            req.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');

            // Apply extracted query parameter headers
            extraHeaders.forEach((key, value) {
              final keyLower = key.toLowerCase();
              if (keyLower == 'referer') {
                req.headers.set('Referer', value);
              } else if (keyLower == 'origin') {
                req.headers.set('Origin', value);
              } else {
                req.headers.set(key, value);
              }
            });

            // Auto-inject VidLink headers for VidLink CDNs (applies to both playlists and absolute segment chunks)
            final targetHostLower = targetHost.toLowerCase();
            if (targetHostLower.contains('vodvidl.site') || targetHostLower.contains('ironwallnet.com')) {
              req.headers.set('Referer', 'https://vidlink.pro/');
              req.headers.set('Origin', 'https://vidlink.pro');
            }
            
            if (request.contentLength > 0 || request.headers.value('transfer-encoding') == 'chunked') {
              await req.addStream(request);
            }
            
            resp = await req.close().timeout(const Duration(seconds: 8));
            debugPrint('CustomDnsProxy HTTP Relay: Target returned status ${resp.statusCode} for $cleanTargetUrl');
            break;
          } catch (e) {
            lastError = e;
            debugPrint('CustomDnsProxy: Fetch attempt ${attempt + 1} failed for $cleanTargetUrl: $e');
            if (attempt < 2) {
              await Future.delayed(const Duration(milliseconds: 300));
            }
          }
        }
        
        if (resp == null) {
          throw lastError ?? Exception('Failed to fetch after retries');
        }
        request.response.statusCode = resp.statusCode;
        
        resp.headers.forEach((name, values) {
          final nameLower = name.toLowerCase();
          if (nameLower == 'location') {
            for (final value in values) {
              try {
                final locUri = Uri.parse(value);
                final hostWithPort = locUri.hasPort ? '${locUri.host}:${locUri.port}' : locUri.host;
                final proxyRedirect = 'http://127.0.0.1:$port/proxy/${locUri.scheme}/$hostWithPort${locUri.path}${locUri.hasQuery ? "?" + locUri.query : ""}';
                request.response.headers.set('location', proxyRedirect);
                debugPrint('CustomDnsProxy: Rewrote redirect location: $proxyRedirect');
              } catch (_) {
                request.response.headers.add(name, value);
              }
            }
          } else if (nameLower != 'connection' && nameLower != 'keep-alive' && nameLower != 'transfer-encoding') {
            for (final value in values) {
              request.response.headers.add(name, value);
            }
          }
        });
        
        // If it's HLS playlist, rewrite absolute and relative stream URLs to go through our proxy
        if (targetUrl.contains('.m3u8')) {
          final bodyBytes = await resp.fold<List<int>>([], (p, e) => p..addAll(e));
          final contentEncoding = resp.headers.value('content-encoding')?.toLowerCase() ?? '';
          List<int> decodedBytes;
          if (contentEncoding.contains('gzip')) {
            try {
              decodedBytes = gzip.decode(bodyBytes);
            } catch (e) {
              debugPrint('CustomDnsProxy: Error decompressing GZIP body: $e');
              decodedBytes = bodyBytes;
            }
          } else {
            decodedBytes = bodyBytes;
          }
          
          var bodyStr = utf8.decode(decodedBytes);
          final incomingHeadersParam = request.uri.queryParameters['headers'];
          final selectedAudio = request.uri.queryParameters['selected_audio'];
          
          // Parse and rewrite HLS playlist line by line to resolve and proxy all links (playlists, keys, and segments)
          final lines = bodyStr.split('\n');
          final baseUri = Uri.parse(cleanTargetUrl);
          
          for (int i = 0; i < lines.length; i++) {
            var line = lines[i].trim();
            if (line.isEmpty) continue;
            
            if (line.startsWith('#')) {
              // Handle EXT-X-MEDIA audio track preference rewriting
              if (selectedAudio != null && selectedAudio.isNotEmpty && line.startsWith('#EXT-X-MEDIA:TYPE=AUDIO')) {
                final isSelected = line.contains('NAME="$selectedAudio"') || 
                                   line.contains('LANGUAGE="${selectedAudio.toLowerCase()}"') ||
                                   line.contains('LANGUAGE="$selectedAudio"');
                
                // Clean existing DEFAULT/AUTOSELECT attributes first to avoid duplicates
                line = line
                    .replaceAll(RegExp(r',?DEFAULT=(YES|NO)', caseSensitive: false), '')
                    .replaceAll(RegExp(r',?AUTOSELECT=(YES|NO)', caseSensitive: false), '');
                
                if (isSelected) {
                  line += ',DEFAULT=YES,AUTOSELECT=YES';
                } else {
                  line += ',DEFAULT=NO,AUTOSELECT=NO';
                }
              }
              
              // Parse URI attribute if present (e.g. URI="...")
              if (line.contains('URI="')) {
                final uriMatch = RegExp(r'URI="([^"]+)"').firstMatch(line);
                if (uriMatch != null) {
                  final relativeUrl = uriMatch.group(1)!;
                  if (!relativeUrl.contains('127.0.0.1') && !relativeUrl.contains('localhost')) {
                    try {
                      final resolvedUri = baseUri.resolve(relativeUrl);
                      final hostWithPort = resolvedUri.hasPort ? '${resolvedUri.host}:${resolvedUri.port}' : resolvedUri.host;
                      
                      var rewrittenUri = resolvedUri;
                      if (incomingHeadersParam != null && incomingHeadersParam.isNotEmpty) {
                        final newParams = Map<String, String>.from(resolvedUri.queryParameters);
                        newParams['headers'] = incomingHeadersParam;
                        rewrittenUri = resolvedUri.replace(queryParameters: newParams);
                      }
                      
                      final proxyUrl = 'http://127.0.0.1:$port/proxy/${rewrittenUri.scheme}/$hostWithPort${rewrittenUri.path}${rewrittenUri.hasQuery ? "?" + rewrittenUri.query : ""}';
                      lines[i] = line.replaceFirst('URI="$relativeUrl"', 'URI="$proxyUrl"');
                    } catch (_) {}
                  }
                }
              }
            } else {
              // Line is a direct playlist or segment URL
              if (!line.contains('127.0.0.1') && !line.contains('localhost')) {
                try {
                  final resolvedUri = baseUri.resolve(line);
                  final hostWithPort = resolvedUri.hasPort ? '${resolvedUri.host}:${resolvedUri.port}' : resolvedUri.host;
                  
                  var rewrittenUri = resolvedUri;
                  if (incomingHeadersParam != null && incomingHeadersParam.isNotEmpty) {
                    final newParams = Map<String, String>.from(resolvedUri.queryParameters);
                    newParams['headers'] = incomingHeadersParam;
                    rewrittenUri = resolvedUri.replace(queryParameters: newParams);
                  }
                  
                  final proxyUrl = 'http://127.0.0.1:$port/proxy/${rewrittenUri.scheme}/$hostWithPort${rewrittenUri.path}${rewrittenUri.hasQuery ? "?" + rewrittenUri.query : ""}';
                  lines[i] = proxyUrl;
                } catch (_) {}
              }
            }
          }
          bodyStr = lines.join('\n');
          
          request.response.headers.removeAll('content-encoding');
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
      // Do not close client here, let connection pool be kept-alive
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

  static List<String> blocklist = [
    'remoteconsultinggroup',
    'streamimdb',
    'vidsrc',
    'vidlink',
    'streamtape',
    'strcloud',
    'tpead.net',
    'vodvidl.site',
    'ironwallnet.com',
    'hakunamatata',
  ];

  @override
  String findProxyFromEnvironment(Uri uri, Map<String, String>? environment) {
    final host = uri.host.toLowerCase();
    for (final pattern in blocklist) {
      if (host.contains(pattern)) {
        return 'PROXY 127.0.0.1:$port';
      }
    }
    return 'DIRECT';
  }
}
