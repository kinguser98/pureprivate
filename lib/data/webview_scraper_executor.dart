import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dns_proxy.dart';
import '../widgets/special_search_dialog.dart';
import 'crypto_js_source.dart';

class WebViewScraperExecutor {
  static HeadlessInAppWebView? _headlessWebView;
  static InAppWebViewController? _webViewController;
  static final Map<String, Completer<List<dynamic>>> _pendingRequests = {};
  static final Map<String, Completer<Map<String, dynamic>>> _pendingFetches = {};
  static int _requestId = 0;
  static bool _initialized = false;

  /// Initializes the headless webview and registers JS callback handlers
  static Future<void> ensureInitialized() async {
    if (_initialized) return;

    final completer = Completer<void>();
    _headlessWebView = HeadlessInAppWebView(
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        domStorageEnabled: true,
        databaseEnabled: true,
        allowFileAccessFromFileURLs: true,
        allowUniversalAccessFromFileURLs: true,
        mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
      ),
      onWebViewCreated: (controller) async {
        _webViewController = controller;
        
        // Scraper result callback
        controller.addJavaScriptHandler(
          handlerName: 'onScraperResult',
          callback: (args) {
            if (args.length >= 2) {
              final reqId = args[0].toString();
              final result = args[1];
              final error = args.length >= 3 ? args[2] : null;

              final reqCompleter = _pendingRequests.remove(reqId);
              if (reqCompleter != null) {
                if (error != null) {
                  reqCompleter.completeError(error);
                } else {
                  reqCompleter.complete(result as List<dynamic>);
                }
              }
            }
          },
        );

        // Fetch proxy callback
        controller.addJavaScriptHandler(
          handlerName: 'onFetchRequest',
          callback: (args) async {
            if (args.length >= 2) {
              final reqId = args[0].toString();
              final url = args[1].toString();
              final options = args.length >= 3 ? args[2] as Map? : null;

              _executeNativeFetch(controller, reqId, url, options);
            }
          },
        );

        // Load dummy HTML document to trigger injection of window.flutter_inappwebview
        await controller.loadData(data: "<html><head><script></script></head><body></body></html>");
      },
      onLoadStop: (controller, url) {
        if (!completer.isCompleted) {
          completer.complete();
        }
      },
      onConsoleMessage: (controller, consoleMessage) {
        debugPrint('WebViewScraperExecutor JS Console: [${consoleMessage.messageLevel}] ${consoleMessage.message}');
      },
    );

