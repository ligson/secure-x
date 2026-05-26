import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:securex_app/src/api_client.dart';
import 'package:securex_app/src/chat_protocol.dart';
import 'package:securex_app/src/crypto_service.dart';
import 'package:securex_app/src/models.dart';

const _baseUrl = 'http://127.0.0.1:8080';
const _loginPassword = '12345678';
const _unlockPassword = 'yonyou@1988';
const _smokeAppInstance = 'codex-smoke';

Future<void> main() async {
  final api = ApiClient();
  final protocol = SecureXChatProtocolV1();
  final crypto = CryptoService();

  await _assertBackendHealthy();

  final testPhone = await ChatSmokeClient.login(
    api: api,
    protocol: protocol,
    crypto: crypto,
    baseUrl: _baseUrl,
    identifier: 'test',
    password: _loginPassword,
    unlockPassword: _unlockPassword,
    deviceId: 'codex-smoke-test-phone',
  );
  final testDesktop = await ChatSmokeClient.login(
    api: api,
    protocol: protocol,
    crypto: crypto,
    baseUrl: _baseUrl,
    identifier: 'test',
    password: _loginPassword,
    unlockPassword: _unlockPassword,
    deviceId: 'codex-smoke-test-desktop',
  );
  final test2Phone = await ChatSmokeClient.login(
    api: api,
    protocol: protocol,
    crypto: crypto,
    baseUrl: _baseUrl,
    identifier: 'test2',
    password: _loginPassword,
    unlockPassword: _unlockPassword,
    deviceId: 'codex-smoke-test2-phone',
  );
  final test3Phone = await ChatSmokeClient.login(
    api: api,
    protocol: protocol,
    crypto: crypto,
    baseUrl: _baseUrl,
    identifier: 'test3',
    password: _loginPassword,
    unlockPassword: _unlockPassword,
    deviceId: 'codex-smoke-test3-phone',
  );

  final clients = [testPhone, testDesktop, test2Phone, test3Phone];
  String? tempGroupId;

  try {
    for (final client in clients) {
      await client.connect();
    }
    for (final client in clients) {
      await client.pullPendingAndProcess();
      client.resetTransientObservations();
    }

    await ensureFriendship(requester: testPhone, accepter: test2Phone);
    await ensureFriendship(requester: testPhone, accepter: test3Phone);

    await testPhone.waitPresence(test2Phone.user.id, true, 'test2 用户上线广播');
    await testPhone.waitPresence(test3Phone.user.id, true, 'test3 用户上线广播');
    await test2Phone.waitPresence(testPhone.user.id, true, 'test 用户上线广播');

    final directOnlineText = _messageText('direct-online');
    final directOnlineId = _messageId('direct-online');
    await testPhone.sendDirectMessage(
      recipientUserId: test2Phone.user.id,
      messageId: directOnlineId,
      text: directOnlineText,
    );
    await test2Phone.waitDirectMessage(
      directOnlineId,
      directOnlineText,
      '在线单聊直推',
    );
    await testPhone.waitDeliveryAckFromDevice(
      directOnlineId,
      test2Phone.identity.deviceId,
      '在线单聊送达确认',
    );

    final multiDeviceText = _messageText('multi-device');
    final multiDeviceId = _messageId('multi-device');
    await test2Phone.sendDirectMessage(
      recipientUserId: testPhone.user.id,
      messageId: multiDeviceId,
      text: multiDeviceText,
    );
    await testPhone.waitDirectMessage(
      multiDeviceId,
      multiDeviceText,
      '同账号设备 1 收到消息',
    );
    await testDesktop.waitDirectMessage(
      multiDeviceId,
      multiDeviceText,
      '同账号设备 2 收到消息',
    );
    await test2Phone.waitDeliveryAckFromDevice(
      multiDeviceId,
      testPhone.identity.deviceId,
      '设备 1 送达确认',
    );
    await test2Phone.waitDeliveryAckFromDevice(
      multiDeviceId,
      testDesktop.identity.deviceId,
      '设备 2 送达确认',
    );

    await testDesktop.disconnect();
    final perDeviceOfflineText = _messageText('device-offline');
    final perDeviceOfflineId = _messageId('device-offline');
    await test2Phone.sendDirectMessage(
      recipientUserId: testPhone.user.id,
      messageId: perDeviceOfflineId,
      text: perDeviceOfflineText,
    );
    await testPhone.waitDirectMessage(
      perDeviceOfflineId,
      perDeviceOfflineText,
      '在线设备继续收到消息',
    );
    await test2Phone.waitDeliveryAckFromDevice(
      perDeviceOfflineId,
      testPhone.identity.deviceId,
      '在线设备送达确认',
    );
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (testDesktop.hasDirectMessage(perDeviceOfflineId)) {
      throw StateError('离线设备不应在重连前直接收到单聊消息');
    }
    await testDesktop.connect();
    await testDesktop.pullPendingAndProcess();
    await testDesktop.waitDirectMessage(
      perDeviceOfflineId,
      perDeviceOfflineText,
      '离线设备重连后补拉消息',
    );
    await test2Phone.waitDeliveryAckFromDevice(
      perDeviceOfflineId,
      testDesktop.identity.deviceId,
      '离线设备补拉后的送达确认',
    );

    await test2Phone.disconnect();
    await testPhone.waitPresence(test2Phone.user.id, false, 'test2 整用户离线广播');
    final userOfflineText = _messageText('user-offline');
    final userOfflineId = _messageId('user-offline');
    await testPhone.sendDirectMessage(
      recipientUserId: test2Phone.user.id,
      messageId: userOfflineId,
      text: userOfflineText,
    );
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (test2Phone.hasDirectMessage(userOfflineId)) {
      throw StateError('整用户离线时不应直接收到单聊消息');
    }
    await test2Phone.connect();
    await testPhone.waitPresence(test2Phone.user.id, true, 'test2 重连后上线广播');
    await test2Phone.pullPendingAndProcess();
    await test2Phone.waitDirectMessage(
      userOfflineId,
      userOfflineText,
      '整用户重连补拉消息',
    );
    await testPhone.waitDeliveryAckFromDevice(
      userOfflineId,
      test2Phone.identity.deviceId,
      '整用户重连后的送达确认',
    );

    tempGroupId = 'group-smoke-${DateTime.now().microsecondsSinceEpoch}';
    await testPhone.createGroup(
      groupId: tempGroupId,
      title: 'codex-smoke-group',
      memberUserIds: [test2Phone.user.id, test3Phone.user.id],
    );
    await test2Phone.waitGroupVisible(tempGroupId, 'test2 群聊列表同步');
    await test3Phone.waitGroupVisible(tempGroupId, 'test3 群聊列表同步');

    final groupOnlineText = _messageText('group-online');
    final groupOnlineId = _messageId('group-online');
    await testPhone.sendGroupMessage(
      conversationId: tempGroupId,
      groupName: 'codex-smoke-group',
      memberUserIds: [
        testPhone.user.id,
        test2Phone.user.id,
        test3Phone.user.id,
      ],
      adminUserId: testPhone.user.id,
      recipientUserIds: [test2Phone.user.id, test3Phone.user.id],
      messageId: groupOnlineId,
      text: groupOnlineText,
    );
    await test2Phone.waitGroupMessage(
      groupOnlineId,
      groupOnlineText,
      '群聊在线消息 test2',
    );
    await test3Phone.waitGroupMessage(
      groupOnlineId,
      groupOnlineText,
      '群聊在线消息 test3',
    );
    await testPhone.waitDeliveryAckFromDevice(
      groupOnlineId,
      test2Phone.identity.deviceId,
      '群聊 test2 送达确认',
    );
    await testPhone.waitDeliveryAckFromDevice(
      groupOnlineId,
      test3Phone.identity.deviceId,
      '群聊 test3 送达确认',
    );

    await test3Phone.disconnect();
    await testPhone.waitPresence(test3Phone.user.id, false, 'test3 群成员离线广播');
    final groupOfflineText = _messageText('group-offline');
    final groupOfflineId = _messageId('group-offline');
    await testPhone.sendGroupMessage(
      conversationId: tempGroupId,
      groupName: 'codex-smoke-group',
      memberUserIds: [
        testPhone.user.id,
        test2Phone.user.id,
        test3Phone.user.id,
      ],
      adminUserId: testPhone.user.id,
      recipientUserIds: [test2Phone.user.id, test3Phone.user.id],
      messageId: groupOfflineId,
      text: groupOfflineText,
    );
    await test2Phone.waitGroupMessage(
      groupOfflineId,
      groupOfflineText,
      '群聊在线成员即时收到消息',
    );
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (test3Phone.hasGroupMessage(groupOfflineId)) {
      throw StateError('离线群成员不应在重连前直接收到群消息');
    }
    await test3Phone.connect();
    await testPhone.waitPresence(test3Phone.user.id, true, 'test3 群成员重连上线广播');
    await test3Phone.pullPendingAndProcess();
    await test3Phone.waitGroupMessage(
      groupOfflineId,
      groupOfflineText,
      '群聊离线成员补拉消息',
    );
    await testPhone.waitDeliveryAckFromDevice(
      groupOfflineId,
      test3Phone.identity.deviceId,
      '群聊离线成员补拉后的送达确认',
    );

    await testPhone.dissolveGroup(tempGroupId);
    await test2Phone.waitGroupDissolved(tempGroupId, 'test2 看到群聊已解散');
    await test3Phone.waitGroupDissolved(tempGroupId, 'test3 看到群聊已解散');
    await test2Phone.leaveGroup(tempGroupId);
    await test3Phone.leaveGroup(tempGroupId);
    tempGroupId = null;

    for (final client in clients) {
      final pending = await client.pendingMessageCount();
      if (pending != 0) {
        throw StateError(
          '${client.identifier} (${client.identity.deviceId}) 仍有未确认待处理消息：$pending',
        );
      }
    }

    stdout.writeln('聊天联调通过：单聊、群聊、多设备、整用户离线恢复、设备级离线恢复、群解散清理全部正常。');
  } finally {
    if (tempGroupId != null) {
      await _cleanupGroup(
        groupId: tempGroupId,
        owner: testPhone,
        members: [test2Phone, test3Phone],
      );
    }
    for (final client in clients) {
      await client.close();
    }
  }
}

