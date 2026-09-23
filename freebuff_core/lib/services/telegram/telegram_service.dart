import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mtflute/mtflute.dart';

import 'telegram_index_db.dart';
import 'telegram_video_item.dart';

enum TelegramStatus {
  unconfigured,
  awaitingPhone,
  awaitingCode,
  awaitingPassword,
  ready,
  error,
}

class TelegramException implements Exception {
  final String message;
  final Object? cause;
  TelegramException(this.message, [this.cause]);
  @override
  String toString() => 'TelegramException: $message';
}

class TelegramCredentials {
  final int apiId;
  final String apiHash;
  const TelegramCredentials({required this.apiId, required this.apiHash});
}

class TelegramService {
  TelegramService._internal();
  static final TelegramService instance = TelegramService._internal();

  static const String sourceKey = 'telegram';

  final ValueNotifier<TelegramStatus> status =
      ValueNotifier<TelegramStatus>(TelegramStatus.unconfigured);

  final ValueNotifier<String?> statusMessage = ValueNotifier<String?>(null);

  MtpClient? _client;
  TelegramFileStreamServer? _streamServer;
  
  MtpClient? get client => _client;
  TelegramFileStreamServer? get streamServer => _streamServer;
  Future<void> ensureStreamServerStarted() => _ensureStreamServerStarted();
  
  String? _phoneNumber;
  String? _phoneCodeHash;

  Future<bool> get hasSession async {
    try {
      final s = await TelegramIndexDb.loadSession();
      if (s == null || s.isEmpty) return false;
      return s['userId'] != null;
    } catch (_) {
      return false;
    }
  }

  static Future<TelegramCredentials?> Function()? _remoteCredentialsProvider;

  static void registerRemoteCredentialsProvider(
      Future<TelegramCredentials?> Function() provider) {
    _remoteCredentialsProvider = provider;
  }

  static void resetRemoteCredentialsProvider() {
    _remoteCredentialsProvider = null;
  }

  /// Updates the API credentials. Only triggers a full logout+reconnect when
  /// the credentials have actually changed — avoids destroying the active
  /// session every time the remote config is fetched (which happens on every
  /// movie open).
  Future<void> setCredentials(int? apiId, String? apiHash) async {
    final currentId = await TelegramIndexDb.loadApiIdOverride();
    final currentHash = await TelegramIndexDb.loadApiHashOverride();
    if (currentId == apiId && currentHash == apiHash) {
      return; // No change — preserve the active session.
    }
    await TelegramIndexDb.saveApiIdOverride(apiId);
    await TelegramIndexDb.saveApiHashOverride(apiHash);
    // Credentials changed — must reconnect with new keys.
    await logout();
  }

  Future<TelegramCredentials?> getCredentials() async {
    final idOverride = await TelegramIndexDb.loadApiIdOverride();
    final hashOverride = await TelegramIndexDb.loadApiHashOverride();
    if (idOverride != null && hashOverride != null && hashOverride.isNotEmpty) {
      return TelegramCredentials(apiId: idOverride, apiHash: hashOverride);
    }
    final fromEnv = _fromEnv();
    if (fromEnv != null) {
      return fromEnv;
    }
    try {
      final provider = _remoteCredentialsProvider;
      if (provider != null) {
        final remote = await provider();
        if (remote != null) return remote;
      }
    } catch (e) {
      debugPrint('TelegramService.getCredentials remote lookup failed: $e');
    }
    // Fallback: read api_id / api_hash that were saved during sign-in.
    // This keeps us from returning null when the remote provider is offline.
    try {
      final session = await TelegramIndexDb.loadSession();
      if (session != null &&
          session['apiId'] != null &&
          session['apiHash'] != null) {
        return TelegramCredentials(
          apiId: session['apiId'] as int,
          apiHash: session['apiHash'] as String,
        );
      }
    } catch (e) {
      debugPrint('TelegramService.getCredentials session fallback failed: $e');
    }
    return null;
  }

  TelegramCredentials? _fromEnv() {
    const envId = String.fromEnvironment('TELEGRAM_API_ID');
    const envHash = String.fromEnvironment('TELEGRAM_API_HASH');
    if (envId.isEmpty || envHash.isEmpty) return null;
    final id = int.tryParse(envId);
    if (id == null) return null;
    return TelegramCredentials(apiId: id, apiHash: envHash);
  }

