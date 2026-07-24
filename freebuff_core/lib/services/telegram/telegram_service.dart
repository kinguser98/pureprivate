import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
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
          peer = InputPeerChannel(channelId: channelId, accessHash: 0);
        }
      } else if (item.chatId < 0) {
        peer = InputPeerChat(chatId: -item.chatId);
      } else if (item.chatId > 0) {
        peer = InputPeerUser(userId: item.chatId, accessHash: 0);
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
}

class _Scored<T> {
  final T value;
  final double score;
  _Scored(this.value, this.score);
}
