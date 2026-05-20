import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:securex_app/main.dart';
import 'package:securex_app/src/api_client.dart';
import 'package:securex_app/src/app_controller.dart';
import 'package:securex_app/src/crypto_service.dart';

void main() {
  testWidgets('shows splash before initialization completes', (tester) async {
    final controller = AppController(
      apiClient: ApiClient(),
      cryptoService: CryptoService(),
      secureStorage: const FlutterSecureStorage(),
    );

    await tester.pumpWidget(SecureXApp(controller: controller));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
