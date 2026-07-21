import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/api_client.dart';
import '../config/api_config.dart';
import 'auth_provider.dart';

final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsState>((ref) {
  return SettingsNotifier(ref.read(apiClientProvider));
});

class SettingsState {
  final Map<String, String> settings;
  final bool isLoading;
  final String? error;

  const SettingsState({
    this.settings = const {},
    this.isLoading = false,
    this.error,
  });

  SettingsState copyWith({
    Map<String, String>? settings,
    bool? isLoading,
    String? error,
  }) {
    return SettingsState(
      settings: settings ?? this.settings,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  final ApiClient _apiClient;

  SettingsNotifier(this._apiClient) : super(const SettingsState());

  Future<void> fetchSettings() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final response = await _apiClient.get(ApiConfig.appSettings);
      final settingsMap = response.map<String, String>(
        (key, value) => MapEntry(key.toString(), value.toString()),
      );

      state = state.copyWith(
        settings: settingsMap,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  Future<void> saveSetting(String key, String value) async {
    try {
      await _apiClient.post(ApiConfig.saveAppSetting, {
        'key': key,
        'value': value,
      });

      final updatedSettings = Map<String, String>.from(state.settings);
      updatedSettings[key] = value;

      state = state.copyWith(settings: updatedSettings);
    } catch (e) {
      state = state.copyWith(
        error: e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  Future<void> bulkSaveSettings(Map<String, String> newSettings) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      await _apiClient.post(ApiConfig.bulkSaveAppSettings, newSettings);

      final updatedSettings = Map<String, String>.from(state.settings);
      updatedSettings.addAll(newSettings);

      state = state.copyWith(
        settings: updatedSettings,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  String? getSetting(String key) => state.settings[key];

  List<String> getHiddenCategories() {
    final raw = state.settings['live_tv_hidden_categories'];
    if (raw == null || raw.isEmpty) return [];
    try {
      return (raw as List).cast<String>();
    } catch (_) {
      return [];
    }
  }

  Map<String, String> getCategoryRenames() {
    final raw = state.settings['live_tv_category_renames'];
    if (raw == null || raw.isEmpty) return {};
    try {
      return Map<String, String>.from(raw as Map);
    } catch (_) {
      return {};
    }
  }
}