  Future<void> init() async {
    // Already connected and confirmed ready — nothing to do.
    if (_client != null && status.value == TelegramStatus.ready) return;

    final creds = await getCredentials();
    if (creds == null) {
      // Don't clobber an active session just because the remote creds
      // endpoint is temporarily unreachable.
      if (status.value == TelegramStatus.ready) return;
      status.value = TelegramStatus.unconfigured;
      statusMessage.value = 'Telegram api_id / api_hash not configured.';
      return;
    }

    if (_client != null &&
        (_client!.appId != creds.apiId || _client!.appHash != creds.apiHash)) {
      await logout();
    }

    final dir = await getApplicationDocumentsDirectory();
    final sessionPath = '${dir.path}/mtflute.session';
    final sessionFile = File(sessionPath);

    if (_client == null) {
      _client = MtpClient(
        appId: creds.apiId,
        appHash: creds.apiHash,
        sessionFile: sessionPath,
      );
    }

    // ── FAST PATH: session file exists → user was previously authenticated.
    // We trust the local file rather than making a live MTProto network call
    // (isAuthorized() invokes UpdatesGetState which takes 1-3 s on first
    // connect and resets status to awaitingPhone if the network is slow).
    // MtpClient will auto-connect + re-authenticate on the first real call.
    if (sessionFile.existsSync() && sessionFile.lengthSync() > 0) {
      status.value = TelegramStatus.ready;
      statusMessage.value = 'Connected to Telegram.';
      // Stream server starts lazily on first resolveStream / loadSavedMessages.
      return;
    }

    // ── SLOW PATH: no session file → either first install or after logout.
    // We must reach Telegram to know if there's somehow an active session.
    try {
      final isAuth = await _client!.isAuthorized();
      if (isAuth) {
        status.value = TelegramStatus.ready;
        statusMessage.value = 'Connected to Telegram.';
        unawaited(_ensureStreamServerStarted());
      } else {
        status.value = TelegramStatus.awaitingPhone;
        statusMessage.value = null;
      }
    } catch (e) {
      status.value = TelegramStatus.error;
      statusMessage.value = e.toString();
    }
  }

  Future<void> startAuth(String phoneNumber) async {
    await init();
    if (_client == null) {
      throw TelegramException('Telegram client not initialized.');
    }
    final cleaned = phoneNumber.replaceAll(RegExp(r'\s+'), '');
    if (cleaned.length < 6) {
      throw TelegramException('Phone number looks invalid. Include the country code (e.g. +91…).');
    }
    _phoneNumber = cleaned;
    statusMessage.value = null;

    try {
      final sent = await _client!.sendCode(cleaned);
      if (sent is AuthSentCodeObj) {
        _phoneCodeHash = sent.phoneCodeHash;
        status.value = TelegramStatus.awaitingCode;
        statusMessage.value = 'Enter the verification code sent to your Telegram device.';
      } else {
        throw TelegramException('Unexpected response from Telegram sendCode: ${sent.runtimeType}');
      }
    } catch (e) {
      status.value = TelegramStatus.error;
      statusMessage.value = e.toString();
      rethrow;
    }
  }

  Future<void> signIn(String code) async {
    if (_client == null || _phoneNumber == null || _phoneCodeHash == null) {
      throw TelegramException('Start authentication first by entering your phone number.');
    }
    try {
      final auth = await _client!.signIn(
        phone: _phoneNumber!,
        codeHash: _phoneCodeHash!,
        code: code,
      );
      
      status.value = TelegramStatus.ready;
      statusMessage.value = 'Signed in successfully.';
      await _ensureStreamServerStarted();

      final creds = await getCredentials();
      if (creds != null) {
        await TelegramIndexDb.saveApiIdOverride(creds.apiId);
        await TelegramIndexDb.saveApiHashOverride(creds.apiHash);
      }
      await TelegramIndexDb.saveSession({
        'apiId': creds!.apiId,
        'apiHash': creds.apiHash,
        'userId': 1, // Dummy user ID
        'phoneNumber': _phoneNumber,
      });
      await TelegramIndexDb.saveUserPhone(_phoneNumber!);
    } on TgError catch (e) {
      if (e.matches('SESSION_PASSWORD_NEEDED')) {
        status.value = TelegramStatus.awaitingPassword;
        statusMessage.value = 'Two-factor password required.';
        return;
      }
      status.value = TelegramStatus.error;
      statusMessage.value = e.message;
      rethrow;
    } catch (e) {
      status.value = TelegramStatus.error;
      statusMessage.value = e.toString();
      rethrow;
    }
  }

  Future<void> completePassword(String password) async {
    if (_client == null) {
      throw TelegramException('Telegram client not initialized.');
    }
    try {
      final auth = await _client!.checkPassword(password);
      
      status.value = TelegramStatus.ready;
      statusMessage.value = 'Signed in successfully.';
      await _ensureStreamServerStarted();

      final creds = await getCredentials();
      if (creds != null) {
        await TelegramIndexDb.saveApiIdOverride(creds.apiId);
        await TelegramIndexDb.saveApiHashOverride(creds.apiHash);
      }
      await TelegramIndexDb.saveSession({
        'apiId': creds!.apiId,
        'apiHash': creds.apiHash,
        'userId': 1, // Dummy user ID
        'phoneNumber': _phoneNumber,
      });
      if (_phoneNumber != null) {
        await TelegramIndexDb.saveUserPhone(_phoneNumber!);
      }
    } catch (e) {
      status.value = TelegramStatus.error;
      statusMessage.value = e.toString();
      rethrow;
    }
  }

  Future<void> logout() async {
    try {
      await _streamServer?.stop();
      _streamServer = null;
    } catch (_) {}

    try {
      await _client?.close();
      _client = null;
    } catch (_) {}

    _phoneNumber = null;
    _phoneCodeHash = null;

    final dir = await getApplicationDocumentsDirectory();
    final sessionFile = File('${dir.path}/mtflute.session');
    if (sessionFile.existsSync()) {
      try {
        sessionFile.deleteSync();
      } catch (_) {}
    }

    await TelegramIndexDb.clearSession();
    await TelegramIndexDb.instance.clearIndex();
    await TelegramIndexDb.resetSyncCursor();

    status.value = TelegramStatus.unconfigured;
    statusMessage.value = null;
  }

