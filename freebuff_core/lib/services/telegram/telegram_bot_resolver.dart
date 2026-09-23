import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:mtflute/mtflute.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'telegram_service.dart';
import 'telegram_video_item.dart';

class _BotAction {
  final String botUsername;
  final String startParam;
  const _BotAction(this.botUsername, this.startParam);
}

class TelegramBotResolver {
  static final TelegramBotResolver instance = TelegramBotResolver._();
  TelegramBotResolver._();

  static const String _keyTempChannels = 'tg_temp_joined_channels';

  /// Determines whether a user query or URL is a Telegram post link or bot deep link.
  bool canHandle(String input) {
    final t = input.trim();
    if (t.startsWith('tg://callback')) return true;
    if (!t.contains('t.me/')) return false;
    return isPrivatePostLink(t) || isBotStartLink(t) || isPublicPostLink(t);
  }

  bool isPrivatePostLink(String input) =>
      RegExp(r't\.me/c/(\d+)/(\d+)').hasMatch(input);

  bool isPublicPostLink(String input) =>
      RegExp(r't\.me/([a-zA-Z0-9_]{4,})/(?:[a-zA-Z0-9_]+/)?(\d+)').hasMatch(input);

  bool isBotStartLink(String input) =>
      RegExp(r'(?:t\.me|telegram\.me)/([a-zA-Z0-9_]+)\?start=([^\s&]+)', caseSensitive: false)
          .hasMatch(input);

  /// Resolves a Telegram post link or bot link into a playable [TelegramVideoItem].
  Future<TelegramVideoItem?> resolveLink(
    String input, {
    void Function(String status)? onStatus,
  }) async {
    final text = input.trim();
    await TelegramService.instance.init();
    final client = TelegramService.instance.client;
    if (client == null ||
        TelegramService.instance.status.value != TelegramStatus.ready) {
      throw TelegramException(
        'Telegram is not connected. Sign in from Settings first.',
      );
    }

    // Proactively prune expired temporary channels in the background
    unawaited(pruneExpiredChannels(client));

    // Case 0: Inline callback link
    if (text.startsWith('tg://callback')) {
      final uri = Uri.parse(text);
      final chatId = int.parse(uri.queryParameters['chatId']!);
      final msgId = int.parse(uri.queryParameters['msgId']!);
      final data = base64Url.decode(uri.queryParameters['data']!);

      onStatus?.call('Requesting download link from bot...');
      int hash = 0;
      try {
        hash = client.cache.getChannelAccessHash(chatId);
      } catch (_) {}
      final peer = InputPeerChannel(channelId: chatId, accessHash: hash);

      final ans = await client.invoke(
        MessagesGetBotCallbackAnswerRequest(
          peer: peer,
          msgId: msgId,
          data: data,
        ),
      );

      if (ans is MessagesBotCallbackAnswerObj) {
        if (ans.url != null && ans.url!.isNotEmpty) {
          return await resolveLink(ans.url!, onStatus: onStatus);
        } else if (ans.message != null && ans.message!.isNotEmpty) {
          onStatus?.call(ans.message!);
        }
      }
      await Future.delayed(const Duration(milliseconds: 2500));
      return null;
    }

    // Case 1: Direct bot deep link: https://t.me/SomeBot?start=XYZ
    final botStartMatch = RegExp(
      r'(?:t\.me|telegram\.me)/([a-zA-Z0-9_]+)\?start=([^\s&]+)',
      caseSensitive: false,
    ).firstMatch(text);
    if (botStartMatch != null) {
      final botUser = botStartMatch.group(1)!;
      final param = botStartMatch.group(2)!;
      return await _triggerBotAndResolveVideo(
        client,
        botUser,
        param,
        onStatus: onStatus,
      );
    }

    // Case 2: Private post link: https://t.me/c/4460753442/597194
    final privatePostMatch =
        RegExp(r't\.me/c/(\d+)/(\d+)').firstMatch(text);
    if (privatePostMatch != null) {
      final channelId = int.parse(privatePostMatch.group(1)!);
      final msgId = int.parse(privatePostMatch.group(2)!);
      return await _resolveFromChannelMessage(
        client,
        channelId: channelId,
        messageId: msgId,
        isPrivate: true,
        onStatus: onStatus,
      );
    }

    // Case 3: Public post link: https://t.me/channel_name/12345
    final publicPostMatch =
        RegExp(r't\.me/([a-zA-Z0-9_]{4,})/(?:[a-zA-Z0-9_]+/)?(\d+)')
            .firstMatch(text);
    if (publicPostMatch != null) {
      final channelName = publicPostMatch.group(1)!;
      final msgId = int.parse(publicPostMatch.group(2)!);
      return await _resolveFromPublicChannelMessage(
        client,
        channelName: channelName,
        messageId: msgId,
        onStatus: onStatus,
      );
    }

    return null;
  }

