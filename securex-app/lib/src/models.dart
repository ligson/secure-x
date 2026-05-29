const secureXAvatarPresetIds = <String>{
  'sunrise',
  'forest',
  'ocean',
  'ember',
  'violet',
  'sky',
  'stone',
  'mint',
  'orbit',
  'shield',
};

const secureXDefaultUserAvatarPreset = 'sunrise';
const secureXDefaultGroupAvatarPreset = 'shield';

String normalizeSecureXAvatarPreset(String? value, {bool group = false}) {
  final normalized = (value ?? '').trim();
  if (secureXAvatarPresetIds.contains(normalized)) {
    return normalized;
  }
  return group
      ? secureXDefaultGroupAvatarPreset
      : secureXDefaultUserAvatarPreset;
}

class UserProfile {
  UserProfile({
    required this.id,
    required this.username,
    required this.nickname,
    required String avatarPreset,
    this.avatarUrl = '',
    required this.email,
    required this.kdfAlgorithm,
    required this.masterKeySalt,
    required this.masterKeyIterations,
    required this.wrappedVaultKey,
  }) : avatarPreset = normalizeSecureXAvatarPreset(avatarPreset);

  final String id;
  final String username;
  final String nickname;
  final String avatarPreset;
  final String avatarUrl;
  final String email;
  final String kdfAlgorithm;
  final String masterKeySalt;
  final int masterKeyIterations;
  final String wrappedVaultKey;

  String get displayName {
    if (nickname.trim().isNotEmpty) {
      return nickname.trim();
    }
    if (username.trim().isNotEmpty) {
      return username.trim();
    }
    return email.trim();
  }

  UserProfile copyWith({
    String? username,
    String? nickname,
    String? avatarPreset,
    String? avatarUrl,
    String? email,
    String? kdfAlgorithm,
    String? masterKeySalt,
    int? masterKeyIterations,
    String? wrappedVaultKey,
  }) {
    return UserProfile(
      id: id,
      username: username ?? this.username,
      nickname: nickname ?? this.nickname,
      avatarPreset: avatarPreset ?? this.avatarPreset,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      email: email ?? this.email,
      kdfAlgorithm: kdfAlgorithm ?? this.kdfAlgorithm,
      masterKeySalt: masterKeySalt ?? this.masterKeySalt,
      masterKeyIterations: masterKeyIterations ?? this.masterKeyIterations,
      wrappedVaultKey: wrappedVaultKey ?? this.wrappedVaultKey,
    );
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      username: json['username'] as String,
      nickname: json['nickname'] as String? ?? '',
      avatarPreset: json['avatarPreset'] as String? ?? '',
      avatarUrl: json['avatarUrl'] as String? ?? '',
      email: json['email'] as String,
      kdfAlgorithm: json['kdfAlgorithm'] as String,
      masterKeySalt: json['masterKeySalt'] as String,
      masterKeyIterations: (json['masterKeyIterations'] as num).toInt(),
      wrappedVaultKey: json['wrappedVaultKey'] as String,
    );
  }
}

class FolderRecord {
  FolderRecord({
    required this.id,
    required this.payload,
    required this.version,
    this.parentFolderId,
  });

  final String id;
  final String payload;
  final int version;
  final String? parentFolderId;

  factory FolderRecord.fromJson(Map<String, dynamic> json) {
    return FolderRecord(
      id: json['id'] as String,
      payload: json['payload'] as String,
      version: (json['version'] as num).toInt(),
      parentFolderId: json['parentFolderId'] as String?,
    );
  }
}

class FileFolderRecord {
  FileFolderRecord({
    required this.id,
    required this.payload,
    required this.version,
    this.parentFolderId,
  });

  final String id;
  final String payload;
  final int version;
  final String? parentFolderId;

  factory FileFolderRecord.fromJson(Map<String, dynamic> json) {
    return FileFolderRecord(
      id: json['id'] as String,
      payload: json['payload'] as String,
      version: (json['version'] as num).toInt(),
      parentFolderId: json['parentFolderId'] as String?,
    );
  }
}

class VaultItemRecord {
  VaultItemRecord({
    required this.id,
    required this.kind,
    required this.payload,
    required this.version,
    this.folderId,
  });

  final String id;
  final String kind;
  final String payload;
  final int version;
  final String? folderId;

