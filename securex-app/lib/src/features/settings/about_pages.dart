part of '../../../main.dart';

const _currentVersionHighlights = [
  '客户端加密、客户端解密，服务端只保存密文。',
  '支持密码库、分类管理、密码生成器与文件加密上传下载。',
  '支持好友、单聊、群聊和端到端加密实时信令。',
  '支持跨平台桌面与移动端，并可手动配置私有部署后端地址。',
  '后端发布包包含 secure-x 可执行文件、生产脚本和 systemd 示例。',
];

class _AboutPage extends StatefulWidget {
  const _AboutPage();

  @override
  State<_AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<_AboutPage> {
  final _updateService = UpdateService();
  AppVersionInfo? _version;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final version = await _updateService.currentVersion();
    if (!mounted) {
      return;
    }
    setState(() {
      _version = version;
    });
  }

  @override
  Widget build(BuildContext context) {
    final version = _version?.version ?? '读取中';
    return Scaffold(
      appBar: AppBar(title: const Text('关于 secure-x')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
              children: [
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Image.asset(
                      'assets/brand/securex_app_icon_square.png',
                      width: 112,
                      height: 112,
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  'secure-x',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Version $version',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: context.sx.mutedText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 34),
                Card(
                  child: Column(
                    children: [
                      _SettingsMenuTile(
                        icon: Icons.article_outlined,
                        title: '版本介绍',
                        subtitle: '查看当前版本能力和安全边界',
                        onTap: () {
                          Navigator.of(context).push<void>(
                            MaterialPageRoute(
                              builder: (context) => _VersionIntroPage(
                                version: _version?.version ?? '当前版本',
                              ),
                            ),
                          );
                        },
                      ),
                      Divider(height: 1, color: context.sx.border),
                      _SettingsMenuTile(
                        icon: Icons.system_update_alt_outlined,
                        title: '版本更新',
                        subtitle: '从 GitHub Release 检查最新版本',
                        onTap: () {
                          Navigator.of(context).push<void>(
                            MaterialPageRoute(
                              builder: (context) => const _VersionUpdatePage(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 36),
                Text(
                  'Secure X 是一个私有部署优先的安全敏感信息存储系统。\n'
                  '密码、文件和聊天内容默认只在客户端加解密。',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.sx.mutedText,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Copyright © 2026 ligson. All Rights Reserved.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.sx.mutedText.withValues(alpha: 0.72),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VersionIntroPage extends StatelessWidget {
  const _VersionIntroPage({required this.version});

  final String version;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('版本介绍')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _SettingsDetailHeader(
                  icon: Icons.article_outlined,
                  title: 'secure-x $version',
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '当前版本重点',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 14),
                        for (final item in _currentVersionHighlights)
                          _BulletText(text: item),
                        const SizedBox(height: 18),
                        _InlineNotice(
                          message:
                              '安全提示：版本介绍只展示本机内置说明；完整发布记录以 GitHub Release 和 CHANGELOG.md 为准。',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VersionUpdatePage extends StatefulWidget {
  const _VersionUpdatePage();

  @override
  State<_VersionUpdatePage> createState() => _VersionUpdatePageState();
}

class _VersionUpdatePageState extends State<_VersionUpdatePage> {
  final _updateService = UpdateService();
  AppVersionInfo? _current;
  ReleaseInfo? _latest;
  ReleaseAsset? _asset;
  String _message = '点击检查更新，将从 GitHub Release 获取最新版本。';
  bool _checking = false;
  bool _downloading = false;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _loadCurrentVersion();
  }

  Future<void> _loadCurrentVersion() async {
    final current = await _updateService.currentVersion();
    if (!mounted) {
      return;
    }
    setState(() {
      _current = current;
    });
  }

  Future<void> _checkUpdate() async {
    setState(() {
      _checking = true;
      _message = '正在连接 GitHub Release...';
    });
    try {
      final current = await _updateService.currentVersion();
      final latest = await _updateService.fetchLatestRelease();
      final asset = await _updateService.pickAssetForCurrentPlatform(latest);
      final hasNewVersion =
          UpdateService.compareVersions(latest.tagName, current.version) > 0;
      if (!mounted) {
        return;
      }
      setState(() {
        _current = current;
        _latest = latest;
        _asset = asset;
        _message = hasNewVersion ? '发现新版本 ${latest.tagName}。' : '当前已经是最新版本。';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _message = '检查更新失败：$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _checking = false;
        });
      }
    }
  }

  Future<void> _downloadAndInstall() async {
    final latest = _latest;
    if (latest == null) {
      await _checkUpdate();
      return;
    }

    if (Platform.isIOS) {
      setState(() {
        _message =
            'iOS 不允许普通应用在应用内自安装，请通过 TestFlight、App Store 或 Release 页面安装。';
      });
      await _updateService.openReleasePage(latest.htmlUrl);
      return;
    }

    final asset = _asset;
    if (asset == null) {
      setState(() {
        _message = '没有找到适合当前平台的安装包，已打开 Release 页面。';
      });
      await _updateService.openReleasePage(latest.htmlUrl);
      return;
    }

    setState(() {
      _downloading = true;
      _progress = 0;
      _message = '正在下载 ${asset.name}...';
    });

    try {
      final file = await _updateService.downloadAsset(
        asset,
        onProgress: (received, total) {
          if (!mounted || total <= 0) {
            return;
          }
          setState(() {
            _progress = received / total;
          });
        },
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _message = Platform.isAndroid ? '下载完成，正在打开系统安装器。' : '下载完成，正在打开安装文件。';
      });
      await _updateService.openDownloadedFile(file);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _message = '下载或打开安装包失败：$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _downloading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final latest = _latest;
    final asset = _asset;
    return Scaffold(
      appBar: AppBar(title: const Text('版本更新')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const _SettingsDetailHeader(
                  icon: Icons.system_update_alt_outlined,
                  title: '版本更新',
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SettingsRow(
                          label: '当前版本',
                          value: _current?.version ?? '读取中',
                        ),
                        const SizedBox(height: 10),
                        _SettingsRow(
                          label: '最新版本',
                          value: latest?.tagName ?? '未检查',
                        ),
                        if (asset != null) ...[
                          const SizedBox(height: 10),
                          _SettingsRow(label: '安装包', value: asset.name),
                        ],
                        const SizedBox(height: 16),
                        _InlineNotice(message: _message),
                        if (_downloading) ...[
                          const SizedBox(height: 16),
                          LinearProgressIndicator(
                            value: _progress <= 0 ? null : _progress,
                            minHeight: 8,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ],
                        if (latest != null &&
                            latest.body.trim().isNotEmpty) ...[
                          const SizedBox(height: 18),
                          Text(
                            '发布说明',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 8),
                          SelectableText(
                            latest.body.trim(),
                            style: Theme.of(
                              context,
                            ).textTheme.bodyMedium?.copyWith(height: 1.55),
                          ),
                        ],
                        const SizedBox(height: 18),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            FilledButton.icon(
                              onPressed: _checking || _downloading
                                  ? null
                                  : _checkUpdate,
                              icon: const Icon(Icons.refresh),
                              label: Text(_checking ? '检查中' : '检查更新'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _checking || _downloading
                                  ? null
                                  : _downloadAndInstall,
                              icon: const Icon(Icons.download_outlined),
                              label: Text(_downloading ? '下载中' : '下载并安装'),
                            ),
                            TextButton.icon(
                              onPressed: latest == null
                                  ? null
                                  : () => _updateService.openReleasePage(
                                      latest.htmlUrl,
                                    ),
                              icon: const Icon(Icons.open_in_new),
                              label: const Text('打开发布页'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BulletText extends StatelessWidget {
  const _BulletText({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 8, right: 10),
            decoration: BoxDecoration(
              color: context.sx.primary,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                height: 1.5,
                color: context.sx.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