  Future<TelegramVideoItem?> _resolveFromChannelMessage(
    MtpClient client, {
    required int channelId,
    required int messageId,
    required bool isPrivate,
    void Function(String status)? onStatus,
  }) async {
    onStatus?.call('Looking up channel message...');
    int accessHash = 0;
    try {
      accessHash = client.cache.getChannelAccessHash(channelId);
    } catch (_) {}

    if (accessHash == 0) {
      // Refresh dialogs to discover channel access hash
      onStatus?.call('Fetching channel credentials from dialogs...');
      try {
        await client.getDialogs(limit: 100);
        accessHash = client.cache.getChannelAccessHash(channelId);
      } catch (e) {
        debugPrint('[TelegramBotResolver] getDialogs note: $e');
      }
    }

    final peer = InputPeerChannel(channelId: channelId, accessHash: accessHash);
    final msg = await client.getMessage(peer: peer, id: messageId);
    if (msg == null || msg is! MessageObj) {
      throw TelegramException('Message $messageId not found in channel.');
    }

    // If message is already a video file, return it directly
    final directVideo = _extractVideo(msg, -1000000000000 - channelId);
    if (directVideo != null) {
      onStatus?.call('Direct video found!');
      return directVideo;
    }

    // Otherwise, check for bot action in inline buttons
    final botAction = _extractBotAction(msg);
    if (botAction != null) {
      return await _triggerBotAndResolveVideo(
        client,
        botAction.botUsername,
        botAction.startParam,
        onStatus: onStatus,
      );
    }

    throw TelegramException(
      'No video or bot download button found in this post.',
    );
  }

  Future<TelegramVideoItem?> _resolveFromPublicChannelMessage(
    MtpClient client, {
    required String channelName,
    required int messageId,
    void Function(String status)? onStatus,
  }) async {
    onStatus?.call('Resolving channel @$channelName...');
    final resolved = await client.resolveUsername(channelName);
    if (resolved is! ContactsResolvedPeerObj || resolved.chats.isEmpty) {
      throw TelegramException('Could not resolve public channel @$channelName');
    }
    final ch = resolved.chats.first;
    if (ch is! Channel) {
      throw TelegramException('Target @$channelName is not a channel.');
    }

    final peer = InputPeerChannel(
      channelId: ch.id,
      accessHash: ch.accessHash ?? 0,
    );
    final msg = await client.getMessage(peer: peer, id: messageId);
    if (msg == null || msg is! MessageObj) {
      throw TelegramException('Message $messageId not found in channel.');
    }

    final directVideo = _extractVideo(msg, -1000000000000 - ch.id);
    if (directVideo != null) {
      onStatus?.call('Direct video found!');
      return directVideo;
    }

    final botAction = _extractBotAction(msg);
    if (botAction != null) {
      return await _triggerBotAndResolveVideo(
        client,
        botAction.botUsername,
        botAction.startParam,
        onStatus: onStatus,
      );
    }

    throw TelegramException('No video or bot link in this channel message.');
  }