  factory VaultItemRecord.fromJson(Map<String, dynamic> json) {
    return VaultItemRecord(
      id: json['id'] as String,
      kind: json['kind'] as String,
      payload: json['payload'] as String,
      version: (json['version'] as num).toInt(),
      folderId: json['folderId'] as String?,
    );
  }
}

class StoredFileRecord {
  StoredFileRecord({
    required this.id,
    required this.payload,
    required this.cipherSize,
    required this.version,
    this.folderId,
  });

  final String id;
  final String payload;
  final int cipherSize;
  final int version;
  final String? folderId;

  factory StoredFileRecord.fromJson(Map<String, dynamic> json) {
    return StoredFileRecord(
      id: json['id'] as String,
      payload: json['payload'] as String,
      cipherSize: (json['cipherSize'] as num).toInt(),
      version: (json['version'] as num).toInt(),
      folderId: json['folderId'] as String?,
    );
  }
}

class DecryptedFolder {
  DecryptedFolder({
    required this.id,
    required this.name,
    required this.version,
    this.parentFolderId,
  });

  final String id;
  final String name;
  final int version;
  final String? parentFolderId;
}

class DecryptedFileFolder {
  DecryptedFileFolder({
    required this.id,
    required this.name,
    required this.version,
    this.parentFolderId,
  });

  final String id;
  final String name;
  final int version;
  final String? parentFolderId;
}

class DecryptedLoginItem {
  DecryptedLoginItem({
    required this.id,
    required this.title,
    required this.username,
    required this.password,
    required this.url,
    required this.note,
    required this.version,
    this.folderId,
  });

  final String id;
  final String title;
  final String username;
  final String password;
  final String url;
  final String note;
  final int version;
  final String? folderId;
}

class DecryptedFileRecord {
  DecryptedFileRecord({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.originalSize,
    required this.fileKey,
    required this.cipherSize,
    required this.version,
    this.chunkCipherSizes = const [],
    this.folderId,
  });

  final String id;
  final String name;
  final String mimeType;
  final int originalSize;
  final String fileKey;
  final int cipherSize;
  final int version;
  final List<int> chunkCipherSizes;
  final String? folderId;

  bool get chunked => chunkCipherSizes.isNotEmpty;
}

class PublicUser {
  PublicUser({
    required this.id,
    required this.username,
    required this.email,
    this.nickname = '',
    String avatarPreset = '',
    this.avatarUrl = '',
    this.remarkName = '',
  }) : avatarPreset = normalizeSecureXAvatarPreset(avatarPreset);

  final String id;
  final String username;
  final String nickname;
  final String avatarPreset;
  final String avatarUrl;
  final String email;
  final String remarkName;

  String get displayName {
    if (remarkName.trim().isNotEmpty) {
      return remarkName.trim();
    }
    if (nickname.trim().isNotEmpty) {
      return nickname.trim();
    }
    if (username.trim().isNotEmpty) {
      return username.trim();
    }
    return email.trim();
  }

  String get searchableText =>
      '${remarkName.toLowerCase()} ${nickname.toLowerCase()} ${username.toLowerCase()} ${email.toLowerCase()}';

  PublicUser copyWith({
    String? username,
    String? nickname,
    String? avatarPreset,
    String? avatarUrl,
    String? email,
    String? remarkName,
  }) {
    return PublicUser(
      id: id,
      username: username ?? this.username,
      nickname: nickname ?? this.nickname,
      avatarPreset: avatarPreset ?? this.avatarPreset,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      email: email ?? this.email,
      remarkName: remarkName ?? this.remarkName,
    );
  }

  factory PublicUser.fromJson(Map<String, dynamic> json) {
    return PublicUser(
      id: json['id'] as String? ?? '',
      username: json['username'] as String? ?? '',
      nickname: json['nickname'] as String? ?? '',
      avatarPreset: json['avatarPreset'] as String? ?? '',
      avatarUrl: json['avatarUrl'] as String? ?? '',
      email: json['email'] as String? ?? '',
      remarkName: json['remarkName'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'nickname': nickname,
      'avatarPreset': avatarPreset,
      'avatarUrl': avatarUrl,
      'email': email,
      'remarkName': remarkName,
    };
  }
}

class FriendAliasRecord {
  FriendAliasRecord({
    required this.friendId,
    required this.payload,
    required this.version,
  });

  final String friendId;
  final String payload;
  final int version;

