part of '../../../main.dart';

class _FileFolderEditorPage extends StatefulWidget {
  const _FileFolderEditorPage({required this.folder, required this.folders});

  final DecryptedFileFolder? folder;
  final List<DecryptedFileFolder> folders;

  @override
  State<_FileFolderEditorPage> createState() => _FileFolderEditorPageState();
}

class _FileFolderEditorPageState extends State<_FileFolderEditorPage> {
  late final TextEditingController _nameController;
  late String _parentFolderId;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.folder?.name ?? '');
    _parentFolderId = widget.folder?.parentFolderId ?? '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  List<DropdownMenuItem<String>> _parentFolderItems() {
    return [
      const DropdownMenuItem<String>(value: '', child: Text('根目录')),
      ...widget.folders
          .where((candidate) => candidate.id != widget.folder?.id)
          .map(
            (candidate) => DropdownMenuItem<String>(
              value: candidate.id,
              child: Text(candidate.name),
            ),
          ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.folder == null ? '新建文件夹' : '编辑文件夹')),
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
                          controller: _nameController,
                          decoration: const InputDecoration(labelText: '名称'),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _parentFolderId,
                          items: _parentFolderItems(),
                          onChanged: (value) {
                            setState(() {
                              _parentFolderId = value ?? '';
                            });
                          },
                          decoration: const InputDecoration(labelText: '上级目录'),
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
                      _FolderDraft(
                        name: _nameController.text.trim(),
                        parentFolderId: _parentFolderId,
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
