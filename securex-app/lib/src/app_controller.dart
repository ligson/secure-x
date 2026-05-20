import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'crypto_service.dart';
import 'models.dart';

class AppController extends ChangeNotifier {
  AppController({
    required ApiClient apiClient,
    required CryptoService cryptoService,
    required FlutterSecureStorage secureStorage,
  }) : _apiClient = apiClient,
       _cryptoService = cryptoService,
       _secureStorage = secureStorage;

  static const _baseUrlKey = 'securex.baseUrl';
  static const _tokenKey = 'securex.token';

  final ApiClient _apiClient;
  final CryptoService _cryptoService;
  final FlutterSecureStorage _secureStorage;

  bool _initialized = false;
  bool _busy = false;
  String? _statusMessage;
  String _baseUrl = 'http://127.0.0.1:8080';
  String? _token;
  UserProfile? _user;
  Uint8List? _vaultKey;
  List<DecryptedFolder> _folders = [];
  List<DecryptedLoginItem> _items = [];
  List<DecryptedFileRecord> _files = [];

  bool get initialized => _initialized;
  bool get busy => _busy;
  String get baseUrl => _baseUrl;
  String? get token => _token;
  UserProfile? get user => _user;
  bool get authenticated => _token != null;
  bool get unlocked => _vaultKey != null;
  String? get statusMessage => _statusMessage;
  List<DecryptedFolder> get folders => List.unmodifiable(_folders);
  List<DecryptedLoginItem> get items => List.unmodifiable(_items);
  List<DecryptedFileRecord> get files => List.unmodifiable(_files);

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString(_baseUrlKey) ?? _baseUrl;
    _token = await _secureStorage.read(key: _tokenKey);

    if (_token != null) {
      try {
        _user = await _apiClient.me(baseUrl: _baseUrl, token: _token!);
      } catch (_) {
        await logout();
      }
    }

