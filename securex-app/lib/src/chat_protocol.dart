import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'models.dart';

class ChatIdentityBundle {
  ChatIdentityBundle({
    required this.deviceId,
    required this.seedBase64,
    required this.publicKeyBase64,
  });

  final String deviceId;
  final String seedBase64;
  final String publicKeyBase64;
}

class ChatOutgoingEnvelope {
  ChatOutgoingEnvelope({
    required this.recipientUserId,
    required this.recipientDeviceId,
    required this.senderDeviceId,
    required this.protocol,
    required this.payload,
    this.expiresInSeconds = 2592000,
  });

  final String recipientUserId;
  final String recipientDeviceId;
  final String senderDeviceId;
  final String protocol;
  final String payload;
  final int expiresInSeconds;

  Map<String, dynamic> toJson() {
    return {
      'recipientUserId': recipientUserId,
      'recipientDeviceId': recipientDeviceId,
      'senderDeviceId': senderDeviceId,
      'protocol': protocol,
      'payload': payload,
      'expiresInSeconds': expiresInSeconds,
    };
  }
}

class ChatDecryptedEnvelope {
  ChatDecryptedEnvelope({
    required this.kind,
    required this.body,
    required this.senderUserId,
    required this.senderDeviceId,
  });

  final String kind;
  final Map<String, dynamic> body;
  final String senderUserId;
  final String senderDeviceId;
}

abstract class ChatProtocol {
  String get protocolId;

  Future<ChatIdentityBundle> createIdentity({
    required String? existingDeviceId,
    required String? existingSeedBase64,
  });

  Future<ChatOutgoingEnvelope> encryptForDevice({
    required ChatIdentityBundle senderIdentity,
    required String senderUserId,
    required ChatDeviceRecord recipientDevice,
    required String kind,
    required Map<String, dynamic> body,
  });

  Future<ChatDecryptedEnvelope> decryptEnvelope({
    required ChatIdentityBundle recipientIdentity,
    required QueuedChatEnvelopeRecord envelope,
  });
}

class SecureXChatProtocolV1 implements ChatProtocol {
  SecureXChatProtocolV1();

  static const schemaVersion = 1;
  static const protocolName = 'securex-e2ee-v1';

  final X25519 _x25519 = X25519();
  final AesGcm _aesGcm = AesGcm.with256bits();
  final Random _random = Random.secure();

  @override
  String get protocolId => protocolName;

  @override
  Future<ChatIdentityBundle> createIdentity({
    required String? existingDeviceId,
    required String? existingSeedBase64,
  }) async {
    final seed = existingSeedBase64?.trim().isNotEmpty == true
        ? base64Decode(existingSeedBase64!.trim())
        : _randomBytes(32);
    final keyPair = await _x25519.newKeyPairFromSeed(seed);
    final publicKey = await keyPair.extractPublicKey();
    return ChatIdentityBundle(
      deviceId: _normalizeDeviceId(existingDeviceId),
      seedBase64: base64Encode(seed),
      publicKeyBase64: base64Encode(publicKey.bytes),
    );
  }