  Future<TelegramVideoItem?> _triggerBotAndResolveVideo(
    MtpClient client,
    String botUsername,
    String startParam, {
    void Function(String msg)? onStatus,
  }) async {
    onStatus?.call('Connecting to bot @$botUsername...');
    final resolved = await client.resolveUsername(botUsername);
    if (resolved is! ContactsResolvedPeerObj || resolved.users.isEmpty) {
      throw TelegramException('Could not resolve bot @$botUsername');
    }
    final botUser = resolved.users.first;
    if (botUser is! UserObj) {
      throw TelegramException('@$botUsername is not a valid user/bot.');
    }

    final inputUser = InputUserObj(
      userId: botUser.id,
      accessHash: botUser.accessHash ?? 0,
    );
    final botPeer = InputPeerUser(
      userId: botUser.id,
      accessHash: botUser.accessHash ?? 0,
    );

    onStatus?.call('Sending command to bot...');
    final randomId = DateTime.now().millisecondsSinceEpoch;
    await client.invoke(
      MessagesStartBotRequest(
        bot: inputUser,
        peer: botPeer,
        randomId: randomId,
        startParam: startParam,
      ),
    );

    // Initial wait for bot response
    await Future.delayed(const Duration(milliseconds: 2000));

    // Poll for bot response (up to 4 attempts)
    for (int attempt = 0; attempt < 4; attempt++) {
      final history = await client.getHistory(peer: botPeer, limit: 6);
      List<dynamic> messages = const [];
      try {
        messages = (history as dynamic).messages ?? const [];
      } catch (_) {}

      for (final m in messages) {
        if (m is! MessageObj) continue;

        // Check if video file has arrived!
        final videoItem = _extractVideo(m, botUser.id);
        if (videoItem != null) {
          final securedItem = await _secureInSavedMessages(
            client,
            botPeer,
            m,
            videoItem,
            onStatus: onStatus,
          );
          onStatus?.call('Video retrieved successfully!');
          return securedItem;
        }

        // Check for Force-Subscribe verification buttons or action buttons
        if (m.replyMarkup != null) {
          final joinedAny = await _handleForceSubscribe(
            client,
            m.replyMarkup!,
            onStatus: onStatus,
          );
          final hasAction = _hasActionCallbackButton(m.replyMarkup!);
          if (joinedAny || hasAction) {
            onStatus?.call(joinedAny
                ? 'Channels joined. Confirming with bot...'
                : 'Confirming with bot...');
            await _clickVerificationOrRetry(
              client,
              botPeer,
              m,
              inputUser,
              startParam,
            );
            await Future.delayed(const Duration(milliseconds: 2500));
            break; // Re-poll history after clicking confirmation
          }
        }
      }
      await Future.delayed(const Duration(milliseconds: 1500));
    }

    throw TelegramException(
      'Bot did not return a playable video file. Please check if the bot requires manual verification.',
    );
  }

  bool _hasActionCallbackButton(ReplyMarkup markup) {
    final buttons = _collectAllButtons(markup);
    for (final btn in buttons) {
      if (btn is KeyboardButtonCallback) {
        final lower = btn.text.toLowerCase();
        if (lower.contains('try again') ||
            lower.contains('refresh') ||
            lower.contains('joined') ||
            lower.contains('check') ||
            lower.contains('continue') ||
            lower.contains('get file') ||
            lower.contains('verify') ||
            lower.contains('done') ||
            lower.contains('start') ||
            lower.contains('download')) {
          return true;
        }
      }
    }
    return false;
  }

