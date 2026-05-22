import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'app_logger.dart';
import 'crypto_service.dart';
import 'models.dart';
import 'realtime_chat_service.dart';

part 'app_controller_auth.dart';
part 'app_controller_vault.dart';
part 'app_controller_uploads.dart';
part 'app_controller_records.dart';
part 'app_controller_friends.dart';
part 'app_controller_chat.dart';
part 'app_controller_session.dart';
part 'app_controller_helpers.dart';

class FileUploadTask {
  FileUploadTask({
    required this.id,
    required this.name,
    required this.totalBytes,
    this.completedBytes = 0,
    this.status = '准备上传',
    this.done = false,
    this.failed = false,
  });

  final String id;
  final String name;
  final int totalBytes;
  int completedBytes;
  String status;
  bool done;
  bool failed;

  double get progress {
    if (totalBytes <= 0) {
      return done ? 1 : 0;
    }
    return (completedBytes / totalBytes).clamp(0, 1);
  }
}

class AppController extends ChangeNotifier {
  AppController({
    required ApiClient apiClient,
    required CryptoService cryptoService,
    required FlutterSecureStorage secureStorage,
  }) : _apiClient = apiClient,
       _cryptoService = cryptoService,
       _secureStorage = secureStorage {
    _realtimeChatService.onMessage = _handleRealtimeIncomingMessage;
    _realtimeChatService.onGroupControl = (control) {
      unawaited(_handleRealtimeGroupControl(control));
    };
    _realtimeChatService.onHistoryRequest = (request) {
      unawaited(_handleRealtimeHistoryRequest(request));
    };
    _realtimeChatService.onHistoryResponse = (response) {
      unawaited(_handleRealtimeHistoryResponse(response));
    };
    _realtimeChatService.onDelivered = _markRealtimeMessageDelivered;
    _realtimeChatService.onPeerStatus = _handleRealtimePeerStatus;
    _realtimeChatService.onFriendshipUpdated = _handleRealtimeFriendshipUpdated;
  }

  static const _baseUrlKey = 'baseUrl';
  static const _tokenKey = 'token';
  static const _debugTokenFallbackKey = 'debug.token';
  static const _themeIdKey = 'themeId';
  static const _compileTimeDevInstance = String.fromEnvironment(
    'SECUREX_DEV_INSTANCE',
    defaultValue: 'default',
  );

  final ApiClient _apiClient;
  final CryptoService _cryptoService;
  final FlutterSecureStorage _secureStorage;
  final RealtimeChatService _realtimeChatService = RealtimeChatService();
  final String _storageNamespace = _resolveStorageNamespace();
  final String _devDataDir = Platform.environment['SECUREX_DEV_DATA_DIR'] ?? '';

  bool _initialized = false;
  bool _busy = false;
  String? _statusMessage;
  String _baseUrl = 'http://127.0.0.1:8080';
  String _themeId = 'dawn';
  String? _token;
  UserProfile? _user;
  Uint8List? _vaultKey;
  List<DecryptedFolder> _folders = [];
  List<DecryptedFileFolder> _fileFolders = [];
  List<DecryptedLoginItem> _items = [];
  List<DecryptedFileRecord> _files = [];
  List<PublicUser> _friends = [];
  List<FriendRequestRecord> _incomingFriendRequests = [];
  List<FriendRequestRecord> _outgoingFriendRequests = [];
  List<ChatConversation> _chatConversations = [];
  final Map<String, bool> _chatFriendOnline = {};
  final Set<String> _historyRequestedPeerIds = {};
  RealtimeConfig? _realtimeConfig;
  final List<FileUploadTask> _uploadTasks = [];

  bool get initialized => _initialized;
  bool get busy => _busy;
  String get baseUrl => _baseUrl;
  String? get token => _token;
  UserProfile? get user => _user;
  bool get authenticated => _token != null;
  bool get unlocked => _vaultKey != null;
  String? get statusMessage => _statusMessage;
  String get themeId => _themeId;
  List<DecryptedFolder> get folders => List.unmodifiable(_folders);
  List<DecryptedFileFolder> get fileFolders => List.unmodifiable(_fileFolders);
  List<DecryptedLoginItem> get items => List.unmodifiable(_items);
  List<DecryptedFileRecord> get files => List.unmodifiable(_files);
  List<PublicUser> get friends => List.unmodifiable(_friends);
  List<FriendRequestRecord> get incomingFriendRequests =>
      List.unmodifiable(_incomingFriendRequests);
  List<FriendRequestRecord> get outgoingFriendRequests =>
      List.unmodifiable(_outgoingFriendRequests);
  List<ChatConversation> get chatConversations =>
      List.unmodifiable(_chatConversations);
  RealtimeConfig? get realtimeConfig => _realtimeConfig;
  List<FileUploadTask> get uploadTasks => List.unmodifiable(_uploadTasks);

  String get devInstance => _storageNamespace;

  bool isChatFriendOnline(String friendId) =>
      _chatFriendOnline[friendId] == true;

  void dismissUploadTask(String id) {
    _uploadTasks.removeWhere(
      (task) => task.id == id && (task.done || task.failed),
    );
    notifyListeners();
  }

  static String _resolveStorageNamespace() {
    final runtimeInstance = Platform.environment['SECUREX_DEV_INSTANCE'] ?? '';
    final value = runtimeInstance.trim().isNotEmpty
        ? runtimeInstance.trim()
        : _compileTimeDevInstance.trim();
    final safe = value.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]+'), '-');
    return safe.isEmpty ? 'default' : safe;
  }
}
