import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/api_client.dart';
import '../config/api_config.dart';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.read(apiClientProvider));
});

class AuthState {
  final bool isAuthenticated;
  final bool isLoading;
  final String? error;
  final String? username;

  const AuthState({
    this.isAuthenticated = false,
    this.isLoading = false,
    this.error,
    this.username,
  });

  AuthState copyWith({
    bool? isAuthenticated,
    bool? isLoading,
    String? error,
    String? username,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      username: username ?? this.username,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final ApiClient _apiClient;

  AuthNotifier(this._apiClient) : super(const AuthState(isAuthenticated: false, username: 'admin')) {
    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    // ALWAYS require fresh login when opening admin panel
    state = state.copyWith(isAuthenticated: false, username: 'admin');
  }

  Future<void> login(String username, String password) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      // Use the shared Dio to ensure cookie capture
      final response = await _apiClient.post(ApiConfig.login, {
        'username': username,
        'password': password,
      });

      // Login PHP returns 302 redirect on success
      if (response['success'] == true) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('username', username);
        await prefs.setBool('is_logged_in', true);

        state = state.copyWith(
          isAuthenticated: true,
          isLoading: false,
          username: username,
          error: null,
        );
      } else {
        state = state.copyWith(
          isLoading: false,
          error: 'Invalid credentials',
        );
      }
    } catch (e) {
      // If API fails, try to extract PHPSESSID from any DioException cookies
      try {
        // Force a GET to login.php to get a new session cookie
        await _apiClient.get(ApiConfig.login);
      } catch (_) {}
      
      state = state.copyWith(
        isLoading: false,
        error: 'Connection failed: ${e.toString().replaceFirst("Exception: ", "")}',
      );
    }
  }

  Future<void> logout() async {
    try {
      await _apiClient.get(ApiConfig.logout);
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('username');
    await prefs.remove('token');
    await prefs.setBool('is_logged_in', false);

    state = const AuthState();
  }
}