  factory FriendAliasRecord.fromJson(Map<String, dynamic> json) {
    return FriendAliasRecord(
      friendId: json['friendId'] as String? ?? '',
      payload: json['payload'] as String? ?? '',
      version: (json['version'] as num?)?.toInt() ?? 1,
    );
  }
}

class FriendListResponse {
  FriendListResponse({required this.friends, required this.aliases});

  final List<PublicUser> friends;
  final List<FriendAliasRecord> aliases;
}

class FriendRequestRecord {
  FriendRequestRecord({
    required this.id,
    required this.requester,
    required this.addressee,
    required this.message,
    required this.status,
  });

  final String id;
  final PublicUser requester;
  final PublicUser addressee;
  final String message;
  final String status;

  factory FriendRequestRecord.fromJson(Map<String, dynamic> json) {
    return FriendRequestRecord(
      id: json['id'] as String? ?? '',
      requester: PublicUser.fromJson(
        json['requester'] as Map<String, dynamic>? ?? <String, dynamic>{},
      ),
      addressee: PublicUser.fromJson(
        json['addressee'] as Map<String, dynamic>? ?? <String, dynamic>{},
      ),
      message: json['message'] as String? ?? '',
      status: json['status'] as String? ?? '',
    );
  }
}

class GroupRecord {
  GroupRecord({
    required this.id,
    required this.creatorUserId,
    required this.adminUserId,
    required this.status,
    required this.isDissolved,
    required this.version,
    required this.snapshotPayload,
    required this.snapshotVersion,
    required this.members,
    this.dissolvedAt,
    this.dissolvedByUserId,
  });

  final String id;
  final String creatorUserId;
  final String adminUserId;
  final String status;
  final bool isDissolved;
  final DateTime? dissolvedAt;
  final String? dissolvedByUserId;
  final int version;
  final String snapshotPayload;
  final int snapshotVersion;
  final List<PublicUser> members;

  factory GroupRecord.fromJson(Map<String, dynamic> json) {
    return GroupRecord(
      id: json['id'] as String? ?? '',
      creatorUserId: json['creatorUserId'] as String? ?? '',
      adminUserId: json['adminUserId'] as String? ?? '',
      status: json['status'] as String? ?? 'active',
      isDissolved: json['isDissolved'] as bool? ?? false,
      dissolvedAt: DateTime.tryParse(json['dissolvedAt'] as String? ?? ''),
      dissolvedByUserId: json['dissolvedByUserId'] as String?,
      version: (json['version'] as num?)?.toInt() ?? 1,
      snapshotPayload: json['snapshotPayload'] as String? ?? '',
      snapshotVersion: (json['snapshotVersion'] as num?)?.toInt() ?? 0,
      members: (json['members'] as List<dynamic>? ?? const [])
          .map((entry) => PublicUser.fromJson(entry as Map<String, dynamic>))
          .toList(),
    );
  }
}

class ChatArchiveRecord {
  ChatArchiveRecord({required this.payload, required this.version});

  final String payload;
  final int version;

  factory ChatArchiveRecord.fromJson(Map<String, dynamic> json) {
    return ChatArchiveRecord(
      payload: json['payload'] as String? ?? '',
      version: (json['version'] as num?)?.toInt() ?? 0,
    );
  }
}

class ChatArchiveManifestRecord {
  ChatArchiveManifestRecord({
    required this.formatVersion,
    required this.conversations,
  });

  final int formatVersion;
  final List<ChatArchiveConversationSummaryRecord> conversations;

  factory ChatArchiveManifestRecord.fromJson(Map<String, dynamic> json) {
    return ChatArchiveManifestRecord(
      formatVersion: (json['formatVersion'] as num?)?.toInt() ?? 0,
      conversations: (json['conversations'] as List<dynamic>? ?? const [])
          .map(
            (entry) => ChatArchiveConversationSummaryRecord.fromJson(
              entry as Map<String, dynamic>,
            ),
          )
          .toList(),
    );
  }
}

class ChatArchiveConversationSummaryRecord {
  ChatArchiveConversationSummaryRecord({
    required this.conversationId,
    required this.summaryPayload,
    required this.version,
    required this.updatedAt,
  });

  final String conversationId;
  final String summaryPayload;
  final int version;
  final DateTime? updatedAt;

