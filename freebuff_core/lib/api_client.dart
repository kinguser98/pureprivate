import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiClient {
  final Dio _dio;
  final String baseUrl;

  ApiClient({required this.baseUrl}) : _dio = Dio(BaseOptions(baseUrl: baseUrl)) {
    // Add common interceptors (auth, logging, timeout)
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        // attach auth token if present
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('auth_token');
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
      onError: (e, handler) {
        // simple error logging – can be expanded later
        print('API error: ${e.message}');
        return handler.next(e);
      },
    ));
  }

  Future<Response<T>> get<T>(String path, {Map<String, dynamic>? queryParameters}) {
    return _dio.get<T>(path, queryParameters: queryParameters);
  }

  Future<Response<T>> post<T>(String path, {dynamic data}) {
    return _dio.post<T>(path, data: data);
  }

  // Add other HTTP verbs as needed (put, delete, patch)
}
