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
    _vaultKey = null;
    _folders = [];
    _fileFolders = [];
    _items = [];
    _files = [];
    notifyListeners();
  }

  Future<void> logout() async {
    _token = null;
    _user = null;
    _vaultKey = null;
    _folders = [];
    _fileFolders = [];
    _items = [];
    _files = [];
    await _clearPersistedToken();
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
