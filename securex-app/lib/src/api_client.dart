import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'chat_protocol.dart';
import 'models.dart';

class ApiClient {
  ApiClient();

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  Future<Map<String, dynamic>> register({
    required String baseUrl,
    required String username,
    required String email,
    required String password,
    required String kdfAlgorithm,
    required String masterKeySalt,
    required int masterKeyIterations,
    required String wrappedVaultKey,
  }) async {
    return _unwrapMap(
      await _dio.post<Map<String, dynamic>>(
        '$baseUrl/api/v1/auth/register',
        data: {
          'username': username,
          'email': email,
          'password': password,
          'kdfAlgorithm': kdfAlgorithm,
          'masterKeySalt': masterKeySalt,
          'masterKeyIterations': masterKeyIterations,
          'wrappedVaultKey': wrappedVaultKey,
        },
      ),
    );
  }

  Future<Map<String, dynamic>> login({
    required String baseUrl,
    required String identifier,
    required String password,
  }) async {
    return _unwrapMap(
      await _dio.post<Map<String, dynamic>>(
        '$baseUrl/api/v1/auth/login',
        data: {'identifier': identifier, 'password': password},
      ),
    );
  }

  Future<UserProfile> me({
    required String baseUrl,
    required String token,
  }) async {
    final data = _unwrapMap(
      await _dio.get<Map<String, dynamic>>(
        '$baseUrl/api/v1/auth/me',
        options: _authorized(token),
      ),
    );

    return UserProfile.fromJson(
      _resolveRelativeAvatarUrls(data['user'] as Map<String, dynamic>, baseUrl)
          as Map<String, dynamic>,
    );
  }

  Future<UserProfile> updateProfile({
    required String baseUrl,
    required String token,
    required String nickname,
    required String avatarPreset,
  }) async {
    final data = _unwrapMap(
      await _dio.put<Map<String, dynamic>>(
        '$baseUrl/api/v1/auth/profile',
        data: {'nickname': nickname, 'avatarPreset': avatarPreset},
        options: _authorized(token),
      ),
    );

    return UserProfile.fromJson(
      _resolveRelativeAvatarUrls(data['user'] as Map<String, dynamic>, baseUrl)
          as Map<String, dynamic>,
    );
  }

  Future<UserProfile> uploadProfileAvatar({
    required String baseUrl,
    required String token,
    required Uint8List bytes,
    required String filename,
  }) async {
    final data = _unwrapMap(
      await _dio.post<Map<String, dynamic>>(
        '$baseUrl/api/v1/auth/profile/avatar',
        data: FormData.fromMap({
          'avatar': MultipartFile.fromBytes(bytes, filename: filename),
        }),
        options: _authorized(token),
      ),
    );

    return UserProfile.fromJson(
      _resolveRelativeAvatarUrls(data['user'] as Map<String, dynamic>, baseUrl)
          as Map<String, dynamic>,
    );
  }

  Future<void> changePassword({
    required String baseUrl,
    required String token,
    required String currentPassword,
    required String newPassword,
  }) async {
    await _dio.put<Map<String, dynamic>>(
      '$baseUrl/api/v1/auth/password',
      data: {'currentPassword': currentPassword, 'newPassword': newPassword},
      options: _authorized(token),
    );
  }

  Future<UserProfile> changeUnlockPassword({
    required String baseUrl,
    required String token,
    required String kdfAlgorithm,
    required String masterKeySalt,
    required int masterKeyIterations,
    required String wrappedVaultKey,
  }) async {
    final data = _unwrapMap(
      await _dio.put<Map<String, dynamic>>(
        '$baseUrl/api/v1/auth/unlock-password',
        data: {
          'kdfAlgorithm': kdfAlgorithm,
          'masterKeySalt': masterKeySalt,
          'masterKeyIterations': masterKeyIterations,
          'wrappedVaultKey': wrappedVaultKey,
        },
        options: _authorized(token),
      ),
    );

    return UserProfile.fromJson(
      _resolveRelativeAvatarUrls(data['user'] as Map<String, dynamic>, baseUrl)
          as Map<String, dynamic>,
    );
  }

