import 'json_utils.dart';

class CommentUser {
  const CommentUser({
    required this.uid,
    required this.secUid,
    required this.nickname,
    required this.avatarUrl,
  });

  final String uid;
  final String secUid;
  final String nickname;
  final String avatarUrl;

  factory CommentUser.fromJson(Map<String, dynamic> json) {
    final avatar = asMap(json['avatar_thumb']);
    return CommentUser(
      uid: asString(json['uid']),
      secUid: asString(json['sec_uid']),
      nickname: asString(json['nickname']),
      avatarUrl: firstUrlOf(avatar) ?? '',
    );
  }
}

class Comment {
  const Comment({
    required this.cid,
    required this.text,
    required this.createTime,
    required this.diggCount,
    required this.replyCount,
    required this.ipLabel,
    required this.user,
    this.replyComment,
    this.mediaUrl,
  });

  final String cid;
  final String text;
  final int createTime;
  final int diggCount;
  final int replyCount;
  final String ipLabel;
  final CommentUser user;
  final Comment? replyComment;
  final String? mediaUrl;

  factory Comment.fromJson(Map<String, dynamic> json) {
    final reply = asMap(json['reply_comment']);
    return Comment(
      cid: asString(json['cid']),
      text: asString(json['text']),
      createTime: asInt(json['create_time']),
      diggCount: asInt(json['digg_count']),
      replyCount: asInt(json['reply_comment_total']),
      ipLabel: asString(json['ip_label']),
      user: CommentUser.fromJson(asMap(json['user'])),
      replyComment: reply.isEmpty ? null : Comment.fromJson(reply),
      mediaUrl: _extractMediaUrl(json),
    );
  }
}

/// Comments sometimes contain only a sticker or image with no text. Pull the
/// first usable URL from the common media containers without relying on one
/// exact schema version.
String? _extractMediaUrl(Map<String, dynamic> json) {
  for (final key in const [
    'sticker',
    'image_list',
    'image_list_v2',
    'images',
  ]) {
    final url = _firstUrlDeep(json[key], 0);
    if (url != null) return url;
  }
  return null;
}

String? _firstUrlDeep(dynamic value, int depth) {
  if (depth > 4) return null;
  if (value is List) {
    for (final item in value) {
      final url = _firstUrlDeep(item, depth + 1);
      if (url != null) return url;
    }
    return null;
  }
  if (value is Map) {
    final map = asMap(value);
    final direct = firstUrlOf(map);
    if (direct != null) return direct;
    for (final key in const [
      'origin_url',
      'thumb_url',
      'download_url',
      'static_url',
      'dynamic_url',
    ]) {
      final url = _firstUrlDeep(map[key], depth + 1);
      if (url != null) return url;
    }
  }
  return null;
}

class CommentPage {
  const CommentPage({
    required this.items,
    required this.cursor,
    required this.hasMore,
    required this.total,
  });

  final List<Comment> items;
  final String cursor;
  final bool hasMore;
  final int total;

  factory CommentPage.fromJson(Map<String, dynamic> json) {
    return CommentPage(
      items: [
        for (final raw in asList(json['comments']))
          if (asString(asMap(raw)['cid']).isNotEmpty)
            Comment.fromJson(asMap(raw)),
      ],
      cursor: asString(json['cursor']),
      hasMore: asBool(json['has_more']),
      total: asInt(json['total']),
    );
  }
}