  factory ChatArchiveConversationSummaryRecord.fromJson(
    Map<String, dynamic> json,
  ) {
    return ChatArchiveConversationSummaryRecord(
      conversationId: json['conversationId'] as String? ?? '',
      summaryPayload: json['summaryPayload'] as String? ?? '',
      version: (json['version'] as num?)?.toInt() ?? 0,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
    );
  }
}

class ChatArchiveConversationRecord {
  ChatArchiveConversationRecord({
    required this.conversationId,
    required this.summaryPayload,
    required this.payload,
    required this.version,
    required this.updatedAt,
  });

  final String conversationId;
  final String summaryPayload;
  final String payload;
  final int version;
  final DateTime? updatedAt;

  factory ChatArchiveConversationRecord.fromJson(Map<String, dynamic> json) {
    return ChatArchiveConversationRecord(
      conversationId: json['conversationId'] as String? ?? '',
      summaryPayload: json['summaryPayload'] as String? ?? '',
      payload: json['payload'] as String? ?? '',
      version: (json['version'] as num?)?.toInt() ?? 0,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
    );
  }
}

class ChatDeviceRecord {
  ChatDeviceRecord({
    required this.id,
    required this.userId,
    required this.protocol,
    required this.protocolVersion,
    required this.publicKey,
    required this.appInstance,
    this.lastSeenAt,
  });

  final String id;
  final String userId;
  final String protocol;
  final int protocolVersion;
  final String publicKey;
  final String appInstance;
  final DateTime? lastSeenAt;

  factory ChatDeviceRecord.fromJson(Map<String, dynamic> json) {
    return ChatDeviceRecord(
      id: json['id'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      protocol: json['protocol'] as String? ?? '',
      protocolVersion: (json['protocolVersion'] as num?)?.toInt() ?? 1,
      publicKey: json['publicKey'] as String? ?? '',
      appInstance: json['appInstance'] as String? ?? '',
      lastSeenAt: DateTime.tryParse(json['lastSeenAt'] as String? ?? ''),
    );
  }
}

class QueuedChatEnvelopeRecord {
  QueuedChatEnvelopeRecord({
    required this.id,
    required this.senderUserId,
    required this.senderDeviceId,
    required this.protocol,
    required this.payload,
  });

  final String id;
  final String senderUserId;
  final String senderDeviceId;
  final String protocol;
  final String payload;

  factory QueuedChatEnvelopeRecord.fromJson(Map<String, dynamic> json) {
    return QueuedChatEnvelopeRecord(
      id: json['id'] as String? ?? '',
      senderUserId: json['senderUserId'] as String? ?? '',
      senderDeviceId: json['senderDeviceId'] as String? ?? '',
      protocol: json['protocol'] as String? ?? '',
      payload: json['payload'] as String? ?? '',
    );
  }
}

class ChatPresenceRecord {
  ChatPresenceRecord({
    required this.userId,
    required this.online,
    this.lastSeenAt,
  });

  final String userId;
  final bool online;
  final DateTime? lastSeenAt;

  factory ChatPresenceRecord.fromJson(Map<String, dynamic> json) {
    return ChatPresenceRecord(
      userId: json['userId'] as String? ?? '',
      online: json['online'] as bool? ?? false,
      lastSeenAt: DateTime.tryParse(json['lastSeenAt'] as String? ?? ''),
    );
  }
}

class RealtimeConfig {
  RealtimeConfig({
    required this.transport,
    required this.signalingUrl,
    required this.signalingEnabled,
    required this.iceServers,
    required this.rtc,
  });

  final String transport;
  final String signalingUrl;
  final bool signalingEnabled;
  final List<String> iceServers;
  final RealtimeRtcConfig rtc;

  factory RealtimeConfig.fromJson(Map<String, dynamic> json) {
    return RealtimeConfig(
      transport: json['transport'] as String? ?? 'webrtc',
      signalingUrl: json['signalingUrl'] as String? ?? '',
      signalingEnabled: json['signalingEnabled'] as bool? ?? false,
      iceServers: (json['iceServers'] as List<dynamic>? ?? [])
          .map((entry) => entry.toString())
          .toList(),
      rtc: RealtimeRtcConfig.fromJson(
        json['rtc'] as Map<String, dynamic>? ?? const {},
      ),
    );
  }
}

class RealtimeRtcConfig {
  RealtimeRtcConfig({
    required this.provider,
    required this.enabled,
    required this.url,
    required this.turnMode,
  });

  final String provider;
  final bool enabled;
  final String url;
  final String turnMode;

  bool get liveKitReady => provider == 'livekit' && enabled && url.isNotEmpty;

