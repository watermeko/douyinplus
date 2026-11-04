/// Result of a request executed inside the signed web page context.
///
/// The body is kept only in memory for the current request. Callers must not
/// log or persist it: signed URLs and user content may be present.
class SignatureResponse {
  const SignatureResponse({
    required this.statusCode,
    required this.body,
    this.error,
    this.duration = Duration.zero,
  });

  final int statusCode;
  final String body;
  final String? error;
  final Duration duration;

  bool get isSuccess =>
      error == null && statusCode >= 200 && statusCode < 300 && body.isNotEmpty;

  String? get failureReason {
    if (error != null && error!.isNotEmpty) return error;
    if (statusCode == 401) return '登录态失效';
    if (statusCode == 403) return '风控或签名失效';
    if (statusCode >= 200 && statusCode < 300 && body.isEmpty) {
      return '空响应（签名或风控）';
    }
    if (statusCode < 200 || statusCode >= 300) return 'HTTP $statusCode';
    return null;
  }
}

/// Minimal transport used by repositories that need signed Douyin requests.
///
/// Keeping this interface separate from [SignatureBridge] lets the data layer
/// be tested with a fake client instead of a real hidden WebView.
abstract class SignedClient {
  Future<SignatureResponse> get(
    String path, [
    Map<String, String> params = const <String, String>{},
  ]);

  Future<SignatureResponse> post(
    String path, {
    Map<String, String> params = const <String, String>{},
    String? body,
  });
}
