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
import 'stremio_addon_resolver.dart';

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

  /// Clears all cached scraper scripts forcing re-download on next use
  static Future<void> clearScriptCache() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith('scraper_js_'));
    for (final key in keys) {
      await prefs.remove(key);
    }
    debugPrint('WebViewScraperExecutor: Cleared all scraper script caches');
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
            // Setup local module/exports compatibility mock for CommonJS to prevent concurrency override
            window.global = window;
            const module = { exports: {} };
            const exports = module.exports;
            
            // Native fetch proxy setup (preserve existing completers across concurrent scrapers)
            window._fetchCompleters = window._fetchCompleters || {};
            window.fetch = window.fetch || function(url, options) {
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

            window.onFetchResponse = window.onFetchResponse || function(reqId, status, body, headers, error) {
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
            window.require = window.require || function(pkg) {
              if (pkg.includes('cheerio')) return window.cheerio;
              if (pkg.includes('crypto-js')) return window.CryptoJS;
              return {};
            };

            // Evaluate the provider JS code
            ${script}

            // Resolve getStreams (prioritize local module exports to avoid concurrent cross-provider overwrites)
            const getStreamsFn = module.exports.getStreams || window.getStreams || (window.module && window.module.exports && window.module.exports.getStreams);
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

  /// Runs getStreams for a dynamic scraper by URL
  static Future<List<StreamSourceInfo>> runDynamicScraper({
    required String scraperId,
    required String scraperName,
    required String scriptUrl,
    required String tmdbId,
    required String mediaType,
    int? season,
    int? episode,
    String? title,
    String? imdbId,
    String? releaseDate,
  }) async {
    try {
      await ensureInitialized();

      final script = await _getDynamicProviderScript(scriptUrl);
      final cryptoJs = await _getCryptoJs();
      final reqId = 'req_${_requestId++}';
      final completer = Completer<List<dynamic>>();
      _pendingRequests[reqId] = completer;

      // We inject the DOMParser-based Cheerio mock and native fetch overrides
      final executionJs = """
        (async function() {
          try {
            // Setup local module/exports compatibility mock for CommonJS to prevent concurrency override
            window.global = window;
            const module = { exports: {} };
            const exports = module.exports;
            
            // Native fetch proxy setup (preserve existing completers across concurrent scrapers)
            window._fetchCompleters = window._fetchCompleters || {};
            window.fetch = window.fetch || function(url, options) {
              const urlStr = url.toString();
              if (urlStr.includes('themoviedb.org/3/') && ${title != null && title.isNotEmpty}) {
                console.log("[WebViewScraperExecutor] Intercepted TMDB fetch request for " + urlStr);
                const isTv = urlStr.includes('/tv/');
                const mockData = {
                  name: isTv ? ${jsonEncode(title)} : undefined,
                  title: !isTv ? ${jsonEncode(title)} : undefined,
                  first_air_date: isTv ? ${jsonEncode(releaseDate)} : undefined,
                  release_date: !isTv ? ${jsonEncode(releaseDate)} : undefined,
                  external_ids: {
                    imdb_id: ${jsonEncode(imdbId)}
                  }
                };
                return Promise.resolve({
                  status: 200,
                  ok: true,
                  headers: {
                    get: function(name) { return 'application/json'; }
                  },
                  text: function() { return Promise.resolve(JSON.stringify(mockData)); },
                  json: function() { return Promise.resolve(mockData); }
                });
              }

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

            window.onFetchResponse = window.onFetchResponse || function(reqId, status, body, headers, error) {
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
                  let elements = [];
                  
                  if (typeof selector === 'string') {
                    let containsText = null;
                    let targetSelector = selector;
                    
                    // Support :contains() filter in selector strings
                    if (targetSelector.includes(':contains(')) {
                      const match = targetSelector.match(/:contains\((["']?)(.*?)\1\)/);
                      if (match) {
                        containsText = match[2];
                        targetSelector = targetSelector.replace(/:contains\(.*?\)/, '');
                      }
                    }
                    
                    // Query elements with cleaned selector
                    try {
                      elements = Array.from(doc.querySelectorAll(targetSelector));
                    } catch (e) {
                      console.warn("cheerio selector fail:", selector, e);
                      elements = [];
                    }
                    
                    if (containsText) {
                      elements = elements.filter(el => el.textContent.includes(containsText));
                    }
                  } else if (selector && selector.tagName) {
                    elements = [selector];
                  } else if (Array.isArray(selector)) {
                    elements = selector;
                  } else if (selector && selector.toArray) {
                    elements = selector.toArray();
                  }
                  
                  // Helper function to wrap elements back into a cheerio selector result
                  const wrap = function(elems) {
                    return selectorFn(elems);
                  };
                  
                  // Cheerio API methods on selection results:
                  elements.attr = function(name) {
                    if (elements.length === 0) return null;
                    if (name === 'href') {
                      return elements[0].getAttribute('href') || elements[0].href || '';
                    }
                    return elements[0].getAttribute(name);
                  };
                  
                  elements.text = function() {
                    return elements.map(el => el.textContent).join(' ').trim();
                  };
                  
                  elements.html = function() {
                    return elements.length > 0 ? elements[0].innerHTML : '';
                  };
                  
                  elements.val = function() {
                    return elements.length > 0 ? elements[0].value || elements[0].getAttribute('value') || '' : '';
                  };
                  
                  elements.prop = function(name) {
                    if (elements.length === 0) return null;
                    return elements[0][name] !== undefined ? elements[0][name] : elements[0].getAttribute(name);
                  };
                  
                  elements.hasClass = function(className) {
                    return elements.some(el => el.classList.contains(className));
                  };
                  
                  elements.find = function(subSelector) {
                    const found = [];
                    let containsText = null;
                    let targetSub = subSelector;
                    
                    if (typeof targetSub === 'string' && targetSub.includes(':contains(')) {
                      const match = targetSub.match(/:contains\((["']?)(.*?)\1\)/);
                      if (match) {
                        containsText = match[2];
                        targetSub = targetSub.replace(/:contains\(.*?\)/, '');
                      }
                    }
                    
                    elements.forEach(el => {
                      try {
                        found.push(...Array.from(el.querySelectorAll(targetSub)));
                      } catch (e) {}
                    });
                    
                    let result = found;
                    if (containsText) {
                      result = result.filter(el => el.textContent.includes(containsText));
                    }
                    return wrap(result);
                  };
                  
                  elements.each = function(callback) {
                    elements.forEach((el, index) => {
                      callback.call(el, index, el);
                    });
                    return elements;
                  };
                  
                  elements.map = function(callback) {
                    const results = elements.map((el, index) => callback.call(el, index, el));
                    return {
                      get: function() { return results; },
                      toArray: function() { return results; }
                    };
                  };
                  
                  elements.filter = function(callback) {
                    if (typeof callback === 'string') {
                      return wrap(elements.filter(el => el.matches(callback)));
                    }
                    return wrap(elements.filter((el, index) => callback.call(el, index, el)));
                  };
                  
                  elements.first = function() {
                    return wrap(elements.length > 0 ? [elements[0]] : []);
                  };
                  
                  elements.last = function() {
                    return wrap(elements.length > 0 ? [elements[elements.length - 1]] : []);
                  };
                  
                  elements.eq = function(index) {
                    if (index < 0) index = elements.length + index;
                    return wrap((index >= 0 && index < elements.length) ? [elements[index]] : []);
                  };
                  
                  elements.parent = function() {
                    const parents = elements.map(el => el.parentElement).filter(el => el != null);
                    return wrap(Array.from(new Set(parents)));
                  };
                  
                  elements.closest = function(subSelector) {
                    const closest = elements.map(el => el.closest(subSelector)).filter(el => el != null);
                    return wrap(Array.from(new Set(closest)));
                  };
                  
                  elements.next = function() {
                    const nextElems = elements.map(el => el.nextElementSibling).filter(el => el != null);
                    return wrap(nextElems);
                  };
                  
                  elements.nextAll = function() {
                    const nextAllElems = [];
                    elements.forEach(el => {
                      let sib = el.nextElementSibling;
                      while (sib) {
                        nextAllElems.push(sib);
                        sib = sib.nextElementSibling;
                      }
                    });
                    return wrap(Array.from(new Set(nextAllElems)));
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
            window.require = window.require || function(pkg) {
              if (pkg.includes('cheerio')) return window.cheerio;
              if (pkg.includes('crypto-js')) return window.CryptoJS;
              return {};
            };

            // Evaluate the provider JS code
            ${script}

            // Resolve getStreams (prioritize local module exports to avoid concurrent cross-provider overwrites)
            const getStreamsFn = module.exports.getStreams || window.getStreams || (window.module && window.module.exports && window.module.exports.getStreams);
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

            var finalUrl = url;
            if (headers.isNotEmpty) {
              finalUrl = Uri.parse(url).replace(queryParameters: {
                ...Uri.parse(url).queryParameters,
                'headers': jsonEncode(headers)
              }).toString();
            }

            // Parse metadata
            final parsedQuality = StremioParser.parseQuality(name, name);
            final parsedLangs = StremioParser.parseLanguages(name, name);
            final parsedSize = StremioParser.parseSize(name);

            sources.add(StreamSourceInfo(
              name: name,
              url: finalUrl,
              type: StreamSourceType.nuveoAddon,
              headers: headers,
              addonName: scraperName,
              originalTitle: name,
              quality: parsedQuality,
              languages: parsedLangs,
              size: parsedSize,
            ));
          }
        }
      }

      return sources;
    } catch (e) {
      debugPrint('WebViewScraperExecutor dynamic error for $scraperName: $e');
      return [];
    }
  }

  static Future<String> _getDynamicProviderScript(String scriptUrl) async {
    final prefs = await SharedPreferences.getInstance();
    final cleanKey = 'dynamic_scraper_js_${base64Encode(utf8.encode(scriptUrl)).replaceAll('=', '')}';
    final cachedScript = prefs.getString(cleanKey);
    
    try {
      final res = await http.get(Uri.parse(scriptUrl)).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final script = res.body;
        if (script.isNotEmpty) {
          await prefs.setString(cleanKey, script);
          return script;
        }
      }
    } catch (e) {
      debugPrint('WebViewScraperExecutor: Failed to fetch fresh script for $scriptUrl: $e');
    }

    if (cachedScript != null && cachedScript.isNotEmpty) {
      return cachedScript;
    }
    
    throw Exception('Scraper script $scriptUrl not available');
  }
}

