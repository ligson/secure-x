// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'app_controller.dart';

extension AppControllerAuthActions on AppController {
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl =
        prefs.getString(_storageKey(AppController._baseUrlKey)) ?? _baseUrl;
    _themeId =
        prefs.getString(_storageKey(AppController._themeIdKey)) ?? _themeId;
    _token = await _readPersistedToken(prefs);

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
    await prefs.setString(_storageKey(AppController._baseUrlKey), _baseUrl);
    notifyListeners();
  }

  Future<void> saveThemeId(String value) async {
    _themeId = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey(AppController._themeIdKey), _themeId);
    notifyListeners();
  }

  Future<void> register({
    required String username,
    required String email,
    required String authPassword,
    required String unlockPassword,
  }) async {
    await _runBusy(() async {
      final bundle = await _cryptoService.createRegisterBundle(unlockPassword);
      final response = await _apiClient.register(
        baseUrl: _baseUrl,
        username: username.trim(),
        email: email.trim(),
        password: authPassword,
        kdfAlgorithm: bundle.kdfAlgorithm,
        masterKeySalt: bundle.masterKeySalt,
        masterKeyIterations: bundle.masterKeyIterations,
        wrappedVaultKey: bundle.wrappedVaultKey,
      );

      _token = response['token'] as String;
      _user = UserProfile.fromJson(response['user'] as Map<String, dynamic>);
      _vaultKey = bundle.vaultKeyBytes;
      final tokenPersisted = await _persistToken(_token!);
      await _loadVaultSnapshot();
      await _loadFriendsSnapshot();
      await _loadChatSnapshot();
      _statusMessage = tokenPersisted
          ? '注册成功，保险库已经解锁。'
          : '注册成功，当前会话已解锁；本机安全存储暂不可用，重启应用后需要重新登录。';
    });
  }

  Future<void> login({
    required String identifier,
    required String authPassword,
  }) async {
    await _runBusy(() async {
      final response = await _apiClient.login(
        baseUrl: _baseUrl,
        identifier: identifier.trim(),
        password: authPassword,
      );

      _token = response['token'] as String;
      _user = UserProfile.fromJson(response['user'] as Map<String, dynamic>);
      _vaultKey = null;
      final tokenPersisted = await _persistToken(_token!);
      _statusMessage = tokenPersisted
          ? '登录成功，请输入解锁密码。'
          : '登录成功，请输入解锁密码；本机安全存储暂不可用，重启应用后需要重新登录。';
    });
  }

  Future<void> unlock(String unlockPassword) async {
    if (_user == null) {
      throw Exception('missing user context');
    }

    await _runBusy(() async {
      _vaultKey = await _cryptoService.unwrapVaultKey(
        wrappedVaultKey: _user!.wrappedVaultKey,
        unlockPassword: unlockPassword,
        saltBase64: _user!.masterKeySalt,
        iterations: _user!.masterKeyIterations,
      );
      await _loadVaultSnapshot();
      await _loadFriendsSnapshot();
      await _loadChatSnapshot();
      _statusMessage = '保险库已解锁。';
    });
  }

  Future<void> changeLoginPassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (_token == null) {
      return;
    }

    await _runBusy(() async {
      await _apiClient.changePassword(
        baseUrl: _baseUrl,
        token: _token!,
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      _statusMessage = '登录密码已修改。';
    });
  }

  Future<void> changeUnlockPassword({
    required String currentUnlockPassword,
    required String newUnlockPassword,
  }) async {
    if (_token == null || _user == null) {
      return;
    }

    await _runBusy(() async {
      final vaultKey = await _cryptoService.unwrapVaultKey(
        wrappedVaultKey: _user!.wrappedVaultKey,
        unlockPassword: currentUnlockPassword,
        saltBase64: _user!.masterKeySalt,
        iterations: _user!.masterKeyIterations,
      );

      if (_vaultKey != null && !listEquals(_vaultKey, vaultKey)) {
        throw const FormatException('unlock password mismatch');
      }

      final bundle = await _cryptoService.rewrapVaultKey(
        vaultKeyBytes: vaultKey,
        unlockPassword: newUnlockPassword,
      );

      _user = await _apiClient.changeUnlockPassword(
        baseUrl: _baseUrl,
        token: _token!,
        kdfAlgorithm: bundle.kdfAlgorithm,
        masterKeySalt: bundle.masterKeySalt,
        masterKeyIterations: bundle.masterKeyIterations,
        wrappedVaultKey: bundle.wrappedVaultKey,
      );
      _vaultKey = vaultKey;
      _statusMessage = '解锁密码已修改。';
    });
  }
}
