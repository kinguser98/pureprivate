import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:cached_network_image/cached_network_image.dart';

class LogoCacheManager {
  static const String key = 'cinema_logo_cache_key';

  static final CacheManager instance = CacheManager(
    Config(
      key,
      stalePeriod: const Duration(days: 30),
      maxNrOfCacheObjects: 500,
      repo: JsonCacheInfoRepository(databaseName: key),
      fileService: HttpFileService(),
    ),
  );

  /// Helper widget that loads network logos with auto-save long-term disk caching.
  static Widget buildCachedLogo({
    required String url,
    double? width,
    double? height,
    BoxFit fit = BoxFit.contain,
    Widget? placeholder,
    Widget? errorWidget,
  }) {
    if (url.isEmpty || !url.startsWith('http')) {
      return errorWidget ?? const Icon(Icons.tv_rounded, color: Colors.white38, size: 20);
    }

    return CachedNetworkImage(
      imageUrl: url,
      cacheManager: instance,
      width: width,
      height: height,
      fit: fit,
      placeholder: (context, url) => placeholder ?? const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white24),
      ),
      errorWidget: (context, url, error) => errorWidget ?? const Icon(Icons.tv_rounded, color: Colors.white38, size: 20),
    );
  }
}
