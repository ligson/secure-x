// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'app_controller.dart';

extension AppControllerInternalHelpers on AppController {
  Future<void> _runBusy(Future<void> Function() action) async {
    _busy = true;
    _statusMessage = null;
    notifyListeners();

    try {
      await action();
    } catch (error) {
      _statusMessage = _friendlyError(error);
      rethrow;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<T> _runBusyWithResult<T>(Future<T> Function() action) async {
    _busy = true;
    _statusMessage = null;
    notifyListeners();

    try {
      return await action();
    } catch (error) {
      _statusMessage = _friendlyError(error);
      rethrow;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Stream<Uint8List> _readFileChunks(File file, int chunkSize) async* {
    final reader = await file.open();
    try {
      while (true) {
        final bytes = await reader.read(chunkSize);
        if (bytes.isEmpty) {
          break;
        }
        yield Uint8List.fromList(bytes);
      }
    } finally {
      await reader.close();
    }
  }

  Future<void> _loadVaultSnapshot() async {
    final snapshot = await _apiClient.exportVault(
      baseUrl: _baseUrl,
      token: _token!,
    );

    final folderRecords = (snapshot['folders'] as List<dynamic>? ?? [])
        .map((entry) => FolderRecord.fromJson(entry as Map<String, dynamic>))
        .toList();
    final fileFolderRecords = (snapshot['fileFolders'] as List<dynamic>? ?? [])
        .map(
          (entry) => FileFolderRecord.fromJson(entry as Map<String, dynamic>),
        )
        .toList();
    final itemRecords = (snapshot['items'] as List<dynamic>? ?? [])
        .map((entry) => VaultItemRecord.fromJson(entry as Map<String, dynamic>))
        .toList();
    final fileRecords = (snapshot['files'] as List<dynamic>? ?? [])
        .map(
          (entry) => StoredFileRecord.fromJson(entry as Map<String, dynamic>),
        )
        .toList();

    _folders = await Future.wait(
      folderRecords.map((folder) async {
        final data = await _cryptoService.decryptJson(
          folder.payload,
          _vaultKey!,
        );
        return DecryptedFolder(
          id: folder.id,
          name: data['name'] as String,
          version: folder.version,
          parentFolderId: folder.parentFolderId,
        );
      }),
    );

    _fileFolders = await Future.wait(
      fileFolderRecords.map((folder) async {
        final data = await _cryptoService.decryptJson(
          folder.payload,
          _vaultKey!,
        );
        return DecryptedFileFolder(
          id: folder.id,
          name: data['name'] as String,
          version: folder.version,
          parentFolderId: folder.parentFolderId,
        );
      }),
    );

    _items = (await Future.wait(
      itemRecords.where((item) => item.kind == 'login').map((item) async {
        final data = await _cryptoService.decryptJson(item.payload, _vaultKey!);
        return DecryptedLoginItem(
          id: item.id,
          title: data['title'] as String? ?? '',
          username: data['username'] as String? ?? '',
          password: data['password'] as String? ?? '',
          url: data['url'] as String? ?? '',
          note: data['note'] as String? ?? '',
          version: item.version,
          folderId: item.folderId,
        );
      }),
    )).toList();

    _files = await Future.wait(
      fileRecords.map((file) async {
        final data = await _cryptoService.decryptJson(file.payload, _vaultKey!);
        return DecryptedFileRecord(
          id: file.id,
          name: data['name'] as String,
          mimeType: data['mimeType'] as String? ?? 'application/octet-stream',
          originalSize: (data['originalSize'] as num).toInt(),
          fileKey: data['fileKey'] as String,
          cipherSize: file.cipherSize,
          version: file.version,
          chunkCipherSizes: (data['chunkCipherSizes'] as List<dynamic>? ?? [])
              .map((value) => (value as num).toInt())
              .toList(),
          folderId: file.folderId,
        );
      }),
    );
  }

  bool get _supportsDebugTokenFallback => !kReleaseMode && Platform.isMacOS;

  Future<String?> _readPersistedToken(SharedPreferences? prefs) async {
    try {
      final secureToken = await _secureStorage.read(
        key: AppController._tokenKey,
      );
      if (secureToken != null && secureToken.isNotEmpty) {
        return secureToken;
      }
    } catch (error) {
      debugPrint('Secure token read failed: $error');
    }

    if (_supportsDebugTokenFallback) {
      final resolvedPrefs = prefs ?? await SharedPreferences.getInstance();
      return resolvedPrefs.getString(AppController._debugTokenFallbackKey);
    }

    return null;
  }

  Future<bool> _persistToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      await _secureStorage.write(key: AppController._tokenKey, value: token);
      if (_supportsDebugTokenFallback) {
        await prefs.remove(AppController._debugTokenFallbackKey);
      }
      return true;
    } catch (error) {
      debugPrint('Secure token write failed: $error');
      if (_supportsDebugTokenFallback) {
        await prefs.setString(AppController._debugTokenFallbackKey, token);
        return true;
      }
      return false;
    }
  }

  Future<void> _clearPersistedToken() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      await _secureStorage.delete(key: AppController._tokenKey);
    } catch (error) {
      debugPrint('Secure token delete failed: $error');
    }
    if (_supportsDebugTokenFallback) {
      await prefs.remove(AppController._debugTokenFallbackKey);
    }
  }

  String _normalizeBaseUrl(String value) {
    final normalized = value.trim();
    if (normalized.endsWith('/')) {
      return normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  String? parentFolderIDOrNull(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  String _friendlyError(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map<String, dynamic> && data['message'] is String) {
        final message = (data['message'] as String).trim();
        if (message.isNotEmpty) {
          return _localizedServerMessage(message);
        }
      }
      if (error.type == DioExceptionType.connectionError) {
        return '无法连接到 $_baseUrl，请确认后端已启动完成，并检查该地址的 /healthz 是否可访问。';
      }
      if (error.type == DioExceptionType.connectionTimeout) {
        return '连接 $_baseUrl 超时，请确认后端正在运行。';
      }
      if (error.type == DioExceptionType.receiveTimeout) {
        return '后端响应超时，请稍后重试。';
      }
      if (error.type == DioExceptionType.badCertificate) {
        return '后端证书校验失败，请检查后端地址或证书配置。';
      }
      if (error.response != null) {
        return '请求失败，请稍后重试。';
      }
      return '网络请求失败，请检查后端地址和网络连接。';
    }
    if (error is SecretBoxAuthenticationError ||
        error is FormatException ||
        error is TypeError) {
      return '解锁密码不正确，无法解锁保险库。';
    }
    if (error is PlatformException) {
      final message = error.message ?? error.details?.toString() ?? '';
      if (message.contains('required entitlement isn\'t present') ||
          error.code.contains('-34018')) {
        return 'macOS 安全存储权限暂未就绪，当前会话仍可使用；如果重启后仍复现，请重新启动应用。';
      }
      return '本地平台能力调用失败，请稍后重试。';
    }
    return '操作失败，请稍后重试。';
  }

  String _localizedServerMessage(String message) {
    switch (message) {
      case 'invalid credentials':
        return '用户名、邮箱或登录密码不正确';
      case 'user already exists':
        return '用户名或邮箱已被使用';
      case 'missing authorization header':
        return '请先登录';
      case 'invalid authorization header':
        return '登录凭证格式不正确';
      case 'invalid token':
        return '登录状态已失效，请重新登录';
      default:
        return message;
    }
  }
}