  Future<bool> _handleForceSubscribe(
    MtpClient client,
    ReplyMarkup markup, {
    void Function(String msg)? onStatus,
  }) async {
    bool joinedAny = false;
    final buttons = _collectAllButtons(markup);

    for (final btn in buttons) {
      if (btn is KeyboardButtonUrl) {
        final url = btn.url;
        // Check for private invite links: t.me/+hash or t.me/joinchat/hash
        final inviteMatch =
            RegExp(r't\.me/(?:\+|joinchat/)([a-zA-Z0-9_\-]+)').firstMatch(url);
        if (inviteMatch != null) {
          final hash = inviteMatch.group(1)!;
          try {
            onStatus?.call('Auto-joining verification channel...');
            final res = await client.invoke(
              MessagesImportChatInviteRequest(hash: hash),
            );
            joinedAny = true;
            _recordJoinedChatResult(res);
          } on TgError catch (e) {
            if (e.matches('USER_ALREADY_PARTICIPANT')) {
              joinedAny = true;
            } else {
              debugPrint('[TelegramBotResolver] Error joining invite $hash: $e');
            }
          } catch (e) {
            debugPrint('[TelegramBotResolver] Error joining invite $hash: $e');
          }
        } else {
          // Check for public channel: t.me/<channel_name>
          final publicMatch =
              RegExp(r't\.me/([a-zA-Z0-9_]{4,})$').firstMatch(url);
          if (publicMatch != null) {
            final chName = publicMatch.group(1)!;
            // Ignore bot links or share links
            if (!chName.toLowerCase().endsWith('bot') && chName != 'share') {
              try {
                onStatus?.call('Auto-joining channel @$chName...');
                final res = await client.resolveUsername(chName);
                if (res is ContactsResolvedPeerObj && res.chats.isNotEmpty) {
                  final ch = res.chats.first;
                  if (ch is Channel) {
                    await client.invoke(
                      ChannelsJoinChannelRequest(
                        channel: InputChannelObj(
                          channelId: ch.id,
                          accessHash: ch.accessHash ?? 0,
                        ),
                      ),
                    );
                    joinedAny = true;
                    await _recordJoinedChannel(ch.id, ch.accessHash ?? 0);
                  }
                }
              } on TgError catch (e) {
                if (e.matches('USER_ALREADY_PARTICIPANT')) {
                  joinedAny = true;
                } else {
                  debugPrint(
                    '[TelegramBotResolver] Error joining public channel @$chName: $e',
                  );
                }
              } catch (e) {
                debugPrint(
                  '[TelegramBotResolver] Error joining public channel @$chName: $e',
                );
              }
            }
          }
        }
      }
    }
    return joinedAny;
  }

  Future<void> _clickVerificationOrRetry(
    MtpClient client,
    InputPeer botPeer,
    MessageObj msg,
    InputUser botUser,
    String startParam,
  ) async {
    final buttons = _collectAllButtons(msg.replyMarkup!);
    KeyboardButtonCallback? confirmBtn;

    for (final btn in buttons) {
      if (btn is KeyboardButtonCallback) {
        final lower = btn.text.toLowerCase();
        if (lower.contains('try again') ||
            lower.contains('refresh') ||
            lower.contains('joined') ||
            lower.contains('check') ||
            lower.contains('continue') ||
            lower.contains('get file') ||
            lower.contains('verify') ||
            lower.contains('done')) {
          confirmBtn = btn;
          break;
        }
      }
    }

    if (confirmBtn != null && confirmBtn.data != null) {
      try {
        await client.invoke(
          MessagesGetBotCallbackAnswerRequest(
            peer: botPeer,
            msgId: msg.id,
            data: confirmBtn.data!,
          ),
        );
      } catch (e) {
        debugPrint('[TelegramBotResolver] Callback answer note: $e');
      }
    } else {
      // Re-invoke start bot request as fallback
      await client.invoke(
        MessagesStartBotRequest(
          bot: botUser,
          peer: botPeer,
          randomId: DateTime.now().millisecondsSinceEpoch,
          startParam: startParam,
        ),
      );
    }
  }

