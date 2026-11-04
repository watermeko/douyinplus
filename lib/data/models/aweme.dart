import 'json_utils.dart';

class Author {
  const Author({
    required this.uid,
    required this.secUid,
    required this.nickname,
    required this.uniqueId,
    required this.avatarUrl,
    required this.followerCount,
  });

  final String uid;
  final String secUid;
  final String nickname;
  final String uniqueId;
  final String? avatarUrl;
  final int followerCount;

  factory Author.fromJson(Map<String, dynamic> json) {
    final avatar =
        firstUrlOf(asMap(json['avatar_thumb'])) ??
        firstUrlOf(asMap(json['avatar_medium'])) ??
        firstUrlOf(asMap(json['avatar_larger'])) ??
        firstUrlOf(asMap(json['avatar_168x168'])) ??
        firstUrlOf(asMap(json['avatar_300x300']));
    return Author(
      uid: asString(json['uid']),
      secUid: asString(json['sec_uid']),
      nickname: asString(json['nickname']),
      uniqueId: asString(json['unique_id']),
      avatarUrl: avatar,
      followerCount: asInt(json['follower_count']),
    );
  }
}

class AwemeStatistics {
  const AwemeStatistics({
    this.diggCount = 0,
    this.commentCount = 0,
    this.collectCount = 0,
    this.shareCount = 0,
    this.playCount = 0,
  });

  final int diggCount;
  final int commentCount;
  final int collectCount;
  final int shareCount;
  final int playCount;

  factory AwemeStatistics.fromJson(Map<String, dynamic> json) {
    return AwemeStatistics(
      diggCount: asInt(json['digg_count']),
      commentCount: asInt(json['comment_count']),
      collectCount: asInt(json['collect_count']),
      shareCount: asInt(json['share_count']),
      playCount: asInt(json['play_count']),
    );
  }
}

class MusicInfo {
  const MusicInfo({required this.title, required this.author, this.playUrl});

  final String title;
  final String author;
  final String? playUrl;

  factory MusicInfo.fromJson(Map<String, dynamic> json) {
    return MusicInfo(
      title: asString(json['title']),
      author: asString(json['author']),
      playUrl: firstUrlOf(asMap(json['play_url'])),
    );
  }
}

class VideoInfo {
  const VideoInfo({
    required this.durationMs,
    required this.width,
    required this.height,
    required this.ratio,
    required this.playUrls,
    required this.h264Urls,
    required this.h265Urls,
    required this.bitRateUrls,
    required this.coverUrl,
    required this.dynamicCoverUrl,
    required this.originCoverUrl,
  });

  final int durationMs;
  final int width;
  final int height;
  final String ratio;
  final List<String> playUrls;
  final List<String> h264Urls;
  final List<String> h265Urls;
  final List<String> bitRateUrls;
  final String? coverUrl;
  final String? dynamicCoverUrl;
  final String? originCoverUrl;

  bool get hasVideo =>
      playUrls.isNotEmpty || h264Urls.isNotEmpty || h265Urls.isNotEmpty;

  /// Ordered list of URLs to attempt. H.264 / default first, then HEVC and
  /// lower bitrate variants as fallbacks.
  List<String> get allPlayUrls =>
      dedupeUrls([...playUrls, ...h264Urls, ...h265Urls, ...bitRateUrls]);

  Duration get duration => Duration(milliseconds: durationMs);

  factory VideoInfo.fromJson(Map<String, dynamic> json) {
    final bitRates = asList(json['bit_rate']).map(asMap).toList()
      ..sort((a, b) => asInt(a['bit_rate']).compareTo(asInt(b['bit_rate'])));
    final bitRateUrls = <String>[
      for (final item in bitRates) ...urlListOf(asMap(item['play_addr'])),
    ];

    final cover =
        firstUrlOf(asMap(json['cover'])) ??
        firstUrlOf(asMap(json['origin_cover'])) ??
        firstUrlOf(asMap(json['dynamic_cover']));

    return VideoInfo(
      durationMs: asInt(json['duration']),
      width: asInt(json['width']),
      height: asInt(json['height']),
      ratio: asString(json['ratio']),
      playUrls: urlListOf(asMap(json['play_addr'])),
      h264Urls: urlListOf(asMap(json['play_addr_h264'])),
      h265Urls: urlListOf(asMap(json['play_addr_265'])),
      bitRateUrls: bitRateUrls,
      coverUrl: cover,
      dynamicCoverUrl: firstUrlOf(asMap(json['dynamic_cover'])),
      originCoverUrl: firstUrlOf(asMap(json['origin_cover'])),
    );
  }
}

class Aweme {
  const Aweme({
    required this.id,
    required this.desc,
    required this.createTime,
    required this.awemeType,
    required this.author,
    required this.video,
    required this.statistics,
    required this.music,
    required this.hashtags,
    required this.imageUrls,
    required this.isImagePost,
  });

  final String id;
  final String desc;
  final int createTime;
  final int awemeType;
  final Author author;
  final VideoInfo video;
  final AwemeStatistics statistics;
  final MusicInfo? music;
  final List<String> hashtags;
  final List<String> imageUrls;
  final bool isImagePost;

  String get coverUrl =>
      video.coverUrl ??
      video.originCoverUrl ??
      video.dynamicCoverUrl ??
      (imageUrls.isNotEmpty ? imageUrls.first : null) ??
      '';

  factory Aweme.fromJson(Map<String, dynamic> json) {
    final videoMap = asMap(json['video']);
    final imageUrls = [
      for (final image in asList(json['images']))
        if (firstUrlOf(asMap(image)) != null) firstUrlOf(asMap(image))!,
    ];
    final hashtags = <String>[
      for (final item in asList(json['text_extra']))
        if (asString(asMap(item)['hashtag_name']).trim().isNotEmpty)
          asString(asMap(item)['hashtag_name']).trim(),
    ];
    final awemeType = asInt(json['aweme_type']);
    final music = asMap(json['music']);

    return Aweme(
      id: asString(json['aweme_id']),
      desc: asString(json['desc']),
      createTime: asInt(json['create_time']),
      awemeType: awemeType,
      author: Author.fromJson(asMap(json['author'])),
      video: VideoInfo.fromJson(videoMap),
      statistics: AwemeStatistics.fromJson(asMap(json['statistics'])),
      music: music.isEmpty ? null : MusicInfo.fromJson(music),
      hashtags: hashtags,
      imageUrls: imageUrls,
      isImagePost: awemeType != 0 || imageUrls.isNotEmpty,
    );
  }
}

class FeedResult {
  const FeedResult({required this.items, required this.hasMore});

  final List<Aweme> items;
  final bool hasMore;
}
