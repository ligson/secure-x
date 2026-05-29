import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image/image.dart' as img;
import 'package:audioplayers/audioplayers.dart' as audio;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart' as record;
import 'package:livekit_client/livekit_client.dart' as lk;

import 'src/api_client.dart';
import 'src/app_controller.dart';
import 'src/app_logger.dart';
import 'src/crypto_service.dart';
import 'src/models.dart';
import 'src/realtime_chat_service.dart';
import 'src/update_service.dart';

part 'src/ui/theme.dart';
part 'src/features/auth/auth_screen.dart';
part 'src/features/auth/unlock_screen.dart';
part 'src/features/settings/settings_widgets.dart';
part 'src/features/settings/security_settings_pages.dart';
part 'src/features/settings/about_pages.dart';
part 'src/features/settings/theme_option_card.dart';
part 'src/features/vault/vault_password_tab.dart';
part 'src/features/vault/vault_generator_tab.dart';
part 'src/features/vault/vault_files_tab.dart';
part 'src/features/chat/chat_pages.dart';
part 'src/features/friends/friends_pages.dart';
part 'src/features/vault/vault_settings_tab.dart';
part 'src/features/vault/vault_helpers.dart';
part 'src/features/vault/password_folder_pages.dart';
part 'src/features/vault/file_folder_pages.dart';
part 'src/features/vault/password_item_pages.dart';
part 'src/features/vault/file_editor_pages.dart';
part 'src/features/vault/vault_drafts.dart';
part 'src/widgets/common_widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    // LiveKit 要求在调用任何 SDK API 前初始化底层 WebRTC 插件。
    await lk.LiveKitClient.initialize();
  } catch (error) {
    appLog('LiveKit 初始化失败，通话能力可能不可用', error);
  }
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

class _SecureXAppState extends State<SecureXApp> with WidgetsBindingObserver {
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _hadReachableNetwork = false;
  bool _connectivityInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.initialize();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      _handleConnectivityChanged,
    );
    unawaited(_initializeConnectivitySnapshot());
  }

  Future<void> _initializeConnectivitySnapshot() async {
    final results = await Connectivity().checkConnectivity();
    _updateConnectivityBaseline(results);
  }

  Future<void> _handleConnectivityChanged(
    List<ConnectivityResult> results,
  ) async {
    final reachable = _updateConnectivityBaseline(results);
    if (!reachable) {
      return;
    }
    if (_hadReachableNetwork) {
      return;
    }
    _hadReachableNetwork = true;
    await widget.controller.handleNetworkReachable();
  }

  bool _updateConnectivityBaseline(List<ConnectivityResult> results) {
    final reachable = results.any(
      (result) => result != ConnectivityResult.none,
    );
    if (!_connectivityInitialized) {
      _connectivityInitialized = true;
      _hadReachableNetwork = reachable;
      return reachable;
    }
    if (!reachable) {
      _hadReachableNetwork = false;
    }
    return reachable;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.controller.handleAppResumed());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.controller.appShellListenable,
        widget.controller.themeListenable,
      ]),
      builder: (context, _) {
        final theme = SecureXThemeSpec.byId(widget.controller.themeId);
        return MaterialApp(
          title: 'secure-x',
          debugShowCheckedModeBanner: false,
          scrollBehavior: const SecureXScrollBehavior(),
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

class SecureXScrollBehavior extends MaterialScrollBehavior {
  const SecureXScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.unknown,
  };
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
  final _friendSearchController = TextEditingController();
  final _settingsBaseUrlController = TextEditingController();
  String _activeVaultFolderId = '';
  String _activeFileFolderId = '';
  String? _dismissedChatRealtimeNotice;
  String? _dismissedPageStatusMessage;
  int _selectedMainIndex = 0;
  int _generatorLength = 20;
  bool _generatorUseUppercase = true;
  bool _generatorUseLowercase = true;
  bool _generatorUseDigits = true;
  bool _generatorUseSymbols = true;
  String _generatedPassword = '';
  final Set<String> _handledIncomingCallIds = {};

  @override
  void initState() {
    super.initState();
    _settingsBaseUrlController.text = widget.controller.baseUrl;
    widget.controller.callListenable.addListener(_handleIncomingCallSignal);
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
    widget.controller.callListenable.removeListener(_handleIncomingCallSignal);
    _itemSearchController.dispose();
    _fileFolderCreateController.dispose();
    _fileSearchController.dispose();
    _friendSearchController.dispose();
    _settingsBaseUrlController.dispose();
    super.dispose();
  }

  void _handleIncomingCallSignal() {
    final signal = widget.controller.lastCallSignal;
    if (signal == null || signal.action != 'invite' || signal.callId.isEmpty) {
      return;
    }
    final key = '${signal.friendId}:${signal.callId}';
    if (_handledIncomingCallIds.contains(key)) {
      return;
    }
    _handledIncomingCallIds.add(key);
    final friend = widget.controller.friends
        .where((entry) => entry.id == signal.friendId)
        .firstOrNull;
    if (friend == null || !mounted) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => _ChatCallPage(
            controller: widget.controller,
            friend: friend,
            initialVideo: signal.media == 'video',
            incomingCallId: signal.callId,
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _buildPasswordVaultTab(context),
      _buildFilesWorkspaceTab(context),
      _buildChatTab(context),
      _buildFriendsTab(context),
      _buildSettingsTab(context),
    ];
    final selectedMainIndex = _selectedMainIndex.clamp(0, pages.length - 1);

    return Scaffold(
      body: SafeArea(
        child: IndexedStack(index: selectedMainIndex, children: pages),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedMainIndex,
        onDestinationSelected: (value) {
          setState(() {
            _selectedMainIndex = value;
          });
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.key_outlined), label: '密码库'),
          NavigationDestination(icon: Icon(Icons.folder_outlined), label: '文件'),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            label: '聊天',
          ),
          NavigationDestination(icon: Icon(Icons.people_outline), label: '好友'),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            label: '设置',
          ),
        ],
      ),
    );
  }
}
