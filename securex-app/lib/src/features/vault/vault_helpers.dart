// ignore_for_file: invalid_use_of_protected_member

part of '../../../main.dart';

extension _VaultHelpers on _VaultScreenState {
  Widget _buildModuleHeader({
    required IconData icon,
    required String title,
    required String tag,
  }) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: context.sx.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.sx.border),
          ),
          child: Icon(icon, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: context.sx.accentSoft,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            tag,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: context.sx.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildModuleHeaderAction({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    bool primary = false,
  }) {
    final style = primary
        ? FilledButton.styleFrom(
            backgroundColor: context.sx.accentSoft,
            foregroundColor: context.sx.primary,
            disabledBackgroundColor: context.sx.subtle,
            disabledForegroundColor: context.sx.mutedText,
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            minimumSize: const Size(0, 40),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          )
        : OutlinedButton.styleFrom(
            foregroundColor: context.sx.text,
            disabledForegroundColor: context.sx.mutedText,
            side: BorderSide(color: context.sx.border),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            minimumSize: const Size(0, 40),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          );

    if (primary) {
      return FilledButton.icon(
        style: style,
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
      );
    }
    return OutlinedButton.icon(
      style: style,
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }

  Future<void> _handleCreateFileFolder() async {
    final name = _fileFolderCreateController.text.trim();
    if (name.isEmpty) {
      return;
    }
    try {
      await widget.controller.createFileFolder(
        name,
        parentFolderId: _activeFileFolderId,
      );
      _fileFolderCreateController.clear();
    } catch (_) {}
  }

  int _countItemsInFolderTree(String? folderId) {
    if (folderId == null || folderId.isEmpty) {
      return widget.controller.items.length;
    }
    final familyIds = widget.controller.passwordFolderFamilyIds(folderId);
    return widget.controller.items
        .where((item) => familyIds.contains(item.folderId ?? ''))
        .length;
  }

  int _countFilesInFolder(String? folderId) {
    final normalizedFolderId = folderId ?? '';
    return widget.controller.files
        .where((file) => (file.folderId ?? '') == normalizedFolderId)
        .length;
  }

  int _countFileFoldersInFolder(String? folderId) {
    final normalizedFolderId = folderId ?? '';
    return widget.controller.fileFolders
        .where((folder) => (folder.parentFolderId ?? '') == normalizedFolderId)
        .length;
  }

  void _regeneratePassword() {
    final canGenerate =
        _generatorUseUppercase ||
        _generatorUseLowercase ||
        _generatorUseDigits ||
        _generatorUseSymbols;
    _generatedPassword = canGenerate
        ? widget.controller.generatePassword(
            length: _generatorLength,
            useUppercase: _generatorUseUppercase,
            useLowercase: _generatorUseLowercase,
            useDigits: _generatorUseDigits,
            useSymbols: _generatorUseSymbols,
          )
        : '';
  }

  Widget _buildVaultTabScrollView({
    required Widget header,
    required List<Widget> sections,
    required Widget listSection,
  }) {
    final listHeight = (MediaQuery.sizeOf(context).height * 0.48).clamp(
      360.0,
      560.0,
    );

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          header,
          const SizedBox(height: 12),
          Expanded(
            child: CustomScrollView(
              slivers: [
                for (var index = 0; index < sections.length; index++) ...[
                  SliverToBoxAdapter(child: sections[index]),
                  if (index != sections.length - 1)
                    const SliverToBoxAdapter(child: SizedBox(height: 12)),
                ],
                if (sections.isNotEmpty)
                  const SliverToBoxAdapter(child: SizedBox(height: 12)),
                SliverToBoxAdapter(
                  child: SizedBox(height: listHeight, child: listSection),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildPageStatusSections({
    _PageNoticeTone tone = _PageNoticeTone.neutral,
  }) {
    final message = widget.controller.busy
        ? '处理中...'
        : widget.controller.statusMessage;
    if (message == null ||
        message.isEmpty ||
        _dismissedPageStatusMessage == message) {
      return const [];
    }

    return [
      _PageNotice(
        message: message,
        tone: tone,
        onClose: () {
          setState(() {
            _dismissedPageStatusMessage = message;
          });
        },
      ),
    ];
  }

  List<DecryptedLoginItem> _filteredVaultItems() {
    final query = _itemSearchController.text.trim().toLowerCase();
    final selectedFolderIds = _activeVaultFolderId.isEmpty
        ? <String>{}
        : widget.controller.passwordFolderFamilyIds(_activeVaultFolderId);
    return widget.controller.items.where((item) {
      final matchesFolder = _activeVaultFolderId.isEmpty
          ? true
          : selectedFolderIds.contains(item.folderId ?? '');
      if (!matchesFolder) {
        return false;
      }
      if (query.isEmpty) {
        return true;
      }
      final folderName = widget.controller
          .folderNameById(item.folderId)
          .toLowerCase();
      return item.title.toLowerCase().contains(query) ||
          item.username.toLowerCase().contains(query) ||
          item.url.toLowerCase().contains(query) ||
          folderName.contains(query);
    }).toList();
  }

  List<DecryptedFileFolder> _visibleFileFolders() {
    final query = _fileSearchController.text.trim().toLowerCase();
    return widget.controller.fileFolders
        .where((folder) => (folder.parentFolderId ?? '') == _activeFileFolderId)
        .where((folder) {
          if (query.isEmpty) {
            return true;
          }
          return folder.name.toLowerCase().contains(query);
        })
        .toList();
  }

  List<DecryptedFileRecord> _filteredVisibleFiles() {
    final query = _fileSearchController.text.trim().toLowerCase();
    return widget.controller.files.where((file) {
      final matchesFolder = (file.folderId ?? '') == _activeFileFolderId;
      if (!matchesFolder) {
        return false;
      }
      if (query.isEmpty) {
        return true;
      }
      final folderName = widget.controller
          .fileFolderNameById(file.folderId)
          .toLowerCase();
      return file.name.toLowerCase().contains(query) ||
          folderName.contains(query);
    }).toList();
  }

  String _activeFileFolderParentId() {
    for (final folder in widget.controller.fileFolders) {
      if (folder.id == _activeFileFolderId) {
        return folder.parentFolderId ?? '';
      }
    }
    return '';
  }

  String? _validateBaseUrl(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return '请先填写后端地址。';
    }
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        !(uri.isScheme('http') || uri.isScheme('https')) ||
        (uri.host.isEmpty && normalized != 'http://localhost')) {
      return '后端地址格式不正确，请使用 http://127.0.0.1:8080 这类完整地址。';
    }
    return null;
  }

  Future<void> _showPasswordComposer() async {
    await _showItemEditor();
  }

  Future<void> _showFolderManager() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) =>
            _PasswordFolderManagerPage(controller: widget.controller),
      ),
    );
    if (!mounted || _activeVaultFolderId.isEmpty) {
      return;
    }
    final selectedExists = widget.controller.folders.any(
      (folder) => folder.id == _activeVaultFolderId,
    );
    if (!selectedExists) {
      setState(() {
        _activeVaultFolderId = '';
      });
    }
  }

  Future<void> _showFileFolderEditor({DecryptedFileFolder? folder}) async {
    final result = await Navigator.of(context).push<_FolderDraft>(
      MaterialPageRoute(
        builder: (context) => _FileFolderEditorPage(
          folder: folder,
          folders: widget.controller.fileFolders,
        ),
      ),
    );

    if (result == null || result.name.isEmpty) {
      return;
    }

    try {
      await widget.controller.upsertFileFolder(
        name: result.name,
        existing: folder,
        parentFolderId: result.parentFolderId,
      );
    } catch (_) {}
  }

  Future<void> _showItemEditor({DecryptedLoginItem? item}) async {
    final result = await Navigator.of(context).push<_LoginItemDraft>(
      MaterialPageRoute(
        builder: (context) => _PasswordEditorPage(
          controller: widget.controller,
          item: item,
          folders: widget.controller.folders,
          initialGeneratedPassword: _generatedPassword,
          onGeneratePassword: () => widget.controller.generatePassword(),
        ),
      ),
    );

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

  Future<void> _showItemDetail(DecryptedLoginItem item) async {
    final action = await Navigator.of(context).push<_PasswordDetailAction>(
      MaterialPageRoute(
        builder: (context) => _PasswordDetailPage(
          item: item,
          folderName: widget.controller.folderNameById(item.folderId),
        ),
      ),
    );
    if (!mounted || action == null) {
      return;
    }
    if (action == _PasswordDetailAction.edit) {
      await _showItemEditor(item: item);
      return;
    }
    if (action == _PasswordDetailAction.delete) {
      final confirmed = await _confirmDelete(
        title: '删除密码项',
        body: '这条密码项会从当前保险库中移除。',
      );
      if (!confirmed) {
        return;
      }
      try {
        await widget.controller.deleteLoginItem(item);
      } catch (_) {}
    }
  }

  Future<void> _showFileEditor({required DecryptedFileRecord file}) async {
    final result = await Navigator.of(context).push<_FileDraft>(
      MaterialPageRoute(
        builder: (context) =>
            _FileEditorPage(file: file, folders: widget.controller.fileFolders),
      ),
    );

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
}
