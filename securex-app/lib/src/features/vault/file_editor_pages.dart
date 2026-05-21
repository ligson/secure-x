part of '../../../main.dart';

class _FileEditorPage extends StatefulWidget {
  const _FileEditorPage({required this.file, required this.folders});

  final DecryptedFileRecord file;
  final List<DecryptedFileFolder> folders;

  @override
  State<_FileEditorPage> createState() => _FileEditorPageState();
}

class _FileEditorPageState extends State<_FileEditorPage> {
  late final TextEditingController _nameController;
  late String _folderId;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.file.name);
    _folderId = widget.file.folderId ?? '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  List<DropdownMenuItem<String>> _folderItems() {
    return [
      const DropdownMenuItem<String>(value: '', child: Text('根目录')),
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
      appBar: AppBar(title: const Text('编辑文件')),
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
                          decoration: const InputDecoration(labelText: '显示名称'),
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
                          decoration: const InputDecoration(labelText: '存放到目录'),
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
                      _FileDraft(
                        name: _nameController.text.trim(),
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
