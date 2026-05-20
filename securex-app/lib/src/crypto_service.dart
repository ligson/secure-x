import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class RegisterBundle {
  RegisterBundle({
    required this.kdfAlgorithm,
    required this.masterKeySalt,
    required this.masterKeyIterations,
    required this.wrappedVaultKey,
    required this.vaultKeyBytes,
  });

  final String kdfAlgorithm;
  final String masterKeySalt;
  final int masterKeyIterations;
  final String wrappedVaultKey;
  final Uint8List vaultKeyBytes;
}

class CryptoService {
  static const int masterKeyIterations = 210000;
  static const String kdfAlgorithm = 'PBKDF2-SHA256';

  final AesGcm _aesGcm = AesGcm.with256bits();
  final Random _random = Random.secure();

  Future<RegisterBundle> createRegisterBundle(String masterPassword) async {
    final salt = _randomBytes(16);
    final masterKey = await deriveMasterKey(
      password: masterPassword,
      salt: salt,
      iterations: masterKeyIterations,
    );
    final vaultKey = _randomBytes(32);

    final wrappedVaultKey = await encryptJson({
      'vaultKey': base64Encode(vaultKey),
    }, masterKey);

    return RegisterBundle(
      kdfAlgorithm: kdfAlgorithm,
      masterKeySalt: base64Encode(salt),
      masterKeyIterations: masterKeyIterations,
      wrappedVaultKey: wrappedVaultKey,
      vaultKeyBytes: vaultKey,
    );
  }

  Future<Uint8List> deriveMasterKey({
    required String password,
    required Uint8List salt,
    required int iterations,
  }) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );

    final key = await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );

    return Uint8List.fromList(await key.extractBytes());
  }

  Future<Uint8List> unwrapVaultKey({
    required String wrappedVaultKey,
    required String masterPassword,
    required String saltBase64,
    required int iterations,
  }) async {
    final masterKey = await deriveMasterKey(
      password: masterPassword,
      salt: Uint8List.fromList(base64Decode(saltBase64)),
      iterations: iterations,
    );
    final data = await decryptJson(wrappedVaultKey, masterKey);
    return Uint8List.fromList(base64Decode(data['vaultKey'] as String));
  }

  Future<String> encryptJson(
    Map<String, dynamic> payload,
    Uint8List keyBytes,
  ) async {
    final nonce = _aesGcm.newNonce();
    final secretBox = await _aesGcm.encrypt(
      utf8.encode(jsonEncode(payload)),
      secretKey: SecretKey(keyBytes),
      nonce: nonce,
    );

    return jsonEncode({
      'algorithm': 'AES-256-GCM',
      'nonce': base64Encode(secretBox.nonce),
      'cipherText': base64Encode(secretBox.cipherText),
      'mac': base64Encode(secretBox.mac.bytes),
    });
  }

  Future<Map<String, dynamic>> decryptJson(
    String payload,
    Uint8List keyBytes,
  ) async {
    final envelope = jsonDecode(payload) as Map<String, dynamic>;
    final secretBox = SecretBox(
      base64Decode(envelope['cipherText'] as String),
      nonce: base64Decode(envelope['nonce'] as String),
      mac: Mac(base64Decode(envelope['mac'] as String)),
    );

    final clearBytes = await _aesGcm.decrypt(
      secretBox,
      secretKey: SecretKey(keyBytes),
    );

    return jsonDecode(utf8.decode(clearBytes)) as Map<String, dynamic>;
  }

  Future<Uint8List> encryptBinary(Uint8List bytes, Uint8List keyBytes) async {
    final nonce = _aesGcm.newNonce();
    final secretBox = await _aesGcm.encrypt(
      bytes,
      secretKey: SecretKey(keyBytes),
      nonce: nonce,
    );

    return Uint8List.fromList([
      ...secretBox.nonce,
      ...secretBox.mac.bytes,
      ...secretBox.cipherText,
    ]);
  }

  Future<Uint8List> decryptBinary(Uint8List bytes, Uint8List keyBytes) async {
    final nonce = bytes.sublist(0, 12);
    final mac = bytes.sublist(12, 28);
    final cipherText = bytes.sublist(28);

    final secretBox = SecretBox(cipherText, nonce: nonce, mac: Mac(mac));

    final clearBytes = await _aesGcm.decrypt(
      secretBox,
      secretKey: SecretKey(keyBytes),
    );

    return Uint8List.fromList(clearBytes);
  }

  String generatePassword({
    int length = 20,
    bool useUppercase = true,
    bool useLowercase = true,
    bool useDigits = true,
    bool useSymbols = true,
  }) {
    final buffer = StringBuffer();
    var alphabet = '';

    if (useUppercase) {
      alphabet += 'ABCDEFGHJKLMNPQRSTUVWXYZ';
    }
    if (useLowercase) {
      alphabet += 'abcdefghijkmnopqrstuvwxyz';
    }
    if (useDigits) {
      alphabet += '23456789';
    }
    if (useSymbols) {
      alphabet += '!@#\$%^&*()-_=+[]{}';
    }

    for (var i = 0; i < length; i++) {
      buffer.write(alphabet[_random.nextInt(alphabet.length)]);
    }

    return buffer.toString();
  }

  Uint8List randomKey() => _randomBytes(32);

  Uint8List _randomBytes(int length) {
    return Uint8List.fromList(
      List<int>.generate(length, (_) => _random.nextInt(256)),
    );
  }
}
