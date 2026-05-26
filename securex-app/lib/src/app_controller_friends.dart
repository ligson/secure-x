// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'app_controller.dart';

extension AppControllerFriendActions on AppController {
  Future<void> refreshFriends() async {
    if (_token == null) {
      return;
    }

    await _runBusy(() async {
      await _loadFriendsSnapshot();
      _statusMessage = '好友列表已同步。';
    });
  }

  Future<void> refreshFriendsSilently() {
    if (_token == null) {
      return Future.value();
    }

    _friendsRefreshTask = _friendsRefreshTask.then((_) async {
      try {
        await _loadFriendsSnapshot();
        if (_vaultKey != null) {
          await _mergeServerGroupsIntoChatConversations();
        }
        _markFriendsChanged();
        _markChatChanged();
        _statusMessage = '好友列表已刷新。';
      } catch (error) {
        _statusMessage = _friendlyError(error);
      }
      notifyListeners();
    });
    return _friendsRefreshTask;
  }

  void _handleRealtimeFriendshipUpdated(String friendId, String status) {
    if (_token == null) {
      return;
    }
    unawaited(_reloadFriendsAfterRealtimeUpdate(friendId, status));
  }

  Future<void> _reloadFriendsAfterRealtimeUpdate(
    String friendId,
    String status,
  ) async {
    try {
      await _loadFriendsSnapshot();
      if (status == 'accepted') {
        await _ensureRealtimeChatConnected();
        await _refreshRealtimePresenceSnapshot(userIds: [friendId]);
        await _requestHistoryFromPeer(friendId);
        _statusMessage = '好友关系已更新。';
      } else if (status == 'deleted') {
        _chatFriendOnline.remove(friendId);
        _statusMessage = '好友关系已更新。';
      }
      _markFriendsChanged();
      _markChatChanged();
      notifyListeners();
    } catch (error) {
      appLog('实时好友关系刷新失败', error);
    }
  }

  Future<void> sendFriendRequest({
    required String identifier,
    required String message,
  }) async {
    if (_token == null) {
      return;
    }

    await _runBusy(() async {
      await _apiClient.sendFriendRequest(
        baseUrl: _baseUrl,
        token: _token!,
        identifier: identifier.trim(),
        message: message.trim(),
      );
      await _loadFriendsSnapshot();
      _statusMessage = '好友申请已发送。';
    });
  }

  Future<void> acceptFriendRequest(FriendRequestRecord request) async {
    if (_token == null) {
      return;
    }

    await _runBusy(() async {
      await _apiClient.acceptFriendRequest(
        baseUrl: _baseUrl,
        token: _token!,
        requestId: request.id,
      );
      await _loadFriendsSnapshot();
      _statusMessage = '已添加好友。';
    });
  }

  Future<void> rejectFriendRequest(FriendRequestRecord request) async {
    if (_token == null) {
      return;
    }

    await _runBusy(() async {
      await _apiClient.rejectFriendRequest(
        baseUrl: _baseUrl,
        token: _token!,
        requestId: request.id,
      );
      await _loadFriendsSnapshot();
      _statusMessage = '已拒绝好友申请。';
    });
  }

  Future<void> deleteFriend(PublicUser friend) async {
    if (_token == null) {
      return;
    }

    await _runBusy(() async {
      await _apiClient.deleteFriend(
        baseUrl: _baseUrl,
        token: _token!,
        friendId: friend.id,
      );
      await _loadFriendsSnapshot();
      _statusMessage = '好友已删除。';
    });
  }
}
