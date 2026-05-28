// ignore_for_file: invalid_use_of_protected_member

part of '../../../main.dart';

extension _VaultPasswordTab on _VaultScreenState {
  Widget _buildPasswordVaultTab(BuildContext context) {
    final folders = widget.controller.orderedPasswordFolders();
    final items = _filteredVaultItems();

    return _buildVaultTabScrollView(
      header: _buildPasswordVaultHeader(context),
      sections: [
        ..._buildPageStatusSections(),
        TextField(
          controller: _itemSearchController,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            hintText: '搜索密码项',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        _PasswordFolderSelector(
          folders: folders,
          activeFolderId: _activeVaultFolderId,
          countItemsInFolderTree: _countItemsInFolderTree,
          folderLabel: widget.controller.passwordFolderLabel,
          folderDepth: widget.controller.passwordFolderDepth,
          onChanged: (folderId) {
            setState(() {
              _activeVaultFolderId = folderId ?? '';
            });
          },
          onManage: widget.controller.busy ? null : _showFolderManager,
        ),
      ],
      listSection: Card(
        child: Column(
          children: [
            const _ListCardHeader(title: '密码标题'),
            Expanded(
              child: items.isEmpty
                  ? const Center(child: Text('还没有密码项'))
                  : ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return ListTile(
                          onTap: () => _showItemDetail(item),
                          leading: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: context.sx.subtle,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.key_outlined, size: 18),
                          ),
                          title: Text(
                            item.title.isEmpty ? '(未命名)' : item.title,
                          ),
                          subtitle: Text(
                            '${widget.controller.folderNameById(item.folderId)}${item.username.isEmpty ? '' : ' · ${item.username}'}',
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPasswordVaultHeader(BuildContext context) {
    final actions = [
      OutlinedButton.icon(
        onPressed: _showGeneratorPage,
        icon: const Icon(Icons.password_outlined),
        label: const Text('生成器'),
      ),
      FilledButton.icon(
        onPressed: widget.controller.busy
            ? null
            : () => _showPasswordComposer(),
        icon: const Icon(Icons.add),
        label: const Text('创建'),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final header = _buildModuleHeader(
          icon: Icons.key_outlined,
          title: '密码库',
          tag: '本地加密',
        );

        if (constraints.maxWidth < 560) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              header,
              const SizedBox(height: 12),
              Wrap(spacing: 10, runSpacing: 10, children: actions),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: header),
            const SizedBox(width: 12),
            ...actions.expand((action) => [action, const SizedBox(width: 10)]),
          ]..removeLast(),
        );
      },
    );
  }
}

class _PasswordFolderSelector extends StatelessWidget {
  const _PasswordFolderSelector({
    required this.folders,
    required this.activeFolderId,
    required this.countItemsInFolderTree,
    required this.folderLabel,
    required this.folderDepth,
    required this.onChanged,
    required this.onManage,
  });

  final List<DecryptedFolder> folders;
  final String activeFolderId;
  final int Function(String? folderId) countItemsInFolderTree;
  final String Function(DecryptedFolder folder) folderLabel;
  final int Function(String folderId) folderDepth;
  final ValueChanged<String?> onChanged;
  final VoidCallback? onManage;

  @override
  Widget build(BuildContext context) {
    final activeValue = folders.any((folder) => folder.id == activeFolderId)
        ? activeFolderId
        : '';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '分类筛选',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: onManage,
                  icon: const Icon(Icons.tune_outlined),
                  label: const Text('管理'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: activeValue,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: '当前分类',
                prefixIcon: Icon(Icons.account_tree_outlined),
              ),
              items: [
                DropdownMenuItem(
                  value: '',
                  child: _PasswordFolderOption(
                    title: '全部分类',
                    subtitle: '${countItemsInFolderTree(null)} 个密码',
                  ),
                ),
                for (final folder in folders)
                  DropdownMenuItem(
                    value: folder.id,
                    child: _PasswordFolderOption(
                      title: folderLabel(folder),
                      subtitle: '${countItemsInFolderTree(folder.id)} 个密码',
                      depth: folderDepth(folder.id),
                    ),
                  ),
              ],
              onChanged: onChanged,
            ),
            const SizedBox(height: 8),
            Text(
              '一次只筛选一个分类，选择父分类时会包含其子分类。',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: context.sx.mutedText),
            ),
          ],
        ),
      ),
    );
  }
}

class _PasswordFolderOption extends StatelessWidget {
  const _PasswordFolderOption({
    required this.title,
    required this.subtitle,
    this.depth = 0,
  });

  final String title;
  final String subtitle;
  final int depth;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: depth * 14.0),
      child: Row(
        children: [
          Icon(
            depth == 0
                ? Icons.folder_open_outlined
                : Icons.subdirectory_arrow_right,
            size: 18,
            color: context.sx.mutedText,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: context.sx.mutedText),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
