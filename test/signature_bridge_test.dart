import 'package:douyinplus/data/signature_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SignatureResponse treats non-empty 2xx as success', () {
    const response = SignatureResponse(
      statusCode: 200,
      body: '{"status_code":0,"comments":[]}',
    );
    expect(response.isSuccess, isTrue);
    expect(response.failureReason, isNull);
  });

  test('SignatureResponse rejects empty 2xx body', () {
    const response = SignatureResponse(statusCode: 200, body: '');
    expect(response.isSuccess, isFalse);
    expect(response.failureReason, contains('空响应'));
  });

  test('SignatureResponse classifies risk, auth and transport errors', () {
    expect(
      const SignatureResponse(statusCode: 403, body: '').failureReason,
      contains('风控'),
    );
    expect(
      const SignatureResponse(statusCode: 401, body: '').failureReason,
      contains('登录态'),
    );
    expect(
      const SignatureResponse(
        statusCode: -1,
        body: '',
        error: 'network',
      ).failureReason,
      'network',
    );
    expect(
      const SignatureResponse(statusCode: 500, body: '').failureReason,
      'HTTP 500',
    );
  });
}