Future<void> ensureFriendship({
  required ChatSmokeClient requester,
  required ChatSmokeClient accepter,
}) async {
  if (await requester.hasFriend(accepter.user.id) &&
      await accepter.hasFriend(requester.user.id)) {
    return;
  }

  final incoming = await accepter.friendRequests();
  final existingIncoming = incoming['incoming']!.where(
    (request) => request.requester.id == requester.user.id,
  );
  if (existingIncoming.isEmpty) {
    await requester.api.sendFriendRequest(
      baseUrl: requester.baseUrl,
      token: requester.token,
      identifier: accepter.user.username,
      message: 'codex smoke',
    );
  }

  await accepter.waitUntil(
    () async {
      final requests = await accepter.friendRequests();
      FriendRequestRecord? request;
      for (final entry in requests['incoming']!) {
        if (entry.requester.id == requester.user.id) {
          request = entry;
          break;
        }
      }
      if (request == null || request.id.isEmpty) {
        return false;
      }
      await accepter.api.acceptFriendRequest(
        baseUrl: accepter.baseUrl,
        token: accepter.token,
        requestId: request.id,
      );
      return true;
    },
    '接受好友申请 ${requester.identifier} -> ${accepter.identifier}',
    timeout: const Duration(seconds: 12),
  );

  if (!await requester.hasFriend(accepter.user.id) ||
      !await accepter.hasFriend(requester.user.id)) {
    throw StateError(
      '建立好友关系失败：${requester.identifier} <-> ${accepter.identifier}',
    );
  }
}

