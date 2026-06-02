// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'app_controller.dart';

extension AppControllerUploadActions on AppController {
  Future<void> uploadFile({String? folderId}) async {
    if (_token == null || _vaultKey == null) {
      return;
    }

    PlatformFile? pickedFile;
    try {
      final result = await FilePicker.platform.pickFiles(withData: false);
      pickedFile = result?.files.single;
    } catch (error) {
      _statusMessage = '无法打开文件选择器：${_friendlyError(error)}';
      notifyListeners();
      return;
    }

    if (pickedFile == null) {
      _statusMessage = '未选择文件。';
      notifyListeners();
      return;
    }

    if (pickedFile.path == null) {
      _statusMessage = '无法读取文件内容。';
      notifyListeners();
      return;
    }

    final task = FileUploadTask(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: pickedFile.name,
      totalBytes: pickedFile.size,
      status: '等待后台上传',
    );
    _uploadTasks.insert(0, task);
    _statusMessage = '文件已加入后台上传。';
    notifyListeners();

    unawaited(_uploadFileInBackground(task, pickedFile, folderId));
  }

  Future<void> _uploadFileInBackground(
    FileUploadTask task,
    PlatformFile selectedFile,
    String? folderId,
  ) async {
    try {
      final token = _token;
      final vaultKey = _vaultKey;
      final path = selectedFile.path;
      if (token == null || vaultKey == null || path == null) {
        return;
      }
      final uploaded = await _uploadEncryptedFileFromPath(
        path: path,
        name: selectedFile.name,
        mimeType: selectedFile.extension ?? 'application/octet-stream',
        folderId: folderId,
        allowedUserIds: const [],
        task: task,
      );
      await _loadVaultSnapshot();
      task.completedBytes = uploaded.originalSize;
      task.status = '上传完成';
      task.done = true;
      _statusMessage = '加密文件已上传。';
      notifyListeners();
    } catch (error) {
      task.failed = true;
      task.status = _friendlyError(error);
      _statusMessage = '文件上传失败：${task.status}';
      notifyListeners();
    }
  }

  Future<DecryptedFileRecord> _uploadEncryptedFileFromPath({
    required String path,
    required String name,
    required String mimeType,
    required String? folderId,
    required List<String> allowedUserIds,
    FileUploadTask? task,
  }) async {
    final token = _token;
    final vaultKey = _vaultKey;
    if (token == null || vaultKey == null) {
      throw Exception('vault is locked');
    }

    const chunkSize = 2 * 1024 * 1024;
    final sourceFile = File(path);
    final originalSize = await sourceFile.length();
    final totalChunks = originalSize == 0
        ? 1
        : ((originalSize + chunkSize - 1) ~/ chunkSize);
    final fileKey = _cryptoService.randomKey();
    final chunkCipherSizes = List<int>.filled(totalChunks, 0);

    task?.status = '创建上传任务';
    notifyListeners();
    final startData = await _apiClient.startChunkedFileUpload(
      baseUrl: _baseUrl,
      token: token,
      totalChunks: totalChunks,
      version: 1,
      folderId: parentFolderIDOrNull(folderId),
      allowedUserIds: allowedUserIds,
    );
    final upload = startData['upload'] as Map<String, dynamic>;
    final uploadId = upload['id'] as String;
    final uploadedChunks = <int>{
      for (final value in startData['uploadedChunks'] as List<dynamic>? ?? [])
        (value as num).toInt(),
    };

    Future<void> refreshUploadedChunks() async {
      final data = await _apiClient.getChunkedFileUpload(
        baseUrl: _baseUrl,
        token: token,
        uploadId: uploadId,
      );
      uploadedChunks
        ..clear()
        ..addAll(
          (data['uploadedChunks'] as List<dynamic>? ?? []).map(
            (value) => (value as num).toInt(),
          ),
        );
    }

    Future<void> uploadChunkWithResume(int index, Uint8List clearChunk) async {
      if (uploadedChunks.contains(index)) {
        return;
      }
      task?.status = '加密分片 ${index + 1} / $totalChunks';
      notifyListeners();
      final cipherBytes = await compute(encryptBinaryChunkForUpload, {
        'bytes': clearChunk,
        'keyBytes': fileKey,
      });
      chunkCipherSizes[index] = cipherBytes.length;

      for (var attempt = 0; attempt < 3; attempt += 1) {
        try {
          task?.status = attempt == 0
              ? '上传分片 ${index + 1} / $totalChunks'
              : '续传分片 ${index + 1} / $totalChunks';
          notifyListeners();
          await _apiClient.uploadFileChunk(
            baseUrl: _baseUrl,
            token: token,
            uploadId: uploadId,
            index: index,
            cipherBytes: cipherBytes,
          );
          uploadedChunks.add(index);
          return;
        } catch (_) {
          await refreshUploadedChunks();
          if (uploadedChunks.contains(index)) {
            return;
          }
          if (attempt == 2) {
            rethrow;
          }
          await Future<void>.delayed(
            Duration(milliseconds: 600 * (attempt + 1)),
          );
        }
      }
    }

    if (originalSize == 0) {
      await uploadChunkWithResume(0, Uint8List(0));
    } else {
      var index = 0;
      await for (final clearChunk in _readFileChunks(sourceFile, chunkSize)) {
        await uploadChunkWithResume(index, clearChunk);
        final completedChunks = uploadedChunks.length.clamp(0, totalChunks);
        task?.completedBytes = (completedChunks * chunkSize).clamp(
          0,
          originalSize,
        );
        index += 1;
        notifyListeners();
      }
    }

    task?.status = '保存文件记录';
    notifyListeners();
    final payload = await _cryptoService.encryptJson({
      'name': name,
      'mimeType': mimeType,
      'originalSize': originalSize,
      'fileKey': base64Encode(fileKey),
      'chunkCipherSizes': chunkCipherSizes,
    }, vaultKey);

    final completed = await _apiClient.completeChunkedFileUpload(
      baseUrl: _baseUrl,
      token: token,
      uploadId: uploadId,
      payload: payload,
    );
    final file = StoredFileRecord.fromJson(
      completed['file'] as Map<String, dynamic>? ?? const {},
    );
    return DecryptedFileRecord(
      id: file.id,
      name: name,
      mimeType: mimeType,
      originalSize: originalSize,
      fileKey: base64Encode(fileKey),
      cipherSize: file.cipherSize,
      version: file.version,
      chunkCipherSizes: chunkCipherSizes,
      folderId: file.folderId,
    );
  }

  Future<void> updateEncryptedFile({
    required DecryptedFileRecord existing,
    required String name,
    String? folderId,
  }) async {
    if (_token == null || _vaultKey == null) {
      return;
    }

    await _runBusy(() async {
      final payload = await _cryptoService.encryptJson({
        'name': name,
        'mimeType': existing.mimeType,
        'originalSize': existing.originalSize,
        'fileKey': existing.fileKey,
      }, _vaultKey!);

      await _apiClient.updateFileMetadata(
        baseUrl: _baseUrl,
        token: _token!,
        fileId: existing.id,
        payload: payload,
        version: existing.version + 1,
        folderId: parentFolderIDOrNull(folderId),
      );
      await _loadVaultSnapshot();
      _statusMessage = '文件信息已更新。';
    });
  }
}
