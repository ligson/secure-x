// ignore_for_file: invalid_use_of_protected_member

part of '../../../main.dart';

extension _VaultFilesTab on _VaultScreenState {
  Widget _buildFilesWorkspaceTab(BuildContext context) {
    final folders = _visibleFileFolders();
    final files = _filteredVisibleFiles();
    final isRoot = _activeFileFolderId.isEmpty;
    final currentFolderName = widget.controller.fileFolderNameById(
      _activeFileFolderId,
    );

    return _buildVaultTabScrollView(
      header: Row(
        children: [
          Expanded(
            child: _buildModuleHeader(
              icon: Icons.folder_outlined,
              title: '文件',
              tag: '加密上传',
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: widget.controller.busy
                ? null
                : () async {
                    try {
                      await widget.controller.uploadFile(
                        folderId: _activeFileFolderId,
                      );
                    } catch (_) {}
                  },
            icon: const Icon(Icons.upload_file_outlined),
            label: const Text('上传文件'),
          ),
        ],
      ),
      sections: [
        ..._buildPageStatusSections(),
        TextField(
          controller: _fileSearchController,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            hintText: '搜索当前目录',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        if (widget.controller.uploadTasks.isNotEmpty)
          _buildUploadProgressCard(),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        currentFolderName,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (!isRoot)
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _activeFileFolderId = _activeFileFolderParentId();
                          });
                        },
                        icon: const Icon(Icons.arrow_upward_outlined),
                        label: const Text('返回上级'),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth < 520) {
                      return Column(
                        children: [
                          TextField(
                            controller: _fileFolderCreateController,
                            decoration: const InputDecoration(
                              hintText: '新建文件夹',
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: widget.controller.busy
                                  ? null
                                  : _handleCreateFileFolder,
                              icon: const Icon(
                                Icons.create_new_folder_outlined,
                              ),
                              label: const Text('创建文件夹'),
                            ),
                          ),
                        ],
                      );
                    }

                    return Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _fileFolderCreateController,
                            decoration: const InputDecoration(
                              hintText: '新建文件夹',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: widget.controller.busy
                              ? null
                              : _handleCreateFileFolder,
                          icon: const Icon(Icons.create_new_folder_outlined),
                          label: const Text('创建文件夹'),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
      listSection: Card(
        child: Column(
          children: [
            const _ListCardHeader(title: '目录内容'),
            Expanded(
              child: folders.isEmpty && files.isEmpty
                  ? const Center(child: Text('还没有内容'))
                  : ListView.separated(
                      itemCount: folders.length + files.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        if (index < folders.length) {
                          return _buildFileFolderTile(folders[index]);
                        }
                        return _buildFileTile(
                          file: files[index - folders.length],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileFolderTile(DecryptedFileFolder folder) {
    return ListTile(
      onTap: () {
        setState(() {
          _activeFileFolderId = folder.id;
          _fileSearchController.clear();
        });
      },
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: context.sx.subtle,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.folder_outlined, size: 18),
      ),
      title: Text(folder.name),
      subtitle: Text(
        '${_countFileFoldersInFolder(folder.id)} 个文件夹 · ${_countFilesInFolder(folder.id)} 个文件',
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (value) async {
          if (value == 'edit') {
            await _showFileFolderEditor(folder: folder);
            return;
          }
          if (value == 'delete') {
            final confirmed = await _confirmDelete(
              title: '删除文件夹',
              body: '删除前请先清空该文件夹内的子文件夹和文件。',
            );
            if (!confirmed) {
              return;
            }
            try {
              await widget.controller.deleteFileFolder(folder);
              setState(() {
                if (_activeFileFolderId == folder.id) {
                  _activeFileFolderId = '';
                }
              });
            } catch (_) {}
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'edit', child: Text('编辑')),
          PopupMenuItem(value: 'delete', child: Text('删除')),
        ],
      ),
    );
  }

  Widget _buildFileTile({required DecryptedFileRecord file}) {
    return ListTile(
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: context.sx.subtle,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.insert_drive_file_outlined, size: 18),
      ),
      title: Text(file.name),
      subtitle: Text(
        '${widget.controller.fileFolderNameById(file.folderId)} · 原始 ${file.originalSize} bytes · 密文 ${file.cipherSize} bytes',
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (value) async {
          if (value == 'download') {
            try {
              final path = await widget.controller.downloadFile(file);
              if (!mounted) {
                return;
              }
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('已解密到 $path')));
            } catch (_) {}
            return;
          }
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
              await widget.controller.deleteEncryptedFile(file);
            } catch (_) {}
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'download', child: Text('下载')),
          PopupMenuItem(value: 'edit', child: Text('编辑')),
          PopupMenuItem(value: 'delete', child: Text('删除')),
        ],
      ),
    );
  }

  Widget _buildUploadProgressCard() {
    final tasks = widget.controller.uploadTasks;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '后台上传',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            for (var index = 0; index < tasks.length; index++) ...[
              _UploadProgressTile(
                task: tasks[index],
                onDismiss: tasks[index].done || tasks[index].failed
                    ? () => widget.controller.dismissUploadTask(tasks[index].id)
                    : null,
              ),
              if (index != tasks.length - 1) const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}