Future<void> _cleanupGroup({
  required String groupId,
  required ChatSmokeClient owner,
  required List<ChatSmokeClient> members,
}) async {
  try {
    await owner.dissolveGroup(groupId);
  } catch (_) {}
  for (final member in members) {
    try {
      await member.leaveGroup(groupId);
    } catch (_) {}
  }
}

Future<void> _assertBackendHealthy() async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse('$_baseUrl/healthz'));
    final response = await request.close();
    if (response.statusCode != 200) {
      throw StateError('本地后端健康检查失败：HTTP ${response.statusCode}');
    }
  } finally {
    client.close(force: true);
  }
}

String _messageId(String prefix) =>
    '$prefix-${DateTime.now().microsecondsSinceEpoch}';

String _messageText(String prefix) =>
    '$prefix-${DateTime.now().microsecondsSinceEpoch}';

class ChatSmokeClient {
  ChatSmokeClient._({
    required this.api,
    required this.protocol,
    required this.crypto,
    required this.baseUrl,
    required this.identifier,
    required this.token,
    required this.user,
    required this.identity,
    required this.vaultKey,
    required this.realtimeConfig,
  });

  final ApiClient api;
  final SecureXChatProtocolV1 protocol;
  final CryptoService crypto;
  final String baseUrl;
  final String identifier;
  final String token;
  final UserProfile user;
  final ChatIdentityBundle identity;
  final Uint8List vaultKey;
  final RealtimeConfig realtimeConfig;

