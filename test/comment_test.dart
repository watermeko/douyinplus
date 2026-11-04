import 'package:douyinplus/data/models/comment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CommentPage parses comments, user, reply and media', () {
    final page = CommentPage.fromJson({
      'comments': [
        {
          'cid': 'c1',
          'text': '一条评论',
          'create_time': 1793578081,
          'digg_count': 12,
          'reply_comment_total': 2,
          'ip_label': '广东',
          'user': {
            'uid': 'u1',
            'sec_uid': 's1',
            'nickname': '小明',
            'avatar_thumb': {
              'url_list': ['https://example.com/avatar.jpg'],
            },
          },
          'reply_comment': {
            'cid': 'c0',
            'text': '作者回复',
            'user': {'nickname': '作者'},
          },
          'sticker': {
            'static_url': {
              'url_list': ['https://example.com/sticker.png'],
            },
          },
        },
        {'cid': '', 'text': '没有 cid 的评论会被丢弃'},
      ],
      'cursor': '10',
      'has_more': 1,
      'total': 100,
    });

    expect(page.items, hasLength(1));
    expect(page.cursor, '10');
    expect(page.hasMore, isTrue);
    expect(page.total, 100);

    final comment = page.items.single;
    expect(comment.cid, 'c1');
    expect(comment.text, '一条评论');
    expect(comment.diggCount, 12);
    expect(comment.replyCount, 2);
    expect(comment.ipLabel, '广东');
    expect(comment.user.nickname, '小明');
    expect(comment.user.avatarUrl, 'https://example.com/avatar.jpg');
    expect(comment.replyComment?.text, '作者回复');
    expect(comment.mediaUrl, 'https://example.com/sticker.png');
  });

  test('CommentPage handles missing fields', () {
    final page = CommentPage.fromJson(const <String, dynamic>{});
    expect(page.items, isEmpty);
    expect(page.cursor, '');
    expect(page.hasMore, isFalse);
    expect(page.total, 0);

    final comment = Comment.fromJson(const <String, dynamic>{});
    expect(comment.cid, '');
    expect(comment.text, '');
    expect(comment.replyComment, isNull);
    expect(comment.mediaUrl, isNull);
  });

  test('Comment extracts image list media url', () {
    final comment = Comment.fromJson({
      'cid': 'c2',
      'image_list': [
        {
          'origin_url': {
            'url_list': ['https://example.com/image.jpg'],
          },
        },
      ],
    });
    expect(comment.mediaUrl, 'https://example.com/image.jpg');
  });
}
