import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'src/api_client.dart';
import 'src/app_controller.dart';
import 'src/crypto_service.dart';
import 'src/models.dart';

part 'src/ui/theme.dart';
part 'src/features/auth/auth_screen.dart';
part 'src/features/auth/unlock_screen.dart';
part 'src/features/settings/settings_widgets.dart';
part 'src/features/settings/security_settings_pages.dart';
part 'src/features/settings/theme_option_card.dart';
part 'src/features/vault/vault_password_tab.dart';
part 'src/features/vault/vault_generator_tab.dart';
part 'src/features/vault/vault_files_tab.dart';
part 'src/features/vault/vault_settings_tab.dart';
part 'src/features/vault/vault_helpers.dart';
part 'src/features/vault/password_folder_pages.dart';
part 'src/features/vault/file_folder_pages.dart';
part 'src/features/vault/password_item_pages.dart';
part 'src/features/vault/file_editor_pages.dart';
part 'src/features/vault/vault_drafts.dart';
part 'src/widgets/common_widgets.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = AppController(
    apiClient: ApiClient(),
    cryptoService: CryptoService(),
    secureStorage: const FlutterSecureStorage(),
  );
  runApp(SecureXApp(controller: controller));
}

class SecureXApp extends StatefulWidget {
  const SecureXApp({super.key, required this.controller});

  final AppController controller;

  @override
  State<SecureXApp> createState() => _SecureXAppState();
}

class _SecureXAppState extends State<SecureXApp> {
  @override
  void initState() {
    super.initState();
    widget.controller.initialize();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final theme = SecureXThemeSpec.byId(widget.controller.themeId);
        return MaterialApp(
          title: 'secure-x',
          debugShowCheckedModeBanner: false,
          theme: theme.toThemeData(),
          home: _buildHome(),
        );
      },
    );
  }

  Widget _buildHome() {
    if (!widget.controller.initialized) {
      return const SplashScreen();
    }
    if (!widget.controller.authenticated) {
      return AuthScreen(controller: widget.controller);
    }
    if (!widget.controller.unlocked) {
      return UnlockScreen(controller: widget.controller);
    }
    return VaultScreen(controller: widget.controller);
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  final _itemSearchController = TextEditingController();
  final _fileFolderCreateController = TextEditingController();
  final _fileSearchController = TextEditingController();
  final _settingsBaseUrlController = TextEditingController();
  String _activeVaultFolderId = '';
  String _activeFileFolderId = '';
  int _selectedMainIndex = 0;
  int _generatorLength = 20;
  bool _generatorUseUppercase = true;
  bool _generatorUseLowercase = true;
  bool _generatorUseDigits = true;
  bool _generatorUseSymbols = true;
  String _generatedPassword = '';

  @override
  void initState() {
    super.initState();
    _settingsBaseUrlController.text = widget.controller.baseUrl;
    _regeneratePassword();
  }

  @override
  void didUpdateWidget(covariant VaultScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_settingsBaseUrlController.text != widget.controller.baseUrl) {
      _settingsBaseUrlController.text = widget.controller.baseUrl;
    }
  }

  @override
  void dispose() {
    _itemSearchController.dispose();
    _fileFolderCreateController.dispose();
    _fileSearchController.dispose();
    _settingsBaseUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _buildPasswordVaultTab(context),
      _buildGeneratorTab(context),
      _buildFilesWorkspaceTab(context),
      _buildSettingsTab(context),
    ];

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            if (widget.controller.statusMessage != null ||
                widget.controller.busy)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: _StatusLine(
                  message: widget.controller.statusMessage,
                  busy: widget.controller.busy,
                ),
              ),
            Expanded(
              child: IndexedStack(index: _selectedMainIndex, children: pages),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedMainIndex,
        onDestinationSelected: (value) {
          setState(() {
            _selectedMainIndex = value;
          });
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.key_outlined), label: '密码库'),
          NavigationDestination(
            icon: Icon(Icons.password_outlined),
            label: '生成器',
          ),
          NavigationDestination(icon: Icon(Icons.folder_outlined), label: '文件'),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            label: '设置',
          ),
        ],
      ),
    );
  }
}
