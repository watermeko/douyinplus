import 'dart:convert';

import 'models/comment.dart';
import 'models/json_utils.dart';
import 'signed_client.dart';

enum CommentErrorKind { network, risk, auth, empty, parse, api, unknown }

class CommentException implements Exception {
  const CommentException(this.message, {this.kind = CommentErrorKind.unknown});

  final String message;
  final CommentErrorKind kind;

  @override
  String toString() => message;
}

/// Read-only comment source, kept as an interface so pagination state can be
/// tested without a WebView.
abstract class CommentSource {
  Future<CommentPage> fetchComments({
    required String awemeId,
    String cursor = '0',
    int count = 20,
  });

  Future<CommentPage> fetchReplies({
    required String commentId,
    String cursor = '0',
    int count = 20,
  });
}

class CommentRepository implements CommentSource {
  CommentRepository(this._bridge);

  final SignedClient _bridge;

  @override
  Future<CommentPage> fetchComments({
    required String awemeId,
    String cursor = '0',
    int count = 20,
  }) {
    return _request('/aweme/v1/web/comment/list/', <String, String>{
      'aweme_id': awemeId,
      'cursor': cursor,
      'count': '$count',
      'item_type': '0',
    });
  }

  @override
  Future<CommentPage> fetchReplies({
    required String commentId,
    String cursor = '0',
    int count = 20,
  }) {
    return _request('/aweme/v1/web/comment/list/reply/', <String, String>{
      'comment_id': commentId,
      'cursor': cursor,
      'count': '$count',
      'item_type': '0',
    });
  }

  Future<CommentPage> _request(String path, Map<String, String> params) async {
    final response = await _bridge.get(path, params);
    if (!response.isSuccess) {
      throw CommentException(_messageFor(response), kind: _kindFor(response));
    }

    Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(response.body);
      json = asMap(decoded);
    } on FormatException {
      throw const CommentException('评论数据解析失败', kind: CommentErrorKind.parse);
    }
    if (json.isEmpty) {
      throw const CommentException('评论数据为空', kind: CommentErrorKind.parse);
    }
    final statusCode = asInt(json['status_code']);
    if (statusCode != 0) {
      throw CommentException(
        asString(json['status_msg']).isNotEmpty
            ? asString(json['status_msg'])
            : '评论接口返回错误（$statusCode）',
        kind: CommentErrorKind.api,
      );
    }
    return CommentPage.fromJson(json);
  }

  CommentErrorKind _kindFor(SignatureResponse response) {
    if (response.statusCode == 401) return CommentErrorKind.auth;
    if (response.statusCode == 403) return CommentErrorKind.risk;
    if (response.error != null &&
        (response.error!.contains('超时') ||
            response.error!.contains('timeout'))) {
      return CommentErrorKind.network;
    }
    if (response.statusCode > 0 && response.body.isEmpty) {
      return CommentErrorKind.empty;
    }
    if (response.statusCode < 0) return CommentErrorKind.network;
    return CommentErrorKind.unknown;
  }

  String _messageFor(SignatureResponse response) {
    switch (_kindFor(response)) {
      case CommentErrorKind.auth:
        return '登录状态已失效，请重新登录';
      case CommentErrorKind.risk:
        return '评论加载被风控拦截，请稍后重试';
      case CommentErrorKind.empty:
        return '评论接口返回空响应，请稍后重试';
      case CommentErrorKind.network:
        return '评论加载超时，请检查网络后重试';
      case CommentErrorKind.parse:
      case CommentErrorKind.api:
      case CommentErrorKind.unknown:
        return response.failureReason ?? '评论加载失败';
    }
  }
}
