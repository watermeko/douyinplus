import 'json_utils.dart';

class UserProfile {
  const UserProfile({
    required this.uid,
    required this.secUid,
    required this.nickname,
    required this.uniqueId,
    required this.shortId,
    required this.signature,
    required this.avatarUrl,
    required this.followerCount,
    required this.followingCount,
    required this.awemeCount,
    required this.totalFavorited,
  });

  final String uid;
  final String secUid;
  final String nickname;
  final String uniqueId;
  final String shortId;
  final String signature;
  final String? avatarUrl;
  final int followerCount;
  final int followingCount;
  final int awemeCount;
  final int totalFavorited;

  String get displayId {
    if (uniqueId.isNotEmpty) return uniqueId;
    if (shortId.isNotEmpty) return shortId;
    return uid;
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final avatar =
        firstUrlOf(asMap(json['avatar_thumb'])) ??
        firstUrlOf(asMap(json['avatar_medium'])) ??
        firstUrlOf(asMap(json['avatar_larger'])) ??
        firstUrlOf(asMap(json['avatar_168x168'])) ??
        firstUrlOf(asMap(json['avatar_300x300']));

    return UserProfile(
      uid: asString(json['uid']),
      secUid: asString(json['sec_uid']),
      nickname: asString(json['nickname']),
      uniqueId: asString(json['unique_id']),
      shortId: asString(json['short_id']),
      signature: asString(json['signature']),
      avatarUrl: avatar,
      followerCount: asInt(json['follower_count']),
      followingCount: asInt(json['following_count']),
      awemeCount: asInt(json['aweme_count']),
      totalFavorited: asInt(json['total_favorited']),
    );
  }
}
