// ignore_for_file: invalid_use_of_protected_member

part of '../../../main.dart';

extension _VaultPasswordTab on _VaultScreenState {
  Widget _buildPasswordVaultTab(BuildContext context) {
    final folders = widget.controller.folders;
    final items = _filteredVaultItems();

    return _buildVaultTabScrollView(
      sections: [
        Row(
          children: [
            Expanded(
              child: _buildModuleHeader(
                icon: Icons.key_outlined,
                title: '密码库',
                tag: '本地加密',
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: widget.controller.busy
                  ? null
                  : () => _showPasswordComposer(),
              icon: const Icon(Icons.add),
              label: const Text('创建'),
            ),
          ],
        ),
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
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      ChoiceChip(
                        label: Text(
                          '全部 ${_countItemsInFolder(null)}',
                          style: _chipLabelStyle(_activeVaultFolderId.isEmpty),
                        ),
                        selected: _activeVaultFolderId.isEmpty,
                        checkmarkColor: context.sx.primary,
                        onSelected: (_) {
                          setState(() {
                            _activeVaultFolderId = '';
                          });
                        },
                      ),
                      ...folders.map(
                        (folder) => ChoiceChip(
                          label: Text(
                            '${folder.name} ${_countItemsInFolder(folder.id)}',
                            style: _chipLabelStyle(
                              _activeVaultFolderId == folder.id,
                            ),
                          ),
                          selected: _activeVaultFolderId == folder.id,
                          checkmarkColor: context.sx.primary,
                          onSelected: (_) {
                            setState(() {
                              _activeVaultFolderId = folder.id;
                            });
                          },
                        ),
                      ),
                    ],
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
}