  factory RealtimeRtcConfig.fromJson(Map<String, dynamic> json) {
    return RealtimeRtcConfig(
      provider: json['provider'] as String? ?? 'none',
      enabled: json['enabled'] as bool? ?? false,
      url: json['url'] as String? ?? '',
      turnMode: json['turnMode'] as String? ?? '',
    );
  }
}

class LiveKitCallToken {
  LiveKitCallToken({
    required this.url,
    required this.token,
    required this.room,
    required this.turnMode,
    required this.media,
    required this.expiresIn,
  });

  final String url;
  final String token;
  final String room;
  final String turnMode;
  final String media;
  final int expiresIn;

  factory LiveKitCallToken.fromJson(Map<String, dynamic> json) {
    return LiveKitCallToken(
      url: json['url'] as String? ?? '',
      token: json['token'] as String? ?? '',
      room: json['room'] as String? ?? '',
      turnMode: json['turnMode'] as String? ?? '',
      media: json['media'] as String? ?? 'audio',
      expiresIn: (json['expiresIn'] as num?)?.toInt() ?? 0,
    );
  }
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.friendId,
    required this.text,
    required this.sentByMe,
    required this.createdAt,
    required this.status,
    this.isRead = true,
    this.senderId = '',
    this.senderName = '',
    this.sentPeerIds = const [],
    this.deliveredPeerIds = const [],
    this.attachmentType = '',
    this.attachmentName = '',
    this.attachmentMimeType = '',
    this.attachmentSize = 0,
    this.attachmentDataBase64 = '',
    this.attachmentObjectId = '',
    this.attachmentKeyBase64 = '',
  });

  final String id;
  final String friendId;
  final String text;
  final bool sentByMe;
  final DateTime createdAt;
  final String status;
  final bool isRead;
  final String senderId;
  final String senderName;
  final List<String> sentPeerIds;
  final List<String> deliveredPeerIds;
  final String attachmentType;
  final String attachmentName;
  final String attachmentMimeType;
  final int attachmentSize;
  final String attachmentDataBase64;
  final String attachmentObjectId;
  final String attachmentKeyBase64;

  bool get hasAttachment =>
      attachmentType.isNotEmpty &&
      (attachmentDataBase64.isNotEmpty ||
          (attachmentObjectId.isNotEmpty && attachmentKeyBase64.isNotEmpty));

  bool get isImageAttachment => attachmentType == 'image';

  bool get isAudioAttachment => attachmentType == 'audio';

  bool get isVideoAttachment => attachmentType == 'video';

  ChatMessage copyWith({
    String? id,
    String? friendId,
    String? text,
    bool? sentByMe,
    DateTime? createdAt,
    String? status,
    bool? isRead,
    String? senderId,
    String? senderName,
    List<String>? sentPeerIds,
    List<String>? deliveredPeerIds,
    String? attachmentType,
    String? attachmentName,
    String? attachmentMimeType,
    int? attachmentSize,
    String? attachmentDataBase64,
    String? attachmentObjectId,
    String? attachmentKeyBase64,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      friendId: friendId ?? this.friendId,
      text: text ?? this.text,
      sentByMe: sentByMe ?? this.sentByMe,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      isRead: isRead ?? this.isRead,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      sentPeerIds: sentPeerIds ?? this.sentPeerIds,
      deliveredPeerIds: deliveredPeerIds ?? this.deliveredPeerIds,
      attachmentType: attachmentType ?? this.attachmentType,
      attachmentName: attachmentName ?? this.attachmentName,
      attachmentMimeType: attachmentMimeType ?? this.attachmentMimeType,
      attachmentSize: attachmentSize ?? this.attachmentSize,
      attachmentDataBase64: attachmentDataBase64 ?? this.attachmentDataBase64,
      attachmentObjectId: attachmentObjectId ?? this.attachmentObjectId,
      attachmentKeyBase64: attachmentKeyBase64 ?? this.attachmentKeyBase64,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'friendId': friendId,
      'text': text,
      'sentByMe': sentByMe,
      'createdAt': createdAt.toIso8601String(),
      'status': status,
      'isRead': isRead,
      'senderId': senderId,
      'senderName': senderName,
      'sentPeerIds': sentPeerIds,
      'deliveredPeerIds': deliveredPeerIds,
      'attachmentType': attachmentType,
      'attachmentName': attachmentName,
      'attachmentMimeType': attachmentMimeType,
      'attachmentSize': attachmentSize,
      'attachmentDataBase64': attachmentDataBase64,
      'attachmentObjectId': attachmentObjectId,
      'attachmentKeyBase64': attachmentKeyBase64,
    };
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String? ?? '',
      friendId: json['friendId'] as String? ?? '',
      text: json['text'] as String? ?? '',
      sentByMe: json['sentByMe'] as bool? ?? false,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      status: json['status'] as String? ?? 'localOnly',
      isRead: json['isRead'] as bool? ?? true,
      senderId: json['senderId'] as String? ?? '',
      senderName: json['senderName'] as String? ?? '',
      sentPeerIds: (json['sentPeerIds'] as List<dynamic>? ?? const [])
          .map((entry) => entry.toString())
          .where((entry) => entry.isNotEmpty)
          .toList(),
      deliveredPeerIds: (json['deliveredPeerIds'] as List<dynamic>? ?? const [])
          .map((entry) => entry.toString())
          .where((entry) => entry.isNotEmpty)
          .toList(),
      attachmentType: json['attachmentType'] as String? ?? '',
      attachmentName: json['attachmentName'] as String? ?? '',
      attachmentMimeType: json['attachmentMimeType'] as String? ?? '',
      attachmentSize: (json['attachmentSize'] as num?)?.toInt() ?? 0,
      attachmentDataBase64: json['attachmentDataBase64'] as String? ?? '',
      attachmentObjectId: json['attachmentObjectId'] as String? ?? '',
      attachmentKeyBase64: json['attachmentKeyBase64'] as String? ?? '',
    );
  }
}