  /// Returns cached movies from the local DB and fetches the latest 100 from
  /// Telegram in the background (if the session is active). This is the
  /// fast path — the app shows what it has immediately, then refreshes.
  ///
  /// To load older movies call [loadMoreMessages].
  Future<List<TelegramVideoItem>> loadSavedMessages() async {
    await init();

    // Always return the DB immediately so the UI isn't blocked.
    if (status.value != TelegramStatus.ready || _client == null) {
      return TelegramIndexDb.instance.all();
    }

    try {
      // Fetch only the newest 100 messages (offsetId = 0 = start from top).
      await _fetchBatch(offsetId: 0, isRefresh: true);
    } catch (e) {
      debugPrint('TelegramService.loadSavedMessages failed: $e');
      statusMessage.value = 'Telegram refresh failed: $e';
    }

    return TelegramIndexDb.instance.all();
  }

  /// Fetches the next batch of 100 older messages beyond what we already have.
  /// Returns true if there are still more messages to load after this batch.
  Future<bool> loadMoreMessages() async {
    await init();
    if (status.value != TelegramStatus.ready || _client == null) return false;

    final hasMore = await TelegramIndexDb.loadSyncHasMore();
    if (!hasMore) return false;

    final offsetId = await TelegramIndexDb.loadSyncOffsetId();
    try {
      return await _fetchBatch(offsetId: offsetId, isRefresh: false);
    } catch (e) {
      debugPrint('TelegramService.loadMoreMessages failed: $e');
      return false;
    }
  }

  /// Returns whether any more messages exist beyond the current cursor.
  Future<bool> get hasSyncMore => TelegramIndexDb.loadSyncHasMore();

  // Fetches exactly 100 messages at [offsetId] and persists them + the cursor.
  // [isRefresh] = true means we start from the top (newest messages).
  Future<bool> _fetchBatch({required int offsetId, required bool isRefresh}) async {
    final res = await _client!.invoke(
      MessagesGetHistoryRequest(
        peer: InputPeerSelf(),
        offsetId: offsetId,
        offsetDate: 0,
        addOffset: 0,
        limit: 100,
        maxId: 0,
        minId: 0,
        hash: 0,
      ),
    );

    if (res is! MessagesMessages) return false;

    List<dynamic> rawMessages = const [];
    try {
      rawMessages = (res as dynamic).messages ?? const [];
    } catch (_) {}

    if (rawMessages.isNotEmpty) {
      final batchItems = _extractItems(res);
      if (batchItems.isNotEmpty) {
        await TelegramIndexDb.instance.upsertAll(batchItems);
      }

      // Save the cursor for the NEXT loadMore call.
      final lastMsg = rawMessages.last;
      if (lastMsg is MessageObj) {
        await TelegramIndexDb.saveSyncOffsetId(lastMsg.id);
      }
    }

    // If Telegram returned fewer than 100 raw messages, we've reached the end.
    final hasMore = rawMessages.length >= 100;
    await TelegramIndexDb.saveSyncHasMore(hasMore);
    return hasMore;
  }


  List<TelegramVideoItem> _extractItems(MessagesMessages result) {
    final out = <TelegramVideoItem>[];
    List<dynamic> messages = const [];
    try {
      messages = (result as dynamic).messages ?? const [];
    } catch (_) {}
    for (final raw in messages) {
      if (raw is! MessageObj) continue;
      final id = raw.id;
      final ts = DateTime.fromMillisecondsSinceEpoch(raw.date * 1000);
      String? caption = raw.message.trim();
      if (caption.isEmpty) caption = null;
      final media = raw.media;
      if (media == null) {
        if (caption != null && _isStreamUrl(caption)) {
          out.add(TelegramVideoItem(
            localId: 'msg-$id',
            messageId: id,
            chatId: 0,
            date: ts,
            fileName: null,
            caption: caption,
            directUrl: caption,
          ));
        }
        continue;
      }
      if (media is MessageMediaDocument) {
        final doc = media.document;
        if (doc is! DocumentObj) continue;
        final documentId = doc.id;
        final accessHash = doc.accessHash;
        final dcId = doc.dcId;

        String? fileName;
        int? sizeBytes = doc.size;
        int? durationSeconds;

        for (final a in doc.attributes) {
          if (a is DocumentAttributeFilename) {
            fileName = a.fileName;
          } else if (a is DocumentAttributeVideo) {
            durationSeconds = a.duration.toInt();
          }
        }

        final localId = 'doc-$documentId-$accessHash-$dcId';
        final item = TelegramVideoItem(
          localId: localId,
          messageId: id,
          chatId: 0,
          date: ts,
          fileName: fileName,
          caption: caption,
          sizeBytes: sizeBytes,
          durationSeconds: durationSeconds,
        );
        out.add(item);
      }
    }
    return out;
  }

  bool _isStreamUrl(String s) {
    final lower = s.toLowerCase();
    return lower.contains('http://') || lower.contains('https://');
  }