  final Map<String, bool> presence = {};
  final Map<String, String> receivedDirectMessages = {};
  final Map<String, GroupSmokeMessage> receivedGroupMessages = {};
  final Map<String, Set<String>> deliveryAckDeviceIds = {};

  WebSocket? _socket;
  bool _closed = false;

  static Future<ChatSmokeClient> login({
    required ApiClient api,
    required SecureXChatProtocolV1 protocol,
    required CryptoService crypto,
    required String baseUrl,
    required String identifier,
    required String password,
    required String unlockPassword,
    required String deviceId,
  }) async {
    final loginData = await api.login(
      baseUrl: baseUrl,
      identifier: identifier,
      password: password,
    );
    final token = loginData['token'] as String? ?? '';
    if (token.isEmpty) {
      throw StateError('登录失败：$identifier 未返回 token');
    }

    final user = await api.me(baseUrl: baseUrl, token: token);
    final vaultKey = await crypto.unwrapVaultKey(
      wrappedVaultKey: user.wrappedVaultKey,
      unlockPassword: unlockPassword,
      saltBase64: user.masterKeySalt,
      iterations: user.masterKeyIterations,
    );
    final identity = await protocol.createIdentity(
      existingDeviceId: deviceId,
      existingSeedBase64: await _deterministicSeedBase64(deviceId),
    );
    await api.upsertCurrentChatDevice(
      baseUrl: baseUrl,
      token: token,
      deviceId: identity.deviceId,
      protocol: protocol.protocolId,
      protocolVersion: SecureXChatProtocolV1.schemaVersion,
      publicKey: identity.publicKeyBase64,
      appInstance: _smokeAppInstance,
    );
    final realtimeConfig = await api.realtimeConfig(
      baseUrl: baseUrl,
      token: token,
    );

    return ChatSmokeClient._(
      api: api,
      protocol: protocol,
      crypto: crypto,
      baseUrl: baseUrl,
      identifier: identifier,
      token: token,
      user: user,
      identity: identity,
      vaultKey: vaultKey,
      realtimeConfig: realtimeConfig,
    );
  }

