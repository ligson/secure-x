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
    _chatIdentity = null;
    _chatFriendOnline.clear();
    _historyRequestedPeerIds.clear();
    _realtimeConfig = null;
    _cancelPendingChatArchiveSync();
    _markAppShellChanged();
    notifyListeners();
  }

  Future<void> logout() async {
    await _flushPendingChatArchiveSync();
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
    _chatIdentity = null;
    _chatFriendOnline.clear();
    _historyRequestedPeerIds.clear();
    _realtimeConfig = null;
    _cancelPendingChatArchiveSync();
    await _clearPersistedToken();
    _markAppShellChanged();
    notifyListeners();
  }

  String folderNameById(String? folderId) {
    if (folderId == null || folderId.isEmpty) {
      return '未分类';
    }

    for (final folder in _folders) {
      if (folder.id == folderId) {
        return folder.name;
      }
    }

    return '未知文件夹';
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
}
