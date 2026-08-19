import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../config/api_config.dart';
import 'admin_api_client.dart';

class ApiClient {
  final Dio _dio = AdminApiClient.sharedDio;
  
  Future<Map<String, dynamic>> get(String endpoint, {Map<String, dynamic>? queryParams}) async {
    try {
      final response = await _dio.get(endpoint, queryParameters: queryParams);
      return response.data is Map ? response.data as Map<String, dynamic> : {};
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }
  
  Future<Map<String, dynamic>> post(String endpoint, dynamic data, {Map<String, dynamic>? queryParams}) async {
    try {
      final isJson = endpoint.contains('bulk_save_app_settings');
      final response = await _dio.post(
        endpoint,
        data: isJson ? data : (data is Map<String, dynamic> ? FormData.fromMap(data) : data),
        queryParameters: queryParams,
        options: Options(
          contentType: isJson ? 'application/json' : 'application/x-www-form-urlencoded',
          followRedirects: false,
        ),
      );
      if (response.statusCode == 302) {
        return {'success': true, 'redirect': response.headers.value('location') ?? ''};
      }
      return response.data is Map ? response.data as Map<String, dynamic> : {};
    } on DioException catch (e) {
      if (e.response?.statusCode == 302) {
        return {'success': true, 'redirect': e.response?.headers.value('location') ?? ''};
      }
      throw _handleError(e);
    }
  }
  
  Future<List<dynamic>> getList(String endpoint, {Map<String, dynamic>? queryParams}) async {
    try {
      final response = await _dio.get(endpoint, queryParameters: queryParams);
      return response.data is List ? response.data as List : [];
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }
  
  Exception _handleError(DioException error) {
    String message;
    String details = '';
    if (error.response != null) {
      final statusCode = error.response?.statusCode;
      if (statusCode == 302) message = 'Session expired. Please login again.';
      else if (statusCode == 401) message = 'Unauthorized. Please login again.';
      else if (statusCode == 404) message = 'Resource not found';
      else if (statusCode == 500) message = 'Server error';
      else message = 'Server error ($statusCode)';
      details = 'HTTP $statusCode';
    } else {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.sendTimeout:
          message = 'Connection timed out. Server not responding.';
          break;
        case DioExceptionType.connectionError:
          message = 'Cannot connect to ot.goprivate.fun';
          break;
        case DioExceptionType.badCertificate:
          message = 'SSL certificate error';
          break;
        default:
          message = 'Network error';
          details = error.message ?? '';
      }
    }
    if (kDebugMode) debugPrint('ApiClient error: $message | $details');
    return Exception('$message');
  }
}
