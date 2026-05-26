import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'models.dart';

class RealtimeIncomingMessage {
  RealtimeIncomingMessage({
    required this.friendId,
    required this.messageId,
    required this.text,
    this.groupId = '',
    this.groupName = '',
    this.memberIds = const [],
    this.adminUserId = '',
  });

  final String friendId;
  final String messageId;
  final String text;
  final String groupId;
  final String groupName;
  final List<String> memberIds;
  final String adminUserId;
}

class RealtimeGroupControl {
  RealtimeGroupControl({
    required this.friendId,
    required this.controlId,
    required this.controlType,
    required this.groupId,
    required this.groupName,
    required this.memberIds,
    required this.adminUserId,
    required this.removedUserId,
    this.groupStatus = 'active',
    this.isDissolved = false,
    this.dissolvedByUserId = '',
  });

  final String friendId;
  final String controlId;
  final String controlType;
  final String groupId;
  final String groupName;
  final List<String> memberIds;
  final String adminUserId;
  final String removedUserId;
  final String groupStatus;
  final bool isDissolved;
  final String dissolvedByUserId;
}

class RealtimeHistoryRequest {
  RealtimeHistoryRequest({required this.friendId, required this.requestId});

  final String friendId;
  final String requestId;
}

class RealtimeHistoryResponse {
  RealtimeHistoryResponse({
    required this.friendId,
    required this.requestId,
    required this.conversations,
  });

  final String friendId;
  final String requestId;
  final List<Map<String, dynamic>> conversations;
}

class RealtimeChatService {
  final _x25519 = X25519();
  final _aesGcm = AesGcm.with256bits();
  final _peers = <String, _PeerSession>{};

  WebSocket? _socket;
  Timer? _reconnectTimer;
  Future<void> _signalQueue = Future.value();
  String _signalingUrl = '';
  String _token = '';
  String _userId = '';
  String _deviceId = '';
  List<String> _iceServers = [];
  bool _manualDisconnect = true;
  int _reconnectAttempt = 0;

  void Function(RealtimeIncomingMessage message)? onMessage;
  void Function(RealtimeGroupControl control)? onGroupControl;
  void Function(RealtimeHistoryRequest request)? onHistoryRequest;
  void Function(RealtimeHistoryResponse response)? onHistoryResponse;
  void Function(String friendId, String messageId)? onDelivered;
  void Function(String recipientDeviceId, String senderUserId)? onPendingChat;
  void Function(String friendId, String status)? onPeerStatus;
  void Function(String friendId, String status)? onFriendshipUpdated;
  void Function(String status)? onSignalingState;

  bool get connected => _socket?.readyState == WebSocket.open;
  bool get _preferWebRTC => _iceServers.isNotEmpty;

  Future<void> connect({
    required String signalingUrl,
    required String token,
    required String userId,
    required String deviceId,
    required List<String> iceServers,
    bool forceReconnect = false,
  }) async {
    if (!forceReconnect &&
        connected &&
        _userId == userId &&
        _deviceId == deviceId) {
      return;
    }

    await _closeSocketAndPeers();
    _manualDisconnect = false;
    _signalingUrl = signalingUrl;
    _token = token;
    _userId = userId;
    _deviceId = deviceId;
    _iceServers = iceServers;
    onSignalingState?.call('connecting');
    await _openSocket();
  }

  Future<void> _openSocket() async {
    if (_manualDisconnect || _signalingUrl.isEmpty || _token.isEmpty) {
      return;
    }
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    final signalingUri = Uri.parse(_signalingUrl);
    final websocketUri = signalingUri.replace(
      queryParameters: {
        ...signalingUri.queryParameters,
        if (_deviceId.isNotEmpty) 'deviceId': _deviceId,
      },
    );
    _socket = await WebSocket.connect(
      websocketUri.toString(),
      headers: {'Authorization': 'Bearer $_token'},
    );
    _reconnectAttempt = 0;
    _socket!.pingInterval = const Duration(seconds: 20);
    _socket!.listen(
      (data) {
        _signalQueue = _signalQueue.then((_) => _handleSignal(data)).catchError(
          (error) {
            // A malformed or out-of-order signal must not kill the listener.
            stderr.writeln('Realtime signal failed: $error');
          },
        );
      },
      onDone: _handleSocketClosed,
      onError: (_) => _handleSocketClosed(),
      cancelOnError: true,
    );
    onSignalingState?.call('connected');
  }

