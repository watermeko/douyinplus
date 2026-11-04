import 'package:douyinplus/data/models/aweme.dart';
import 'package:douyinplus/data/models/user_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Aweme.fromJson parses core fields and playback urls', () {
    final aweme = Aweme.fromJson({
      'aweme_id': '7703206229157416235',
      'aweme_type': 0,
      'create_time': 1793578081,
      'desc': '测试视频 #话题',
      'author': {
        'uid': '130163525296012',
        'sec_uid': 'MS4wLjABAAAA_test',
        'nickname': '测试作者',
        'avatar_thumb': {
          'url_list': ['https://example.com/avatar.jpeg'],
        },
      },
      'statistics': {
        'digg_count': 10633,
        'comment_count': 59,
        'collect_count': 1157,
        'share_count': 475,
      },
      'video': {
        'duration': 237819,
        'width': 1920,
        'height': 1080,
        'play_addr': {
          'url_list': ['https://example.com/video.mp4'],
        },
        'play_addr_265': {
          'url_list': ['https://example.com/video-265.mp4'],
        },
        'cover': {
          'url_list': ['https://example.com/cover.jpeg'],
        },
      },
      'music': {'title': '原声', 'author': '测试作者'},
      'text_extra': [
        {'hashtag_name': '话题'},
      ],
    });

    expect(aweme.id, '7703206229157416235');
    expect(aweme.desc, '测试视频 #话题');
    expect(aweme.author.nickname, '测试作者');
    expect(aweme.author.avatarUrl, 'https://example.com/avatar.jpeg');
    expect(aweme.statistics.diggCount, 10633);
    expect(aweme.video.durationMs, 237819);
    expect(aweme.video.allPlayUrls.first, 'https://example.com/video.mp4');
    expect(
      aweme.video.allPlayUrls,
      contains('https://example.com/video-265.mp4'),
    );
    expect(aweme.coverUrl, 'https://example.com/cover.jpeg');
    expect(aweme.hashtags, ['话题']);
    expect(aweme.isImagePost, isFalse);
  });

  test('Aweme.fromJson detects image posts', () {
    final aweme = Aweme.fromJson({
      'aweme_id': '1',
      'aweme_type': 2,
      'images': [
        {
          'url_list': ['https://example.com/image.jpeg'],
        },
      ],
    });

    expect(aweme.isImagePost, isTrue);
    expect(aweme.imageUrls, ['https://example.com/image.jpeg']);
    expect(aweme.coverUrl, 'https://example.com/image.jpeg');
    expect(aweme.video.hasVideo, isFalse);
  });

  test('UserProfile.fromJson parses profile fields', () {
    final profile = UserProfile.fromJson({
      'uid': '1000000000000000',
      'sec_uid': 'MS4wLjABAAAA_user',
      'nickname': '测试用户',
      'unique_id': '12345678',
      'short_id': '12345678',
      'signature': '签名',
      'follower_count': 29,
      'following_count': 419,
      'aweme_count': 0,
      'total_favorited': 0,
      'avatar_thumb': {
        'url_list': ['https://example.com/me.jpeg'],
      },
    });

    expect(profile.nickname, '测试用户');
    expect(profile.displayId, '12345678');
    expect(profile.followerCount, 29);
    expect(profile.avatarUrl, 'https://example.com/me.jpeg');
  });
}
