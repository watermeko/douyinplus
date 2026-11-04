import 'package:douyinplus/data/interaction_repository.dart';
import 'package:douyinplus/data/signed_client.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSignedClient implements SignedClient {
  SignatureResponse response = const SignatureResponse(
    statusCode: 200,
    body: '{"status_code":0}',
  );
  String? lastPath;
  String? lastBody;

  @override
  Future<SignatureResponse> get(
    String path, [
    Map<String, String> params = const <String, String>{},
  ]) async {
    return response;
  }

  @override
  Future<SignatureResponse> post(
    String path, {
    Map<String, String> params = const <String, String>{},
    String? body,
  }) async {
    lastPath = path;
    lastBody = body;
    return response;
  }
}

void main() {
  test('setDigg sends the documented form body', () async {
    final client = _FakeSignedClient();
    final repository = InteractionRepository(client);

    await repository.setDigg(awemeId: '123', liked: true);
    expect(client.lastPath, '/aweme/v1/web/commit/item/digg/');
    expect(client.lastBody, 'aweme_id=123&item_type=0&type=1');

    await repository.setDigg(awemeId: '123', liked: false);
    expect(client.lastBody, 'aweme_id=123&item_type=0&type=0');
  });

  test('setCollect sends action and aweme type', () async {
    final client = _FakeSignedClient();
    final repository = InteractionRepository(client);

    await repository.setCollect(awemeId: '456', collected: true, awemeType: 2);
    expect(client.lastPath, '/aweme/v1/web/aweme/collect/');
    expect(client.lastBody, 'aweme_id=456&action=1&aweme_type=2');

    await repository.setCollect(awemeId: '456', collected: false);
    expect(client.lastBody, 'aweme_id=456&action=0&aweme_type=0');
  });

  test('maps risk-control and API errors to readable messages', () async {
    final client = _FakeSignedClient();
    final repository = InteractionRepository(client);

    client.response = const SignatureResponse(statusCode: 403, body: '');
    await expectLater(
      repository.setDigg(awemeId: '1', liked: true),
      throwsA(
        isA<InteractionException>()
            .having((e) => e.kind, 'kind', InteractionErrorKind.risk)
            .having(
              (e) => e.message,
              'message',
              '点赞被风控拦截，本次操作已撤销；若反复出现请重新登录',
            ),
      ),
    );

    client.response = const SignatureResponse(
      statusCode: 200,
      body: '{"status_code":4,"status_msg":"啊哦，服务器打瞌睡了"}',
    );
    await expectLater(
      repository.setDigg(awemeId: '1', liked: true),
      throwsA(
        isA<InteractionException>()
            .having((e) => e.kind, 'kind', InteractionErrorKind.api)
            .having((e) => e.message, 'message', '点赞失败：啊哦，服务器打瞌睡了'),
      ),
    );
  });

  test('bridge risk-control message is classified as risk', () async {
    final client = _FakeSignedClient()
      ..response = const SignatureResponse(
        statusCode: -1,
        body: '',
        error: '需要完成抖音安全验证，请重新登录后再试',
      );
    final repository = InteractionRepository(client);

    await expectLater(
      repository.setDigg(awemeId: '1', liked: true),
      throwsA(
        isA<InteractionException>().having(
          (e) => e.kind,
          'kind',
          InteractionErrorKind.risk,
        ),
      ),
    );
  });

  test('empty response is reported as an empty/risk response', () async {
    final client = _FakeSignedClient()
      ..response = const SignatureResponse(statusCode: 200, body: '');
    final repository = InteractionRepository(client);

    await expectLater(
      repository.setCollect(awemeId: '1', collected: true),
      throwsA(
        isA<InteractionException>()
            .having((e) => e.kind, 'kind', InteractionErrorKind.empty)
            .having((e) => e.message, 'message', '收藏接口返回空响应，请稍后重试'),
      ),
    );
  });
}
