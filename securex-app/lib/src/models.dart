class UserProfile {
  UserProfile({
    required this.id,
    required this.username,
    required this.email,
    required this.kdfAlgorithm,
    required this.masterKeySalt,
    required this.masterKeyIterations,
    required this.wrappedVaultKey,
  });

  final String id;
  final String username;
  final String email;
  final String kdfAlgorithm;
  final String masterKeySalt;
  final int masterKeyIterations;
  final String wrappedVaultKey;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      username: json['username'] as String,
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
  PublicUser({required this.id, required this.username, required this.email});

  final String id;
  final String username;
  final String email;

  factory PublicUser.fromJson(Map<String, dynamic> json) {
    return PublicUser(
      id: json['id'] as String? ?? '',
      username: json['username'] as String? ?? '',
      email: json['email'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'username': username, 'email': email};
  }
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
    required this.version,
    required this.snapshotPayload,
    required this.snapshotVersion,
    required this.members,
  });

  final String id;
  final String creatorUserId;
  final String adminUserId;
  final int version;
  final String snapshotPayload;
  final int snapshotVersion;
  final List<PublicUser> members;

  factory GroupRecord.fromJson(Map<String, dynamic> json) {
    return GroupRecord(
      id: json['id'] as String? ?? '',
      creatorUserId: json['creatorUserId'] as String? ?? '',
      adminUserId: json['adminUserId'] as String? ?? '',
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

class ChatDeviceRecord {
  ChatDeviceRecord({
    required this.id,
    required this.userId,
    required this.protocol,
    required this.protocolVersion,
    required this.publicKey,
    required this.appInstance,
  });

  final String id;
  final String userId;
  final String protocol;
  final int protocolVersion;
  final String publicKey;
  final String appInstance;

  factory ChatDeviceRecord.fromJson(Map<String, dynamic> json) {
    return ChatDeviceRecord(
      id: json['id'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      protocol: json['protocol'] as String? ?? '',
      protocolVersion: (json['protocolVersion'] as num?)?.toInt() ?? 1,
      publicKey: json['publicKey'] as String? ?? '',
      appInstance: json['appInstance'] as String? ?? '',
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

class RealtimeConfig {
  RealtimeConfig({
    required this.transport,
    required this.signalingUrl,
    required this.signalingEnabled,
    required this.iceServers,
  });

  final String transport;
  final String signalingUrl;
  final bool signalingEnabled;
  final List<String> iceServers;

  factory RealtimeConfig.fromJson(Map<String, dynamic> json) {
    return RealtimeConfig(
      transport: json['transport'] as String? ?? 'webrtc',
      signalingUrl: json['signalingUrl'] as String? ?? '',
      signalingEnabled: json['signalingEnabled'] as bool? ?? false,
      iceServers: (json['iceServers'] as List<dynamic>? ?? [])
          .map((entry) => entry.toString())
          .toList(),
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
    this.senderId = '',
    this.senderName = '',
    this.sentPeerIds = const [],
    this.deliveredPeerIds = const [],
  });

  final String id;
  final String friendId;
  final String text;
  final bool sentByMe;
  final DateTime createdAt;
  final String status;
  final String senderId;
  final String senderName;
  final List<String> sentPeerIds;
  final List<String> deliveredPeerIds;

  ChatMessage copyWith({
    String? id,
    String? friendId,
    String? text,
    bool? sentByMe,
    DateTime? createdAt,
    String? status,
    String? senderId,
    String? senderName,
    List<String>? sentPeerIds,
    List<String>? deliveredPeerIds,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      friendId: friendId ?? this.friendId,
      text: text ?? this.text,
      sentByMe: sentByMe ?? this.sentByMe,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      sentPeerIds: sentPeerIds ?? this.sentPeerIds,
      deliveredPeerIds: deliveredPeerIds ?? this.deliveredPeerIds,
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
      'senderId': senderId,
      'senderName': senderName,
      'sentPeerIds': sentPeerIds,
      'deliveredPeerIds': deliveredPeerIds,
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
    );
  }
}

class ChatConversation {
  ChatConversation({
    required this.messages,
    this.friend,
    String? id,
    String? title,
    List<PublicUser>? members,
    this.adminUserId = '',
    this.isGroup = false,
  }) : id = id ?? friend?.id ?? '',
       title = title ?? _chatUserDisplayName(friend),
       members = List.unmodifiable(
         members ?? (friend == null ? const <PublicUser>[] : [friend]),
       );

  final String id;
  final String title;
  final PublicUser? friend;
  final List<PublicUser> members;
  final String adminUserId;
  final bool isGroup;
  final List<ChatMessage> messages;

  ChatMessage? get lastMessage => messages.isEmpty ? null : messages.last;

  int get pendingCount =>
      messages.where((message) => message.status != 'delivered').length;

  String get displayTitle {
    if (isGroup) {
      return title.isEmpty ? '未命名群聊' : title;
    }
    return _chatUserDisplayName(friend);
  }

  ChatConversation copyWith({
    String? id,
    String? title,
    PublicUser? friend,
    List<PublicUser>? members,
    String? adminUserId,
    bool? isGroup,
    List<ChatMessage>? messages,
  }) {
    return ChatConversation(
      id: id ?? this.id,
      title: title ?? this.title,
      friend: friend ?? this.friend,
      members: members ?? this.members,
      adminUserId: adminUserId ?? this.adminUserId,
      isGroup: isGroup ?? this.isGroup,
      messages: messages ?? this.messages,
    );
  }
}

String _chatUserDisplayName(PublicUser? user) {
  if (user == null) {
    return '';
  }
  return user.username.isEmpty ? user.email : user.username;
}
