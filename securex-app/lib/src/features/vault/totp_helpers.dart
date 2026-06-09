part of '../../../main.dart';

class _TotpValue {
  const _TotpValue({
    required this.code,
    required this.remainingSeconds,
    required this.period,
  });

  final String code;
  final int remainingSeconds;
  final int period;
}

TotpConfig _parseTotpInput(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    return const TotpConfig(secret: '');
  }
  final lower = trimmed.toLowerCase();
  if (!lower.startsWith('otpauth://')) {
    final secret = _normalizeTotpSecret(trimmed);
    _decodeBase32(secret);
    return TotpConfig(secret: secret);
  }

  final uri = Uri.parse(trimmed);
  if (uri.scheme.toLowerCase() != 'otpauth' ||
      uri.host.toLowerCase() != 'totp') {
    throw const FormatException('仅支持 TOTP 验证器二维码');
  }

  final secretParam = uri.queryParameters['secret'];
  if (secretParam == null || secretParam.trim().isEmpty) {
    throw const FormatException('二维码中没有验证器密钥');
  }

  final label = uri.pathSegments.isEmpty ? '' : uri.pathSegments.join('/');
  var issuer = uri.queryParameters['issuer']?.trim() ?? '';
  var account = '';
  if (label.isNotEmpty) {
    final colonIndex = label.indexOf(':');
    if (colonIndex >= 0) {
      issuer = issuer.isEmpty ? label.substring(0, colonIndex).trim() : issuer;
      account = label.substring(colonIndex + 1).trim();
    } else {
      account = label.trim();
    }
  }

  final secret = _normalizeTotpSecret(secretParam);
  _decodeBase32(secret);
  final digits =
      _boundedInt(uri.queryParameters['digits'], min: 6, max: 8) ?? 6;
  final period =
      _boundedInt(uri.queryParameters['period'], min: 10, max: 120) ?? 30;
  final algorithm = _normalizeTotpAlgorithm(uri.queryParameters['algorithm']);

  return TotpConfig(
    secret: secret,
    issuer: issuer,
    account: account,
    algorithm: algorithm,
    digits: digits,
    period: period,
  );
}

String _normalizeTotpSecret(String value) {
  return value
      .replaceAll(RegExp(r'[\s-]'), '')
      .replaceAll('=', '')
      .toUpperCase();
}

String _normalizeTotpAlgorithm(String? value) {
  final normalized = (value ?? 'SHA1').trim().toUpperCase().replaceAll('-', '');
  switch (normalized) {
    case 'SHA256':
    case 'SHA512':
      return normalized;
    case 'SHA1':
    default:
      return 'SHA1';
  }
}

int? _boundedInt(String? value, {required int min, required int max}) {
  final parsed = int.tryParse(value ?? '');
  if (parsed == null) {
    return null;
  }
  return parsed.clamp(min, max).toInt();
}

_TotpValue _generateTotp(TotpConfig config, {DateTime? now}) {
  if (config.isEmpty) {
    return _TotpValue(
      code: '',
      remainingSeconds: config.period,
      period: config.period,
    );
  }
  final timestamp = ((now ?? DateTime.now()).millisecondsSinceEpoch / 1000)
      .floor();
  final period = config.period <= 0 ? 30 : config.period;
  final counter = timestamp ~/ period;
  final remaining = period - (timestamp % period);
  final secretBytes = _decodeBase32(config.secret);
  final counterBytes = Uint8List(8);
  var movingCounter = counter;
  for (var index = 7; index >= 0; index -= 1) {
    counterBytes[index] = movingCounter & 0xff;
    movingCounter >>= 8;
  }

  final digest = _totpHmac(config.algorithm, secretBytes, counterBytes);
  final offset = digest.last & 0x0f;
  final binary =
      ((digest[offset] & 0x7f) << 24) |
      ((digest[offset + 1] & 0xff) << 16) |
      ((digest[offset + 2] & 0xff) << 8) |
      (digest[offset + 3] & 0xff);
  final modulo = pow(10, config.digits).toInt();
  final code = (binary % modulo).toString().padLeft(config.digits, '0');
  return _TotpValue(code: code, remainingSeconds: remaining, period: period);
}

List<int> _totpHmac(String algorithm, List<int> secret, List<int> message) {
  final hash = switch (_normalizeTotpAlgorithm(algorithm)) {
    'SHA256' => crypto.sha256,
    'SHA512' => crypto.sha512,
    _ => crypto.sha1,
  };
  return crypto.Hmac(hash, secret).convert(message).bytes;
}

List<int> _decodeBase32(String input) {
  final normalized = _normalizeTotpSecret(input);
  if (normalized.isEmpty) {
    throw const FormatException('验证器密钥不能为空');
  }

  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  var buffer = 0;
  var bitsLeft = 0;
  final bytes = <int>[];
  for (final unit in normalized.codeUnits) {
    final char = String.fromCharCode(unit);
    final value = alphabet.indexOf(char);
    if (value < 0) {
      throw const FormatException('验证器密钥格式不正确');
    }
    buffer = (buffer << 5) | value;
    bitsLeft += 5;
    if (bitsLeft >= 8) {
      bytes.add((buffer >> (bitsLeft - 8)) & 0xff);
      bitsLeft -= 8;
    }
  }
  if (bytes.isEmpty) {
    throw const FormatException('验证器密钥格式不正确');
  }
  return bytes;
}

String _formatTotpCode(String code) {
  if (code.length <= 3) {
    return code;
  }
  final midpoint = code.length ~/ 2;
  return '${code.substring(0, midpoint)} ${code.substring(midpoint)}';
}