  Future<void> connect() async {
    _closed = false;
    await disconnect();
    final baseUri = Uri.parse(realtimeConfig.signalingUrl);
    final signalingUri = baseUri.replace(
      queryParameters: {
        ...baseUri.queryParameters,
        'deviceId': identity.deviceId,
      },
    );
    _socket = await WebSocket.connect(
      signalingUri.toString(),
      headers: {'Authorization': 'Bearer $token'},
    );
    _socket!.pingInterval = const Duration(seconds: 20);
    _socket!.listen(
      _handleSocketMessage,
      onDone: () => _socket = null,
      onError: (_) => _socket = null,
      cancelOnError: true,
    );
  }

  Future<void> disconnect() async {
    final socket = _socket;
    _socket = null;
    await socket?.close();
  }

  Future<void> close() async {
    _closed = true;
    await disconnect();
  }

  void resetTransientObservations() {
    receivedDirectMessages.clear();
    receivedGroupMessages.clear();
    deliveryAckDeviceIds.clear();
  }

  Future<bool> hasFriend(String friendUserId) async {
    final friends = await api.listFriends(baseUrl: baseUrl, token: token);
    return friends.any((friend) => friend.id == friendUserId);
  }

  Future<Map<String, List<FriendRequestRecord>>> friendRequests() {
    return api.listFriendRequests(baseUrl: baseUrl, token: token);
  }

  Future<void> createGroup({
    required String groupId,
    required String title,
    required List<String> memberUserIds,
  }) async {
    final payload = await crypto.encryptJson({
      'id': groupId,
      'title': title,
      'memberIds': memberUserIds,
      'adminUserId': user.id,
    }, vaultKey);
    await api.createGroup(
      baseUrl: baseUrl,
      token: token,
      groupId: groupId,
      payload: payload,
      version: DateTime.now().millisecondsSinceEpoch,
      memberIds: memberUserIds,
    );
  }

  Future<void> dissolveGroup(String groupId) {
    return api.dissolveGroup(baseUrl: baseUrl, token: token, groupId: groupId);
  }

  Future<void> leaveGroup(String groupId) {
    return api.leaveGroup(baseUrl: baseUrl, token: token, groupId: groupId);
  }

  Future<void> sendDirectMessage({
    required String recipientUserId,
    required String messageId,
    required String text,
  }) async {
    final devices = await _smokeDevicesForUser(recipientUserId);
    if (devices.isEmpty) {
      throw StateError('未找到用户 $recipientUserId 的 smoke 聊天设备');
    }
    final outgoing = <ChatOutgoingEnvelope>[];
    for (final device in devices) {
      outgoing.add(
        await protocol.encryptForDevice(
          senderIdentity: identity,
          senderUserId: user.id,
          recipientDevice: device,
          kind: 'direct-message',
          body: {'messageId': messageId, 'text': text},
        ),
      );
    }
    await api.dispatchChatMessages(
      baseUrl: baseUrl,
      token: token,
      messages: outgoing,
    );
  }

  Future<void> sendGroupMessage({
    required String conversationId,
    required String groupName,
    required List<String> memberUserIds,
    required String adminUserId,
    required List<String> recipientUserIds,
    required String messageId,
    required String text,
  }) async {
    final outgoing = <ChatOutgoingEnvelope>[];
    for (final recipientUserId in recipientUserIds) {
      final devices = await _smokeDevicesForUser(recipientUserId);
      for (final device in devices) {
        outgoing.add(
          await protocol.encryptForDevice(
            senderIdentity: identity,
            senderUserId: user.id,
            recipientDevice: device,
            kind: 'group-message',
            body: {
              'messageId': messageId,
              'text': text,
              'groupId': conversationId,
              'groupName': groupName,
              'memberIds': memberUserIds,
              'adminUserId': adminUserId,
            },
          ),
        );
      }
    }
    if (outgoing.isEmpty) {
      throw StateError('群聊 $conversationId 没有可用 smoke 目标设备');
    }
    await api.dispatchChatMessages(
      baseUrl: baseUrl,
      token: token,
      messages: outgoing,
    );
  }