    await _headlessWebView!.run();
    await completer.future;
    _initialized = true;
    debugPrint('WebViewScraperExecutor: Headless Webview Initialized successfully');
  }

  /// Executes native fetch request on behalf of the webview to bypass CORS completely
  static Future<void> _executeNativeFetch(
    InAppWebViewController controller,
    String reqId,
    String url,
    Map? options,
  ) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);
    client.badCertificateCallback = (cert, host, port) => true;
    client.connectionFactory = (Uri uri, String? proxyHost, int? proxyPort) async {
      final targetHost = uri.host;
      final targetPort = uri.port;
      final resolvedHost = await CustomDnsProxy().resolveHostForNative(targetHost);
      final socket = await Socket.connect(resolvedHost, targetPort).timeout(const Duration(seconds: 10));
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
      final method = options?['method']?.toString() ?? 'GET';
      final Uri uri = Uri.parse(url);
      final req = await client.openUrl(method, uri);

      // Disable redirects following if configured in options
      req.followRedirects = options?['followRedirects'] != false;

      // Copy headers
      bool hasUserAgent = false;
      if (options?['headers'] is Map) {
        (options!['headers'] as Map).forEach((k, v) {
          final keyStr = k.toString();
          if (keyStr.toLowerCase() == 'user-agent') {
            hasUserAgent = true;
          }
          req.headers.set(keyStr, v.toString());
        });
      }

      if (!hasUserAgent) {
        req.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
      }

      // Copy body
      if (options?['body'] != null) {
        req.write(options!['body']);
      }

      final res = await req.close().timeout(const Duration(seconds: 12));
      final body = await res.transform(utf8.decoder).join();

      final Map<String, String> resHeaders = {};
      res.headers.forEach((name, values) {
        resHeaders[name.toLowerCase()] = values.join(', ');
      });

      final jsCall = """
        if (window.onFetchResponse) {
          window.onFetchResponse(
            "$reqId", 
            ${res.statusCode}, 
            ${jsonEncode(body)}, 
            ${jsonEncode(resHeaders)}
          );
        }
      """;
      await controller.evaluateJavascript(source: jsCall);
    } catch (e) {
      debugPrint('WebViewScraperExecutor native fetch failed for $url: $e');
      final jsCall = """
        if (window.onFetchResponse) {
          window.onFetchResponse("$reqId", 500, "", {}, "${e.toString()}");
        }
      """;
      await controller.evaluateJavascript(source: jsCall);
    } finally {
      client.close();
    }
  }

  /// Gets crypto-js library (fully bundled offline asset)
  static Future<String> _getCryptoJs() async {
    return CryptoJSAsset.source;
  }

  /// Fetches the latest JS provider script from yoruix repo (caches locally in SharedPreferences)
  static Future<String> _getProviderScript(String providerName) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'scraper_js_$providerName';
    final cachedScript = prefs.getString(cacheKey);
    
    try {
      final url = 'https://raw.githubusercontent.com/yoruix/nuvio-providers/refs/heads/main/providers/$providerName.js';
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final script = res.body;
        if (script.isNotEmpty) {
          await prefs.setString(cacheKey, script);
          return script;
        }
      }
    } catch (e) {
      debugPrint('WebViewScraperExecutor: Failed to fetch fresh script for $providerName: $e');
    }

    if (cachedScript != null && cachedScript.isNotEmpty) {
      return cachedScript;
    }
    
    throw Exception('Scraper script $providerName not available');
  }

  /// Runs getStreams for a given scraper
  static Future<List<StreamSourceInfo>> runScraper(
    String providerName,
    String tmdbId,
    String mediaType, {
    int? season,
    int? episode,
  }) async {
    try {
      await ensureInitialized();

      final script = await _getProviderScript(providerName);
      final cryptoJs = await _getCryptoJs();
      final reqId = 'req_${_requestId++}';
      final completer = Completer<List<dynamic>>();
      _pendingRequests[reqId] = completer;

      // We inject the DOMParser-based Cheerio mock and native fetch overrides
      final executionJs = """
        (async function() {
          try {
            // Setup global module/exports compatibility mock for CommonJS
            window.global = window;
            if (typeof module === 'undefined') {
              window.module = { exports: {} };
            }
            if (typeof exports === 'undefined') {
              window.exports = window.module.exports;
            }
            
            // Native fetch proxy setup
            window._fetchCompleters = {};
            window.fetch = function(url, options) {
              return new Promise((resolve, reject) => {
                const reqId = 'fetch_' + Math.random() + '_' + Date.now();
                window._fetchCompleters[reqId] = { resolve, reject };

                let headers = {};
                if (options && options.headers) {
                  if (options.headers.forEach) {
                    options.headers.forEach((v, k) => { headers[k] = v; });
                  } else {
                    headers = options.headers;
                  }
                }

                const cleanOptions = {
                  method: (options && options.method) || 'GET',
                  headers: headers,
                  body: (options && options.body) || null,
                  followRedirects: (options && options.redirect !== 'manual')
                };

                window.flutter_inappwebview.callHandler('onFetchRequest', reqId, url.toString(), cleanOptions);
              });
            };

            window.onFetchResponse = function(reqId, status, body, headers, error) {
              const completer = window._fetchCompleters[reqId];
              if (completer) {
                delete window._fetchCompleters[reqId];
                if (error) {
                  completer.reject(new Error(error));
                  return;
                }

                completer.resolve({
                  status: status,
                  ok: status >= 200 && status < 300,
                  headers: {
                    get: function(name) { return headers[name.toLowerCase()] || null; }
                  },
                  text: function() { return Promise.resolve(body); },
                  json: function() { return Promise.resolve(JSON.parse(body)); }
                });
              }
            };
            
            // Cheerio mock using native browser DOMParser
            window.cheerio = {
              load: function(htmlText) {
                const parser = new DOMParser();
                const doc = parser.parseFromString(htmlText, 'text/html');
                
                const selectorFn = function(selector) {
                  if (selector === 'html') {
                    return {
                      html: function() { return htmlText; }
                    };
                  }
                  
                  let elements = [];
                  if (typeof selector === 'string') {
                    elements = Array.from(doc.querySelectorAll(selector));
                  } else if (selector && selector.tagName) {
                    elements = [selector];
                  } else if (Array.isArray(selector)) {
                    elements = selector;
                  }
                  
                  elements.attr = function(name) {
                    if (elements.length > 0) {
                      if (name === 'href') {
                        const hrefVal = elements[0].getAttribute('href') || elements[0].href;
                        // Return normalized absolute or relative value
                        return hrefVal;
                      }
                      return elements[0].getAttribute(name);
                    }
                    return null;
                  };
                  
                  elements.each = function(callback) {
                    elements.forEach((el, index) => {
                      callback.call(el, index, el);
                    });
                    return elements;
                  };
                  
                  elements.text = function() {
                    return elements.map(el => el.textContent).join(' ');
                  };
                  
                  elements.find = function(subSelector) {
                    const found = [];
                    elements.forEach(el => {
                      found.push(...Array.from(el.querySelectorAll(subSelector)));
                    });
                    return selectorFn(found);
                  };
                  
                  elements.toArray = function() {
                    return elements;
                  };
                  
                  return elements;
                };
                
                selectorFn.html = function() { return htmlText; };
                return selectorFn;
              }
            };

            // Inject crypto-js library
            if (typeof CryptoJS === 'undefined' && `${cryptoJs}`.length > 0) {
              const cryptoScript = document.createElement('script');
              cryptoScript.textContent = `${cryptoJs}`;
              document.head.appendChild(cryptoScript);
            }

            // CommonJS Require Mock
            window.require = function(pkg) {
              if (pkg.includes('cheerio')) return window.cheerio;
              if (pkg.includes('crypto-js')) return window.CryptoJS;
              return {};
            };

            // Evaluate the provider JS code
            ${script}

            // Resolve getStreams
            const getStreamsFn = window.getStreams || (window.module && window.module.exports && window.module.exports.getStreams);
            if (!getStreamsFn) {
              throw new Error("getStreams function not found in script");
            }

            const result = await getStreamsFn(
              "$tmdbId", 
              "$mediaType", 
              ${season != null ? season : 'null'}, 
              ${episode != null ? episode : 'null'}
            );
            
            window.flutter_inappwebview.callHandler('onScraperResult', "$reqId", result);
          } catch (e) {
            window.flutter_inappwebview.callHandler('onScraperResult', "$reqId", null, e.toString());
          }
        })();
      """;

      await _webViewController!.evaluateJavascript(source: executionJs);
      final List<dynamic> rawList = await completer.future.timeout(const Duration(seconds: 25));
      final List<StreamSourceInfo> sources = [];

      for (final rawItem in rawList) {
        if (rawItem is Map) {
          final name = rawItem['name']?.toString() ?? 'Server Link';
          final url = rawItem['url']?.toString() ?? '';
          
          if (url.isNotEmpty) {
            final Map<String, String> headers = {};
            if (rawItem['headers'] is Map) {
              (rawItem['headers'] as Map).forEach((k, v) {
                headers[k.toString()] = v.toString();
              });
            }

            // Encode headers into url query parameters
            var finalUrl = url;
            if (headers.isNotEmpty) {
              finalUrl = Uri.parse(url).replace(queryParameters: {
                ...Uri.parse(url).queryParameters,
                'headers': jsonEncode(headers)
              }).toString();
            }

            sources.add(StreamSourceInfo(
              name: name,
              url: finalUrl,
              type: _getScraperSourceType(providerName),
            ));
          }
        }
      }

      return sources;
    } catch (e) {
      debugPrint('WebViewScraperExecutor error for $providerName: $e');
      return [];
    }
  }

  static StreamSourceType _getScraperSourceType(String providerName) {
    switch (providerName) {
      case 'dvdplay':
        return StreamSourceType.dvdplay;
      case 'mallumv':
        return StreamSourceType.mallumv;
      case 'vidnest':
        return StreamSourceType.vidnest;
      case 'hdhub4u':
        return StreamSourceType.hdhub4u;
      case 'castle':
        return StreamSourceType.castle;
      default:
        return StreamSourceType.netmirror;
    }
  }
}