  Future<Map<String, dynamic>> exportVault({
    required String baseUrl,
    required String token,
  }) async {
    return _unwrapMap(
      await _dio.get<Map<String, dynamic>>(
        '$baseUrl/api/v1/sync/export',
        options: _authorized(token),
      ),
    );
  }

  Future<void> createFolder({
    required String baseUrl,
    required String token,
    required String payload,
    required int version,
    String? parentFolderId,
  }) async {
    await _dio.post<Map<String, dynamic>>(
      '$baseUrl/api/v1/folders',
      data: {
        'parentFolderId': parentFolderId,
        'payload': payload,
        'version': version,
      },
      options: _authorized(token),
    );
  }

  Future<void> updateFolder({
    required String baseUrl,
    required String token,
    required String folderId,
    required String payload,
    required int version,
    String? parentFolderId,
  }) async {
    await _dio.put<Map<String, dynamic>>(
      '$baseUrl/api/v1/folders/$folderId',
      data: {
        'parentFolderId': parentFolderId,
        'payload': payload,
        'version': version,
      },
      options: _authorized(token),
    );
  }

  Future<void> deleteFolder({
    required String baseUrl,
    required String token,
    required String folderId,
  }) async {
    await _dio.delete<Map<String, dynamic>>(
      '$baseUrl/api/v1/folders/$folderId',
      options: _authorized(token),
    );
  }

  Future<void> createFileFolder({
    required String baseUrl,
    required String token,
    required String payload,
    required int version,
    String? parentFolderId,
  }) async {
    await _dio.post<Map<String, dynamic>>(
      '$baseUrl/api/v1/file-folders',
      data: {
        'parentFolderId': parentFolderId,
        'payload': payload,
        'version': version,
      },
      options: _authorized(token),
    );
  }

  Future<void> updateFileFolder({
    required String baseUrl,
    required String token,
    required String folderId,
    required String payload,
    required int version,
    String? parentFolderId,
  }) async {
    await _dio.put<Map<String, dynamic>>(
      '$baseUrl/api/v1/file-folders/$folderId',
      data: {
        'parentFolderId': parentFolderId,
        'payload': payload,
        'version': version,
      },
      options: _authorized(token),
    );
  }

  Future<void> deleteFileFolder({
    required String baseUrl,
    required String token,
    required String folderId,
  }) async {
    await _dio.delete<Map<String, dynamic>>(
      '$baseUrl/api/v1/file-folders/$folderId',
      options: _authorized(token),
    );
  }

  Future<void> createItem({
    required String baseUrl,
    required String token,
    required String kind,
    required String payload,
    required int version,
    String? folderId,
  }) async {
    await _dio.post<Map<String, dynamic>>(
      '$baseUrl/api/v1/items',
      data: {
        'folderId': folderId,
        'kind': kind,
        'payload': payload,
        'version': version,
      },
      options: _authorized(token),
    );
  }

  Future<void> updateItem({
    required String baseUrl,
    required String token,
    required String itemId,
    required String kind,
    required String payload,
    required int version,
    String? folderId,
  }) async {
    await _dio.put<Map<String, dynamic>>(
      '$baseUrl/api/v1/items/$itemId',
      data: {
        'folderId': folderId,
        'kind': kind,
        'payload': payload,
        'version': version,
      },
      options: _authorized(token),
    );
  }

  Future<void> deleteItem({
    required String baseUrl,
    required String token,
    required String itemId,
  }) async {
    await _dio.delete<Map<String, dynamic>>(
      '$baseUrl/api/v1/items/$itemId',
      options: _authorized(token),
    );
  }