  Future<List<TelegramVideoItem>> search(String query) async {
    final items = await TelegramIndexDb.instance.all();
    if (query.trim().isEmpty) {
      return items.take(8).toList();
    }
    final tokens = _tokenize(query);
    final scored = <_Scored<TelegramVideoItem>>[];
    for (final item in items) {
      final score = _scoreItem(item, tokens);
      if (score > 0) scored.add(_Scored(item, score));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(12).map((e) => e.value).toList();
  }

  Future<String> resolveStream(TelegramVideoItem item) async {
    if (item.directUrl != null && item.directUrl!.isNotEmpty) {
      return item.directUrl!;
    }
    await init();
    if (status.value != TelegramStatus.ready || _client == null) {
      throw TelegramException('Telegram is not connected. Sign in from Settings first.');
    }
    await _ensureStreamServerStarted();

    // ── CONNECTION HEALTH CHECK ──────────────────────────────────────────────
    // After syncing many messages the main DC connection can become stale or
    // the auth key can be invalidated by Telegram. Probing here catches the
    // problem early and surfaces a clear error instead of silently looping
    // with AUTH_KEY_UNREGISTERED inside the stream server.
    try {
      await _client!.invoke(UpdatesGetStateRequest());
    } on TgError catch (e) {
      if (e.code == 401 || e.matches('AUTH_KEY_UNREGISTERED')) {
        // Session fully expired — clean up so the user is prompted to sign in.
        try { await _streamServer?.stop(); _streamServer = null; } catch (_) {}
        try { await _client?.close(); _client = null; } catch (_) {}
        status.value = TelegramStatus.awaitingPhone;
        statusMessage.value = 'Session expired.';
        throw TelegramException(
          'Telegram session expired. Please sign in again from Settings → Telegram.',
        );
      }
      // Other TG errors (flood wait, etc.) are transient — proceed.
    } catch (_) {
      // Network errors — proceed and let the stream server handle retries.
    }

    // Target DC warmup is now handled synchronously inside publishMessage in mtflute stream server.

    // Determine MIME type override based on file extension from fileName or caption
    final fileName = item.fileName?.toLowerCase() ?? '';
    final caption = item.caption?.toLowerCase() ?? '';
    String? mimeOverride;
    String ext = '.mp4';

    String? getMime(String extension) {
      return switch (extension) {
        '.mp4' || '.m4v' => 'video/mp4',
        '.mkv' => 'video/x-matroska',
        '.mov' => 'video/quicktime',
        '.webm' => 'video/webm',
        '.avi' => 'video/x-msvideo',
        '.flv' => 'video/x-flv',
        '.3gp' => 'video/3gpp',
        '.ts' => 'video/mp2t',
        '.m3u8' => 'application/x-mpegURL',
        _ => null,
      };
    }

    // 1. Try to extract extension directly from filename
    if (fileName.isNotEmpty && fileName.contains('.')) {
      final fileExt = fileName.substring(fileName.lastIndexOf('.'));
      final mime = getMime(fileExt);
      if (mime != null) {
        mimeOverride = mime;
        ext = fileExt;
      }
    }

    // 2. If not resolved from filename, fallback to searching keywords in combined name
    if (mimeOverride == null) {
      final combined = '$fileName $caption';
      if (combined.contains('.mkv')) {
        mimeOverride = 'video/x-matroska';
        ext = '.mkv';
      } else if (combined.contains('.mp4')) {
        mimeOverride = 'video/mp4';
        ext = '.mp4';
      } else if (combined.contains('.webm')) {
        mimeOverride = 'video/webm';
        ext = '.webm';
      } else if (combined.contains('.ts')) {
        mimeOverride = 'video/mp2t';
        ext = '.ts';
      } else if (combined.contains('.avi')) {
        mimeOverride = 'video/x-msvideo';
        ext = '.avi';
      } else if (combined.contains('.m3u8')) {
        mimeOverride = 'application/x-mpegURL';
        ext = '.m3u8';
      } else if (combined.contains('.mov')) {
        mimeOverride = 'video/quicktime';
        ext = '.mov';
      } else if (combined.contains('.flv')) {
        mimeOverride = 'video/x-flv';
        ext = '.flv';
      } else if (combined.contains('.3gp')) {
        mimeOverride = 'video/3gpp';
        ext = '.3gp';
      } else {
        mimeOverride = 'video/mp4';
        ext = '.mp4';
      }
    }

    InputPeer peer = InputPeerSelf();
    if (item.chatId != 0) {
      final chatIdStr = item.chatId.toString();
      if (chatIdStr.startsWith('-100')) {
        final channelId = int.tryParse(chatIdStr.substring(4)) ?? 0;
        if (channelId > 0) {
          int accessHash = 0;
          try {
            accessHash = _client?.cache.getChannelAccessHash(channelId) ?? 0;
          } catch (_) {}
          peer = InputPeerChannel(channelId: channelId, accessHash: accessHash);
        }
      } else if (item.chatId < 0) {
        peer = InputPeerChat(chatId: -item.chatId);
      } else if (item.chatId > 0) {
        int accessHash = 0;
        try {
          accessHash = _client?.cache.getUserAccessHash(item.chatId) ?? 0;
        } catch (_) {}
        peer = InputPeerUser(userId: item.chatId, accessHash: accessHash);
      }
    }

    var url = await _streamServer!.publishMessage(
      peer: peer,
      msgId: item.messageId,
      mimeOverride: mimeOverride,
    );

    // Append a clean file name with the correct extension so media player / FFmpeg / libmpv
    // can correctly identify the container format without encountering spaces or URL encoding issues.
    final safeName = 'video$ext';
    if (url.endsWith('/')) {
      url = '$url$safeName';
    } else {
      url = '$url/$safeName';
    }
    return url;
  }

  Future<void> _ensureStreamServerStarted() async {
    if (_client == null) return;
    if (_streamServer != null) return; // Already running
    try {
      _streamServer = TelegramFileStreamServer(
        _client!,
        chunkSize: 128 * 1024,
        prefetchAhead: 8,
      );
      await _streamServer!.start();
      try {
        await _streamServer!.warmup(dcId: _client!.dcId, workers: 4);
      } catch (e) {
        debugPrint('Stream server warmup warning: $e');
      }
    } catch (e) {
      debugPrint('Stream server start error: $e');
      _streamServer = null; // Allow retry next time
    }
  }

  // ---- helpers ---------------------------------------------------------

  static List<String> _tokenize(String query) {
    return query
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9 ]+'), ' ')
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
  }

