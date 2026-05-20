import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'src/api_client.dart';
import 'src/app_controller.dart';
import 'src/crypto_service.dart';
import 'src/models.dart';

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
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0C6C7A),
      brightness: Brightness.light,
    );

    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return MaterialApp(
          title: 'Secure X',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: colorScheme,
            scaffoldBackgroundColor: const Color(0xFFF7F4EC),
            useMaterial3: true,
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: const Color(0xFFF7F6F2),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: const BorderSide(color: Color(0xFFE3DED3)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: const BorderSide(
                  color: Color(0xFF0C6C7A),
                  width: 1.4,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 18,
              ),
            ),
            filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0C6C7A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 18,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
            cardTheme: CardThemeData(
              elevation: 0,
              color: Colors.white.withValues(alpha: 0.94),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(32),
              ),
            ),
          ),
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

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final TextEditingController _baseUrlController;
  final _loginIdentifierController = TextEditingController();
  final _loginPasswordController = TextEditingController();
  final _loginMasterPasswordController = TextEditingController();
  final _registerUsernameController = TextEditingController();
  final _registerEmailController = TextEditingController();
  final _registerPasswordController = TextEditingController();
  final _registerMasterPasswordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _baseUrlController = TextEditingController(text: widget.controller.baseUrl);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _baseUrlController.dispose();
    _loginIdentifierController.dispose();
    _loginPasswordController.dispose();
    _loginMasterPasswordController.dispose();
    _registerUsernameController.dispose();
    _registerEmailController.dispose();
    _registerPasswordController.dispose();
    _registerMasterPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const _AuthBackdrop(),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, viewport) {
                final isCompact = viewport.maxWidth < 980;
                final desktopHeight = (viewport.maxHeight - 56)
                    .clamp(720.0, 860.0)
                    .toDouble();

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(28),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1280),
                      child: isCompact
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _HeroPanel(baseUrl: widget.controller.baseUrl),
                                const SizedBox(height: 24),
                                _buildAuthWorkspaceCard(
                                  context,
                                  contentHeight: 560,
                                  desktop: false,
                                ),
                              ],
                            )
                          : SizedBox(
                              height: desktopHeight,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    flex: 11,
                                    child: _HeroPanel(
                                      baseUrl: widget.controller.baseUrl,
                                    ),
                                  ),
                                  const SizedBox(width: 28),
                                  Expanded(
                                    flex: 10,
                                    child: _buildAuthWorkspaceCard(
                                      context,
                                      contentHeight: desktopHeight - 56,
                                      desktop: true,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthWorkspaceCard(
    BuildContext context, {
    required double contentHeight,
    required bool desktop,
  }) {
    return Card(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          desktop ? 32 : 24,
          desktop ? 32 : 24,
          desktop ? 32 : 24,
          desktop ? 24 : 20,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE9F5F3),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    desktop ? 'Desktop Client' : 'Universal Client',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: Color(0xFF0C6C7A),
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  desktop ? 'Private Vault Access' : 'One Codebase',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF7C776C),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Text(
              '连接你的私有保险库',
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text(
              '先指定服务地址，再用登录密码和主密码进入零知识保险库。',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: const Color(0xFF675F52),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 22),
            _EndpointBanner(
              controller: _baseUrlController,
              busy: widget.controller.busy,
              onSave: () async {
                await widget.controller.saveBaseUrl(_baseUrlController.text);
                if (!context.mounted) {
                  return;
                }
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('后端地址已保存')));
              },
            ),
            const SizedBox(height: 22),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF6F1E8),
                borderRadius: BorderRadius.circular(22),
              ),
              padding: const EdgeInsets.all(8),
              child: TabBar(
                controller: _tabController,
                dividerColor: Colors.transparent,
                indicator: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 18,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                labelStyle: const TextStyle(fontWeight: FontWeight.w800),
                tabs: const [
                  Tab(text: '登录'),
                  Tab(text: '注册'),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: contentHeight,
              child: TabBarView(
                controller: _tabController,
                children: [_buildLogin(), _buildRegister()],
              ),
            ),
            const SizedBox(height: 16),
            _StatusLine(
              message: widget.controller.statusMessage,
              busy: widget.controller.busy,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogin() {
    return ListView(
      children: [
        _SectionLabel(title: '登录身份', caption: '登录密码用于服务端认证，主密码只在本地解锁保险库。'),
        const SizedBox(height: 14),
        TextField(
          controller: _loginIdentifierController,
          decoration: const InputDecoration(
            labelText: '用户名或邮箱',
            prefixIcon: Icon(Icons.person_outline),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _loginPasswordController,
          decoration: const InputDecoration(
            labelText: '登录密码',
            prefixIcon: Icon(Icons.login_outlined),
          ),
          obscureText: true,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _loginMasterPasswordController,
          decoration: const InputDecoration(
            labelText: '主密码',
            prefixIcon: Icon(Icons.key_outlined),
          ),
          obscureText: true,
        ),
        const SizedBox(height: 22),
        FilledButton.icon(
          onPressed: widget.controller.busy
              ? null
              : () async {
                  try {
                    await widget.controller.saveBaseUrl(
                      _baseUrlController.text,
                    );
                    await widget.controller.login(
                      identifier: _loginIdentifierController.text,
                      authPassword: _loginPasswordController.text,
                      masterPassword: _loginMasterPasswordController.text,
                    );
                  } catch (_) {}
                },
          icon: const Icon(Icons.lock_open_rounded),
          label: const Text('登录并解锁'),
        ),
        const SizedBox(height: 14),
        Text(
          '登录成功后，数据仍需主密码才能在本机解密显示。',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: const Color(0xFF7C776C),
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildRegister() {
    return ListView(
      children: [
        _SectionLabel(
          title: '创建新保险库',
          caption: '注册后会在客户端生成并封装保险库主密钥，服务端只保存密文。',
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _registerUsernameController,
          decoration: const InputDecoration(
            labelText: '用户名',
            prefixIcon: Icon(Icons.badge_outlined),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _registerEmailController,
          decoration: const InputDecoration(
            labelText: '邮箱',
            prefixIcon: Icon(Icons.alternate_email),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _registerPasswordController,
          decoration: const InputDecoration(
            labelText: '登录密码',
            prefixIcon: Icon(Icons.verified_user_outlined),
          ),
          obscureText: true,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _registerMasterPasswordController,
          decoration: const InputDecoration(
            labelText: '主密码',
            prefixIcon: Icon(Icons.enhanced_encryption_outlined),
          ),
          obscureText: true,
        ),
        const SizedBox(height: 22),
        FilledButton.icon(
          onPressed: widget.controller.busy
              ? null
              : () async {
                  try {
                    await widget.controller.saveBaseUrl(
                      _baseUrlController.text,
                    );
                    await widget.controller.register(
                      username: _registerUsernameController.text,
                      email: _registerEmailController.text,
                      authPassword: _registerPasswordController.text,
                      masterPassword: _registerMasterPasswordController.text,
                    );
                  } catch (_) {}
                },
          icon: const Icon(Icons.person_add_alt_1_rounded),
          label: const Text('创建账户'),
        ),
        const SizedBox(height: 14),
        Text(
          '建议登录密码与主密码分开设置，降低单一口令泄露后的风险。',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: const Color(0xFF7C776C),
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final _masterPasswordController = TextEditingController();

  @override
  void dispose() {
    _masterPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.controller.user;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '欢迎回来，${user?.username ?? ''}',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text('服务端：${widget.controller.baseUrl}'),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _masterPasswordController,
                      decoration: const InputDecoration(
                        labelText: '输入主密码以解锁保险库',
                      ),
                      obscureText: true,
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: widget.controller.busy
                          ? null
                          : () async {
                              try {
                                await widget.controller.unlock(
                                  _masterPasswordController.text,
                                );
                              } catch (_) {}
                            },
                      child: const Text('解锁'),
                    ),
                    TextButton(
                      onPressed: widget.controller.busy
                          ? null
                          : widget.controller.logout,
                      child: const Text('退出登录'),
                    ),
                    _StatusLine(
                      message: widget.controller.statusMessage,
                      busy: widget.controller.busy,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  final _folderController = TextEditingController();
  final _folderSearchController = TextEditingController();
  final _itemTitleController = TextEditingController();
  final _itemUsernameController = TextEditingController();
  final _itemPasswordController = TextEditingController();
  final _itemUrlController = TextEditingController();
  final _itemNoteController = TextEditingController();
  final _itemSearchController = TextEditingController();
  final _fileSearchController = TextEditingController();
  String _selectedItemFolderId = '';
  String _selectedUploadFolderId = '';

  @override
  void dispose() {
    _folderController.dispose();
    _folderSearchController.dispose();
    _itemTitleController.dispose();
    _itemUsernameController.dispose();
    _itemPasswordController.dispose();
    _itemUrlController.dispose();
    _itemNoteController.dispose();
    _itemSearchController.dispose();
    _fileSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Secure X'),
              Text(
                '${widget.controller.user?.username} · ${widget.controller.baseUrl}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: '刷新',
              onPressed: widget.controller.busy
                  ? null
                  : widget.controller.refreshVault,
              icon: const Icon(Icons.sync),
            ),
            IconButton(
              tooltip: '锁定',
              onPressed: widget.controller.busy ? null : widget.controller.lock,
              icon: const Icon(Icons.lock_outline),
            ),
            IconButton(
              tooltip: '退出登录',
              onPressed: widget.controller.busy
                  ? null
                  : widget.controller.logout,
              icon: const Icon(Icons.logout),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: '文件夹'),
              Tab(text: '登录项'),
              Tab(text: '文件'),
            ],
          ),
        ),
        body: Column(
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
              child: TabBarView(
                children: [
                  _buildFoldersTab(context),
                  _buildItemsTab(context),
                  _buildFilesTab(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFoldersTab(BuildContext context) {
    final folders = _filteredFolders();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _folderController,
                          decoration: const InputDecoration(
                            labelText: '新文件夹名称',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        onPressed: widget.controller.busy
                            ? null
                            : () async {
                                if (_folderController.text.trim().isEmpty) {
                                  return;
                                }
                                try {
                                  await widget.controller.createFolder(
                                    _folderController.text.trim(),
                                  );
                                  _folderController.clear();
                                } catch (_) {}
                              },
                        child: const Text('创建'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _folderSearchController,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: '搜索文件夹',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Card(
              child: folders.isEmpty
                  ? const Center(child: Text('还没有文件夹'))
                  : ListView.separated(
                      itemCount: folders.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final folder = folders[index];
                        return ListTile(
                          leading: const Icon(Icons.folder_outlined),
                          title: Text(folder.name),
                          subtitle: Text(
                            '${widget.controller.folderNameById(folder.parentFolderId)} · 版本 ${folder.version}',
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (value) async {
                              if (value == 'edit') {
                                await _showFolderEditor(folder: folder);
                                return;
                              }
                              if (value == 'delete') {
                                final confirmed = await _confirmDelete(
                                  title: '删除文件夹',
                                  body: '删除前请先清空该文件夹内的子文件夹、登录项和文件。',
                                );
                                if (!confirmed) {
                                  return;
                                }
                                try {
                                  await widget.controller.deleteFolder(folder);
                                } catch (_) {}
                              }
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(value: 'edit', child: Text('编辑')),
                              PopupMenuItem(value: 'delete', child: Text('删除')),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemsTab(BuildContext context) {
    final items = _filteredItems();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  TextField(
                    controller: _itemTitleController,
                    decoration: const InputDecoration(labelText: '标题'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _itemUsernameController,
                    decoration: const InputDecoration(labelText: '用户名'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _itemPasswordController,
                    decoration: InputDecoration(
                      labelText: '密码',
                      suffixIcon: TextButton(
                        onPressed: () {
                          _itemPasswordController.text = widget.controller
                              .generatePassword();
                        },
                        child: const Text('生成'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _itemUrlController,
                    decoration: const InputDecoration(labelText: '地址'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _itemNoteController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: '备注'),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedItemFolderId,
                    items: _folderItems(),
                    onChanged: (value) {
                      setState(() {
                        _selectedItemFolderId = value ?? '';
                      });
                    },
                    decoration: const InputDecoration(labelText: '存放到文件夹'),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: widget.controller.busy
                          ? null
                          : () async {
                              try {
                                await widget.controller.createLoginItem(
                                  title: _itemTitleController.text,
                                  username: _itemUsernameController.text,
                                  password: _itemPasswordController.text,
                                  url: _itemUrlController.text,
                                  note: _itemNoteController.text,
                                  folderId: _selectedItemFolderId,
                                );
                                _clearItemComposer();
                              } catch (_) {}
                            },
                      child: const Text('保存登录项'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _itemSearchController,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: '搜索登录项',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Card(
              child: items.isEmpty
                  ? const Center(child: Text('还没有登录信息'))
                  : ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return ListTile(
                          leading: const Icon(Icons.key_outlined),
                          title: Text(
                            item.title.isEmpty ? '(未命名)' : item.title,
                          ),
                          subtitle: Text(
                            '${widget.controller.folderNameById(item.folderId)} · ${item.username} · ${item.url}',
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (value) async {
                              if (value == 'edit') {
                                await _showItemEditor(item: item);
                                return;
                              }
                              if (value == 'delete') {
                                final confirmed = await _confirmDelete(
                                  title: '删除登录项',
                                  body: '这条登录信息会从当前保险库中移除。',
                                );
                                if (!confirmed) {
                                  return;
                                }
                                try {
                                  await widget.controller.deleteLoginItem(item);
                                } catch (_) {}
                              }
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(value: 'edit', child: Text('编辑')),
                              PopupMenuItem(value: 'delete', child: Text('删除')),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilesTab(BuildContext context) {
    final files = _filteredFiles();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.upload_file_outlined),
                      const SizedBox(width: 12),
                      const Expanded(child: Text('文件会先在客户端加密，再上传到服务端存储。')),
                      const SizedBox(width: 12),
                      FilledButton(
                        onPressed: widget.controller.busy
                            ? null
                            : () async {
                                try {
                                  await widget.controller.uploadFile(
                                    folderId: _selectedUploadFolderId,
                                  );
                                } catch (_) {}
                              },
                        child: const Text('选择文件'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedUploadFolderId,
                    items: _folderItems(),
                    onChanged: (value) {
                      setState(() {
                        _selectedUploadFolderId = value ?? '';
                      });
                    },
                    decoration: const InputDecoration(labelText: '上传到文件夹'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _fileSearchController,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: '搜索文件',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Card(
              child: files.isEmpty
                  ? const Center(child: Text('还没有加密文件'))
                  : ListView.separated(
                      itemCount: files.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final file = files[index];
                        return ListTile(
                          leading: const Icon(Icons.description_outlined),
                          title: Text(file.name),
                          subtitle: Text(
                            '${widget.controller.folderNameById(file.folderId)} · 原始 ${file.originalSize} bytes · 密文 ${file.cipherSize} bytes',
                          ),
                          trailing: Wrap(
                            spacing: 4,
                            children: [
                              TextButton(
                                onPressed: widget.controller.busy
                                    ? null
                                    : () async {
                                        try {
                                          final path = await widget.controller
                                              .downloadFile(file);
                                          if (!context.mounted) {
                                            return;
                                          }
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text('已解密到 $path'),
                                            ),
                                          );
                                        } catch (_) {}
                                      },
                                child: const Text('下载解密'),
                              ),
                              PopupMenuButton<String>(
                                onSelected: (value) async {
                                  if (value == 'edit') {
                                    await _showFileEditor(file: file);
                                    return;
                                  }
                                  if (value == 'delete') {
                                    final confirmed = await _confirmDelete(
                                      title: '删除文件',
                                      body: '服务端中的密文文件也会一并删除。',
                                    );
                                    if (!confirmed) {
                                      return;
                                    }
                                    try {
                                      await widget.controller
                                          .deleteEncryptedFile(file);
                                    } catch (_) {}
                                  }
                                },
                                itemBuilder: (context) => const [
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: Text('编辑'),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('删除'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  List<DecryptedFolder> _filteredFolders() {
    final query = _folderSearchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return widget.controller.folders;
    }
    return widget.controller.folders
        .where((folder) => folder.name.toLowerCase().contains(query))
        .toList();
  }

  List<DecryptedLoginItem> _filteredItems() {
    final query = _itemSearchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return widget.controller.items;
    }
    return widget.controller.items.where((item) {
      final folderName = widget.controller
          .folderNameById(item.folderId)
          .toLowerCase();
      return item.title.toLowerCase().contains(query) ||
          item.username.toLowerCase().contains(query) ||
          item.url.toLowerCase().contains(query) ||
          folderName.contains(query);
    }).toList();
  }

  List<DecryptedFileRecord> _filteredFiles() {
    final query = _fileSearchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return widget.controller.files;
    }
    return widget.controller.files.where((file) {
      final folderName = widget.controller
          .folderNameById(file.folderId)
          .toLowerCase();
      return file.name.toLowerCase().contains(query) ||
          folderName.contains(query);
    }).toList();
  }

  List<DropdownMenuItem<String>> _folderItems() {
    return [
      const DropdownMenuItem<String>(value: '', child: Text('未分类')),
      ...widget.controller.folders.map(
        (folder) => DropdownMenuItem<String>(
          value: folder.id,
          child: Text(folder.name),
        ),
      ),
    ];
  }

  Future<void> _showFolderEditor({DecryptedFolder? folder}) async {
    final nameController = TextEditingController(text: folder?.name ?? '');
    var parentFolderId = folder?.parentFolderId ?? '';
    final result = await showDialog<_FolderDraft>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(folder == null ? '新建文件夹' : '编辑文件夹'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: '名称'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: parentFolderId,
                      items: [
                        const DropdownMenuItem<String>(
                          value: '',
                          child: Text('无父级文件夹'),
                        ),
                        ...widget.controller.folders
                            .where((candidate) => candidate.id != folder?.id)
                            .map(
                              (candidate) => DropdownMenuItem<String>(
                                value: candidate.id,
                                child: Text(candidate.name),
                              ),
                            ),
                      ],
                      onChanged: (value) {
                        setDialogState(() {
                          parentFolderId = value ?? '';
                        });
                      },
                      decoration: const InputDecoration(labelText: '父级文件夹'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop(
                      _FolderDraft(
                        name: nameController.text.trim(),
                        parentFolderId: parentFolderId,
                      ),
                    );
                  },
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );
    nameController.dispose();

    if (result == null || result.name.isEmpty) {
      return;
    }

    try {
      await widget.controller.upsertFolder(
        name: result.name,
        existing: folder,
        parentFolderId: result.parentFolderId,
      );
    } catch (_) {}
  }

  Future<void> _showItemEditor({DecryptedLoginItem? item}) async {
    final titleController = TextEditingController(text: item?.title ?? '');
    final usernameController = TextEditingController(
      text: item?.username ?? '',
    );
    final passwordController = TextEditingController(
      text: item?.password ?? '',
    );
    final urlController = TextEditingController(text: item?.url ?? '');
    final noteController = TextEditingController(text: item?.note ?? '');
    var folderId = item?.folderId ?? '';

    final result = await showDialog<_LoginItemDraft>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(item == null ? '新建登录项' : '编辑登录项'),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: titleController,
                        decoration: const InputDecoration(labelText: '标题'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: usernameController,
                        decoration: const InputDecoration(labelText: '用户名'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: passwordController,
                        decoration: InputDecoration(
                          labelText: '密码',
                          suffixIcon: TextButton(
                            onPressed: () {
                              passwordController.text = widget.controller
                                  .generatePassword();
                            },
                            child: const Text('生成'),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: urlController,
                        decoration: const InputDecoration(labelText: '地址'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: noteController,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(labelText: '备注'),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: folderId,
                        items: _folderItems(),
                        onChanged: (value) {
                          setDialogState(() {
                            folderId = value ?? '';
                          });
                        },
                        decoration: const InputDecoration(labelText: '存放到文件夹'),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop(
                      _LoginItemDraft(
                        title: titleController.text.trim(),
                        username: usernameController.text.trim(),
                        password: passwordController.text,
                        url: urlController.text.trim(),
                        note: noteController.text.trim(),
                        folderId: folderId,
                      ),
                    );
                  },
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );

    titleController.dispose();
    usernameController.dispose();
    passwordController.dispose();
    urlController.dispose();
    noteController.dispose();

    if (result == null) {
      return;
    }

    try {
      await widget.controller.upsertLoginItem(
        title: result.title,
        username: result.username,
        password: result.password,
        url: result.url,
        note: result.note,
        folderId: result.folderId,
        existing: item,
      );
    } catch (_) {}
  }

  Future<void> _showFileEditor({required DecryptedFileRecord file}) async {
    final nameController = TextEditingController(text: file.name);
    var folderId = file.folderId ?? '';

    final result = await showDialog<_FileDraft>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('编辑文件'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: '显示名称'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: folderId,
                      items: _folderItems(),
                      onChanged: (value) {
                        setDialogState(() {
                          folderId = value ?? '';
                        });
                      },
                      decoration: const InputDecoration(labelText: '存放到文件夹'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop(
                      _FileDraft(
                        name: nameController.text.trim(),
                        folderId: folderId,
                      ),
                    );
                  },
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();

    if (result == null || result.name.isEmpty) {
      return;
    }

    try {
      await widget.controller.updateEncryptedFile(
        existing: file,
        name: result.name,
        folderId: result.folderId,
      );
    } catch (_) {}
  }

  Future<bool> _confirmDelete({
    required String title,
    required String body,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('确认删除'),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }

  void _clearItemComposer() {
    _itemTitleController.clear();
    _itemUsernameController.clear();
    _itemPasswordController.clear();
    _itemUrlController.clear();
    _itemNoteController.clear();
    setState(() {
      _selectedItemFolderId = '';
    });
  }
}

class _FolderDraft {
  _FolderDraft({required this.name, required this.parentFolderId});

  final String name;
  final String parentFolderId;
}

class _LoginItemDraft {
  _LoginItemDraft({
    required this.title,
    required this.username,
    required this.password,
    required this.url,
    required this.note,
    required this.folderId,
  });

  final String title;
  final String username;
  final String password;
  final String url;
  final String note;
  final String folderId;
}

class _FileDraft {
  _FileDraft({required this.name, required this.folderId});

  final String name;
  final String folderId;
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({required this.baseUrl});

  final String baseUrl;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(36),
        gradient: const LinearGradient(
          colors: [Color(0xFF083842), Color(0xFF0D6674), Color(0xFF1B8C88)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x2209434B),
            blurRadius: 40,
            offset: Offset(0, 24),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.16),
                    ),
                  ),
                  child: const Icon(
                    Icons.shield_moon_outlined,
                    color: Colors.white,
                    size: 34,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Secure X',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Private Zero-Knowledge Vault',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.72),
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            Text(
              '把密码、登录信息和加密文件放在同一座私有保险库里。',
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                height: 1.08,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              '所有敏感数据只在客户端完成加密与解密，服务器负责保存密文、索引和同步版本。你可以自己决定服务地址，也可以把它部署在自己的基础设施上。',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.84),
                height: 1.6,
              ),
            ),
            const SizedBox(height: 26),
            const Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _FeatureChip(label: '桌面 + 移动统一客户端'),
                _FeatureChip(label: '登录密码与主密码分离'),
                _FeatureChip(label: '文件与密码同库管理'),
                _FeatureChip(label: '服务端仅存密文'),
              ],
            ),
            const SizedBox(height: 26),
            LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 520;
                if (stacked) {
                  return const Column(
                    children: [
                      _InfoMetric(
                        value: 'AES-256-GCM',
                        label: '文本与文件密文封装',
                      ),
                      SizedBox(height: 12),
                      _InfoMetric(
                        value: 'PBKDF2',
                        label: '当前主密钥派生策略',
                      ),
                      SizedBox(height: 12),
                      _InfoMetric(
                        value: 'Self-host',
                        label: '支持私有部署与自定义地址',
                      ),
                    ],
                  );
                }

                return const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _InfoMetric(
                        value: 'AES-256-GCM',
                        label: '文本与文件密文封装',
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: _InfoMetric(
                        value: 'PBKDF2',
                        label: '当前主密钥派生策略',
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: _InfoMetric(
                        value: 'Self-host',
                        label: '支持私有部署与自定义地址',
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.route_outlined,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '当前目标服务',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: Colors.white.withValues(alpha: 0.78),
                              ),
                        ),
                        const SizedBox(height: 6),
                        SelectableText(
                          baseUrl,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  const _FeatureChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label),
      labelStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Colors.white,
        fontWeight: FontWeight.w700,
      ),
      side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      backgroundColor: Colors.white.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    );
  }
}

class _AuthBackdrop extends StatelessWidget {
  const _AuthBackdrop();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFF8F1E4), Color(0xFFF1F6F2), Color(0xFFEAF7F8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: -120,
            top: -100,
            child: _GlowOrb(size: 320, color: const Color(0x33D98324)),
          ),
          Positioned(
            right: -80,
            top: 90,
            child: _GlowOrb(size: 280, color: const Color(0x3317A6A0)),
          ),
          Positioned(
            left: 280,
            bottom: -140,
            child: _GlowOrb(size: 360, color: const Color(0x26C3A45F)),
          ),
        ],
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: color, blurRadius: 120, spreadRadius: 24),
          ],
        ),
      ),
    );
  }
}

class _EndpointBanner extends StatelessWidget {
  const _EndpointBanner({
    required this.controller,
    required this.busy,
    required this.onSave,
  });

  final TextEditingController controller;
  final bool busy;
  final Future<void> Function() onSave;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F4EC),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE7DFD0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '连接端点',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: busy ? null : onSave,
                icon: const Icon(Icons.save_outlined),
                label: const Text('保存'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: '后端地址',
              prefixIcon: Icon(Icons.lan_outlined),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title, required this.caption});

  final String title;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          caption,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: const Color(0xFF7C776C),
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

class _InfoMetric extends StatelessWidget {
  const _InfoMetric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.72),
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.message, required this.busy});

  final String? message;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    if (!busy && (message == null || message!.isEmpty)) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        children: [
          if (busy) ...[
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(
              message ?? '处理中...',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