  List<KeyboardButton> _collectAllButtons(ReplyMarkup markup) {
    final out = <KeyboardButton>[];
    if (markup is ReplyInlineMarkup) {
      for (final row in markup.rows) {
        if (row is KeyboardButtonRowObj) {
          out.addAll(row.buttons);
        }
      }
    }
    return out;
  }

  _BotAction? _extractBotAction(MessageObj msg) {
    if (msg.replyMarkup == null) return null;
    final buttons = _collectAllButtons(msg.replyMarkup!);
    for (final btn in buttons) {
      if (btn is KeyboardButtonUrl) {
        final match = RegExp(
          r'(?:t\.me|telegram\.me)/([a-zA-Z0-9_]+)\?start=([^\s&]+)',
          caseSensitive: false,
        ).firstMatch(btn.url);
        if (match != null) {
          return _BotAction(match.group(1)!, match.group(2)!);
        }
      }
    }
    return null;
  }

  TelegramVideoItem? _extractVideo(MessageObj msg, int chatId) {
    final media = msg.media;
    if (media is! MessageMediaDocument) return null;
    final doc = media.document;
    if (doc is! DocumentObj) return null;

    String? fileName;
    int? durationSeconds;
    bool isVideo = false;

    for (final a in doc.attributes) {
      if (a is DocumentAttributeFilename) {
        fileName = a.fileName;
        final lower = fileName.toLowerCase();
        if (lower.endsWith('.mp4') ||
            lower.endsWith('.mkv') ||
            lower.endsWith('.avi') ||
            lower.endsWith('.mov') ||
            lower.endsWith('.ts') ||
            lower.endsWith('.webm')) {
          isVideo = true;
        }
      } else if (a is DocumentAttributeVideo) {
        isVideo = true;
        durationSeconds = a.duration.toInt();
      }
    }

    if (!isVideo && (doc.mimeType?.startsWith('video/') ?? false)) {
      isVideo = true;
    }

    if (!isVideo) return null;

    String? caption = msg.message.trim();
    if (caption.isEmpty) caption = null;

    final documentId = doc.id;
    final accessHash = doc.accessHash;
    final dcId = doc.dcId;
    final localId = 'doc-$documentId-$accessHash-$dcId';

    return TelegramVideoItem(
      localId: localId,
      messageId: msg.id,
      chatId: chatId,
      date: DateTime.fromMillisecondsSinceEpoch(msg.date * 1000),
      fileName: fileName,
      caption: caption,
      sizeBytes: doc.size,
      durationSeconds: durationSeconds,
      source: 'telegram_bot',
    );
  }

  // --- Temporary Channel Tracking & Auto-Pruning ---

