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
import 'chat_protocol.dart';
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
part 'app_controller_runtime.dart';
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

enum SecureXCallPhase {
  idle,
  outgoing,
  incoming,
  accepting,
  joining,
  connected,
  reconnecting,
  ended,
  failed,
}

enum IncomingCallHandling { open, duplicate, handledByActiveCall, rejectBusy }

class QueuedCallSignal {
  const QueuedCallSignal({required this.sequence, required this.signal});

  final int sequence;
  final RealtimeCallSignal signal;
}

class QueuedGroupCallSignal {
  const QueuedGroupCallSignal({required this.sequence, required this.signal});

  final int sequence;
  final GroupCallSignal signal;
}

class GroupCallSignal {
  const GroupCallSignal({
    required this.senderUserId,
    required this.groupId,
    required this.groupName,
    required this.callId,
    required this.action,
    required this.media,
    this.payload = const {},
  });

  final String senderUserId;
  final String groupId;
  final String groupName;
  final String callId;
  final String action;
  final String media;
  final Map<String, dynamic> payload;
}

class ActiveCallSession {
  const ActiveCallSession({
    required this.friendId,
    required this.callId,
    required this.media,
    required this.incoming,
    required this.phase,
    required this.diagnosticId,
    required this.startedAt,
    this.connectedAt,
    this.updatedAt,
  });

  final String friendId;
  final String callId;
  final String media;
  final bool incoming;
  final SecureXCallPhase phase;
  final String diagnosticId;
  final DateTime startedAt;
  final DateTime? connectedAt;
  final DateTime? updatedAt;

  bool get active =>
      phase != SecureXCallPhase.ended && phase != SecureXCallPhase.failed;

  ActiveCallSession copyWith({
    String? friendId,
    String? callId,
    String? media,
    bool? incoming,
    SecureXCallPhase? phase,
    String? diagnosticId,
    DateTime? startedAt,
    DateTime? connectedAt,
    bool clearConnectedAt = false,
  }) {
    return ActiveCallSession(
      friendId: friendId ?? this.friendId,
      callId: callId ?? this.callId,
      media: media ?? this.media,
      incoming: incoming ?? this.incoming,
      phase: phase ?? this.phase,
      diagnosticId: diagnosticId ?? this.diagnosticId,
      startedAt: startedAt ?? this.startedAt,
      connectedAt: clearConnectedAt ? null : connectedAt ?? this.connectedAt,
      updatedAt: DateTime.now(),
    );
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
    _realtimeChatService.onPendingChat = (recipientDeviceId, senderUserId) {
      unawaited(
        _pullPendingChatMessages(
          expectedDeviceId: recipientDeviceId,
          senderUserId: senderUserId,
        ),
      );
    };
    _realtimeChatService.onQueuedEnvelope = (envelope) {
      unawaited(_handleRealtimeQueuedEnvelope(envelope));
    };
    _realtimeChatService.onPeerStatus = _handleRealtimePeerStatus;
    _realtimeChatService.onFriendshipUpdated = _handleRealtimeFriendshipUpdated;
    _realtimeChatService.onSignalingState = _handleRealtimeSignalingState;
    _realtimeChatService.onCallSignal = _handleRealtimeCallSignal;
  }

  static const _baseUrlKey = 'baseUrl';
  static const _tokenKey = 'token';
  static const _debugTokenFallbackKey = 'debug.token';
  static const _themeIdKey = 'themeId';
  static const _chatDeviceIdKey = 'chat.device.id';
  static const _chatIdentitySeedKey = 'chat.identity.seed';
  static const _debugSecretFallbackPrefix = 'debug.secret';
  static const _compileTimeDevInstance = String.fromEnvironment(
    'SECUREX_DEV_INSTANCE',
    defaultValue: 'default',
  );

