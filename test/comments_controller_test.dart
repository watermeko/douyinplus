import 'package:douyinplus/data/comment_repository.dart';
import 'package:douyinplus/data/comments_controller.dart';
import 'package:douyinplus/data/models/comment.dart';
import 'package:flutter_test/flutter_test.dart';

Comment _comment(String cid) =>
    Comment.fromJson(<String, dynamic>{'cid': cid, 'text': '评论 $cid'});

CommentPage _page({
  required List<String> cids,
  required String cursor,
  required bool hasMore,
  int total = 3,
}) {
  return CommentPage(
    items: [for (final cid in cids) _comment(cid)],
    cursor: cursor,
    hasMore: hasMore,
    total: total,
  );
}

class _FakeCommentSource implements CommentSource {
  _FakeCommentSource(this.pages);

  final List<CommentPage> pages;
  Object? error;
  int calls = 0;
  final List<String> cursors = <String>[];

  @override
  Future<CommentPage> fetchComments({
    required String awemeId,
    String cursor = '0',
    int count = 20,
  }) async {
    cursors.add(cursor);
    if (error != null) throw error!;
    return pages[calls++];
  }

  @override
  Future<CommentPage> fetchReplies({
    required String commentId,
    String cursor = '0',
    int count = 20,
  }) {
    throw UnimplementedError();
  }
}

void main() {
  test('loads pages, dedupes by cid and stops at has_more=0', () async {
    final source = _FakeCommentSource([
      _page(cids: ['c1', 'c2'], cursor: '10', hasMore: true),
      _page(cids: ['c2', 'c3'], cursor: '20', hasMore: false),
    ]);
    final controller = CommentsController(
      repository: source,
      awemeId: 'aweme-1',
    );

    await controller.loadInitial();
    expect(controller.items.map((item) => item.cid), ['c1', 'c2']);
    expect(controller.total, 3);
    expect(controller.hasMore, isTrue);
    expect(controller.loading, isFalse);

    await controller.loadMore();
    expect(controller.items.map((item) => item.cid), ['c1', 'c2', 'c3']);
    expect(controller.hasMore, isFalse);
    expect(controller.loadingMore, isFalse);
    expect(source.cursors, ['0', '10']);

    await controller.loadMore();
    expect(source.calls, 2, reason: 'no request after has_more=0');
    controller.dispose();
  });

  test('sets a readable error and can retry', () async {
    final source = _FakeCommentSource([
      _page(cids: ['c1'], cursor: '10', hasMore: true, total: 1),
    ]);
    source.error = const CommentException('评论加载超时，请检查网络后重试');
    final controller = CommentsController(
      repository: source,
      awemeId: 'aweme-1',
    );

    await controller.loadInitial();
    expect(controller.error, '评论加载超时，请检查网络后重试');
    expect(controller.items, isEmpty);
    expect(controller.loading, isFalse);

    source.error = null;
    await controller.retry();
    expect(controller.error, isNull);
    expect(controller.items.single.cid, 'c1');
    expect(controller.loading, isFalse);
    controller.dispose();
  });

  test('loadMore records an error but keeps loaded comments', () async {
    final source = _FakeCommentSource([
      _page(cids: ['c1'], cursor: '10', hasMore: true),
    ]);
    final controller = CommentsController(
      repository: source,
      awemeId: 'aweme-1',
    );
    await controller.loadInitial();

    source.error = Exception('boom');
    await controller.loadMore();

    expect(controller.loadMoreError, '评论加载失败，请稍后重试');
    expect(controller.items.single.cid, 'c1');
    expect(controller.hasMore, isTrue);
    controller.dispose();
  });
}