  @override
  Future<ChatOutgoingEnvelope> encryptForDevice({
    required ChatIdentityBundle senderIdentity,
    required String senderUserId,
    required ChatDeviceRecord recipientDevice,
    required String kind,
    required Map<String, dynamic> body,
  }) async {
    final senderEphemeral = await _x25519.newKeyPair();
    final senderEphemeralPublic = await senderEphemeral.extractPublicKey();
    final recipientPublic = SimplePublicKey(
      base64Decode(recipientDevice.publicKey),
      type: KeyPairType.x25519,
    );
    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: senderEphemeral,
      remotePublicKey: recipientPublic,
    );
    final messageKey = await _deriveEnvelopeKey(
      sharedSecret: sharedSecret,
      senderUserId: senderUserId,
      senderDeviceId: senderIdentity.deviceId,
      recipientDeviceId: recipientDevice.id,
    );
    final clearPayload = jsonEncode({
      'schemaVersion': schemaVersion,
      'kind': kind,
      'body': body,
      'senderUserId': senderUserId,
      'senderDeviceId': senderIdentity.deviceId,
    });
    final cipherPayload = await _encryptText(clearPayload, messageKey);
    return ChatOutgoingEnvelope(
      recipientUserId: recipientDevice.userId,
      recipientDeviceId: recipientDevice.id,
      senderDeviceId: senderIdentity.deviceId,
      protocol: protocolId,
      payload: jsonEncode({
        'protocol': protocolId,
        'schemaVersion': schemaVersion,
        'senderUserId': senderUserId,
        'senderDeviceId': senderIdentity.deviceId,
        'senderEphemeralPublicKey': base64Encode(senderEphemeralPublic.bytes),
        'cipher': jsonDecode(cipherPayload),
      }),
    );
  }

  @override
  Future<ChatDecryptedEnvelope> decryptEnvelope({
    required ChatIdentityBundle recipientIdentity,
    required QueuedChatEnvelopeRecord envelope,
  }) async {
    final payload = jsonDecode(envelope.payload) as Map<String, dynamic>;
    if ((payload['protocol'] as String? ?? '') != protocolId) {
      throw const FormatException('unsupported chat protocol');
    }
    final senderUserId =
        payload['senderUserId'] as String? ?? envelope.senderUserId;
    final senderDeviceId =
        payload['senderDeviceId'] as String? ?? envelope.senderDeviceId;
    final senderEphemeral = SimplePublicKey(
      base64Decode(payload['senderEphemeralPublicKey'] as String? ?? ''),
      type: KeyPairType.x25519,
    );
    final recipientKeyPair = await _x25519.newKeyPairFromSeed(
      base64Decode(recipientIdentity.seedBase64),
    );
    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: recipientKeyPair,
      remotePublicKey: senderEphemeral,
    );
    final messageKey = await _deriveEnvelopeKey(
      sharedSecret: sharedSecret,
      senderUserId: senderUserId,
      senderDeviceId: senderDeviceId,
      recipientDeviceId: recipientIdentity.deviceId,
    );
    final cipher = jsonEncode(
      payload['cipher'] as Map<String, dynamic>? ?? <String, dynamic>{},
    );
    final clearPayload = await _decryptText(cipher, messageKey);
    final clearData = jsonDecode(clearPayload) as Map<String, dynamic>;
    return ChatDecryptedEnvelope(
      kind: clearData['kind'] as String? ?? '',
      body: clearData['body'] as Map<String, dynamic>? ?? <String, dynamic>{},
      senderUserId: clearData['senderUserId'] as String? ?? senderUserId,
      senderDeviceId: clearData['senderDeviceId'] as String? ?? senderDeviceId,
    );
  }

  Future<Uint8List> _deriveEnvelopeKey({
    required SecretKey sharedSecret,
    required String senderUserId,
    required String senderDeviceId,
    required String recipientDeviceId,
  }) async {
    final secretBytes = await sharedSecret.extractBytes();
    final transcript = utf8.encode(
      [protocolId, senderUserId, senderDeviceId, recipientDeviceId].join(':'),
    );
    final digest = await Sha256().hash([...secretBytes, ...transcript]);
    return Uint8List.fromList(digest.bytes);
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
      base64Decode(data['cipherText'] as String? ?? ''),
      nonce: base64Decode(data['nonce'] as String? ?? ''),
      mac: Mac(base64Decode(data['mac'] as String? ?? '')),
    );
    final clear = await _aesGcm.decrypt(box, secretKey: SecretKey(keyBytes));
    return utf8.decode(clear);
  }

  String _normalizeDeviceId(String? existingDeviceId) {
    final trimmed = existingDeviceId?.trim() ?? '';
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
    return base64UrlEncode(_randomBytes(18)).replaceAll('=', '');
  }

  Uint8List _randomBytes(int length) {
    return Uint8List.fromList(
      List<int>.generate(length, (_) => _random.nextInt(256)),
    );
  }
}