  final ApiClient _apiClient;
  final CryptoService _cryptoService;
  final FlutterSecureStorage _secureStorage;
  final ChatProtocol _chatProtocol = SecureXChatProtocolV1();
  final RealtimeChatService _realtimeChatService = RealtimeChatService();
  final ValueNotifier<int> _appShellRevision = ValueNotifier(0);
  final ValueNotifier<int> _themeRevision = ValueNotifier(0);
  final ValueNotifier<int> _chatRevision = ValueNotifier(0);
  final ValueNotifier<int> _callRevision = ValueNotifier(0);
  final ValueNotifier<int> _friendsRevision = ValueNotifier(0);
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
  Map<String, String> _friendRemarks = {};
  List<FriendRequestRecord> _incomingFriendRequests = [];
  List<FriendRequestRecord> _outgoingFriendRequests = [];
  List<ChatConversation> _chatConversations = [];
  RealtimeCallSignal? _lastCallSignal;
  final List<QueuedCallSignal> _callSignals = [];
  final List<QueuedGroupCallSignal> _groupCallSignals = [];
  int _callSignalSequence = 0;
  int _groupCallSignalSequence = 0;
  ActiveCallSession? _activeCallSession;
  ChatIdentityBundle? _chatIdentity;
  final Map<String, bool> _chatFriendOnline = {};
  final Set<String> _activeConversationIds = {};
  final Set<String> _loadedChatConversationIds = {};
  final Set<String> _loadingChatConversationIds = {};
  final Set<String> _historyRequestedPeerIds = {};
  RealtimeConfig? _realtimeConfig;
  final List<FileUploadTask> _uploadTasks = [];
  Future<void> _realtimeResumeTask = Future.value();
  Future<void> _realtimeConnectTask = Future.value();
  Future<void> _chatRefreshTask = Future.value();
  Future<void> _friendsRefreshTask = Future.value();
  Timer? _pendingChatPollTimer;
  Timer? _chatArchiveSyncTimer;
  int _latestRealtimeResumeRequestId = 0;
  DateTime? _lastRealtimeForceReconnectAt;
  DateTime? _lastChatDeviceRegisteredAt;
  String? _lastRegisteredChatDeviceId;
  String? _lastRegisteredChatPublicKey;
  String? _pendingChatArchivePayload;
  int _pendingChatArchiveVersion = 0;
  final Map<String, int> _pendingChatConversationVersions = {};
  final Set<String> _pendingDeletedChatConversationIds = {};
  Future<void> _chatArchiveSyncTask = Future.value();
  Future<void> _pendingChatSyncTask = Future.value();
  final Map<String, Future<void>> _chatConversationLoadTasks = {};
  final Map<String, Future<Uint8List>> _chatAttachmentBytesCache = {};
  final Map<String, Uint8List> _chatAttachmentPlainBytesCache = {};

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
  String friendRemarkName(String friendId) => _friendRemarks[friendId] ?? '';
  List<FriendRequestRecord> get incomingFriendRequests =>
      List.unmodifiable(_incomingFriendRequests);
  List<FriendRequestRecord> get outgoingFriendRequests =>
      List.unmodifiable(_outgoingFriendRequests);
  List<ChatConversation> get chatConversations =>
      List.unmodifiable(_chatConversations);
  RealtimeConfig? get realtimeConfig => _realtimeConfig;
  String get currentChatDeviceId => _chatIdentity?.deviceId ?? '';
  List<FileUploadTask> get uploadTasks => List.unmodifiable(_uploadTasks);
  Listenable get appShellListenable => _appShellRevision;
  Listenable get themeListenable => _themeRevision;
  Listenable get chatListenable => _chatRevision;
  Listenable get callListenable => _callRevision;
  Listenable get friendsListenable => _friendsRevision;
  RealtimeCallSignal? get lastCallSignal => _lastCallSignal;
  int get latestCallSignalSequence => _callSignalSequence;
  int get latestGroupCallSignalSequence => _groupCallSignalSequence;
  ActiveCallSession? get activeCallSession => _activeCallSession;
  bool get hasActiveCall => _activeCallSession?.active == true;

  String get devInstance => _storageNamespace;

  bool isChatFriendOnline(String friendId) =>
      _chatFriendOnline[friendId] == true;

  bool isChatConversationLoading(String conversationId) =>
      _loadingChatConversationIds.contains(conversationId);

  List<QueuedCallSignal> callSignalsAfter(int sequence) {
    return List.unmodifiable(
      _callSignals.where((entry) => entry.sequence > sequence),
    );
  }

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

  void _bumpRevision(ValueNotifier<int> revision) {
    revision.value = revision.value + 1;
  }

  void _markAppShellChanged() => _bumpRevision(_appShellRevision);

  void _markThemeChanged() => _bumpRevision(_themeRevision);

  void _markChatChanged() => _bumpRevision(_chatRevision);

  void _markCallChanged() => _bumpRevision(_callRevision);

  void _markFriendsChanged() => _bumpRevision(_friendsRevision);

