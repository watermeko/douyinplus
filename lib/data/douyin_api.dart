import 'dart:convert';

import 'package:dio/dio.dart';

import 'models/aweme.dart';
import 'models/json_utils.dart';
import 'models/user_profile.dart';
import 'session_store.dart';

const kDouyinUserAgent =
    'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/156.0.0.0 Safari/537.36';

class DouyinApiException implements Exception {
  const DouyinApiException(
    this.message, {
    this.statusCode,
    this.apiCode,
    this.isRisk = false,
    this.isAuthError = false,
  });

  final String message;
  final int? statusCode;
  final int? apiCode;
  final bool isRisk;
  final bool isAuthError;

  @override
  String toString() => message;
}

class DouyinApi {
  DouyinApi(this._session, {Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: 'https://www.douyin.com',
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              sendTimeout: const Duration(seconds: 15),
              responseType: ResponseType.plain,
              validateStatus: (status) => status != null && status < 500,
            ),
          );

  final SessionStore _session;
  final Dio _dio;

  Map<String, String> get _baseParams => <String, String>{
    'device_platform': 'webapp',
    'aid': '6383',
    'channel': 'channel_pc_web',
    'pc_client_type': '1',
    'pc_libra_divert': 'Linux',
    'support_h265': '1',
    'support_dash': '1',
    'version_code': '170400',
    'version_name': '17.4.0',
    'cookie_enabled': 'true',
    'screen_width': '1080',
    'screen_height': '2400',
    'browser_language': 'zh-CN',
    'browser_platform': 'Linux x86_64',
    'browser_name': 'Chrome',
    'browser_version': '156.0.0.0',
    'browser_online': 'true',
    'engine_name': 'Blink',
    'engine_version': '156.0.0.0',
    'os_name': 'Linux',
    'os_version': 'x86_64',
    'platform': 'PC',
    'downlink': '10',
    'effective_type': '4g',
    'round_trip_time': '200',
  };

  Future<Map<String, String>> _headers({
    String referer = 'https://www.douyin.com/?recommend=1',
  }) async {
    final cookie = await _session.cookieHeader();
    return <String, String>{
      'User-Agent': kDouyinUserAgent,
      'Accept': 'application/json, text/plain, */*',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      'Referer': referer,
      'sec-ch-ua': '"Not:A-Brand";v="8", "Chromium";v="156"',
      'sec-ch-ua-mobile': '?0',
      'sec-ch-ua-platform': '"Linux"',
      if (cookie != null && cookie.isNotEmpty) 'Cookie': cookie,
    };
  }

  Future<Map<String, dynamic>> _getJson(
    String path,
    Map<String, String> params, {
    required String referer,
  }) async {
    final response = await _dio.get<String>(
      path,
      queryParameters: params,
      options: Options(
        headers: await _headers(referer: referer),
        responseType: ResponseType.plain,
      ),
    );

    final status = response.statusCode ?? 0;
    final body = (response.data ?? '').trim();

    if (status == 403 || body.contains('ArgusSecurityPlugin')) {
      throw DouyinApiException(
        body.isEmpty ? '请求被抖音风控拦截（403）' : body,
        statusCode: status,
        isRisk: true,
      );
    }
    if (status >= 400) {
      throw DouyinApiException(
        '请求失败（HTTP $status）',
        statusCode: status,
        isRisk: status == 403,
      );
    }
    if (body.isEmpty) {
      throw const DouyinApiException(
        '接口返回空响应，可能登录已失效或触发风控',
        isRisk: true,
        isAuthError: true,
      );
    }

    Map<String, dynamic> json;
    try {
      json = asMap(jsonDecode(body));
    } on FormatException {
      throw DouyinApiException('接口响应格式异常（HTTP $status）', statusCode: status);
    }

    final apiCode = asInt(json['status_code']);
    if (apiCode != 0) {
      throw DouyinApiException(
        asString(json['status_msg']).isNotEmpty
            ? asString(json['status_msg'])
            : '抖音接口返回错误（$apiCode）',
        statusCode: status,
        apiCode: apiCode,
      );
    }
    return json;
  }

  Future<FeedResult> fetchFeed({
    int refreshIndex = 1,
    String filterGids = '',
    int count = 6,
  }) async {
    final params = <String, String>{
      ..._baseParams,
      'count': '$count',
      'refresh_index': '$refreshIndex',
      'pull_type': refreshIndex == 1 ? '0' : '1',
      'video_type_select': '1',
      'filterGids': filterGids,
    };

    final uifid = await _session.valueOf('UIFID');
    if (uifid != null && uifid.isNotEmpty) {
      params['uifid'] = uifid;
    }

    final json = await _getJson(
      '/aweme/v1/web/tab/feed/',
      params,
      referer: 'https://www.douyin.com/?recommend=1',
    );

    final items = <Aweme>[
      for (final raw in asList(json['aweme_list']))
        if (asString(asMap(raw)['aweme_id']).isNotEmpty)
          Aweme.fromJson(asMap(raw)),
    ];

    return FeedResult(items: items, hasMore: asBool(json['has_more']));
  }

  Future<UserProfile?> fetchSelfProfile() async {
    final json = await _getJson(
      '/aweme/v1/web/user/profile/self/',
      _baseParams,
      referer: 'https://www.douyin.com/',
    );

    final user = asMap(json['user']);
    if (user.isEmpty || asString(user['uid']).isEmpty) {
      throw const DouyinApiException(
        '登录状态无效，请重新登录',
        isAuthError: true,
        isRisk: true,
      );
    }
    return UserProfile.fromJson(user);
  }

  Future<UserProfile?> fetchUserProfile(String secUid) async {
    final json = await _getJson('/aweme/v1/web/user/profile/other/', {
      ..._baseParams,
      'sec_user_id': secUid,
      'publish_video_strategy_type': '2',
    }, referer: 'https://www.douyin.com/');
    final user = asMap(json['user']);
    if (user.isEmpty) return null;
    return UserProfile.fromJson(user);
  }

  String describeError(Object error) {
    if (error is DouyinApiException) {
      return error.message;
    }
    final text = error.toString();
    if (text.contains('SocketException') ||
        text.contains('Connection') ||
        text.contains('timed out')) {
      return '网络连接失败，请检查网络后重试';
    }
    return text;
  }
}
