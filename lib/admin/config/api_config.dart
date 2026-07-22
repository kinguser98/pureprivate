class ApiConfig {
  static const String baseUrl = 'https://ott.redapp.space';
  
  // Authentication
  static const String login = '/login.php';
  static const String logout = '/logout.php';
  
  // Dashboard
  static const String dashboard = '/index.php';
  
  // Movies
  static const String movies = '/api.php';
  static const String addMovie = '/add_movie.php';
  static const String editMovie = '/edit_movie.php';
  static const String viewAllMovies = '/view_all.php';
  
  // Languages
  static const String languages = '/languages.php';
  
  // IPTV
  static const String iptvSettings = '/iptv_settings.php';
  static const String iptvChannels = '/iptv_channels.php';
  static const String stalkerSettings = '/api.php?action=get_stalker_settings';
  static const String stalkerVodCategories = '/api.php?action=get_stalker_vod_categories';
  static const String stalkerVodMovies = '/api.php?action=get_stalker_vod_movies';
  static const String liveChannels = '/api.php?action=get_live_channels';
  
  // Settings
  static const String appSettings = '/api.php?action=get_app_settings';
  static const String appSettingsPhp = '/app_settings.php';
  static const String saveAppSetting = '/api.php?action=save_app_setting';
  static const String bulkSaveAppSettings = '/api.php?action=bulk_save_app_settings';
  
  // Bulk Updater
  static const String bulkUpdater = '/bulk_updater.php';
  
  // Streamtape
  static const String streamtapeManager = '/streamtape_manager.php';
  
  // Backups
  static const String backups = '/backups.php';
  static const String autoBackup = '/auto_backup.php';
  
  // OTT Providers
  static const String ottProviders = '/ott_admin.php';
  
  // Account
  static const String accountSettings = '/settings.php';
  
  // Favorites & Progress
  static const String getFavorites = '/api.php?action=get_favorites';
  static const String toggleFavorite = '/api.php?action=toggle_favorite';
  static const String checkFavorite = '/api.php?action=check_favorite';
  static const String saveProgress = '/api.php?action=save_progress';
  static const String getProgress = '/api.php?action=get_progress';
  
  // Proxy
  static const String proxyFetch = '/api.php?action=proxy_fetch';
  static const String proxyStreamtape = '/api.php?action=proxy_streamtape';
  
  // Headers
  static const Map<String, String> headers = {'Accept': 'application/json'};
  
  // Timeouts
  static const int connectTimeout = 15000;
  static const int receiveTimeout = 15000;
}
