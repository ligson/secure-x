import 'package:flutter/foundation.dart';

bool get appVerboseLoggingEnabled => !kReleaseMode;

void appLog(String message, [Object? error]) {
  final time = DateTime.now().toIso8601String();
  final suffix = error == null ? '' : '：$error';
  // 统一前端本地日志格式，桌面端会输出到控制台，移动端可在系统日志里查看。
  debugPrint('[$time] Secure X $message$suffix');
}

void appLogVerbose(String message, [Object? error]) {
  if (!appVerboseLoggingEnabled) {
    return;
  }
  appLog(message, error);
}
