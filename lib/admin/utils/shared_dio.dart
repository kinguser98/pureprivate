import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';

class SharedDio {
  static final SharedDio _instance = SharedDio._internal();
  static SharedDio get instance => _instance;
  
  late final Dio dio;
  static String? _cookie;

  static void setCookie(String? cookie) {
    _cookie = cookie;
  }
  
  static String? getCookie() => _cookie;

  SharedDio._internal() {
    dio = Dio();
    dio.options = BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Accept': 'application/json'},
      followRedirects: true,
      maxRedirects: 5,
    );
    
    try {
      (dio.httpClientAdapter as IOHttpClientAdapter).onHttpClientCreate = (client) {
        client.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
        return client;
      };
    } catch (_) {}
    
    // Cookie storage using simple header management
    String? _cookie;
    
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        options.headers['User-Agent'] = 'Mozilla/5.0 (Linux; Android 14; SM-S908E) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.6099.230 Mobile Safari/537.36';
        options.headers['Accept-Language'] = 'en-US,en;q=0.9';
        options.headers['Cache-Control'] = 'no-cache';
        if (_cookie != null) {
          options.headers['Cookie'] = _cookie;
        }
        handler.next(options);
      },
      onResponse: (response, handler) {
        final setCookie = response.headers.value('set-cookie');
        if (setCookie != null) {
          _cookie = setCookie.split(';')[0].trim();
        }
        handler.next(response);
      },
      onError: (error, handler) {
        final setCookie = error.response?.headers.value('set-cookie');
        if (setCookie != null) {
          _cookie = setCookie.split(';')[0].trim();
        }
        handler.next(error);
      },
    ));
    
    if (kDebugMode) {
      dio.interceptors.add(LogInterceptor(requestBody: true, responseBody: true));
    }
  }
}
