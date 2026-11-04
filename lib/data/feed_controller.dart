import 'package:flutter/foundation.dart';

import 'douyin_api.dart';
import 'models/aweme.dart';

class FeedController extends ChangeNotifier {
  FeedController(this._api, {this.pageSize = 6});

  final DouyinApi _api;
  final int pageSize;

  final List<Aweme> items = <Aweme>[];
  final Set<String> _seenIds = <String>{};

  bool isLoading = false;
  bool isLoadingMore = false;
  bool hasMore = true;
  int currentIndex = 0;
  int refreshIndex = 0;
  String filterGids = '';
  String? error;

  bool _disposed = false;

  bool get isEmpty => items.isEmpty;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> loadInitial() async {
    if (isLoading) return;
    isLoading = true;
    isLoadingMore = false;
    error = null;
    refreshIndex = 0;
    filterGids = '';
    hasMore = true;
    items.clear();
    _seenIds.clear();
    currentIndex = 0;
    _notify();

    try {
      await _fetchNext();
      // The first page is often intentionally short (2–3 items); pull one
      // more batch so the vertical feed feels populated.
      if (items.length < 4 && hasMore) {
        await _fetchNext();
      }
    } catch (exception) {
      error = _api.describeError(exception);
    } finally {
      isLoading = false;
      _notify();
    }
  }

  Future<void> loadMore() async {
    if (isLoading || isLoadingMore || !hasMore) return;
    isLoadingMore = true;
    error = null;
    _notify();
    try {
      await _fetchNext();
    } catch (exception) {
      error = _api.describeError(exception);
    } finally {
      isLoadingMore = false;
      _notify();
    }
  }

  Future<void> retry() async {
    if (items.isEmpty) {
      await loadInitial();
    } else {
      await loadMore();
    }
  }

  Future<void> refresh() async {
    await loadInitial();
  }

  void setCurrentIndex(int index) {
    currentIndex = index;
  }

  Future<void> _fetchNext() async {
    final nextRefreshIndex = refreshIndex + 1;
    final result = await _api.fetchFeed(
      refreshIndex: nextRefreshIndex,
      filterGids: filterGids,
      count: pageSize,
    );

    refreshIndex = nextRefreshIndex;
    hasMore = result.hasMore;

    var added = 0;
    for (final item in result.items) {
      if (_seenIds.add(item.id)) {
        items.add(item);
        added++;
      }
    }
    if (result.items.isNotEmpty) {
      filterGids = result.items.last.id;
    }
    if (added == 0 && result.items.isNotEmpty) {
      // Avoid tight loop when the server keeps returning duplicates.
      hasMore = false;
    }
  }
}
