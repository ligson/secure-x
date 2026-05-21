// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'app_controller.dart';

extension AppControllerRecordActions on AppController {
  Future<void> deleteFolder(DecryptedFolder folder) async {
    if (_token == null) {
      return;
    }

    await _runBusy(() async {
      await _apiClient.deleteFolder(
        baseUrl: _baseUrl,
        token: _token!,
        folderId: folder.id,
      );
      await _loadVaultSnapshot();
      _statusMessage = '分类已删除。';
    });
  }

  Future<void> deleteFileFolder(DecryptedFileFolder folder) async {
    if (_token == null) {
      return;
    }

    await _runBusy(() async {
      await _apiClient.deleteFileFolder(
        baseUrl: _baseUrl,
        token: _token!,
        folderId: folder.id,
      );
      await _loadVaultSnapshot();
      _statusMessage = '文件夹已删除。';
    });
  }

  Future<void> deleteLoginItem(DecryptedLoginItem item) async {
    if (_token == null) {
      return;
    }

    await _runBusy(() async {
      await _apiClient.deleteItem(
        baseUrl: _baseUrl,
        token: _token!,
        itemId: item.id,
      );
      await _loadVaultSnapshot();
      _statusMessage = '登录信息已删除。';
    });
  }

  Future<void> deleteEncryptedFile(DecryptedFileRecord file) async {
    if (_token == null) {
      return;
    }

    await _runBusy(() async {
      await _apiClient.deleteFile(
        baseUrl: _baseUrl,
        token: _token!,
        fileId: file.id,
      );
      await _loadVaultSnapshot();
      _statusMessage = '文件已删除。';
    });
  }

  Future<String> downloadFile(DecryptedFileRecord file) async {
    if (_token == null || _vaultKey == null) {
      throw Exception('vault is locked');
    }

    return _runBusyWithResult(() async {
      final encryptedBytes = await _apiClient.downloadEncryptedFile(
        baseUrl: _baseUrl,
        token: _token!,
        fileId: file.id,
      );

      final directory = await getApplicationDocumentsDirectory();
      final output = File('${directory.path}/${file.name}');
      final fileKey = Uint8List.fromList(base64Decode(file.fileKey));
      if (file.chunked) {
        final sink = output.openWrite();
        var offset = 0;
        try {
          for (final cipherSize in file.chunkCipherSizes) {
            final nextOffset = offset + cipherSize;
            final clearBytes = await _cryptoService.decryptBinary(
              encryptedBytes.sublist(offset, nextOffset),
              fileKey,
            );
            sink.add(clearBytes);
            offset = nextOffset;
          }
        } finally {
          await sink.close();
        }
      } else {
        final clearBytes = await _cryptoService.decryptBinary(
          encryptedBytes,
          fileKey,
        );
        await output.writeAsBytes(clearBytes, flush: true);
      }
      _statusMessage = '文件已解密到 ${output.path}';
      return output.path;
    });
  }
}
