import 'package:flutter/foundation.dart';

import 'comment_repository.dart';
import 'models/comment.dart';

class CommentsController extends ChangeNotifier {
  CommentsController({required this.repository, required this.awemeId});

  final CommentSource repository;
  final String awemeId;

  final List<Comment> items = <Comment>[];
  final Set<String> _seenCids = <String>{};

  String _cursor = '0';
  bool hasMore = true;
  bool loading = false;
  bool loadingMore = false;
  String? error;
  String? loadMoreError;
  int total = 0;
  bool _disposed = false;

  Future<void> loadInitial() async {
    if (loading) return;
    loading = true;
    error = null;
    loadMoreError = null;
    _notify();
    try {
      final page = await repository.fetchComments(awemeId: awemeId);
      if (_disposed) return;
      items.clear();
      _seenCids.clear();
      _append(page.items);
      _cursor = page.cursor;
      hasMore = page.hasMore && page.cursor.isNotEmpty;
      total = page.total;
    } catch (exception) {
      if (_disposed) return;
      error = _messageOf(exception);
    } finally {
      if (!_disposed) {
        loading = false;
        _notify();
      }
    }
  }

  Future<void> loadMore() async {
    if (loading || loadingMore || !hasMore) return;
    loadingMore = true;
    loadMoreError = null;
    _notify();
    try {
      final page = await repository.fetchComments(
        awemeId: awemeId,
        cursor: _cursor,
      );
      if (_disposed) return;
      _append(page.items);
      _cursor = page.cursor;
      hasMore = page.hasMore && page.cursor.isNotEmpty;
      if (page.total > 0) total = page.total;
    } catch (exception) {
      if (_disposed) return;
      loadMoreError = _messageOf(exception);
    } finally {
      if (!_disposed) {
        loadingMore = false;
        _notify();
      }
    }
  }

  Future<void> retry() => loadInitial();

  Future<void> retryLoadMore() => loadMore();

  void _append(List<Comment> comments) {
    for (final comment in comments) {
      if (_seenCids.add(comment.cid)) items.add(comment);
    }
  }

  String _messageOf(Object exception) {
    if (exception is CommentException) return exception.message;
    return '评论加载失败，请稍后重试';
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
