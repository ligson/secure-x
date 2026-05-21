part of '../../../main.dart';

enum _PasswordDetailAction { edit, delete }

class _PasswordFolderManagerPage extends StatefulWidget {
  const _PasswordFolderManagerPage({required this.controller});

  final AppController controller;

  @override
  State<_PasswordFolderManagerPage> createState() =>
      _PasswordFolderManagerPageState();
}

class _PasswordFolderManagerPageState
    extends State<_PasswordFolderManagerPage> {
  final _nameController = TextEditingController();
  String? _localMessage;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final folders = widget.controller.folders;
        return Scaffold(
          appBar: AppBar(title: const Text('分类管理')),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const _SettingsDetailHeader(
                      icon: Icons.category_outlined,
                      title: '分类管理',
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '新增分类',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _nameController,
                                    decoration: const InputDecoration(
                                      hintText: '分类名称',
                                    ),
                                    onSubmitted: (_) => _createFolder(),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                FilledButton(
                                  onPressed: widget.controller.busy
                                      ? null
                                      : _createFolder,
                                  child: const Text('新增'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_localMessage != null) ...[
                      _InlineNotice(message: _localMessage!),
                      const SizedBox(height: 12),
                    ],
                    _StatusLine(
                      message: widget.controller.statusMessage,
                      busy: widget.controller.busy,
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Column(
                        children: [
                          const _ListCardHeader(title: '已有分类'),
                          if (folders.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                '还没有分类',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: context.sx.mutedText),
                              ),
                            )
                          else
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: folders.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final folder = folders[index];
                                final itemCount = _countItems(folder);
                                final childCount = _countChildren(folder);
                                return ListTile(
                                  leading: Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: context.sx.subtle,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(
                                      Icons.folder_outlined,
                                      size: 18,
                                    ),
                                  ),
                                  title: Text(folder.name),
                                  subtitle: Text(
                                    '$itemCount 个密码 · $childCount 个子分类',
                                  ),
                                  trailing: PopupMenuButton<String>(
                                    onSelected: (value) async {
                                      if (value == 'edit') {
                                        await _editFolder(folder);
                                        return;
                                      }
                                      if (value == 'delete') {
                                        await _deleteFolder(folder);
                                      }
                                    },
                                    itemBuilder: (context) => const [
                                      PopupMenuItem(
                                        value: 'edit',
                                        child: Text('修改'),
                                      ),
                                      PopupMenuItem(
                                        value: 'delete',
                                        child: Text('删除'),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  int _countItems(DecryptedFolder folder) {
    return widget.controller.items
        .where((item) => item.folderId == folder.id)
        .length;
  }

  int _countChildren(DecryptedFolder folder) {
    return widget.controller.folders
        .where((candidate) => candidate.parentFolderId == folder.id)
        .length;
  }

  Future<void> _createFolder() async {
    final name = _nameController.text.trim();
    setState(() {
      _localMessage = null;
    });
    if (name.isEmpty) {
      setState(() {
        _localMessage = '请输入分类名称。';
      });
      return;
    }

    try {
      await widget.controller.createFolder(name);
      if (!mounted) {
        return;
      }
      _nameController.clear();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('分类已新增')));
    } catch (_) {}
  }

  Future<void> _editFolder(DecryptedFolder folder) async {
    final name = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (context) => _PasswordFolderEditorPage(folder: folder),
      ),
    );
    if (name == null || name.isEmpty) {
      return;
    }

    try {
      await widget.controller.upsertFolder(
        name: name,
        existing: folder,
        parentFolderId: folder.parentFolderId ?? '',
      );
    } catch (_) {}
  }

  Future<void> _deleteFolder(DecryptedFolder folder) async {
    setState(() {
      _localMessage = null;
    });

    final itemCount = _countItems(folder);
    if (itemCount > 0) {
      setState(() {
        _localMessage = '“${folder.name}”下面还有 $itemCount 个密码，请先移动或删除这些密码。';
      });
      return;
    }

    final childCount = _countChildren(folder);
    if (childCount > 0) {
      setState(() {
        _localMessage = '“${folder.name}”下面还有 $childCount 个子分类，请先处理子分类。';
      });
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('删除分类'),
          content: Text('确定删除“${folder.name}”吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }

    try {
      await widget.controller.deleteFolder(folder);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('分类已删除')));
    } catch (_) {}
  }
}

class _PasswordFolderEditorPage extends StatefulWidget {
  const _PasswordFolderEditorPage({required this.folder});

  final DecryptedFolder folder;

  @override
  State<_PasswordFolderEditorPage> createState() =>
      _PasswordFolderEditorPageState();
}

class _PasswordFolderEditorPageState extends State<_PasswordFolderEditorPage> {
  late final TextEditingController _nameController;
  String? _localMessage;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.folder.name);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('修改分类')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const _SettingsDetailHeader(
                  icon: Icons.edit_outlined,
                  title: '修改分类',
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        TextField(
                          controller: _nameController,
                          decoration: const InputDecoration(labelText: '分类名称'),
                          onSubmitted: (_) => _submit(),
                        ),
                        if (_localMessage != null) ...[
                          const SizedBox(height: 12),
                          _InlineNotice(message: _localMessage!),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _submit,
                  child: const Text('保存'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() {
        _localMessage = '请输入分类名称。';
      });
      return;
    }
    Navigator.of(context).pop(name);
  }
}
