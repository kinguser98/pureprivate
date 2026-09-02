enum CloudProvider {
  gdrive,
  onedrivePersonal,
  onedriveBusiness,
  telegramMtproto,
  telegramBot,
}

extension CloudProviderExt on CloudProvider {
  String get displayName {
    switch (this) {
      case CloudProvider.gdrive:
        return 'Google Drive';
      case CloudProvider.onedrivePersonal:
        return 'OneDrive (Personal)';
      case CloudProvider.onedriveBusiness:
        return 'OneDrive (Work / School)';
      case CloudProvider.telegramMtproto:
        return 'Telegram (User Account)';
      case CloudProvider.telegramBot:
        return 'Telegram (Bot)';
    }
  }

  String get iconName {
    switch (this) {
      case CloudProvider.gdrive:
        return 'gdrive';
      case CloudProvider.onedrivePersonal:
      case CloudProvider.onedriveBusiness:
        return 'onedrive';
      case CloudProvider.telegramMtproto:
      case CloudProvider.telegramBot:
        return 'telegram';
    }
  }
}

class CloudAccount {
  final String id;
  final CloudProvider provider;
  final String accountName;
  final String email;
  final String? avatarUrl;
  final String? accessToken;
  final String? refreshToken;
  final int? tokenExpiryMs;
  final String? tenantId; // For OneDrive Business / Azure AD
  final String? defaultFolderId;
  final String? defaultFolderName;
  final int? totalStorageBytes;
  final int? usedStorageBytes;
  final String? telegramChatId;
  final String? telegramBotToken;
  final DateTime connectedAt;

  const CloudAccount({
    required this.id,
    required this.provider,
    required this.accountName,
    required this.email,
    this.avatarUrl,
    this.accessToken,
    this.refreshToken,
    this.tokenExpiryMs,
    this.tenantId,
    this.defaultFolderId,
    this.defaultFolderName,
    this.totalStorageBytes,
    this.usedStorageBytes,
    this.telegramChatId,
    this.telegramBotToken,
    required this.connectedAt,
  });

  bool get isExpired {
    if (tokenExpiryMs == null) return false;
    return DateTime.now().millisecondsSinceEpoch > (tokenExpiryMs! - 60000);
  }

  CloudAccount copyWith({
    String? id,
    CloudProvider? provider,
    String? accountName,
    String? email,
    String? avatarUrl,
    String? accessToken,
    String? refreshToken,
    int? tokenExpiryMs,
    String? tenantId,
    String? defaultFolderId,
    String? defaultFolderName,
    int? totalStorageBytes,
    int? usedStorageBytes,
    String? telegramChatId,
    String? telegramBotToken,
    DateTime? connectedAt,
  }) {
    return CloudAccount(
      id: id ?? this.id,
      provider: provider ?? this.provider,
      accountName: accountName ?? this.accountName,
      email: email ?? this.email,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      tokenExpiryMs: tokenExpiryMs ?? this.tokenExpiryMs,
      tenantId: tenantId ?? this.tenantId,
      defaultFolderId: defaultFolderId ?? this.defaultFolderId,
      defaultFolderName: defaultFolderName ?? this.defaultFolderName,
      totalStorageBytes: totalStorageBytes ?? this.totalStorageBytes,
      usedStorageBytes: usedStorageBytes ?? this.usedStorageBytes,
      telegramChatId: telegramChatId ?? this.telegramChatId,
      telegramBotToken: telegramBotToken ?? this.telegramBotToken,
      connectedAt: connectedAt ?? this.connectedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'provider': provider.name,
      'accountName': accountName,
      'email': email,
      'avatarUrl': avatarUrl,
      'accessToken': accessToken,
      'refreshToken': refreshToken,
      'tokenExpiryMs': tokenExpiryMs,
      'tenantId': tenantId,
      'defaultFolderId': defaultFolderId,
      'defaultFolderName': defaultFolderName,
      'totalStorageBytes': totalStorageBytes,
      'usedStorageBytes': usedStorageBytes,
      'telegramChatId': telegramChatId,
      'telegramBotToken': telegramBotToken,
      'connectedAt': connectedAt.toIso8601String(),
    };
  }

  factory CloudAccount.fromJson(Map<String, dynamic> json) {
    return CloudAccount(
      id: json['id'] as String,
      provider: CloudProvider.values.firstWhere(
        (e) => e.name == json['provider'],
        orElse: () => CloudProvider.gdrive,
      ),
      accountName: json['accountName'] as String? ?? 'Cloud Account',
      email: json['email'] as String? ?? '',
      avatarUrl: json['avatarUrl'] as String?,
      accessToken: json['accessToken'] as String?,
      refreshToken: json['refreshToken'] as String?,
      tokenExpiryMs: json['tokenExpiryMs'] as int?,
      tenantId: json['tenantId'] as String?,
      defaultFolderId: json['defaultFolderId'] as String?,
      defaultFolderName: json['defaultFolderName'] as String?,
      totalStorageBytes: json['totalStorageBytes'] as int?,
      usedStorageBytes: json['usedStorageBytes'] as int?,
      telegramChatId: json['telegramChatId'] as String?,
      telegramBotToken: json['telegramBotToken'] as String?,
      connectedAt: json['connectedAt'] != null
          ? DateTime.tryParse(json['connectedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