    _initialized = true;
    notifyListeners();
  }

  Future<void> saveBaseUrl(String value) async {
    _baseUrl = _normalizeBaseUrl(value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseUrlKey, _baseUrl);
    notifyListeners();
  }

  Future<void> register({
    required String username,
    required String email,
    required String authPassword,
    required String masterPassword,
  }) async {
    await _runBusy(() async {
      final bundle = await _cryptoService.createRegisterBundle(masterPassword);
      final response = await _apiClient.register(
        baseUrl: _baseUrl,
        username: username,
        email: email,
        password: authPassword,
        kdfAlgorithm: bundle.kdfAlgorithm,
        masterKeySalt: bundle.masterKeySalt,
        masterKeyIterations: bundle.masterKeyIterations,
        wrappedVaultKey: bundle.wrappedVaultKey,
      );

      _token = response['token'] as String;
      _user = UserProfile.fromJson(response['user'] as Map<String, dynamic>);
      _vaultKey = bundle.vaultKeyBytes;
      await _secureStorage.write(key: _tokenKey, value: _token);
      await _loadVaultSnapshot();
      _statusMessage = '注册成功，保险库已经解锁。';
    });
  }

  Future<void> login({
    required String identifier,
    required String authPassword,
    required String masterPassword,
  }) async {
    await _runBusy(() async {
      final response = await _apiClient.login(
        baseUrl: _baseUrl,
        identifier: identifier,
        password: authPassword,
      );

      _token = response['token'] as String;
      _user = UserProfile.fromJson(response['user'] as Map<String, dynamic>);
      _vaultKey = await _cryptoService.unwrapVaultKey(
        wrappedVaultKey: _user!.wrappedVaultKey,
        masterPassword: masterPassword,
        saltBase64: _user!.masterKeySalt,
        iterations: _user!.masterKeyIterations,
      );
      await _secureStorage.write(key: _tokenKey, value: _token);
      await _loadVaultSnapshot();
      _statusMessage = '登录成功，保险库已经同步。';
    });
  }

  Future<void> unlock(String masterPassword) async {
    if (_user == null) {
      throw Exception('missing user context');
    }

    await _runBusy(() async {
      _vaultKey = await _cryptoService.unwrapVaultKey(
        wrappedVaultKey: _user!.wrappedVaultKey,
        masterPassword: masterPassword,
        saltBase64: _user!.masterKeySalt,
        iterations: _user!.masterKeyIterations,
      );
      await _loadVaultSnapshot();
      _statusMessage = '保险库已解锁。';
    });
  }

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
      _statusMessage = existing == null ? '文件夹已创建。' : '文件夹已更新。';
    });
  }

  Future<void> createLoginItem({
    required String title,
    required String username,
    required String password,
    required String url,
    required String note,
    String? folderId,
  }) async {
    await upsertLoginItem(
      title: title,
      username: username,
      password: password,
      url: url,
      note: note,
      folderId: folderId,
    );
  }

  Future<void> upsertLoginItem({
    required String title,
    required String username,
    required String password,
    required String url,
    required String note,
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

  Future<void> uploadFile({String? folderId}) async {
    if (_token == null || _vaultKey == null) {
      return;
    }

    final result = await FilePicker.platform.pickFiles(withData: true);
    final pickedFile = result?.files.single;
    if (pickedFile == null) {
      return;
    }

    final bytes = await _pickBytes(pickedFile);
    if (bytes == null) {
      throw Exception('无法读取文件内容');
    }

    await _runBusy(() async {
      final fileKey = _cryptoService.randomKey();
      final cipherBytes = await _cryptoService.encryptBinary(bytes, fileKey);
      final payload = await _cryptoService.encryptJson({
        'name': pickedFile.name,
        'mimeType': pickedFile.extension ?? 'application/octet-stream',
        'originalSize': bytes.length,
        'fileKey': base64Encode(fileKey),
      }, _vaultKey!);

      await _apiClient.uploadEncryptedFile(
        baseUrl: _baseUrl,
        token: _token!,
        payload: payload,
        cipherBytes: cipherBytes,
        version: 1,
        folderId: parentFolderIDOrNull(folderId),
      );
      await _loadVaultSnapshot();
      _statusMessage = '加密文件已上传。';
    });
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
      final clearBytes = await _cryptoService.decryptBinary(
        encryptedBytes,
        Uint8List.fromList(base64Decode(file.fileKey)),
      );

      final directory = await getApplicationDocumentsDirectory();
      final output = File('${directory.path}/${file.name}');
      await output.writeAsBytes(clearBytes, flush: true);
      _statusMessage = '文件已解密到 ${output.path}';
      return output.path;
    });
  }

  String generatePassword() => _cryptoService.generatePassword();

  Future<void> lock() async {
    _vaultKey = null;
    _folders = [];
    _items = [];
    _files = [];
    notifyListeners();
  }

  Future<void> logout() async {
    _token = null;
    _user = null;
    _vaultKey = null;
    _folders = [];
    _items = [];
    _files = [];
    await _secureStorage.delete(key: _tokenKey);
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

  Future<Uint8List?> _pickBytes(PlatformFile file) async {
    if (file.bytes != null) {
      return Uint8List.fromList(file.bytes!);
    }
    if (file.path == null) {
      return null;
    }

    return Uint8List.fromList(await File(file.path!).readAsBytes());
  }

  Future<void> _loadVaultSnapshot() async {
    final snapshot = await _apiClient.exportVault(
      baseUrl: _baseUrl,
      token: _token!,
    );

    final folderRecords = (snapshot['folders'] as List<dynamic>? ?? [])
        .map((entry) => FolderRecord.fromJson(entry as Map<String, dynamic>))
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
          folderId: file.folderId,
        );
      }),
    );
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
        return data['message'] as String;
      }
      return error.message ?? '网络请求失败';
    }
    return error.toString();
  }
}