  Future<void> _recordJoinedChatResult(dynamic result) async {
    try {
      if (result is UpdatesObj) {
        for (final chat in result.chats) {
          if (chat is Channel) {
            await _recordJoinedChannel(chat.id, chat.accessHash ?? 0);
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _recordJoinedChannel(int channelId, int accessHash) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyTempChannels);
      List<dynamic> list = raw != null && raw.isNotEmpty ? jsonDecode(raw) : [];
      list.removeWhere((item) => item['channelId'] == channelId);
      list.add({
        'channelId': channelId,
        'accessHash': accessHash,
        'joinedAt': DateTime.now().millisecondsSinceEpoch,
      });
      await prefs.setString(_keyTempChannels, jsonEncode(list));
    } catch (e) {
      debugPrint('[TelegramBotResolver] Error recording joined channel: $e');
    }
  }

  /// Automatically leaves temporary channels older than [maxAgeHours] (default: 48h)
  /// to protect the user's account from hitting the Telegram channel limit.
  Future<void> pruneExpiredChannels(
    MtpClient client, {
    int maxAgeHours = 48,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyTempChannels);
      if (raw == null || raw.isEmpty) return;
      final List<dynamic> list = jsonDecode(raw);
      final now = DateTime.now().millisecondsSinceEpoch;
      final maxAgeMs = maxAgeHours * 3600 * 1000;
      final remaining = <Map<String, dynamic>>[];

      for (final item in list) {
        final joinedAt = item['joinedAt'] as int? ?? 0;
        final channelId = item['channelId'] as int? ?? 0;
        final accessHash = item['accessHash'] as int? ?? 0;

        if (now - joinedAt > maxAgeMs && channelId > 0) {
          try {
            await client.invoke(
              ChannelsLeaveChannelRequest(
                channel: InputChannelObj(
                  channelId: channelId,
                  accessHash: accessHash,
                ),
              ),
            );
            debugPrint(
              '[TelegramBotResolver] Pruned expired temporary channel: $channelId',
            );
          } catch (e) {
            debugPrint(
              '[TelegramBotResolver] Note leaving expired channel $channelId: $e',
            );
          }
        } else {
          remaining.add(Map<String, dynamic>.from(item));
        }
      }
      await prefs.setString(_keyTempChannels, jsonEncode(remaining));
    } catch (e) {
      debugPrint('[TelegramBotResolver] Prune error: $e');
    }
  }

  Future<TelegramVideoItem> _secureInSavedMessages(
    MtpClient client,
    InputPeer botPeer,
    MessageObj m,
    TelegramVideoItem videoItem, {
    void Function(String msg)? onStatus,
  }) async {
    try {
      onStatus?.call('Securing video in Saved Messages...');
      final fwdRes = await client.invoke(
        MessagesForwardMessagesRequest(
          fromPeer: botPeer,
          id: [m.id],
          randomId: [DateTime.now().millisecondsSinceEpoch],
          toPeer: InputPeerSelf(),
        ),
      );

      int? savedMsgId = _extractForwardedMsgId(fwdRes);

      // Reliable verification: check top of Saved Messages
      if (savedMsgId == null || savedMsgId <= 0) {
        final savedHistory = await client.getHistory(peer: InputPeerSelf(), limit: 3);
        final list = (savedHistory as dynamic).messages ?? const [];
        for (final sm in list) {
          if (sm is MessageObj && sm.media != null) {
            savedMsgId = sm.id;
            break;
          }
        }
      }

      if (savedMsgId != null && savedMsgId > 0) {
        debugPrint('[TelegramBotResolver] Secured video in Saved Messages as msgId: $savedMsgId');
        onStatus?.call('Video secured against auto-deletion!');
        return TelegramVideoItem(
          localId: 'tg_saved_$savedMsgId',
          messageId: savedMsgId,
          chatId: 0, // 0 = Saved Messages / InputPeerSelf()
          date: DateTime.now(),
          fileName: videoItem.fileName,
          caption: videoItem.caption,
          sizeBytes: videoItem.sizeBytes,
          durationSeconds: videoItem.durationSeconds,
          thumbnailUrl: videoItem.thumbnailUrl,
          directUrl: videoItem.directUrl,
          source: videoItem.source,
        );
      }
    } catch (e) {
      debugPrint('[TelegramBotResolver] Forwarding to Saved Messages notice: $e');
    }
    return videoItem;
  }

  int? _extractForwardedMsgId(dynamic res) {
    if (res == null) return null;
    try {
      if (res is UpdatesObj) {
        for (final u in res.updates) {
          if (u is UpdateNewMessage && u.message is MessageObj) return (u.message as MessageObj).id;
          if (u is UpdateMessageID) return u.id;
        }
      } else if (res is UpdatesCombined) {
        for (final u in res.updates) {
          if (u is UpdateNewMessage && u.message is MessageObj) return (u.message as MessageObj).id;
          if (u is UpdateMessageID) return u.id;
        }
      } else if (res is UpdateShortSentMessage) {
        return res.id;
      }
    } catch (_) {}
    return null;
  }
}