  Future<int> pendingMessageCount() async {
    final pending = await api.listPendingChatMessages(
      baseUrl: baseUrl,
      token: token,
      deviceId: identity.deviceId,
    );
    return pending.length;
  }

  Future<void> pullPendingAndProcess() async {
    final pending = await api.listPendingChatMessages(
      baseUrl: baseUrl,
      token: token,
      deviceId: identity.deviceId,
    );
    final ackIds = <String>[];
    for (final envelope in pending) {
      final handled = await _processEnvelope(envelope);
      if (handled) {
        ackIds.add(envelope.id);
      }
    }
    if (ackIds.isNotEmpty) {
      await api.ackChatMessages(
        baseUrl: baseUrl,
        token: token,
        deviceId: identity.deviceId,
        messageIds: ackIds,
      );
    }
  }

  bool hasDirectMessage(String messageId) =>
      receivedDirectMessages.containsKey(messageId);

  bool hasGroupMessage(String messageId) =>
      receivedGroupMessages.containsKey(messageId);

  Future<void> waitPresence(
    String peerUserId,
    bool online,
    String reason,
  ) async {
    await waitUntil(
      () async {
        if (presence[peerUserId] == online) {
          return true;
        }
        final statuses = await api.listRealtimePresence(
          baseUrl: baseUrl,
          token: token,
          userIds: [peerUserId],
        );
        for (final status in statuses) {
          presence[status.userId] = status.online;
        }
        return presence[peerUserId] == online;
      },
      reason,
      timeout: const Duration(seconds: 12),
    );
  }

  Future<void> waitDirectMessage(
    String messageId,
    String text,
    String reason,
  ) async {
    await waitUntil(
      () async => receivedDirectMessages[messageId] == text,
      reason,
      timeout: const Duration(seconds: 12),
    );
  }

  Future<void> waitGroupMessage(
    String messageId,
    String text,
    String reason,
  ) async {
    await waitUntil(
      () async => receivedGroupMessages[messageId]?.text == text,
      reason,
      timeout: const Duration(seconds: 12),
    );
  }

  Future<void> waitDeliveryAckFromDevice(
    String messageId,
    String deviceId,
    String reason,
  ) async {
    await waitUntil(
      () async => deliveryAckDeviceIds[messageId]?.contains(deviceId) == true,
      reason,
      timeout: const Duration(seconds: 12),
    );
  }

  Future<void> waitGroupVisible(String groupId, String reason) async {
    await waitUntil(
      () async => (await api.listGroups(
        baseUrl: baseUrl,
        token: token,
      )).any((group) => group.id == groupId),
      reason,
      timeout: const Duration(seconds: 12),
    );
  }

  Future<void> waitGroupDissolved(String groupId, String reason) async {
    await waitUntil(
      () async => (await api.listGroups(
        baseUrl: baseUrl,
        token: token,
      )).any((group) => group.id == groupId && group.isDissolved),
      reason,
      timeout: const Duration(seconds: 12),
    );
  }

