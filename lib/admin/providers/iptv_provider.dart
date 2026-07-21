import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/iptv_channel.dart';
import '../utils/api_client.dart';
import '../utils/storage.dart';
import '../config/api_config.dart';
import 'auth_provider.dart';

final iptvProvider = StateNotifierProvider<IptvNotifier, IptvState>((ref) {
  return IptvNotifier(ref.read(apiClientProvider));
});

class IptvState {
  final List<IptvChannel> channels;
  final List<String> categories;
  final bool isLoading;
  final String? error;
  final String? stalkerVodCategories;
  final List<dynamic> stalkerVods;

  const IptvState({
    this.channels = const [],
    this.categories = const [],
    this.isLoading = false,
    this.error,
    this.stalkerVodCategories,
    this.stalkerVods = const [],
  });

  IptvState copyWith({
    List<IptvChannel>? channels,
    List<String>? categories,
    bool? isLoading,
    String? error,
    String? stalkerVodCategories,
    List<dynamic>? stalkerVods,
  }) {
    return IptvState(
      channels: channels ?? this.channels,
      categories: categories ?? this.categories,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      stalkerVodCategories: stalkerVodCategories ?? this.stalkerVodCategories,
      stalkerVods: stalkerVods ?? this.stalkerVods,
    );
  }

  List<IptvChannel> get enabledChannels => channels.where((c) => c.enabled).toList();

  List<IptvChannel> getChannelsByCategory(String category) {
    return channels.where((c) => c.categoryName == category).toList();
  }

  Map<String, List<IptvChannel>> get channelsByCategory {
    final map = <String, List<IptvChannel>>{};
    for (final channel in channels) {
      map.putIfAbsent(channel.categoryName, () => []);
      map[channel.categoryName]!.add(channel);
    }
    return map;
  }
}

class IptvNotifier extends StateNotifier<IptvState> {
  final ApiClient _apiClient;

  IptvNotifier(this._apiClient) : super(const IptvState()) {
    _loadCachedChannels();
  }

  Future<void> _loadCachedChannels() async {
    try {
      final cached = await Storage.getCachedChannels();
      if (cached.isNotEmpty && state.channels.isEmpty) {
        _updateState(channels: cached);
      }
    } catch (_) {}
  }

  Future<void> fetchChannels() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final response = await _apiClient.getList(
        ApiConfig.liveChannels,
        queryParams: {'all': '1'},
      );
      final channels = response
          .map((e) => IptvChannel.fromJson(e as Map<String, dynamic>))
          .toList();

      _updateState(channels: channels, isLoading: false);

      try {
        await Storage.cacheChannels(channels);
      } catch (_) {}
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  Future<void> fetchStalkerVodCategories() async {
    try {
      final data = await _apiClient.get(ApiConfig.stalkerVodCategories);
      state = state.copyWith(stalkerVodCategories: data.toString());
    } catch (e) {
      state = state.copyWith(
        error: e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  Future<void> fetchStalkerVodMovies(String category) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final data = await _apiClient.get(ApiConfig.stalkerVodMovies, queryParams: {
        'category': category,
        'page': '1',
      });
      final movies = data['movies'] ?? [];
      state = state.copyWith(
        stalkerVods: movies as List<dynamic>,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  List<IptvChannel> searchChannels(String query) {
    if (query.isEmpty) return state.channels;
    final lowerQuery = query.toLowerCase();
    return state.channels.where((channel) {
      return channel.name.toLowerCase().contains(lowerQuery) ||
          channel.categoryName.toLowerCase().contains(lowerQuery) ||
          (channel.customName?.toLowerCase().contains(lowerQuery) ?? false);
    }).toList();
  }

  void _updateState({
    List<IptvChannel>? channels,
    List<String>? categories,
    bool? isLoading,
  }) {
    state = state.copyWith(
      channels: channels,
      categories: categories,
      isLoading: isLoading,
    );
  }
}
