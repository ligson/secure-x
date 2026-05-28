// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'app_controller.dart';

extension AppControllerSessionActions on AppController {
  String generatePassword({
    int length = 20,
    bool useUppercase = true,
    bool useLowercase = true,
    bool useDigits = true,
    bool useSymbols = true,
  }) => _cryptoService.generatePassword(
    length: length,
    useUppercase: useUppercase,
    useLowercase: useLowercase,
    useDigits: useDigits,
    useSymbols: useSymbols,
  );

  Future<void> lock() async {
    await _flushPendingChatArchiveSync();
    _stopPendingChatPolling();
    await _realtimeChatService.disconnect();
    _vaultKey = null;
    _folders = [];
    _fileFolders = [];
    _items = [];
    _files = [];
    _friends = [];
    _incomingFriendRequests = [];
    _outgoingFriendRequests = [];
    _chatConversations = [];
    _loadedChatConversationIds.clear();
    _loadingChatConversationIds.clear();
    _chatConversationLoadTasks.clear();
    _chatIdentity = null;
    _clearChatDeviceRegistrationCache();
    _chatFriendOnline.clear();
    _historyRequestedPeerIds.clear();
    _realtimeConfig = null;
    _cancelPendingChatArchiveSync();
    _markAppShellChanged();
    notifyListeners();
  }

  Future<void> logout() async {
    await _flushPendingChatArchiveSync();
    _stopPendingChatPolling();
    await _realtimeChatService.disconnect();
    _token = null;
    _user = null;
    _vaultKey = null;
    _folders = [];
    _fileFolders = [];
    _items = [];
    _files = [];
    _friends = [];
    _incomingFriendRequests = [];
    _outgoingFriendRequests = [];
    _chatConversations = [];
    _loadedChatConversationIds.clear();
    _loadingChatConversationIds.clear();
    _chatConversationLoadTasks.clear();
    _chatIdentity = null;
    _clearChatDeviceRegistrationCache();
    _chatFriendOnline.clear();
    _historyRequestedPeerIds.clear();
    _realtimeConfig = null;
    _cancelPendingChatArchiveSync();
    await _clearPersistedToken();
    _markAppShellChanged();
    notifyListeners();
  }

  Future<List<ChatDeviceRecord>> listOwnChatDevices() async {
    final token = _token;
    if (token == null) {
      return const [];
    }
    await _ensureChatIdentity(registerOnServer: true);
    return _apiClient.listOwnChatDevices(baseUrl: _baseUrl, token: token);
  }

  Future<void> deleteOwnChatDevice(String deviceId) async {
    final token = _token;
    final normalizedDeviceId = deviceId.trim();
    if (token == null || normalizedDeviceId.isEmpty) {
      return;
    }
    if (normalizedDeviceId == currentChatDeviceId) {
      _statusMessage = '当前正在使用的设备不能删除。';
      notifyListeners();
      return;
    }
    await _runBusy(() async {
      await _apiClient.deleteOwnChatDevice(
        baseUrl: _baseUrl,
        token: token,
        deviceId: normalizedDeviceId,
      );
      _statusMessage = '设备已删除。';
    });
  }

  String folderNameById(String? folderId) {
    if (folderId == null || folderId.isEmpty) {
      return '未分类';
    }
    return _passwordFolderPathById(folderId) ?? '未知分类';
  }

  String fileFolderNameById(String? folderId) {
    if (folderId == null || folderId.isEmpty) {
      return '根目录';
    }

    for (final folder in _fileFolders) {
      if (folder.id == folderId) {
        return folder.name;
      }
    }

    return '未知文件夹';
  }

  List<DecryptedFolder> orderedPasswordFolders() {
    final folders = [..._folders];
    final childrenByParent = <String, List<DecryptedFolder>>{};
    for (final folder in folders) {
      final parentId = folder.parentFolderId ?? '';
      childrenByParent.putIfAbsent(parentId, () => []).add(folder);
    }
    for (final children in childrenByParent.values) {
      children.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    }

    final ordered = <DecryptedFolder>[];
    void visit(String parentId) {
      for (final folder
          in childrenByParent[parentId] ?? const <DecryptedFolder>[]) {
        ordered.add(folder);
        visit(folder.id);
      }
    }

    visit('');
    return ordered;
  }

  int passwordFolderDepth(String folderId) {
    final depthById = <String, int>{};
    int compute(String currentId, Set<String> visiting) {
      final cached = depthById[currentId];
      if (cached != null) {
        return cached;
      }
      if (!visiting.add(currentId)) {
        return 0;
      }
      DecryptedFolder? folder;
      for (final entry in _folders) {
        if (entry.id == currentId) {
          folder = entry;
          break;
        }
      }
      if (folder == null || (folder.parentFolderId ?? '').isEmpty) {
        depthById[currentId] = 0;
        visiting.remove(currentId);
        return 0;
      }
      final depth = compute(folder.parentFolderId!, visiting) + 1;
      depthById[currentId] = depth;
      visiting.remove(currentId);
      return depth;
    }

    return compute(folderId, <String>{});
  }

  Set<String> passwordFolderFamilyIds(String folderId) {
    final result = <String>{folderId};
    var changed = true;
    while (changed) {
      changed = false;
      for (final folder in _folders) {
        final parentId = folder.parentFolderId ?? '';
        if (result.contains(parentId) && result.add(folder.id)) {
          changed = true;
        }
      }
    }
    return result;
  }

  bool canMovePasswordFolder({
    required String folderId,
    required String nextParentFolderId,
  }) {
    if (folderId.isEmpty || nextParentFolderId.isEmpty) {
      return true;
    }
    return !passwordFolderFamilyIds(folderId).contains(nextParentFolderId);
  }

  String passwordFolderLabel(DecryptedFolder folder) {
    final depth = passwordFolderDepth(folder.id);
    final prefix = depth <= 0 ? '' : '  ' * depth;
    return '$prefix${folder.name}';
  }

  String? _passwordFolderPathById(String folderId) {
    final folderById = {for (final folder in _folders) folder.id: folder};
    final visited = <String>{};
    final parts = <String>[];
    var currentId = folderId;
    while (currentId.isNotEmpty) {
      if (!visited.add(currentId)) {
        break;
      }
      final folder = folderById[currentId];
      if (folder == null) {
        break;
      }
      parts.insert(0, folder.name);
      currentId = folder.parentFolderId ?? '';
    }
    if (parts.isEmpty) {
      return null;
    }
    return parts.join(' / ');
  }
}