  Future<void> waitUntil(
    Future<bool> Function() condition,
    String reason, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await condition()) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    throw TimeoutException('等待超时：$reason');
  }

  void _handleSocketMessage(dynamic raw) {
    if (_closed) {
      return;
    }
    final data = jsonDecode(raw as String) as Map<String, dynamic>;
    final type = data['type'] as String? ?? '';
    final from = data['from'] as String? ?? '';
    final payload = data['payload'] as Map<String, dynamic>? ?? const {};
    switch (type) {
      case 'presence':
        presence[from] = payload['online'] as bool? ?? false;
        return;
      case 'chat-envelope':
        final envelope = QueuedChatEnvelopeRecord(
          id: payload['envelopeId'] as String? ?? '',
          senderUserId: payload['senderUserId'] as String? ?? from,
          senderDeviceId: payload['senderDeviceId'] as String? ?? '',
          protocol: payload['protocol'] as String? ?? '',
          payload: payload['payload'] as String? ?? '',
        );
        unawaited(_handleRealtimeEnvelope(envelope));
        return;
      default:
        return;
    }
  }

  Future<void> _handleRealtimeEnvelope(
    QueuedChatEnvelopeRecord envelope,
  ) async {
    final handled = await _processEnvelope(envelope);
    if (!handled) {
      return;
    }
    await api.ackChatMessages(
      baseUrl: baseUrl,
      token: token,
      deviceId: identity.deviceId,
      messageIds: [envelope.id],
    );
  }

  Future<bool> _processEnvelope(QueuedChatEnvelopeRecord envelope) async {
    final decrypted = await protocol.decryptEnvelope(
      recipientIdentity: identity,
      envelope: envelope,
    );
    switch (decrypted.kind) {
      case 'direct-message':
        final messageId = decrypted.body['messageId'] as String? ?? '';
        final text = decrypted.body['text'] as String? ?? '';
        if (messageId.isEmpty || text.isEmpty) {
          return false;
        }
        receivedDirectMessages[messageId] = text;
        await _sendDeliveryAck(
          recipientUserId: decrypted.senderUserId,
          messageId: messageId,
        );
        return true;
      case 'group-message':
        final messageId = decrypted.body['messageId'] as String? ?? '';
        final text = decrypted.body['text'] as String? ?? '';
        final groupId = decrypted.body['groupId'] as String? ?? '';
        if (messageId.isEmpty || text.isEmpty || groupId.isEmpty) {
          return false;
        }
        receivedGroupMessages[messageId] = GroupSmokeMessage(
          id: messageId,
          text: text,
          groupId: groupId,
          senderUserId: decrypted.senderUserId,
        );
        await _sendDeliveryAck(
          recipientUserId: decrypted.senderUserId,
          messageId: messageId,
          groupId: groupId,
        );
        return true;
      case 'delivery-ack':
        final messageId = decrypted.body['messageId'] as String? ?? '';
        if (messageId.isEmpty) {
          return false;
        }
        deliveryAckDeviceIds
            .putIfAbsent(messageId, () => <String>{})
            .add(decrypted.senderDeviceId);
        return true;
      default:
        return true;
    }
  }

  Future<void> _sendDeliveryAck({
    required String recipientUserId,
    required String messageId,
    String groupId = '',
  }) async {
    final devices = await _smokeDevicesForUser(recipientUserId);
    if (devices.isEmpty) {
      return;
    }
    final outgoing = <ChatOutgoingEnvelope>[];
    for (final device in devices) {
      outgoing.add(
        await protocol.encryptForDevice(
          senderIdentity: identity,
          senderUserId: user.id,
          recipientDevice: device,
          kind: 'delivery-ack',
          body: {
            'messageId': messageId,
            if (groupId.isNotEmpty) 'groupId': groupId,
          },
        ),
      );
    }
    await api.dispatchChatMessages(
      baseUrl: baseUrl,
      token: token,
      messages: outgoing,
    );
  }

  Future<List<ChatDeviceRecord>> _smokeDevicesForUser(String userId) async {
    final devices = await api.listUserChatDevices(
      baseUrl: baseUrl,
      token: token,
      userId: userId,
    );
    return devices
        .where(
          (device) =>
              device.protocol == protocol.protocolId &&
              device.publicKey.isNotEmpty &&
              device.appInstance == _smokeAppInstance,
        )
        .toList();
  }
}

class GroupSmokeMessage {
  GroupSmokeMessage({
    required this.id,
    required this.text,
    required this.groupId,
    required this.senderUserId,
  });

  final String id;
  final String text;
  final String groupId;
  final String senderUserId;
}

Future<String> _deterministicSeedBase64(String deviceId) async {
  final digest = await Sha256().hash(utf8.encode('securex-smoke:$deviceId'));
  return base64Encode(digest.bytes);
}
