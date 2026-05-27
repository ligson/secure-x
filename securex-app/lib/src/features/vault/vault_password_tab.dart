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
                        '分类',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: widget.controller.busy
                          ? null
                          : _showFolderManager,
                      icon: const Icon(Icons.tune_outlined),
                      label: const Text('管理'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (folders.isEmpty)
                  Text(
                    '还没有分类',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: context.sx.mutedText,
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 260),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        _PasswordFolderTreeTile(
                          title: '全部',
                          subtitle: '${_countItemsInFolderTree(null)} 个密码',
                          selected: _activeVaultFolderId.isEmpty,
                          depth: 0,
                          onTap: () {
                            setState(() {
                              _activeVaultFolderId = '';
                            });
                          },
                        ),
                        for (final folder in folders)
                          _PasswordFolderTreeTile(
                            title: folder.name,
                            subtitle:
                                '${_countItemsInFolderTree(folder.id)} 个密码',
                            selected: _activeVaultFolderId == folder.id,
                            depth: widget.controller.passwordFolderDepth(
                              folder.id,
                            ),
                            onTap: () {
                              setState(() {
                                _activeVaultFolderId = folder.id;
                              });
                            },
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
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

class _PasswordFolderTreeTile extends StatelessWidget {
  const _PasswordFolderTreeTile({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.depth,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final int depth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final leftPadding = 10.0 + depth * 18.0;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: EdgeInsets.fromLTRB(leftPadding, 10, 12, 10),
        decoration: BoxDecoration(
          color: selected ? context.sx.accentSoft : context.sx.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? context.sx.primary : context.sx.border,
          ),
        ),
        child: Row(
          children: [
            Icon(
              depth == 0
                  ? Icons.folder_open_outlined
                  : Icons.subdirectory_arrow_right,
              size: 18,
              color: selected ? context.sx.primary : context.sx.mutedText,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: selected ? context.sx.primary : context.sx.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.sx.mutedText,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle, size: 18, color: context.sx.primary),
          ],
        ),
      ),
    );
  }
}
