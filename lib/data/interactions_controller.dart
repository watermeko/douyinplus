import 'package:flutter/foundation.dart';

import 'interaction_repository.dart';

/// Optimistic like / collect state for the feed.
///
/// The initial state of the account is unknown (the feed response does not
/// include `user_digged` / `user_collected`). Toggling is still correct: the
/// write endpoints are idempotent and the local flag tracks the user's taps.
class InteractionsController extends ChangeNotifier {
  InteractionsController({required this.gateway, this.enabled = true});

  final InteractionGateway gateway;
  final bool enabled;

  final Set<String> _liked = <String>{};
  final Set<String> _collected = <String>{};
  final Set<String> _likesInFlight = <String>{};
  final Set<String> _collectsInFlight = <String>{};

  bool isLiked(String awemeId) => _liked.contains(awemeId);

  bool isCollected(String awemeId) => _collected.contains(awemeId);

  int likeDelta(String awemeId) => _liked.contains(awemeId) ? 1 : 0;

  int collectDelta(String awemeId) => _collected.contains(awemeId) ? 1 : 0;

  /// Returns an error message for the caller to toast, or null on success /
  /// when another request for the same video is already in flight.
  Future<String?> toggleLike(String awemeId) async {
    if (!enabled) return '互动功能测试中，暂未开放';
    if (!_likesInFlight.add(awemeId)) return null;

    final wasLiked = _liked.contains(awemeId);
    _setLiked(awemeId, !wasLiked);
    try {
      await gateway.setDigg(awemeId: awemeId, liked: !wasLiked);
      return null;
    } catch (exception) {
      _setLiked(awemeId, wasLiked);
      return _messageOf(exception, '点赞');
    } finally {
      _likesInFlight.remove(awemeId);
    }
  }

  Future<String?> toggleCollect(String awemeId, {int awemeType = 0}) async {
    if (!enabled) return '互动功能测试中，暂未开放';
    if (!_collectsInFlight.add(awemeId)) return null;

    final wasCollected = _collected.contains(awemeId);
    _setCollected(awemeId, !wasCollected);
    try {
      await gateway.setCollect(
        awemeId: awemeId,
        collected: !wasCollected,
        awemeType: awemeType,
      );
      return null;
    } catch (exception) {
      _setCollected(awemeId, wasCollected);
      return _messageOf(exception, '收藏');
    } finally {
      _collectsInFlight.remove(awemeId);
    }
  }

  /// Hydrate state from a future `aweme/detail` response.
  void setLiked(String awemeId, bool value) => _setLiked(awemeId, value);

  void setCollected(String awemeId, bool value) =>
      _setCollected(awemeId, value);

  void _setLiked(String awemeId, bool value) {
    final changed = value ? _liked.add(awemeId) : _liked.remove(awemeId);
    if (changed) notifyListeners();
  }

  void _setCollected(String awemeId, bool value) {
    final changed = value
        ? _collected.add(awemeId)
        : _collected.remove(awemeId);
    if (changed) notifyListeners();
  }

  String _messageOf(Object exception, String action) {
    if (exception is InteractionException) return exception.message;
    return '$action失败，请稍后重试';
  }
}
