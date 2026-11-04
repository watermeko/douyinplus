import 'package:douyinplus/data/comment_repository.dart';
import 'package:douyinplus/data/signed_client.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSignedClient implements SignedClient {
  SignatureResponse response = const SignatureResponse(
    statusCode: 200,
    body: '{"comments":[],"cursor":"0","has_more":0}',
  );
  String? lastPath;
  Map<String, String>? lastParams;

  @override
  Future<SignatureResponse> get(
    String path, [
    Map<String, String> params = const <String, String>{},
  ]) async {
    lastPath = path;
    lastParams = params;
    return response;
  }

  @override
  Future<SignatureResponse> post(
    String path, {
    Map<String, String> params = const <String, String>{},
    String? body,
  }) async {
    lastPath = path;
    lastParams = params;
    return response;
  }
}

void main() {
  test('fetchComments sends the documented query', () async {
    final client = _FakeSignedClient();
    final repository = CommentRepository(client);

    await repository.fetchComments(awemeId: '123', cursor: '20', count: 15);
    expect(client.lastPath, '/aweme/v1/web/comment/list/');
    expect(client.lastParams, <String, String>{
      'aweme_id': '123',
      'cursor': '20',
      'count': '15',
      'item_type': '0',
    });
  });

  test('bridge risk-control error is classified as risk', () async {
    final client = _FakeSignedClient()
      ..response = const SignatureResponse(
        statusCode: -1,
        body: '',
        error: '需要完成抖音安全验证，请重新登录后再试',
      );
    final repository = CommentRepository(client);

    await expectLater(
      repository.fetchComments(awemeId: '123'),
      throwsA(
        isA<CommentException>()
            .having((e) => e.kind, 'kind', CommentErrorKind.risk)
            .having(
              (e) => e.message,
              'message',
              '需要完成抖音安全验证，请重新登录后再试',
            ),
      ),
    );
  });

  test('bridge timeout stays a network error', () async {
    final client = _FakeSignedClient()
      ..response = const SignatureResponse(
        statusCode: -1,
        body: '',
        error: '签名桥请求超时',
      );
    final repository = CommentRepository(client);

    await expectLater(
      repository.fetchComments(awemeId: '123'),
      throwsA(
        isA<CommentException>().having(
          (e) => e.kind,
          'kind',
          CommentErrorKind.network,
        ),
      ),
    );
  });

  test('empty 200 body is reported as an empty response', () async {
    final client = _FakeSignedClient()
      ..response = const SignatureResponse(statusCode: 200, body: '');
    final repository = CommentRepository(client);

    await expectLater(
      repository.fetchComments(awemeId: '123'),
      throwsA(
        isA<CommentException>().having(
          (e) => e.kind,
          'kind',
          CommentErrorKind.empty,
        ),
      ),
    );
  });
}