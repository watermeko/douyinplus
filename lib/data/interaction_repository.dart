import 'dart:convert';

import 'models/json_utils.dart';
import 'signed_client.dart';

enum InteractionErrorKind { network, risk, auth, empty, api, parse, unknown }

class InteractionException implements Exception {
  const InteractionException(
    this.message, {
    this.kind = InteractionErrorKind.unknown,
  });

  final String message;
  final InteractionErrorKind kind;

  @override
  String toString() => message;
}

/// Write operations on the current account. Kept as an interface so the
/// optimistic UI state can be tested without a real signature bridge.
abstract class InteractionGateway {
  Future<void> setDigg({required String awemeId, required bool liked});

  Future<void> setCollect({
    required String awemeId,
    required bool collected,
    int awemeType = 0,
  });

  /// Reads the account's current like / collect state for a video.
  ///
  /// The feed response omits `user_digged` / `user_collected`; `aweme/detail`
  /// carries both. Returns null when the detail request fails or is blocked.
  Future<InteractionState?> fetchState(String awemeId) async => null;
}

class InteractionState {
  const InteractionState({required this.liked, required this.collected});

  final bool liked;
  final bool collected;
}

class InteractionRepository implements InteractionGateway {
  InteractionRepository(this._client);

  final SignedClient _client;

  @override
  Future<void> setDigg({required String awemeId, required bool liked}) async {
    final response = await _client.post(
      '/aweme/v1/web/commit/item/digg/',
      body: _form(<String, String>{
        'aweme_id': awemeId,
        'item_type': '0',
        'type': liked ? '1' : '0',
      }),
    );
    _ensureSuccess(response, action: '点赞');
  }

  @override
  Future<void> setCollect({
    required String awemeId,
    required bool collected,
    int awemeType = 0,
  }) async {
    final response = await _client.post(
      '/aweme/v1/web/aweme/collect/',
      body: _form(<String, String>{
        'aweme_id': awemeId,
        'action': collected ? '1' : '0',
        'aweme_type': '$awemeType',
      }),
    );
    _ensureSuccess(response, action: '收藏');
  }

  @override
  Future<InteractionState?> fetchState(String awemeId) async {
    try {
      final response = await _client.get(
        '/aweme/v1/web/aweme/detail/',
        <String, String>{'aweme_id': awemeId},
      );
      if (!response.isSuccess) return null;
      final json = asMap(jsonDecode(response.body));
      if (asInt(json['status_code']) != 0) return null;
      final detail = asMap(json['aweme_detail']);
      if (detail.isEmpty) return null;
      return InteractionState(
        liked: asInt(detail['user_digged']) == 1,
        collected: asInt(detail['user_collected']) == 1,
      );
    } catch (_) {
      return null;
    }
  }

  void _ensureSuccess(SignatureResponse response, {required String action}) {
    if (!response.isSuccess) {
      throw InteractionException(
        _messageFor(response, action),
        kind: _kindFor(response),
      );
    }

    Map<String, dynamic> json;
    try {
      json = asMap(jsonDecode(response.body));
    } on FormatException {
      throw InteractionException('$action结果解析失败');
    }
    if (json.isEmpty) {
      throw InteractionException('$action结果为空');
    }
    final statusCode = asInt(json['status_code']);
    if (statusCode != 0) {
      final statusMessage = asString(json['status_msg']);
      throw InteractionException(
        statusMessage.isNotEmpty
            ? '$action失败：$statusMessage'
            : '$action被抖音拒绝（$statusCode）',
        kind: InteractionErrorKind.api,
      );
    }
  }

  String _form(Map<String, String> fields) {
    return fields.entries
        .map(
          (entry) =>
              '${Uri.encodeQueryComponent(entry.key)}='
              '${Uri.encodeQueryComponent(entry.value)}',
        )
        .join('&');
  }

  InteractionErrorKind _kindFor(SignatureResponse response) {
    final bridgeError = response.error ?? '';
    if (bridgeError.contains('安全验证') || bridgeError.contains('风控')) {
      return InteractionErrorKind.risk;
    }
    if (bridgeError.contains('登录态')) return InteractionErrorKind.auth;
    if (response.statusCode == 401) return InteractionErrorKind.auth;
    if (response.statusCode == 403) return InteractionErrorKind.risk;
    if (response.error != null &&
        (response.error!.contains('超时') ||
            response.error!.contains('timeout'))) {
      return InteractionErrorKind.network;
    }
    if (response.statusCode > 0 && response.body.isEmpty) {
      return InteractionErrorKind.empty;
    }
    if (response.statusCode < 0) return InteractionErrorKind.network;
    return InteractionErrorKind.unknown;
  }

  String _messageFor(SignatureResponse response, String action) {
    switch (_kindFor(response)) {
      case InteractionErrorKind.auth:
        return '$action失败：登录状态已失效';
      case InteractionErrorKind.risk:
        return '$action被风控拦截，本次操作已撤销；若反复出现请重新登录';
      case InteractionErrorKind.empty:
        return '$action接口返回空响应，请稍后重试';
      case InteractionErrorKind.network:
        return '$action超时，请检查网络后重试';
      case InteractionErrorKind.parse:
      case InteractionErrorKind.api:
      case InteractionErrorKind.unknown:
        return '$action失败：${response.failureReason ?? '未知错误'}';
    }
  }
}
