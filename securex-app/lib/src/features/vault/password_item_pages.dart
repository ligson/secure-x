part of '../../../main.dart';

class _PasswordEditorPage extends StatefulWidget {
  const _PasswordEditorPage({
    required this.item,
    required this.folders,
    required this.initialGeneratedPassword,
    required this.onGeneratePassword,
  });

  final DecryptedLoginItem? item;
  final List<DecryptedFolder> folders;
  final String initialGeneratedPassword;
  final String Function() onGeneratePassword;

  @override
  State<_PasswordEditorPage> createState() => _PasswordEditorPageState();
}

class _PasswordEditorPageState extends State<_PasswordEditorPage> {
  late final TextEditingController _titleController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _urlController;
  late final TextEditingController _noteController;
  late String _folderId;
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.item?.title ?? '');
    _usernameController = TextEditingController(
      text: widget.item?.username ?? '',
    );
    _passwordController = TextEditingController(
      text: widget.item?.password ?? '',
    );
    _urlController = TextEditingController(text: widget.item?.url ?? '');
    _noteController = TextEditingController(text: widget.item?.note ?? '');
    _folderId = widget.item?.folderId ?? '';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _urlController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  List<DropdownMenuItem<String>> _folderItems() {
    return [
      const DropdownMenuItem<String>(value: '', child: Text('未分类')),
      ...widget.folders.map(
        (folder) => DropdownMenuItem<String>(
          value: folder.id,
          child: Text(folder.name),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.item == null ? '创建密码' : '编辑密码')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        TextField(
                          controller: _titleController,
                          decoration: const InputDecoration(labelText: '标题'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _usernameController,
                          decoration: const InputDecoration(labelText: '用户名'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _passwordController,
                          obscureText: !_showPassword,
                          decoration: InputDecoration(
                            labelText: '密码',
                            suffixIcon: Wrap(
                              spacing: 4,
                              children: [
                                IconButton(
                                  tooltip: _showPassword ? '隐藏密码' : '查看密码',
                                  onPressed: () {
                                    setState(() {
                                      _showPassword = !_showPassword;
                                    });
                                  },
                                  icon: Icon(
                                    _showPassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                  ),
                                ),
                                IconButton(
                                  tooltip: '生成密码',
                                  onPressed: () {
                                    _passwordController.text =
                                        widget
                                            .initialGeneratedPassword
                                            .isNotEmpty
                                        ? widget.initialGeneratedPassword
                                        : widget.onGeneratePassword();
                                  },
                                  icon: const Icon(
                                    Icons.auto_fix_high_outlined,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _urlController,
                          decoration: const InputDecoration(labelText: '地址'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _noteController,
                          minLines: 3,
                          maxLines: 5,
                          decoration: const InputDecoration(labelText: '备注'),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _folderId,
                          items: _folderItems(),
                          onChanged: (value) {
                            setState(() {
                              _folderId = value ?? '';
                            });
                          },
                          decoration: const InputDecoration(labelText: '保存到分类'),
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
                  onPressed: () {
                    Navigator.of(context).pop(
                      _LoginItemDraft(
                        title: _titleController.text.trim(),
                        username: _usernameController.text.trim(),
                        password: _passwordController.text,
                        url: _urlController.text.trim(),
                        note: _noteController.text.trim(),
                        folderId: _folderId,
                      ),
                    );
                  },
                  child: const Text('保存'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PasswordDetailPage extends StatefulWidget {
  const _PasswordDetailPage({required this.item, required this.folderName});

  final DecryptedLoginItem item;
  final String folderName;

  @override
  State<_PasswordDetailPage> createState() => _PasswordDetailPageState();
}

class _PasswordDetailPageState extends State<_PasswordDetailPage> {
  bool _showPassword = false;

  Future<void> _copyPassword() async {
    await Clipboard.setData(ClipboardData(text: widget.item.password));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('密码已复制')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.item.title.isEmpty ? '(未命名)' : widget.item.title),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _DetailRow(label: '分类', value: widget.folderName),
                        const SizedBox(height: 12),
                        _DetailRow(label: '用户名', value: widget.item.username),
                        const SizedBox(height: 12),
                        Text(
                          '密码',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: context.sx.mutedText),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: context.sx.subtle,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: context.sx.border),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: SelectableText(
                                  _showPassword
                                      ? (widget.item.password.isEmpty
                                            ? '-'
                                            : widget.item.password)
                                      : (widget.item.password.isEmpty
                                            ? '-'
                                            : '••••••••••••'),
                                  style: Theme.of(context).textTheme.bodyLarge
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ),
                              IconButton(
                                tooltip: '复制密码',
                                onPressed: widget.item.password.isEmpty
                                    ? null
                                    : _copyPassword,
                                icon: const Icon(Icons.copy_outlined),
                              ),
                              IconButton(
                                tooltip: _showPassword ? '隐藏密码' : '查看密码',
                                onPressed: widget.item.password.isEmpty
                                    ? null
                                    : () {
                                        setState(() {
                                          _showPassword = !_showPassword;
                                        });
                                      },
                                icon: Icon(
                                  _showPassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _DetailRow(label: '地址', value: widget.item.url),
                        const SizedBox(height: 12),
                        _DetailRow(label: '备注', value: widget.item.note),
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
                  onPressed: () =>
                      Navigator.of(context).pop(_PasswordDetailAction.delete),
                  child: const Text('删除'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () =>
                      Navigator.of(context).pop(_PasswordDetailAction.edit),
                  child: const Text('编辑'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: context.sx.mutedText),
        ),
        const SizedBox(height: 6),
        SelectableText(
          value.isEmpty ? '-' : value,
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
