// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'app_controller.dart';

extension AppControllerVaultActions on AppController {
  Future<void> refreshVault() async {
    if (_token == null || _vaultKey == null) {
      return;
    }

    await _runBusy(() async {
      await _loadVaultSnapshot();
    });
  }

  Future<void> createFolder(String name) async {
    await upsertFolder(name: name);
  }

  Future<void> upsertFolder({
    required String name,
    DecryptedFolder? existing,
    String? parentFolderId,
  }) async {
    if (_token == null || _vaultKey == null) {
      return;
    }

    await _runBusy(() async {
      final payload = await _cryptoService.encryptJson({
        'name': name,
      }, _vaultKey!);
      if (existing == null) {
        await _apiClient.createFolder(
          baseUrl: _baseUrl,
          token: _token!,
          payload: payload,
          version: 1,
          parentFolderId: parentFolderIDOrNull(parentFolderId),
        );
      } else {
        await _apiClient.updateFolder(
          baseUrl: _baseUrl,
          token: _token!,
          folderId: existing.id,
          payload: payload,
          version: existing.version + 1,
          parentFolderId: parentFolderIDOrNull(parentFolderId),
        );
      }
      await _loadVaultSnapshot();
      _statusMessage = existing == null ? '分类已创建。' : '分类已更新。';
    });
  }

  Future<void> createFileFolder(String name, {String? parentFolderId}) async {
    await upsertFileFolder(name: name, parentFolderId: parentFolderId);
  }

  Future<void> upsertFileFolder({
    required String name,
    DecryptedFileFolder? existing,
    String? parentFolderId,
  }) async {
    if (_token == null || _vaultKey == null) {
      return;
    }

    await _runBusy(() async {
      final payload = await _cryptoService.encryptJson({
        'name': name,
      }, _vaultKey!);
      if (existing == null) {
        await _apiClient.createFileFolder(
          baseUrl: _baseUrl,
          token: _token!,
          payload: payload,
          version: 1,
          parentFolderId: parentFolderIDOrNull(parentFolderId),
        );
      } else {
        await _apiClient.updateFileFolder(
          baseUrl: _baseUrl,
          token: _token!,
          folderId: existing.id,
          payload: payload,
          version: existing.version + 1,
          parentFolderId: parentFolderIDOrNull(parentFolderId),
        );
      }
      await _loadVaultSnapshot();
      _statusMessage = existing == null ? '文件夹已创建。' : '文件夹已更新。';
    });
  }

  Future<void> createLoginItem({
    required String title,
    required String username,
    required String password,
    required String url,
    required String note,
    TotpConfig totp = const TotpConfig(secret: ''),
    String? folderId,
  }) async {
    await upsertLoginItem(
      title: title,
      username: username,
      password: password,
      url: url,
      note: note,
      totp: totp,
      folderId: folderId,
    );
  }

  Future<void> upsertLoginItem({
    required String title,
    required String username,
    required String password,
    required String url,
    required String note,
    TotpConfig totp = const TotpConfig(secret: ''),
    String? folderId,
    DecryptedLoginItem? existing,
  }) async {
    if (_token == null || _vaultKey == null) {
      return;
    }

    await _runBusy(() async {
      final payload = await _cryptoService.encryptJson({
        'title': title,
        'username': username,
        'password': password,
        'url': url,
        'note': note,
        'totpSecret': totp.secret,
        'totpIssuer': totp.issuer,
        'totpAccount': totp.account,
        'totpAlgorithm': totp.algorithm,
        'totpDigits': totp.digits,
        'totpPeriod': totp.period,
      }, _vaultKey!);
      if (existing == null) {
        await _apiClient.createItem(
          baseUrl: _baseUrl,
          token: _token!,
          kind: 'login',
          payload: payload,
          version: 1,
          folderId: parentFolderIDOrNull(folderId),
        );
      } else {
        await _apiClient.updateItem(
          baseUrl: _baseUrl,
          token: _token!,
          itemId: existing.id,
          kind: 'login',
          payload: payload,
          version: existing.version + 1,
          folderId: parentFolderIDOrNull(folderId),
        );
      }
      await _loadVaultSnapshot();
      _statusMessage = existing == null ? '登录信息已保存。' : '登录信息已更新。';
    });
  }
}