  Future<void> uploadEncryptedFile({
    required String baseUrl,
    required String token,
    required String payload,
    required Uint8List cipherBytes,
    required int version,
    String? folderId,
  }) async {
    final formData = FormData.fromMap({
      'metadata': jsonEncode({
        'folderId': folderId,
        'payload': payload,
        'version': version,
      }),
      'cipher_file': MultipartFile.fromBytes(
        cipherBytes,
        filename: 'cipher.bin',
      ),
    });

    await _dio.post<Map<String, dynamic>>(
      '$baseUrl/api/v1/files',
      data: formData,
      options: _authorized(token),
    );
  }

  Future<Map<String, dynamic>> startChunkedFileUpload({
    required String baseUrl,
    required String token,
    required int totalChunks,
    required int version,
    String? folderId,
    List<String> allowedUserIds = const [],
  }) async {
    return _unwrapMap(
      await _dio.post<Map<String, dynamic>>(
        '$baseUrl/api/v1/file-uploads',
        data: {
          'folderId': folderId,
          'version': version,
          'totalChunks': totalChunks,
          'allowedUserIds': allowedUserIds,
        },
        options: _authorized(token),
      ),
    );
  }

  Future<Map<String, dynamic>> getChunkedFileUpload({
    required String baseUrl,
    required String token,
    required String uploadId,
  }) async {
    return _unwrapMap(
      await _dio.get<Map<String, dynamic>>(
        '$baseUrl/api/v1/file-uploads/$uploadId',
        options: _authorized(token),
      ),
    );
  }