  Future<void> reconnect() async {
    if (_signalingUrl.isEmpty || _token.isEmpty || _userId.isEmpty) {
      return;
    }
    await connect(
      signalingUrl: _signalingUrl,
      token: _token,
      userId: _userId,
      deviceId: _deviceId,
      iceServers: _iceServers,
      forceReconnect: true,
    );
  }

  Future<void> disconnect() async {
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempt = 0;
    _signalingUrl = '';
    _token = '';
    _userId = '';
    _deviceId = '';
    _iceServers = [];
    await _closeSocketAndPeers();
    onSignalingState?.call('disconnected');
  }

  Future<void> _closeSocketAndPeers() async {
    final socket = _socket;
    _socket = null;
    for (final peer in _peers.values) {
      await peer.dispose();
    }
    _peers.clear();
    await socket?.close();
  }

  void _handleSocketClosed() {
    if (_socket == null) {
      return;
    }
    final socket = _socket;
    _socket = null;
    socket?.close();
    for (final peer in _peers.values) {
      unawaited(peer.dispose());
      onPeerStatus?.call(peer.friendId, 'disconnected');
    }
    _peers.clear();
    if (!_manualDisconnect) {
      _scheduleReconnect();
    }
    onSignalingState?.call('disconnected');
  }

  void _scheduleReconnect() {
    if (_reconnectTimer != null) {
      return;
    }
    _reconnectAttempt += 1;
    final delaySeconds = (_reconnectAttempt * 2).clamp(2, 12);
    onSignalingState?.call('reconnecting');
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () async {
      _reconnectTimer = null;
      try {
        await _openSocket();
      } catch (_) {
        if (!_manualDisconnect) {
          _scheduleReconnect();
        }
      }
    });
  }

  Future<void> openPeer(PublicUser friend) async {
    if (!connected) {
      return;
    }
    await _ensurePeer(friend.id, initiator: _preferWebRTC);
    _sendSignal(friend.id, 'connect-request', {});
  }

  Future<bool> sendMessage({
    required PublicUser friend,
    required ChatMessage message,
    ChatConversation? conversation,
  }) async {
    if (!connected) {
      return false;
    }

    final initiator = _shouldInitiateOffer(friend.id);
    final peer = await _ensurePeer(friend.id, initiator: initiator);
    if (!initiator && !peer.canSendSecurePayloads) {
      _sendSignal(friend.id, 'connect-request', {});
    }
    if (!peer.canSendSecurePayloads) {
      return false;
    }

    final cipherText = await _encryptText(message.text, peer.sessionKey!);
    final payload = {
      'messageId': message.id,
      'chatKind': conversation?.isGroup == true ? 'group' : 'direct',
      'groupId': conversation?.isGroup == true ? conversation!.id : '',
      'groupName': conversation?.isGroup == true ? conversation!.title : '',
      'memberIds': conversation?.isGroup == true
          ? [_userId, ...conversation!.members.map((member) => member.id)]
          : const <String>[],
      'adminUserId': conversation?.isGroup == true
          ? conversation!.adminUserId
          : '',
      'cipherText': cipherText,
    };
    if (_preferWebRTC && peer.ready) {
      await peer.channel!.send(
        RTCDataChannelMessage(jsonEncode({'type': 'message', ...payload})),
      );
      return true;
    }
    _sendSignal(friend.id, 'relay-message', payload);
    return true;
  }

  Future<bool> sendGroupControl({
    required PublicUser friend,
    required ChatConversation conversation,
    required String controlType,
    required String removedUserId,
    required List<String> memberIds,
    required String adminUserId,
    String groupStatus = 'active',
    bool isDissolved = false,
    String dissolvedByUserId = '',
  }) async {
    if (!connected) {
      return false;
    }

    final initiator = _shouldInitiateOffer(friend.id);
    final peer = await _ensurePeer(friend.id, initiator: initiator);
    if (!initiator && !peer.canSendSecurePayloads) {
      _sendSignal(friend.id, 'connect-request', {});
    }
    if (!peer.canSendSecurePayloads || peer.sessionKey == null) {
      return false;
    }

    final controlId = DateTime.now().microsecondsSinceEpoch.toString();
    final clearPayload = jsonEncode({
      'controlType': controlType,
      'groupId': conversation.id,
      'groupName': conversation.title,
      'memberIds': memberIds,
      'adminUserId': adminUserId,
      'removedUserId': removedUserId,
      'groupStatus': groupStatus,
      'isDissolved': isDissolved,
      'dissolvedByUserId': dissolvedByUserId,
    });
    final cipherText = await _encryptText(clearPayload, peer.sessionKey!);
    final payload = {
      'controlId': controlId,
      'groupId': conversation.id,
      'cipherText': cipherText,
    };
    if (_preferWebRTC && peer.ready) {
      await peer.channel!.send(
        RTCDataChannelMessage(
          jsonEncode({'type': 'group-control', ...payload}),
        ),
      );
      return true;
    }
    _sendSignal(friend.id, 'relay-group-control', payload);
    return true;
  }

  Future<bool> requestHistory({required PublicUser friend}) async {
    return _sendEncryptedControl(
      friend: friend,
      type: 'history-request',
      payload: {'requestId': DateTime.now().microsecondsSinceEpoch.toString()},
    );
  }

  Future<bool> sendHistoryResponse({
    required PublicUser friend,
    required String requestId,
    required List<Map<String, dynamic>> conversations,
  }) async {
    return _sendEncryptedControl(
      friend: friend,
      type: 'history-response',
      payload: {'requestId': requestId, 'conversations': conversations},
    );
  }

  Future<bool> _sendEncryptedControl({
    required PublicUser friend,
    required String type,
    required Map<String, dynamic> payload,
  }) async {
    if (!connected) {
      return false;
    }

    final initiator = _shouldInitiateOffer(friend.id);
    final peer = await _ensurePeer(friend.id, initiator: initiator);
    if (!initiator && !peer.canSendSecurePayloads) {
      _sendSignal(friend.id, 'connect-request', {});
    }
    if (!peer.canSendSecurePayloads || peer.sessionKey == null) {
      return false;
    }

    final cipherText = await _encryptText(
      jsonEncode(payload),
      peer.sessionKey!,
    );
    final payloadWithCipher = {
      'controlId': DateTime.now().microsecondsSinceEpoch.toString(),
      'cipherText': cipherText,
    };
    if (_preferWebRTC && peer.ready) {
      await peer.channel!.send(
        RTCDataChannelMessage(jsonEncode({'type': type, ...payloadWithCipher})),
      );
      return true;
    }
    final relayType = switch (type) {
      'history-request' => 'relay-history-request',
      'history-response' => 'relay-history-response',
      _ => type,
    };
    _sendSignal(friend.id, relayType, payloadWithCipher);
    return true;
  }

  Future<void> _handleSignal(dynamic data) async {
    final raw = jsonDecode(data as String) as Map<String, dynamic>;
    final type = raw['type'] as String? ?? '';
    final from = raw['from'] as String? ?? '';
    final payload = raw['payload'] as Map<String, dynamic>? ?? {};
    if (from.isEmpty || type.isEmpty) {
      return;
    }

    switch (type) {
      case 'presence':
        final online = payload['online'] as bool? ?? false;
        onPeerStatus?.call(
          from,
          online ? 'presence-online' : 'presence-offline',
        );
        break;
      case 'friendship-updated':
        onFriendshipUpdated?.call(
          payload['friendId'] as String? ?? from,
          payload['status'] as String? ?? '',
        );
        break;
      case 'chat-pending':
        onPendingChat?.call(
          payload['recipientDeviceId'] as String? ?? '',
          from,
        );
        break;
      case 'connect-request':
        await _ensurePeer(
          from,
          initiator: _preferWebRTC && _shouldInitiateOffer(from),
        );
        break;
      case 'key':
        final peer = await _ensurePeer(from, initiator: false);
        final hadSessionKey = peer.sessionKey != null;
        await peer.setRemoteKey(payload['publicKey'] as String? ?? '');
        if (!hadSessionKey) {
          await _sendLocalKey(peer);
        }
        if (peer.sessionKey != null) {
          onPeerStatus?.call(
            peer.friendId,
            peer.ready ? 'ready' : 'relay-ready',
          );
        }
        break;
      case 'offer':
        if (!_preferWebRTC) {
          return;
        }
        if (_shouldInitiateOffer(from)) {
          return;
        }
        final peer = await _ensurePeer(from, initiator: false);
        final connection = peer.connection;
        if (connection == null) {
          return;
        }
        await connection.setRemoteDescription(
          RTCSessionDescription(
            payload['sdp'] as String? ?? '',
            payload['sdpType'] as String? ?? 'offer',
          ),
        );
        peer.remoteDescriptionSet = true;
        await _drainPendingCandidates(peer);
        final answer = await connection.createAnswer();
        await connection.setLocalDescription(answer);
        _sendSignal(from, 'answer', {
          'sdp': answer.sdp,
          'sdpType': answer.type,
        });
        break;
      case 'answer':
        if (!_preferWebRTC) {
          return;
        }
        final peer = _peers[from];
        if (peer == null || peer.connection == null) {
          return;
        }
        await peer.connection!.setRemoteDescription(
          RTCSessionDescription(
            payload['sdp'] as String? ?? '',
            payload['sdpType'] as String? ?? 'answer',
          ),
        );
        peer.remoteDescriptionSet = true;
        await _drainPendingCandidates(peer);
        break;
      case 'candidate':
        if (!_preferWebRTC) {
          return;
        }
        final peer = await _ensurePeer(from, initiator: false);
        final candidate = payload['candidate'] as String? ?? '';
        final connection = peer.connection;
        if (candidate.isEmpty || connection == null) {
          return;
        }
        final iceCandidate = RTCIceCandidate(
          candidate,
          payload['sdpMid'] as String?,
          (payload['sdpMLineIndex'] as num?)?.toInt(),
        );
        if (!peer.remoteDescriptionSet) {
          peer.pendingCandidates.add(iceCandidate);
          return;
        }
        await connection.addCandidate(iceCandidate);
        break;
      case 'relay-message':
        await _handleRelayMessage(from, payload);
        break;
      case 'relay-ack':
        onDelivered?.call(from, payload['messageId'] as String? ?? '');
        break;
      case 'relay-group-control':
        await _handleRelayGroupControl(from, payload);
        break;
      case 'relay-history-request':
        await _handleRelayHistoryRequest(from, payload);
        break;
      case 'relay-history-response':
        await _handleRelayHistoryResponse(from, payload);
        break;
    }
  }

  Future<_PeerSession> _ensurePeer(
    String friendId, {
    required bool initiator,
  }) async {
    final existing = _peers[friendId];
    if (existing != null) {
      await existing.initializeKeyPair();
      if (_preferWebRTC && existing.connection == null) {
        await _createPeerConnection(existing);
      }
      if (existing.sessionKey == null) {
        await _sendLocalKey(existing);
      }
      if (_preferWebRTC &&
          initiator &&
          existing.channel == null &&
          !existing.offerStarted) {
        await _startOffer(existing);
      }
      return existing;
    }

    final peer = _PeerSession(
      localUserId: _userId,
      friendId: friendId,
      x25519: _x25519,
    );
    _peers[friendId] = peer;
    await peer.initializeKeyPair();
    await _sendLocalKey(peer);
    if (_preferWebRTC) {
      await _createPeerConnection(peer);
    }
    if (_preferWebRTC && initiator) {
      await _startOffer(peer);
    }

    return peer;
  }

  Future<void> _startOffer(_PeerSession peer) async {
    final connection = peer.connection;
    if (connection == null || peer.offerStarted) {
      return;
    }
    peer.offerStarted = true;
    final channel = await connection.createDataChannel(
      'securex-chat',
      RTCDataChannelInit(),
    );
    _attachDataChannel(peer, channel);
    final offer = await connection.createOffer();
    await connection.setLocalDescription(offer);
    _sendSignal(peer.friendId, 'offer', {
      'sdp': offer.sdp,
      'sdpType': offer.type,
    });
  }

  bool _shouldInitiateOffer(String friendId) {
    return _userId.compareTo(friendId) < 0;
  }

  Future<void> _drainPendingCandidates(_PeerSession peer) async {
    final connection = peer.connection;
    if (connection == null || peer.pendingCandidates.isEmpty) {
      return;
    }
    final candidates = [...peer.pendingCandidates];
    peer.pendingCandidates.clear();
    for (final candidate in candidates) {
      await connection.addCandidate(candidate);
    }
  }

  Future<void> _createPeerConnection(_PeerSession peer) async {
    final configuration = <String, dynamic>{
      'iceServers': [
        if (_iceServers.isNotEmpty) {'urls': _iceServers},
      ],
    };
    final connection = await createPeerConnection(configuration);
    peer.connection = connection;

    connection.onIceCandidate = (candidate) {
      final candidateValue = candidate.candidate;
      if (candidateValue == null || candidateValue.isEmpty) {
        return;
      }
      _sendSignal(peer.friendId, 'candidate', {
        'candidate': candidateValue,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };
    connection.onDataChannel = (channel) {
      _attachDataChannel(peer, channel);
    };
    connection.onConnectionState = (state) {
      onPeerStatus?.call(peer.friendId, 'webrtc-${state.name}');
    };
  }

  void _attachDataChannel(_PeerSession peer, RTCDataChannel channel) {
    peer.channel = channel;
    channel.onDataChannelState = (state) {
      onPeerStatus?.call(peer.friendId, 'data-${state.name}');
      if (peer.ready) {
        onPeerStatus?.call(peer.friendId, 'ready');
      }
    };
    channel.onMessage = (message) async {
      if (message.isBinary) {
        return;
      }
      await _handleDataChannelMessage(peer, message.text);
    };
  }

  Future<void> _handleDataChannelMessage(
    _PeerSession peer,
    String rawMessage,
  ) async {
    final data = jsonDecode(rawMessage) as Map<String, dynamic>;
    final type = data['type'] as String? ?? '';
    if (type == 'ack') {
      onDelivered?.call(peer.friendId, data['messageId'] as String? ?? '');
      return;
    }
    if (type == 'group-control' && peer.sessionKey != null) {
      final clear = await _decryptText(
        data['cipherText'] as String? ?? '',
        peer.sessionKey!,
      );
      final payload = jsonDecode(clear) as Map<String, dynamic>;
      onGroupControl?.call(
        RealtimeGroupControl(
          friendId: peer.friendId,
          controlId: data['controlId'] as String? ?? '',
          controlType: payload['controlType'] as String? ?? '',
          groupId: payload['groupId'] as String? ?? '',
          groupName: payload['groupName'] as String? ?? '',
          memberIds: (payload['memberIds'] as List<dynamic>? ?? const [])
              .map((entry) => entry.toString())
              .where((entry) => entry.isNotEmpty)
              .toList(),
          adminUserId: payload['adminUserId'] as String? ?? '',
          removedUserId: payload['removedUserId'] as String? ?? '',
          groupStatus: payload['groupStatus'] as String? ?? 'active',
          isDissolved: payload['isDissolved'] as bool? ?? false,
          dissolvedByUserId: payload['dissolvedByUserId'] as String? ?? '',
        ),
      );
      return;
    }
    if (type == 'history-request' && peer.sessionKey != null) {
      final clear = await _decryptText(
        data['cipherText'] as String? ?? '',
        peer.sessionKey!,
      );
      final payload = jsonDecode(clear) as Map<String, dynamic>;
      onHistoryRequest?.call(
        RealtimeHistoryRequest(
          friendId: peer.friendId,
          requestId: payload['requestId'] as String? ?? '',
        ),
      );
      return;
    }
    if (type == 'history-response' && peer.sessionKey != null) {
      final clear = await _decryptText(
        data['cipherText'] as String? ?? '',
        peer.sessionKey!,
      );
      final payload = jsonDecode(clear) as Map<String, dynamic>;
      onHistoryResponse?.call(
        RealtimeHistoryResponse(
          friendId: peer.friendId,
          requestId: payload['requestId'] as String? ?? '',
          conversations:
              (payload['conversations'] as List<dynamic>? ?? const [])
                  .map((entry) => entry as Map<String, dynamic>)
                  .toList(),
        ),
      );
      return;
    }
    if (type != 'message' || peer.sessionKey == null) {
      return;
    }

    final messageId = data['messageId'] as String? ?? '';
    final text = await _decryptText(
      data['cipherText'] as String? ?? '',
      peer.sessionKey!,
    );
    onMessage?.call(
      RealtimeIncomingMessage(
        friendId: peer.friendId,
        messageId: messageId,
        text: text,
        groupId: data['groupId'] as String? ?? '',
        groupName: data['groupName'] as String? ?? '',
        memberIds: (data['memberIds'] as List<dynamic>? ?? const [])
            .map((entry) => entry.toString())
            .where((entry) => entry.isNotEmpty)
            .toList(),
        adminUserId: data['adminUserId'] as String? ?? '',
      ),
    );
    await peer.channel?.send(
      RTCDataChannelMessage(
        jsonEncode({'type': 'ack', 'messageId': messageId}),
      ),
    );
  }

  Future<void> _handleRelayMessage(
    String from,
    Map<String, dynamic> payload,
  ) async {
    final peer = await _ensurePeer(from, initiator: false);
    if (peer.sessionKey == null) {
      return;
    }
    final messageId = payload['messageId'] as String? ?? '';
    final text = await _decryptText(
      payload['cipherText'] as String? ?? '',
      peer.sessionKey!,
    );
    onMessage?.call(
      RealtimeIncomingMessage(
        friendId: from,
        messageId: messageId,
        text: text,
        groupId: payload['groupId'] as String? ?? '',
        groupName: payload['groupName'] as String? ?? '',
        memberIds: (payload['memberIds'] as List<dynamic>? ?? const [])
            .map((entry) => entry.toString())
            .where((entry) => entry.isNotEmpty)
            .toList(),
        adminUserId: payload['adminUserId'] as String? ?? '',
      ),
    );
    _sendSignal(from, 'relay-ack', {'messageId': messageId});
  }

  Future<void> _handleRelayGroupControl(
    String from,
    Map<String, dynamic> payload,
  ) async {
    final peer = await _ensurePeer(from, initiator: false);
    if (peer.sessionKey == null) {
      return;
    }
    final clear = await _decryptText(
      payload['cipherText'] as String? ?? '',
      peer.sessionKey!,
    );
    final data = jsonDecode(clear) as Map<String, dynamic>;
    onGroupControl?.call(
      RealtimeGroupControl(
        friendId: from,
        controlId: payload['controlId'] as String? ?? '',
        controlType: data['controlType'] as String? ?? '',
        groupId: data['groupId'] as String? ?? '',
        groupName: data['groupName'] as String? ?? '',
        memberIds: (data['memberIds'] as List<dynamic>? ?? const [])
            .map((entry) => entry.toString())
            .where((entry) => entry.isNotEmpty)
            .toList(),
        adminUserId: data['adminUserId'] as String? ?? '',
        removedUserId: data['removedUserId'] as String? ?? '',
        groupStatus: data['groupStatus'] as String? ?? 'active',
        isDissolved: data['isDissolved'] as bool? ?? false,
        dissolvedByUserId: data['dissolvedByUserId'] as String? ?? '',
      ),
    );
  }

  Future<void> _handleRelayHistoryRequest(
    String from,
    Map<String, dynamic> payload,
  ) async {
    final peer = await _ensurePeer(from, initiator: false);
    if (peer.sessionKey == null) {
      return;
    }
    final clear = await _decryptText(
      payload['cipherText'] as String? ?? '',
      peer.sessionKey!,
    );
    final data = jsonDecode(clear) as Map<String, dynamic>;
    onHistoryRequest?.call(
      RealtimeHistoryRequest(
        friendId: from,
        requestId: data['requestId'] as String? ?? '',
      ),
    );
  }

  Future<void> _handleRelayHistoryResponse(
    String from,
    Map<String, dynamic> payload,
  ) async {
    final peer = await _ensurePeer(from, initiator: false);
    if (peer.sessionKey == null) {
      return;
    }
    final clear = await _decryptText(
      payload['cipherText'] as String? ?? '',
      peer.sessionKey!,
    );
    final data = jsonDecode(clear) as Map<String, dynamic>;
    onHistoryResponse?.call(
      RealtimeHistoryResponse(
        friendId: from,
        requestId: data['requestId'] as String? ?? '',
        conversations: (data['conversations'] as List<dynamic>? ?? const [])
            .map((entry) => entry as Map<String, dynamic>)
            .toList(),
      ),
    );
  }

  Future<void> _sendLocalKey(_PeerSession peer) async {
    final publicKey = await peer.localPublicKeyBase64();
    _sendSignal(peer.friendId, 'key', {'publicKey': publicKey});
  }

  void _sendSignal(String to, String type, Map<String, dynamic> payload) {
    final socket = _socket;
    if (socket == null || socket.readyState != WebSocket.open) {
      return;
    }
    socket.add(jsonEncode({'type': type, 'to': to, 'payload': payload}));
  }

  Future<String> _encryptText(String text, Uint8List keyBytes) async {
    final nonce = _aesGcm.newNonce();
    final box = await _aesGcm.encrypt(
      utf8.encode(text),
      secretKey: SecretKey(keyBytes),
      nonce: nonce,
    );
    return jsonEncode({
      'algorithm': 'AES-256-GCM',
      'nonce': base64Encode(box.nonce),
      'cipherText': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    });
  }

  Future<String> _decryptText(String payload, Uint8List keyBytes) async {
    final data = jsonDecode(payload) as Map<String, dynamic>;
    final box = SecretBox(
      base64Decode(data['cipherText'] as String),
      nonce: base64Decode(data['nonce'] as String),
      mac: Mac(base64Decode(data['mac'] as String)),
    );
    final clear = await _aesGcm.decrypt(box, secretKey: SecretKey(keyBytes));
    return utf8.decode(clear);
  }
}

class _PeerSession {
  _PeerSession({
    required this.localUserId,
    required this.friendId,
    required this.x25519,
  });

  final String localUserId;
  final String friendId;
  final X25519 x25519;

  SimpleKeyPair? localKeyPair;
  Uint8List? sessionKey;
  RTCPeerConnection? connection;
  RTCDataChannel? channel;
  bool offerStarted = false;
  bool remoteDescriptionSet = false;
  final List<RTCIceCandidate> pendingCandidates = [];

  bool get ready =>
      channel?.state == RTCDataChannelState.RTCDataChannelOpen &&
      sessionKey != null;

  bool get canSendSecurePayloads => sessionKey != null;

  Future<void> initializeKeyPair() async {
    localKeyPair ??= await x25519.newKeyPair();
  }

  Future<String> localPublicKeyBase64() async {
    await initializeKeyPair();
    final publicKey = await localKeyPair!.extractPublicKey();
    return base64Encode(publicKey.bytes);
  }

  Future<void> setRemoteKey(String publicKeyBase64) async {
    if (publicKeyBase64.isEmpty || sessionKey != null) {
      return;
    }
    await initializeKeyPair();
    final remotePublicKey = SimplePublicKey(
      base64Decode(publicKeyBase64),
      type: KeyPairType.x25519,
    );
    final sharedSecret = await x25519.sharedSecretKey(
      keyPair: localKeyPair!,
      remotePublicKey: remotePublicKey,
    );
    final sharedBytes = await sharedSecret.extractBytes();
    final pair = [localUserId, friendId]..sort();
    final transcript = utf8.encode(pair.join(':'));
    final digest = await Sha256().hash([...sharedBytes, ...transcript]);
    sessionKey = Uint8List.fromList(digest.bytes);
  }

  Future<void> dispose() async {
    await channel?.close();
    await connection?.close();
    await connection?.dispose();
  }
}