  String callDiagnosticId(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return '-';
    }
    if (normalized.length <= 12) {
      return normalized;
    }
    return '${normalized.substring(0, 4)}...${normalized.substring(normalized.length - 6)}';
  }

  bool canStartCall() {
    final session = _activeCallSession;
    return session == null || !session.active;
  }

  bool reserveOutgoingCall({
    required PublicUser friend,
    required String callId,
    required String media,
  }) {
    final session = _activeCallSession;
    if (session != null &&
        session.active &&
        (session.friendId != friend.id || session.callId != callId)) {
      _statusMessage = '当前已有通话，请先结束后再发起新的通话。';
      notifyListeners();
      return false;
    }
    _activeCallSession = ActiveCallSession(
      friendId: friend.id,
      callId: callId,
      media: _normalizeCallMediaForState(media),
      incoming: false,
      phase: SecureXCallPhase.outgoing,
      diagnosticId: callDiagnosticId(callId),
      startedAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    _markCallChanged();
    return true;
  }

  bool reserveOutgoingGroupCall({
    required ChatConversation conversation,
    required String callId,
    required String media,
  }) {
    final session = _activeCallSession;
    final groupSessionId = _groupCallSessionId(conversation.id);
    if (session != null &&
        session.active &&
        (session.friendId != groupSessionId || session.callId != callId)) {
      _statusMessage = '当前已有通话，请先结束后再发起新的通话。';
      notifyListeners();
      return false;
    }
    _activeCallSession = ActiveCallSession(
      friendId: groupSessionId,
      callId: callId,
      media: _normalizeCallMediaForState(media),
      incoming: false,
      phase: SecureXCallPhase.outgoing,
      diagnosticId: callDiagnosticId(callId),
      startedAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    _markCallChanged();
    return true;
  }

  bool reserveGroupCallJoin({
    required ChatConversation conversation,
    required String callId,
    required String media,
  }) {
    final session = _activeCallSession;
    final groupSessionId = _groupCallSessionId(conversation.id);
    if (session != null &&
        session.active &&
        (session.friendId != groupSessionId || session.callId != callId)) {
      _statusMessage = '当前已有通话，请先结束后再加入群通话。';
      notifyListeners();
      return false;
    }
    _activeCallSession = ActiveCallSession(
      friendId: groupSessionId,
      callId: callId,
      media: _normalizeCallMediaForState(media),
      incoming: true,
      phase: SecureXCallPhase.joining,
      diagnosticId: callDiagnosticId(callId),
      startedAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    _markCallChanged();
    return true;
  }

  IncomingCallHandling prepareIncomingCall(RealtimeCallSignal signal) {
    final session = _activeCallSession;
    if (session != null && session.active) {
      if (session.callId == signal.callId) {
        return IncomingCallHandling.duplicate;
      }
      if (session.friendId == signal.friendId) {
        return IncomingCallHandling.handledByActiveCall;
      }
      return IncomingCallHandling.rejectBusy;
    }
    _activeCallSession = ActiveCallSession(
      friendId: signal.friendId,
      callId: signal.callId,
      media: _normalizeCallMediaForState(signal.media),
      incoming: true,
      phase: SecureXCallPhase.incoming,
      diagnosticId: callDiagnosticId(signal.callId),
      startedAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    _markCallChanged();
    return IncomingCallHandling.open;
  }

  void markCallPhase({
    required String callId,
    required SecureXCallPhase phase,
    DateTime? connectedAt,
    bool clearConnectedAt = false,
  }) {
    final session = _activeCallSession;
    if (session == null || session.callId != callId) {
      return;
    }
    _activeCallSession = session.copyWith(
      phase: phase,
      connectedAt: connectedAt,
      clearConnectedAt: clearConnectedAt,
    );
    _markCallChanged();
  }

  void switchActiveCall({
    required String previousCallId,
    required String callId,
    required String media,
  }) {
    final session = _activeCallSession;
    if (session == null || session.callId != previousCallId) {
      return;
    }
    _activeCallSession = session.copyWith(
      callId: callId,
      media: _normalizeCallMediaForState(media),
      phase: SecureXCallPhase.accepting,
      diagnosticId: callDiagnosticId(callId),
      clearConnectedAt: true,
    );
    _markCallChanged();
  }

  void clearActiveCall(String callId, {bool failed = false}) {
    final session = _activeCallSession;
    if (session == null || session.callId != callId) {
      return;
    }
    _activeCallSession = session.copyWith(
      phase: failed ? SecureXCallPhase.failed : SecureXCallPhase.ended,
    );
    _markCallChanged();
    _activeCallSession = null;
    _markCallChanged();
  }

  String _normalizeCallMediaForState(String media) {
    return media == 'video' ? 'video' : 'audio';
  }

  String _groupCallSessionId(String groupId) => 'group:$groupId';
}