  Future<void> uploadFileChunk({
    required String baseUrl,
    required String token,
    required String uploadId,
    required int index,
    required Uint8List cipherBytes,
    ProgressCallback? onSendProgress,
  }) async {
    await _dio.put<Map<String, dynamic>>(
      '$baseUrl/api/v1/file-uploads/$uploadId/chunks/$index',
      data: Stream.fromIterable([cipherBytes]),
      options: _authorized(token).copyWith(
        contentType: 'application/octet-stream',
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Length': cipherBytes.length,
        },
      ),
      onSendProgress: onSendProgress,
    );
  }

  Future<Map<String, dynamic>> completeChunkedFileUpload({
    required String baseUrl,
    required String token,
    required String uploadId,
    required String payload,
  }) async {
    return _unwrapMap(
      await _dio.post<Map<String, dynamic>>(
        '$baseUrl/api/v1/file-uploads/$uploadId/complete',
        data: {'payload': payload},
        options: _authorized(token),
      ),
    );
  }

  Future<void> updateFileMetadata({
    required String baseUrl,
    required String token,
    required String fileId,
    required String payload,
    required int version,
    String? folderId,
  }) async {
    await _dio.put<Map<String, dynamic>>(
      '$baseUrl/api/v1/files/$fileId',
      data: {'folderId': folderId, 'payload': payload, 'version': version},
      options: _authorized(token),
    );
  }

  Future<void> deleteFile({
    required String baseUrl,
    required String token,
    required String fileId,
  }) async {
    await _dio.delete<Map<String, dynamic>>(
      '$baseUrl/api/v1/files/$fileId',
      options: _authorized(token),
    );
  }

  Future<void> shareEncryptedFile({
    required String baseUrl,
    required String token,
    required String fileId,
    required List<String> allowedUserIds,
  }) async {
    await _dio.post<Map<String, dynamic>>(
      '$baseUrl/api/v1/files/$fileId/share',
      data: {'allowedUserIds': allowedUserIds},
      options: _authorized(token),
    );
  }

  Future<Uint8List> downloadEncryptedFile({
    required String baseUrl,
    required String token,
    required String fileId,
  }) async {
    final data = _unwrapMap(
      await _dio.get<Map<String, dynamic>>(
        '$baseUrl/api/v1/files/$fileId/download',
        options: _authorized(token),
      ),
    );

    return Uint8List.fromList(base64Decode(data['cipherTextBase64'] as String));
  }

  Future<Stream<Uint8List>> downloadEncryptedFileStream({
    required String baseUrl,
    required String token,
    required String fileId,
  }) async {
    final response = await _dio.get<ResponseBody>(
      '$baseUrl/api/v1/files/$fileId/download?raw=1',
      options: _authorized(token, responseType: ResponseType.stream),
    );
    final body = response.data;
    if (body == null) {
      return const Stream<Uint8List>.empty();
    }
    return body.stream.map((chunk) => Uint8List.fromList(chunk));
  }

  Future<Map<String, dynamic>> uploadChatAttachment({
    required String baseUrl,
    required String token,
    required Uint8List cipherBytes,
    required List<String> allowedUserIds,
  }) async {
    final formData = FormData.fromMap({
      'metadata': jsonEncode({'allowedUserIds': allowedUserIds}),
      'cipher_file': MultipartFile.fromBytes(
        cipherBytes,
        filename: 'chat-attachment.bin',
      ),
    });
    final data = _unwrapMap(
      await _dio.post<Map<String, dynamic>>(
        '$baseUrl/api/v1/chat/attachments',
        data: formData,
        options: _authorized(token).copyWith(
          sendTimeout: const Duration(seconds: 60),
          receiveTimeout: const Duration(seconds: 60),
        ),
      ),
    );
    return data['attachment'] as Map<String, dynamic>? ?? <String, dynamic>{};
  }

  Future<Uint8List> downloadChatAttachment({
    required String baseUrl,
    required String token,
    required String attachmentId,
  }) async {
    final data = _unwrapMap(
      await _dio.get<Map<String, dynamic>>(
        '$baseUrl/api/v1/chat/attachments/$attachmentId/download',
        options: _authorized(
          token,
        ).copyWith(receiveTimeout: const Duration(seconds: 60)),
      ),
    );
    final attachment =
        data['attachment'] as Map<String, dynamic>? ?? <String, dynamic>{};
    return Uint8List.fromList(
      base64Decode(attachment['cipherTextBase64'] as String? ?? ''),
    );
  }

  Future<FriendListResponse> listFriends({
    required String baseUrl,
    required String token,
  }) async {
    final data = _unwrapMap(
      await _dio.get<Map<String, dynamic>>(
        '$baseUrl/api/v1/friends',
        options: _authorized(token),
      ),
    );

    final friends = (data['friends'] as List<dynamic>? ?? [])
        .map(
          (entry) => PublicUser.fromJson(
            _resolveRelativeAvatarUrls(entry as Map<String, dynamic>, baseUrl)
                as Map<String, dynamic>,
          ),
        )
        .toList();
    final aliases = (data['aliases'] as List<dynamic>? ?? [])
        .map(
          (entry) => FriendAliasRecord.fromJson(entry as Map<String, dynamic>),
        )
        .toList();
    return FriendListResponse(friends: friends, aliases: aliases);
  }

  Future<Map<String, List<FriendRequestRecord>>> listFriendRequests({
    required String baseUrl,
    required String token,
  }) async {
    final data = _unwrapMap(
      await _dio.get<Map<String, dynamic>>(
        '$baseUrl/api/v1/friend-requests',
        options: _authorized(token),
      ),
    );

    List<FriendRequestRecord> parse(String key) {
      return (data[key] as List<dynamic>? ?? [])
          .map(
            (entry) => FriendRequestRecord.fromJson(
              _resolveRelativeAvatarUrls(entry as Map<String, dynamic>, baseUrl)
                  as Map<String, dynamic>,
            ),
          )
          .toList();
    }

    return {'incoming': parse('incoming'), 'outgoing': parse('outgoing')};
  }

  Future<void> sendFriendRequest({
    required String baseUrl,
    required String token,
    required String identifier,
    required String message,
  }) async {
    await _dio.post<Map<String, dynamic>>(
      '$baseUrl/api/v1/friend-requests',
      data: {'identifier': identifier, 'message': message},
      options: _authorized(token),
    );
  }

  Future<void> acceptFriendRequest({
    required String baseUrl,
    required String token,
    required String requestId,
  }) async {
    await _dio.put<Map<String, dynamic>>(
      '$baseUrl/api/v1/friend-requests/$requestId/accept',
      options: _authorized(token),
    );
  }

  Future<void> rejectFriendRequest({
    required String baseUrl,
    required String token,
    required String requestId,
  }) async {
    await _dio.put<Map<String, dynamic>>(
      '$baseUrl/api/v1/friend-requests/$requestId/reject',
      options: _authorized(token),
    );
  }

  Future<void> deleteFriend({
    required String baseUrl,
    required String token,
    required String friendId,
  }) async {
    await _dio.delete<Map<String, dynamic>>(
      '$baseUrl/api/v1/friends/$friendId',
      options: _authorized(token),
    );
  }

  Future<void> upsertFriendAlias({
    required String baseUrl,
    required String token,
    required String friendId,
    required String payload,
    required int version,
  }) async {
    await _dio.put<Map<String, dynamic>>(
      '$baseUrl/api/v1/friends/$friendId/alias',
      data: {'payload': payload, 'version': version},
      options: _authorized(token),
    );
  }

  Future<void> deleteFriendAlias({
    required String baseUrl,
    required String token,
    required String friendId,
  }) async {
    await _dio.delete<Map<String, dynamic>>(
      '$baseUrl/api/v1/friends/$friendId/alias',
      options: _authorized(token),
    );
  }

  Future<ChatArchiveRecord> getChatArchive({
    required String baseUrl,
    required String token,
  }) async {
    final data = _unwrapMap(
      await _dio.get<Map<String, dynamic>>(
        '$baseUrl/api/v1/chat/archive',
        options: _authorized(token),
      ),
    );
    return ChatArchiveRecord.fromJson(data);
  }

  Future<void> upsertChatArchive({
    required String baseUrl,
    required String token,
    required String payload,
    required int version,
  }) async {
    await _dio.put<Map<String, dynamic>>(
      '$baseUrl/api/v1/chat/archive',
      data: {'payload': payload, 'version': version},
      options: _authorized(token),
    );
  }

  Future<ChatArchiveManifestRecord> getChatArchiveManifest({
    required String baseUrl,
    required String token,
  }) async {
    final data = _unwrapMap(
      await _dio.get<Map<String, dynamic>>(
        '$baseUrl/api/v1/chat/archive/manifest',
        options: _authorized(token),
      ),
    );
    return ChatArchiveManifestRecord.fromJson(data);
  }

  Future<List<ChatArchiveConversationRecord>> listChatArchiveConversations({
    required String baseUrl,
    required String token,
    required List<String> conversationIds,
  }) async {
    final ids = conversationIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toList();
    if (ids.isEmpty) {
      return const [];
    }
    final data = _unwrapMap(
      await _dio.get<Map<String, dynamic>>(
        '$baseUrl/api/v1/chat/archive/conversations',
        queryParameters: {'ids': ids.join(',')},
        options: _authorized(token),
      ),
    );
    return (data['conversations'] as List<dynamic>? ?? const [])
        .map(
          (entry) => ChatArchiveConversationRecord.fromJson(
            entry as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  Future<void> upsertChatArchiveConversations({
    required String baseUrl,
    required String token,
    required List<Map<String, dynamic>> conversations,
    required List<String> deletedConversationIds,
  }) async {
    await _dio.put<Map<String, dynamic>>(
      '$baseUrl/api/v1/chat/archive/conversations',
      data: {
        'conversations': conversations,
        'deletedConversationIds': deletedConversationIds,
      },
      options: _authorized(token),
    );
  }

  Future<ChatDeviceRecord?> getCurrentChatDevice({
    required String baseUrl,
    required String token,
    required String deviceId,
  }) async {
    final data = _unwrapMap(
      await _dio.get<Map<String, dynamic>>(
        '$baseUrl/api/v1/chat/devices/current',
        queryParameters: {'deviceId': deviceId},
        options: _authorized(token),
      ),
    );
    final device =
        data['device'] as Map<String, dynamic>? ?? <String, dynamic>{};
    if (device.isEmpty) {
      return null;
    }
    return ChatDeviceRecord.fromJson(device);
  }

  Future<ChatDeviceRecord> upsertCurrentChatDevice({
    required String baseUrl,
    required String token,
    required String deviceId,
    required String protocol,
    required int protocolVersion,
    required String publicKey,
    required String appInstance,
  }) async {
    final data = _unwrapMap(
      await _dio.put<Map<String, dynamic>>(
        '$baseUrl/api/v1/chat/devices/current',
        data: {
          'deviceId': deviceId,
          'protocol': protocol,
          'protocolVersion': protocolVersion,
          'publicKey': publicKey,
          'appInstance': appInstance,
        },
        options: _authorized(token),
      ),
    );
    return ChatDeviceRecord.fromJson(
      data['device'] as Map<String, dynamic>? ?? <String, dynamic>{},
    );
  }

  Future<List<ChatDeviceRecord>> listUserChatDevices({
    required String baseUrl,
    required String token,
    required String userId,
  }) async {
    final data = _unwrapMap(
      await _dio.get<Map<String, dynamic>>(
        '$baseUrl/api/v1/chat/users/$userId/devices',
        options: _authorized(token),
      ),
    );
    return (data['devices'] as List<dynamic>? ?? const [])
        .map(
          (entry) => ChatDeviceRecord.fromJson(entry as Map<String, dynamic>),
        )
        .toList();
  }

  Future<List<ChatDeviceRecord>> listOwnChatDevices({
    required String baseUrl,
    required String token,
  }) async {
    final data = _unwrapMap(
      await _dio.get<Map<String, dynamic>>(
        '$baseUrl/api/v1/chat/devices',
        options: _authorized(token),
      ),
    );
    return (data['devices'] as List<dynamic>? ?? const [])
        .map(
          (entry) => ChatDeviceRecord.fromJson(entry as Map<String, dynamic>),
        )
        .toList();
  }

  Future<void> deleteOwnChatDevice({
    required String baseUrl,
    required String token,
    required String deviceId,
  }) async {
    await _dio.delete<Map<String, dynamic>>(
      '$baseUrl/api/v1/chat/devices/$deviceId',
      options: _authorized(token),
    );
  }

  Future<String> getChatDeviceRecovery({
    required String baseUrl,
    required String token,
  }) async {
    final data = _unwrapMap(
      await _dio.get<Map<String, dynamic>>(
        '$baseUrl/api/v1/chat/device-recovery',
        options: _authorized(token),
      ),
    );
    final recovery =
        data['recovery'] as Map<String, dynamic>? ?? <String, dynamic>{};
    return recovery['payload'] as String? ?? '';
  }

  Future<void> upsertChatDeviceRecovery({
    required String baseUrl,
    required String token,
    required String payload,
    required int version,
  }) async {
    await _dio.put<Map<String, dynamic>>(
      '$baseUrl/api/v1/chat/device-recovery',
      data: {'payload': payload, 'version': version},
      options: _authorized(token),
    );
  }

  Future<int> dispatchChatMessages({
    required String baseUrl,
    required String token,
    required List<ChatOutgoingEnvelope> messages,
  }) async {
    final data = _unwrapMap(
      await _dio.post<Map<String, dynamic>>(
        '$baseUrl/api/v1/chat/messages',
        data: {
          'messages': messages.map((message) => message.toJson()).toList(),
        },
        options: _authorized(token),
      ),
    );
    return (data['queuedCount'] as num?)?.toInt() ?? 0;
  }

  Future<List<QueuedChatEnvelopeRecord>> listPendingChatMessages({
    required String baseUrl,
    required String token,
    required String deviceId,
    String senderUserId = '',
  }) async {
    final data = _unwrapMap(
      await _dio.get<Map<String, dynamic>>(
        '$baseUrl/api/v1/chat/messages/pending',
        queryParameters: {
          'deviceId': deviceId,
          if (senderUserId.trim().isNotEmpty)
            'senderUserId': senderUserId.trim(),
        },
        options: _authorized(token),
      ),
    );
    return (data['messages'] as List<dynamic>? ?? const [])
        .map(
          (entry) =>
              QueuedChatEnvelopeRecord.fromJson(entry as Map<String, dynamic>),
        )
        .toList();
  }

  Future<List<ChatPresenceRecord>> listRealtimePresence({
    required String baseUrl,
    required String token,
    required List<String> userIds,
  }) async {
    final ids = userIds
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) {
      return const [];
    }

    final data = _unwrapMap(
      await _dio.get<Map<String, dynamic>>(
        '$baseUrl/api/v1/realtime/presence',
        queryParameters: {'userIds': ids},
        options: _authorized(token),
      ),
    );
    return (data['statuses'] as List<dynamic>? ?? const [])
        .map(
          (entry) => ChatPresenceRecord.fromJson(entry as Map<String, dynamic>),
        )
        .toList();
  }

  Future<void> ackChatMessages({
    required String baseUrl,
    required String token,
    required String deviceId,
    required List<String> messageIds,
  }) async {
    await _dio.post<Map<String, dynamic>>(
      '$baseUrl/api/v1/chat/messages/ack',
      data: {'deviceId': deviceId, 'messageIds': messageIds},
      options: _authorized(token),
    );
  }

  Future<List<GroupRecord>> listGroups({
    required String baseUrl,
    required String token,
  }) async {
    final data = _unwrapMap(
      await _dio.get<Map<String, dynamic>>(
        '$baseUrl/api/v1/groups',
        options: _authorized(token),
      ),
    );

    return (data['groups'] as List<dynamic>? ?? [])
        .map(
          (entry) => GroupRecord.fromJson(
            _resolveRelativeAvatarUrls(entry as Map<String, dynamic>, baseUrl)
                as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  Future<GroupRecord> createGroup({
    required String baseUrl,
    required String token,
    required String groupId,
    required String payload,
    required int version,
    required List<String> memberIds,
  }) async {
    final data = _unwrapMap(
      await _dio.post<Map<String, dynamic>>(
        '$baseUrl/api/v1/groups',
        data: {
          'groupId': groupId,
          'payload': payload,
          'version': version,
          'memberIds': memberIds,
        },
        options: _authorized(token),
      ),
    );

    return GroupRecord.fromJson(
      _resolveRelativeAvatarUrls(
            data['group'] as Map<String, dynamic>? ?? <String, dynamic>{},
            baseUrl,
          )
          as Map<String, dynamic>,
    );
  }

  Future<GroupRecord> updateGroup({
    required String baseUrl,
    required String token,
    required String groupId,
    required String payload,
    required int version,
    required List<String> memberIds,
    String? adminUserId,
  }) async {
    final data = _unwrapMap(
      await _dio.put<Map<String, dynamic>>(
        '$baseUrl/api/v1/groups/$groupId',
        data: {
          'payload': payload,
          'version': version,
          'memberIds': memberIds,
          'adminUserId': adminUserId,
        },
        options: _authorized(token),
      ),
    );

    return GroupRecord.fromJson(
      _resolveRelativeAvatarUrls(
            data['group'] as Map<String, dynamic>? ?? <String, dynamic>{},
            baseUrl,
          )
          as Map<String, dynamic>,
    );
  }

  Future<void> upsertGroupSnapshot({
    required String baseUrl,
    required String token,
    required String groupId,
    required String payload,
    required int version,
  }) async {
    await _dio.put<Map<String, dynamic>>(
      '$baseUrl/api/v1/groups/$groupId/snapshot',
      data: {'payload': payload, 'version': version},
      options: _authorized(token),
    );
  }

  Future<Map<String, dynamic>> dissolveGroup({
    required String baseUrl,
    required String token,
    required String groupId,
  }) async {
    return _unwrapMap(
      await _dio.post<Map<String, dynamic>>(
        '$baseUrl/api/v1/groups/$groupId/dissolve',
        options: _authorized(token),
      ),
    );
  }

  Future<Map<String, dynamic>> leaveGroup({
    required String baseUrl,
    required String token,
    required String groupId,
    String? nextAdminUserId,
  }) async {
    return _unwrapMap(
      await _dio.post<Map<String, dynamic>>(
        '$baseUrl/api/v1/groups/$groupId/leave',
        data: {'nextAdminUserId': nextAdminUserId},
        options: _authorized(token),
      ),
    );
  }

  Future<RealtimeConfig> realtimeConfig({
    required String baseUrl,
    required String token,
  }) async {
    final data = _unwrapMap(
      await _dio.get<Map<String, dynamic>>(
        '$baseUrl/api/v1/realtime/config',
        options: _authorized(token),
      ),
    );

    return RealtimeConfig.fromJson(data);
  }

  Future<LiveKitCallToken> createLiveKitCallToken({
    required String baseUrl,
    required String token,
    required String peerUserId,
    required String callId,
    required String media,
    required String deviceId,
  }) async {
    final data = _unwrapMap(
      await _dio.post<Map<String, dynamic>>(
        '$baseUrl/api/v1/calls/livekit-token',
        data: {
          'peerUserId': peerUserId,
          'callId': callId,
          'media': media,
          'deviceId': deviceId,
        },
        options: _authorized(token),
      ),
    );
    return LiveKitCallToken.fromJson(
      data['livekit'] as Map<String, dynamic>? ?? const {},
    );
  }

  Future<void> recordCallEvent({
    required String baseUrl,
    required String token,
    required String peerUserId,
    required String callId,
    required String media,
    required String phase,
    required String reason,
    required String deviceId,
  }) async {
    await _dio.post<Map<String, dynamic>>(
      '$baseUrl/api/v1/calls/events',
      data: {
        'peerUserId': peerUserId,
        'callId': callId,
        'media': media,
        'phase': phase,
        'reason': reason,
        'deviceId': deviceId,
      },
      options: _authorized(token),
    );
  }

  Map<String, dynamic> _unwrapMap(Response<Map<String, dynamic>> response) {
    final envelope = response.data ?? <String, dynamic>{};
    final data = envelope['data'];
    if (data is Map<String, dynamic>) {
      return data;
    }
    return <String, dynamic>{};
  }

  Options _authorized(String token, {ResponseType? responseType}) {
    return Options(
      responseType: responseType,
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  Object? _resolveRelativeAvatarUrls(Object? value, String baseUrl) {
    if (value is List) {
      return value
          .map((entry) => _resolveRelativeAvatarUrls(entry, baseUrl))
          .toList();
    }
    if (value is Map<String, dynamic>) {
      final resolved = <String, dynamic>{};
      for (final entry in value.entries) {
        resolved[entry.key] = _resolveRelativeAvatarUrls(entry.value, baseUrl);
      }
      final avatarUrl = resolved['avatarUrl'] as String? ?? '';
      if (avatarUrl.trim().isNotEmpty) {
        resolved['avatarUrl'] = _absoluteUrl(baseUrl, avatarUrl);
      }
      return resolved;
    }
    return value;
  }

  String _absoluteUrl(String baseUrl, String value) {
    final trimmed = value.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    final normalizedBase = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    return Uri.parse(normalizedBase).resolve(trimmed).toString();
  }
}