  /// Scores a [TelegramVideoItem] against the tokenised movie-title query.
  ///
  /// Returns 0 if no title word is found in the caption/filename — this
  /// ensures unrelated files are completely excluded instead of showing
  /// up on every movie due to unconditional metadata bonuses.
  static double _scoreItem(TelegramVideoItem item, List<String> tokens) {
    if (tokens.isEmpty) return 0.0;

    // Build haystack from the user-visible text: caption first, then filename.
    final parts = [
      if (item.caption != null && item.caption!.isNotEmpty) item.caption!,
      if (item.fileName != null && item.fileName!.isNotEmpty) item.fileName!,
    ];
    if (parts.isEmpty) return 0.0;

    final hay = parts.join(' ').toLowerCase();
    final hayTokens = _tokenize(hay);
    if (hayTokens.isEmpty) return 0.0;

    // Common words that often cause false-positive matches (e.g. "and" matching "Tom and Jerry")
    const stopWords = {
      'and', 'the', 'of', 'co', 'in', 'to', 'or', 'for', 'with', 'on', 'at', 'by',
      'an', 'a', 'is', 'that', 'this', 'movie', 'series', 'season', 'episode',
      'hd', 'dual', 'hindi', 'english', 'tamil', 'telugu', 'org', 'hevc', 'x264',
      'x265', '10bit', 'webrip', 'web', 'dl', 'bluray', 'hdtv', 'aac', 'dd5'
    };

    // Identify year tokens (4 digits starting with 19 or 20)
    final yearRegex = RegExp(r'^(19|20)\d{2}$');
    String? queryYear;
    final titleTokens = <String>[];

    for (final t in tokens) {
      if (yearRegex.hasMatch(t)) {
        queryYear = t;
      } else {
        titleTokens.add(t);
      }
    }

    // If query contains a year, check if haystack has a DIFFERENT year
    if (queryYear != null) {
      for (final ht in hayTokens) {
        if (yearRegex.hasMatch(ht) && ht != queryYear) {
          // Found a different year in the filename/caption -> exclude it
          return 0.0;
        }
      }
    }

    final significantTokens = titleTokens.where((t) => !stopWords.contains(t)).toList();
    final tokensToCheck = significantTokens.isNotEmpty ? significantTokens : titleTokens;

    if (tokensToCheck.isEmpty) return 0.0;

    // Helper to check if a query token matches the haystack tokens
    bool isMatch(String token) {
      for (final ht in hayTokens) {
        if (ht == token) return true;
        // For longer words (>=4 chars), allow partial substring matches (e.g. "inception" matching "inceptions")
        if (token.length >= 4 && ht.contains(token)) return true;
      }
      return false;
    }

    var matchedSignificant = 0;
    for (final t in tokensToCheck) {
      if (isMatch(t)) matchedSignificant++;
    }

    // Must match at least one significant title word — otherwise completely excluded.
    if (matchedSignificant == 0) return 0.0;

    // Calculate coverage using all title tokens
    var matchedTitle = 0;
    for (final t in titleTokens) {
      if (isMatch(t)) matchedTitle++;
    }

    double score = matchedTitle / (titleTokens.isEmpty ? 1 : titleTokens.length);

    // Year match handling
    if (queryYear != null) {
      if (hayTokens.contains(queryYear)) {
        score += 1.0; // high bonus for matching the correct year
      }
    }

    return score;
  }

  // --- Movie Group Search & Discovery ---

  static const String keyMovieGroupId = 'tg_movie_group_id';
  static const String keyMovieGroupTitle = 'tg_movie_group_title';
  static const String keyMovieGroupAccessHash = 'tg_movie_group_access_hash';

