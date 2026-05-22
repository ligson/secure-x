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
  });

  final String friendId;
  final String controlId;
  final String controlType;
  final String groupId;
  final String groupName;
  final List<String> memberIds;
  final String adminUserId;
  final String removedUserId;
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
  List<String> _iceServers = [];
  bool _manualDisconnect = true;

  void Function(RealtimeIncomingMessage message)? onMessage;
  void Function(RealtimeGroupControl control)? onGroupControl;
  void Function(RealtimeHistoryRequest request)? onHistoryRequest;
  void Function(RealtimeHistoryResponse response)? onHistoryResponse;
  void Function(String friendId, String messageId)? onDelivered;
  void Function(String friendId, String status)? onPeerStatus;
  void Function(String friendId, String status)? onFriendshipUpdated;

  bool get connected => _socket?.readyState == WebSocket.open;

  Future<void> connect({
    required String signalingUrl,
    required String token,
    required String userId,
    required List<String> iceServers,
  }) async {
    if (connected && _userId == userId) {
      return;
    }

    await _closeSocketAndPeers();
    _manualDisconnect = false;
    _signalingUrl = signalingUrl;
    _token = token;
    _userId = userId;
    _iceServers = iceServers;
    await _openSocket();
  }

  Future<void> _openSocket() async {
    if (_manualDisconnect || _signalingUrl.isEmpty || _token.isEmpty) {
      return;
    }
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _socket = await WebSocket.connect(
      _signalingUrl,
      headers: {'Authorization': 'Bearer $_token'},
    );
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
  }

  Future<void> disconnect() async {
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _signalingUrl = '';
    _token = '';
    _userId = '';
    _iceServers = [];
    await _closeSocketAndPeers();
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
  }

  void _scheduleReconnect() {
    if (_reconnectTimer != null) {
      return;
    }
    _reconnectTimer = Timer(const Duration(seconds: 2), () async {
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
    final initiator = _shouldInitiateOffer(friend.id);
    await _ensurePeer(friend.id, initiator: initiator);
    if (!initiator) {
      _sendSignal(friend.id, 'connect-request', {});
    }
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
    if (!initiator && !peer.ready) {
      _sendSignal(friend.id, 'connect-request', {});
    }
    if (!peer.ready) {
      return false;
    }

    final cipherText = await _encryptText(message.text, peer.sessionKey!);
    await peer.channel!.send(
      RTCDataChannelMessage(
        jsonEncode({
          'type': 'message',
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
        }),
      ),
    );
    return true;
  }

  Future<bool> sendGroupControl({
    required PublicUser friend,
    required ChatConversation conversation,
    required String controlType,
    required String removedUserId,
    required List<String> memberIds,
    required String adminUserId,
  }) async {
    if (!connected) {
      return false;
    }

    final initiator = _shouldInitiateOffer(friend.id);
    final peer = await _ensurePeer(friend.id, initiator: initiator);
    if (!initiator && !peer.ready) {
      _sendSignal(friend.id, 'connect-request', {});
    }
    if (!peer.ready || peer.sessionKey == null) {
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
    });
    final cipherText = await _encryptText(clearPayload, peer.sessionKey!);
    await peer.channel!.send(
      RTCDataChannelMessage(
        jsonEncode({
          'type': 'group-control',
          'controlId': controlId,
          'groupId': conversation.id,
          'cipherText': cipherText,
        }),
      ),
    );
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
    if (!initiator && !peer.ready) {
      _sendSignal(friend.id, 'connect-request', {});
    }
    if (!peer.ready || peer.sessionKey == null) {
      return false;
    }

    final cipherText = await _encryptText(
      jsonEncode(payload),
      peer.sessionKey!,
    );
    await peer.channel!.send(
      RTCDataChannelMessage(
        jsonEncode({
          'type': type,
          'controlId': DateTime.now().microsecondsSinceEpoch.toString(),
          'cipherText': cipherText,
        }),
      ),
    );
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
      case 'connect-request':
        await _ensurePeer(from, initiator: _shouldInitiateOffer(from));
        break;
      case 'key':
        final peer = await _ensurePeer(from, initiator: false);
        final hadSessionKey = peer.sessionKey != null;
        await peer.setRemoteKey(payload['publicKey'] as String? ?? '');
        if (!hadSessionKey) {
          await _sendLocalKey(peer);
        }
        if (peer.ready) {
          onPeerStatus?.call(peer.friendId, 'ready');
        }
        break;
      case 'offer':
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
    }
  }

  Future<_PeerSession> _ensurePeer(
    String friendId, {
    required bool initiator,
  }) async {
    final existing = _peers[friendId];
    if (existing != null) {
      await existing.initializeKeyPair();
      if (existing.connection == null) {
        await _createPeerConnection(existing);
      }
      if (initiator && existing.channel == null && !existing.offerStarted) {
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
    await _createPeerConnection(peer);
    await _sendLocalKey(peer);

    if (initiator) {
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
      onPeerStatus?.call(peer.friendId, state.name);
    };
  }

  void _attachDataChannel(_PeerSession peer, RTCDataChannel channel) {
    peer.channel = channel;
    channel.onDataChannelState = (state) {
      onPeerStatus?.call(peer.friendId, state.name);
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