class ChatConversation {
  ChatConversation({
    required this.messages,
    this.friend,
    String? id,
    String? title,
    String avatarPreset = '',
    List<PublicUser>? members,
    this.adminUserId = '',
    this.isGroup = false,
    this.groupStatus = 'active',
    this.isDissolved = false,
    this.dissolvedByUserId,
    this.dissolvedAt,
    this.archiveVersion = 0,
  }) : id = id ?? friend?.id ?? '',
       avatarPreset = normalizeSecureXAvatarPreset(
         avatarPreset,
         group: isGroup,
       ),
       title = title ?? _chatUserDisplayName(friend),
       members = List.unmodifiable(
         members ?? (friend == null ? const <PublicUser>[] : [friend]),
       );

  final String id;
  final String title;
  final String avatarPreset;
  final PublicUser? friend;
  final List<PublicUser> members;
  final String adminUserId;
  final bool isGroup;
  final String groupStatus;
  final bool isDissolved;
  final String? dissolvedByUserId;
  final DateTime? dissolvedAt;
  final List<ChatMessage> messages;
  final int archiveVersion;

  ChatMessage? get lastMessage => messages.isEmpty ? null : messages.last;

  int get pendingCount =>
      messages.where((message) => message.status != 'delivered').length;

  int get unreadCount =>
      messages.where((message) => !message.sentByMe && !message.isRead).length;

  String get displayTitle {
    if (isGroup) {
      return title.isEmpty ? '未命名群聊' : title;
    }
    return _chatUserDisplayName(friend);
  }

  ChatConversation copyWith({
    String? id,
    String? title,
    String? avatarPreset,
    PublicUser? friend,
    List<PublicUser>? members,
    String? adminUserId,
    bool? isGroup,
    String? groupStatus,
    bool? isDissolved,
    String? dissolvedByUserId,
    DateTime? dissolvedAt,
    List<ChatMessage>? messages,
    int? archiveVersion,
  }) {
    return ChatConversation(
      id: id ?? this.id,
      title: title ?? this.title,
      avatarPreset: avatarPreset ?? this.avatarPreset,
      friend: friend ?? this.friend,
      members: members ?? this.members,
      adminUserId: adminUserId ?? this.adminUserId,
      isGroup: isGroup ?? this.isGroup,
      groupStatus: groupStatus ?? this.groupStatus,
      isDissolved: isDissolved ?? this.isDissolved,
      dissolvedByUserId: dissolvedByUserId ?? this.dissolvedByUserId,
      dissolvedAt: dissolvedAt ?? this.dissolvedAt,
      messages: messages ?? this.messages,
      archiveVersion: archiveVersion ?? this.archiveVersion,
    );
  }
}

String _chatUserDisplayName(PublicUser? user) {
  if (user == null) {
    return '';
  }
  return user.displayName;
}
