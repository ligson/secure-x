// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'app_controller.dart';

extension AppControllerRuntimeActions on AppController {
  Future<void> handleAppResumed() async {
    await _queueRealtimeResume(
      reason: '应用已回到前台，正在恢复实时加密通道',
      refreshConfig: false,
      forceReconnect: true,
    );
  }

  Future<void> handleNetworkReachable() async {
    await _queueRealtimeResume(
      reason: '网络已恢复，正在重建实时通道',
      refreshConfig: true,
      forceReconnect: true,
    );
  }

  void _handleRealtimeSignalingState(String status) {
    appLog('实时信令状态变化：$status');
    switch (status) {
      case 'connected':
        _historyRequestedPeerIds.clear();
        unawaited(
          _queueRealtimeResume(
            reason: '实时信令已恢复连接',
            refreshConfig: false,
            forceReconnect: false,
          ),
        );
        return;
      case 'reconnecting':
        _statusMessage = '网络切换中，正在自动恢复实时加密通道。';
        notifyListeners();
        return;
      case 'disconnected':
        if (_chatFriendOnline.isNotEmpty) {
          _chatFriendOnline.updateAll((key, value) => false);
        }
        _statusMessage = '实时通道暂时断开，已切换到自动重连。';
        notifyListeners();
        return;
      default:
        return;
    }
  }

  Future<void> _queueRealtimeResume({
    required String reason,
    required bool refreshConfig,
    required bool forceReconnect,
  }) {
    _realtimeResumeTask = _realtimeResumeTask.then((_) async {
      if (!_initialized ||
          _token == null ||
          _user == null ||
          _vaultKey == null) {
        return;
      }

      try {
        if (refreshConfig || _realtimeConfig == null) {
          _realtimeConfig = await _apiClient.realtimeConfig(
            baseUrl: _baseUrl,
            token: _token!,
          );
        }
        await _connectRealtimeChat(forceReconnect: forceReconnect);
        _historyRequestedPeerIds.clear();
        await _openRealtimePeersForHistorySync();
        _statusMessage = reason;
        notifyListeners();
      } catch (error) {
        appLog('移动网络恢复实时通道失败', error);
      }
    });
    return _realtimeResumeTask;
  }
}