  Future<int?> getConfiguredMovieGroupId() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(keyMovieGroupId);
    if (str == null || str.isEmpty) return null;
    return int.tryParse(str);
  }

  Future<String?> getConfiguredMovieGroupTitle() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(keyMovieGroupTitle);
  }

  Future<void> setConfiguredMovieGroup({
    required int id,
    required String title,
    int accessHash = 0,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyMovieGroupId, id.toString());
    await prefs.setString(keyMovieGroupTitle, title);
    await prefs.setInt(keyMovieGroupAccessHash, accessHash);
  }

  Future<void> clearConfiguredMovieGroup() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(keyMovieGroupId);
    await prefs.remove(keyMovieGroupTitle);
    await prefs.remove(keyMovieGroupAccessHash);
  }

  /// Retrieves all joined supergroups and channels for the Group Picker dialog.
  Future<List<Map<String, dynamic>>> getJoinedGroups() async {
    await init();
    if (_client == null || status.value != TelegramStatus.ready) return [];
    try {
      final res = await _client!.getDialogs(limit: 100);
      final List<Chat> chats = [];
      if (res is MessagesDialogsObj) {
        chats.addAll(res.chats);
      } else if (res is MessagesDialogsSlice) {
        chats.addAll(res.chats);
      }
      final List<Map<String, dynamic>> results = [];
      for (final c in chats) {
        if (c is Channel) {
          results.add({
            'id': c.id,
            'accessHash': c.accessHash ?? 0,
            'title': c.title,
            'username': c.username,
            'isGroup': c.megagroup,
            'isChannel': c.broadcast,
          });
        } else if (c is ChatObj) {
          results.add({
            'id': c.id,
            'accessHash': 0,
            'title': c.title,
            'username': null,
            'isGroup': true,
            'isChannel': false,
          });
        }
      }
      return results;
    } catch (e) {
      debugPrint('[TelegramService] getJoinedGroups error: $e');
      return [];
    }
  }

  /// Searches a movie query inside the user's configured movie group.
  Future<List<TelegramGroupSearchResult>> searchMovieInConfiguredGroup(String query) async {
    final groupId = await getConfiguredMovieGroupId();
    if (groupId == null) return [];
    final prefs = await SharedPreferences.getInstance();
    final accessHash = prefs.getInt(keyMovieGroupAccessHash) ?? 0;
    return searchMovieInGroup(groupId: groupId, accessHash: accessHash, query: query);
  }

  /// Searches a movie query inside any specified group/channel by ID.
  Future<List<TelegramGroupSearchResult>> searchMovieInGroup({
    required int groupId,
    int accessHash = 0,
    required String query,
  }) async {
    await init();
    if (_client == null || status.value != TelegramStatus.ready) return [];

    try {
      int hash = accessHash;
      if (hash == 0) {
        try {
          hash = _client!.cache.getChannelAccessHash(groupId);
        } catch (_) {}
      }
      final peer = InputPeerChannel(channelId: groupId, accessHash: hash);

      final List<TelegramGroupSearchResult> results = [];
      final Set<String> seenUrls = {};
      KeyboardButtonCallback? nextPageCallback;
      int? nextPageMsgId;

      void extractFromMessages(List<dynamic> msgs) {
        for (final m in msgs) {
          if (m is! MessageObj) continue;
          debugPrint('[TelegramService] Inspecting bot reply msg id=${m.id}, text="${m.message.replaceAll('\n', ' ')}", markup=${m.replyMarkup?.runtimeType}');

          // Check inline keyboard buttons
          if (m.replyMarkup is ReplyInlineMarkup) {
            final markup = m.replyMarkup as ReplyInlineMarkup;
            for (final row in markup.rows) {
              if (row is! KeyboardButtonRowObj) continue;
              for (final btn in row.buttons) {
                String btnText = '';
                try {
                  btnText = (btn as dynamic).text?.toString().trim() ?? '';
                } catch (_) {}
                final lowerText = btnText.toLowerCase();

                // Detect pagination next-page button
                final isPaginationNext = lowerText.contains('next page') ||
                    lowerText.contains('next ▶') ||
                    lowerText.contains('next ⏩') ||
                    lowerText.contains('nextpage') ||
                    lowerText.contains('⏩') ||
                    (lowerText.contains('next') && !lowerText.contains('season') && !lowerText.contains('episode'));

                // Skip non-stream utility buttons and pagination controls
                final isUtilityOrNav = lowerText == 'close' ||
                    lowerText == 'delete' ||
                    lowerText.contains('how to') ||
                    lowerText.contains('tutorial') ||
                    lowerText.contains('help') ||
                    lowerText.contains('rules') ||
                    lowerText.contains('support') ||
                    lowerText.contains('previous page') ||
                    lowerText.contains('prev page') ||
                    lowerText.contains('back') ||
                    lowerText.contains('page ') ||
                    lowerText.contains('pages') ||
                    RegExp(r'^\s*[\d]+\s*/\s*[\d]+\s*$').hasMatch(lowerText) ||
                    RegExp(r'^[⏪◀️▶️⏩\s\d/]+$').hasMatch(lowerText) ||
                    isPaginationNext;

                if (isPaginationNext && btn is KeyboardButtonCallback) {
                  nextPageCallback = btn;
                  nextPageMsgId = m.id;
                }

                if (isUtilityOrNav) {
                  continue;
                }

                String? qualityOrSize;
                final sizeMatch = RegExp(r'(\d+(?:\.\d+)?\s*(?:GB|MB|KB))', caseSensitive: false).firstMatch(btnText);
                final qMatch = RegExp(r'\b(4K|1080p|720p|480p|HD|HQ|HDRip)\b', caseSensitive: false).firstMatch(btnText);
                if (sizeMatch != null && qMatch != null) {
                  qualityOrSize = '${qMatch.group(1)} • ${sizeMatch.group(1)}';
                } else if (sizeMatch != null) {
                  qualityOrSize = sizeMatch.group(1);
                } else if (qMatch != null) {
                  qualityOrSize = qMatch.group(1);
                }

                // Handle URL buttons (t.me/... or bot deep links)
                if (btn is KeyboardButtonUrl) {
                  final btnUrl = btn.url;
                  debugPrint('[TelegramService] Found KeyboardButtonUrl: "$btnText" -> $btnUrl');
                  if (!seenUrls.contains(btnUrl)) {
                    seenUrls.add(btnUrl);
                    final match = RegExp(
                      r'(?:t\.me|telegram\.me)/([a-zA-Z0-9_]+)\?start=([^\s&]+)',
                      caseSensitive: false,
                    ).firstMatch(btnUrl);

                    final bot = match?.group(1) ?? '';
                    final param = match?.group(2) ?? '';

                    results.add(TelegramGroupSearchResult(
                      title: btnText,
                      botStartUrl: btnUrl,
                      botUsername: bot,
                      startParam: param,
                      qualityOrSize: qualityOrSize,
                    ));
                  }
                }
                // Handle callback buttons (inline query / get file buttons)
                else if (btn is KeyboardButtonCallback) {
                  final callbackUrl = 'tg://callback?chatId=$groupId&msgId=${m.id}&data=${base64Url.encode(btn.data)}';
                  debugPrint('[TelegramService] Found KeyboardButtonCallback: "$btnText" -> data len=${btn.data.length}');
                  if (!seenUrls.contains(callbackUrl)) {
                    seenUrls.add(callbackUrl);
                    results.add(TelegramGroupSearchResult(
                      title: btnText,
                      botStartUrl: callbackUrl,
                      botUsername: 'callback',
                      startParam: base64Url.encode(btn.data),
                      qualityOrSize: qualityOrSize,
                    ));
                  }
                }
              }
            }
          }

          // Also check text links inside m.message
          if (m.message.isNotEmpty) {
            final textMatches = RegExp(
              r'(?:https?://)?(?:t\.me|telegram\.me)/(?:c/\d+/\d+|[a-zA-Z0-9_]+/[0-9]+|[a-zA-Z0-9_]+\?start=[^\s&]+)',
              caseSensitive: false,
            ).allMatches(m.message);

            for (final tm in textMatches) {
              final rawUrl = tm.group(0)!;
              final fullUrl = rawUrl.startsWith('http') ? rawUrl : 'https://$rawUrl';

              if (!seenUrls.contains(fullUrl)) {
                seenUrls.add(fullUrl);
                String title = m.message.split('\n').first.trim();
                for (final line in m.message.split('\n')) {
                  if (line.contains(rawUrl) && line.trim().length > rawUrl.length) {
                    title = line.replaceAll(rawUrl, '').replaceAll(RegExp(r'[:\-–—]'), '').trim();
                    break;
                  }
                }
                if (title.isEmpty) title = 'Stream via Telegram';

                final startMatch = RegExp(r'(?:t\.me|telegram\.me)/([a-zA-Z0-9_]+)\?start=([^\s&]+)').firstMatch(fullUrl);

                results.add(TelegramGroupSearchResult(
                  title: title,
                  botStartUrl: fullUrl,
                  botUsername: startMatch?.group(1) ?? '',
                  startParam: startMatch?.group(2) ?? '',
                ));
              }
            }
          }
        }
      }

      // Send the movie query to the group to trigger the auto-filter bot
      debugPrint('[TelegramService] Sending movie query "$query" to group $groupId...');
      int? mySentMsgId;
      try {
        final sentRes = await _client!.sendMessage(peer: peer, text: query);
        debugPrint('[TelegramService] Query sent, result type: ${sentRes.runtimeType}');

        if (sentRes is UpdateShortSentMessage) {
          mySentMsgId = sentRes.id;
        } else if (sentRes is UpdateShortMessage) {
          mySentMsgId = sentRes.id;
        } else if (sentRes is UpdateShortChatMessage) {
          mySentMsgId = sentRes.id;
        } else if (sentRes is UpdatesObj) {
          for (final u in sentRes.updates) {
            if (u is UpdateNewChannelMessage && u.message is MessageObj) {
              mySentMsgId = (u.message as MessageObj).id;
            } else if (u is UpdateNewMessage && u.message is MessageObj) {
              mySentMsgId = (u.message as MessageObj).id;
            }
          }
        } else if (sentRes is UpdatesCombined) {
          for (final u in sentRes.updates) {
            if (u is UpdateNewChannelMessage && u.message is MessageObj) {
              mySentMsgId = (u.message as MessageObj).id;
            } else if (u is UpdateNewMessage && u.message is MessageObj) {
              mySentMsgId = (u.message as MessageObj).id;
            }
          }
        }
      } catch (e) {
        debugPrint('[TelegramService] Error sending query to group: $e');
      }

      // If mySentMsgId not directly in sent response, look it up in recent messages
      if (mySentMsgId == null) {
        try {
          final recent = await _client!.getHistory(peer: peer, limit: 10);
          List<dynamic> msgs = [];
          if (recent is MessagesChannelMessages) msgs = recent.messages;
          else if (recent is MessagesMessagesSlice) msgs = recent.messages;
          else if (recent is MessagesMessagesObj) msgs = recent.messages;
          else { try { msgs = (recent as dynamic).messages ?? []; } catch (_) {} }

          for (final m in msgs) {
            if (m is MessageObj && m.out == true && m.message.trim().toLowerCase() == query.trim().toLowerCase()) {
              mySentMsgId = m.id;
              debugPrint('[TelegramService] Found mySentMsgId from recent messages: $mySentMsgId');
              break;
            }
          }
        } catch (e) {
          debugPrint('[TelegramService] Error retrieving sent message ID: $e');
        }
      }

      debugPrint('[TelegramService] Waiting for bot replies quoting message $mySentMsgId (query: "$query")...');

      // Poll history for the bot's response quoting our search message (up to 5 attempts)
      for (int attempt = 1; attempt <= 5; attempt++) {
        await Future.delayed(const Duration(milliseconds: 2000));
        try {
          final history = await _client!.getHistory(peer: peer, limit: 25);
          List<dynamic> histMsgs = [];
          if (history is MessagesChannelMessages) {
            histMsgs = history.messages;
          } else if (history is MessagesMessagesSlice) {
            histMsgs = history.messages;
          } else if (history is MessagesMessagesObj) {
            histMsgs = history.messages;
          } else {
            try { histMsgs = (history as dynamic).messages ?? []; } catch (_) {}
          }

          // STRICT FILTER: Only accept messages that quoted or replied to OUR movie search message!
          final List<MessageObj> myBotReplies = [];
          for (final m in histMsgs) {
            if (m is! MessageObj) continue;

            int? repliedId;
            String? quoteText;
            if (m.replyTo is MessageReplyHeaderObj) {
              final r = m.replyTo as MessageReplyHeaderObj;
              repliedId = r.replyToMsgId;
              quoteText = r.quoteText;
            } else if (m.replyTo != null) {
              try { repliedId = (m.replyTo as dynamic).replyToMsgId; } catch (_) {}
              try { quoteText = (m.replyTo as dynamic).quoteText; } catch (_) {}
            }

            bool isReplyToMySearch = false;
            if (mySentMsgId != null && repliedId == mySentMsgId) {
              isReplyToMySearch = true;
            } else if (quoteText != null && quoteText.toLowerCase().contains(query.toLowerCase())) {
              isReplyToMySearch = true;
            }

            if (isReplyToMySearch) {
              myBotReplies.add(m);
            }
          }

          if (myBotReplies.isNotEmpty) {
            debugPrint('[TelegramService] Poll attempt $attempt: Found ${myBotReplies.length} bot reply message(s) quoting our search!');
            extractFromMessages(myBotReplies);

            if (results.isNotEmpty) {
              debugPrint('[TelegramService] Successfully extracted ${results.length} bot results!');

              // If bot has a Next Page button, trigger it to fetch page 2 results!
              if (nextPageCallback != null && nextPageMsgId != null) {
                try {
                  final curPageMsgId = nextPageMsgId!;
                  final cbData = nextPageCallback!.data;
                  nextPageCallback = null;
                  nextPageMsgId = null;

                  debugPrint('[TelegramService] Bot has next page! Sending callback to load next page...');
                  await _client!.invoke(
                    MessagesGetBotCallbackAnswerRequest(
                      peer: peer,
                      msgId: curPageMsgId,
                      data: cbData,
                    ),
                  );
                  await Future.delayed(const Duration(milliseconds: 1500));
                  final updatedMsg = await _client!.getMessage(peer: peer, id: curPageMsgId);
                  if (updatedMsg != null && updatedMsg is MessageObj) {
                    debugPrint('[TelegramService] Extracted page 2 bot results!');
                    extractFromMessages([updatedMsg]);
                  }
                } catch (e) {
                  debugPrint('[TelegramService] Next page fetch note: $e');
                }
              }

              // If we already have multiple results or we're on attempt >= 2, return
              if (results.length >= 2 || attempt >= 2) {
                break;
              }
            }
          } else {
            debugPrint('[TelegramService] Poll attempt $attempt: No replies quoting our search message yet...');
          }
        } catch (e) {
          debugPrint('[TelegramService] Poll error: $e');
        }
      }

      return results;
    } catch (e) {
      debugPrint('[TelegramService] searchMovieInGroup error: $e');
      return [];
    }
  }
}

class TelegramGroupSearchResult {
  final String title;
  final String botStartUrl;
  final String botUsername;
  final String startParam;
  final String? qualityOrSize;

  const TelegramGroupSearchResult({
    required this.title,
    required this.botStartUrl,
    required this.botUsername,
    required this.startParam,
    this.qualityOrSize,
  });
}

class _Scored<T> {
  final T value;
  final double score;
  _Scored(this.value, this.score);
}

