import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'cookie_bridge.dart';
import 'douyin_api.dart';
import 'session_store.dart';
import 'signed_client.dart';

export 'signed_client.dart';

enum SignatureBridgeStatus { idle, loading, ready, error }

/// Runs signed Douyin requests through a hidden, logged-in WebView.
///
/// The WebView loads the official page, so `webmssdk` wraps `XMLHttpRequest`
/// and appends `msToken` / `a_bogus` automatically. Requests are serialized and
/// restricted to a small path allowlist.
class SignatureBridge implements SignedClient {
  SignatureBridge({
    this.pageUrl = 'https://www.douyin.com/?recommend=1',
    this.sessionStore,
  });

  static const _channelName = 'DpBridge';
  static const _readyTimeout = Duration(seconds: 25);
  static const _requestTimeout = Duration(seconds: 25);
  static const _minRequestGap = Duration(milliseconds: 250);

  static const _allowedPaths = <String>{
    '/aweme/v1/web/comment/list/',
    '/aweme/v1/web/comment/list/reply/',
    '/aweme/v1/web/aweme/detail/',
    '/aweme/v1/web/commit/item/digg/',
    '/aweme/v1/web/aweme/collect/',
  };

  final String pageUrl;
  final SessionStore? sessionStore;

  final ValueNotifier<SignatureBridgeStatus> status = ValueNotifier(
    SignatureBridgeStatus.idle,
  );
  final ValueNotifier<String?> lastError = ValueNotifier(null);

  WebViewController? _controller;
  Future<WebViewController>? _attachFuture;
  Future<void> _queue = Future<void>.value();
  final Map<int, Completer<SignatureResponse>> _pending =
      <int, Completer<SignatureResponse>>{};
  Completer<void>? _readyCompleter;
  bool _pageReady = false;
  bool _disposed = false;
  int _nextId = 0;
  DateTime? _lastRequestFinishedAt;

  bool get pageReady => _pageReady;

  Future<WebViewController> attach() {
    if (_disposed) {
      return Future<WebViewController>.error(StateError('SignatureBridge 已释放'));
    }
    final cached = _attachFuture;
    if (cached != null) return cached;
    final future = _createController();
    _attachFuture = future;
    return future;
  }

  Future<WebViewController> _createController() async {
    status.value = SignatureBridgeStatus.loading;
    final controller = WebViewController();
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setBackgroundColor(const Color(0xFF05060D));
    await controller.setUserAgent(kDouyinUserAgent);
    await controller.addJavaScriptChannel(
      _channelName,
      onMessageReceived: _handleMessage,
    );
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onPageStarted: (_) {
          _pageReady = false;
          status.value = SignatureBridgeStatus.loading;
        },
        onPageFinished: (url) {
          unawaited(_handlePageFinished(url));
        },
        onWebResourceError: (error) {
          if (error.isForMainFrame == true) {
            _handlePageError();
          }
        },
      ),
    );

    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      await platform.setAllowFileAccess(false);
      await platform.setMediaPlaybackRequiresUserGesture(true);
      await platform.setUseWideViewPort(true);
    }

    _controller = controller;
    await _injectSessionCookies();
    unawaited(controller.loadRequest(Uri.parse(pageUrl)));
    return controller;
  }

  Future<void> _injectSessionCookies() async {
    final store = sessionStore;
    if (store == null) return;
    Map<String, String> cookies;
    try {
      cookies = await store.loadCookies();
    } catch (_) {
      return;
    }
    if (cookies.isEmpty) return;

    final nativeOk = await CookieBridge.setDouyinCookies(cookies);
    if (nativeOk) return;

    // Non-Android fallback. The native path is preferred because it can keep
    // the cookies HttpOnly.
    final manager = WebViewCookieManager();
    for (final entry in cookies.entries) {
      final name = entry.key.trim();
      if (name.isEmpty || entry.value.isEmpty) continue;
      try {
        await manager.setCookie(
          WebViewCookie(
            name: name,
            value: entry.value,
            domain: '.douyin.com',
            path: '/',
          ),
        );
      } catch (_) {
        // Best effort; the signed page may still work anonymously.
      }
    }
  }

  Future<void> _handlePageFinished(String url) async {
    try {
      if (await _looksLikeRiskPage(url)) {
        _markRiskPage();
      } else {
        await _installHelper();
        _pageReady = true;
        lastError.value = null;
        status.value = SignatureBridgeStatus.ready;
        unawaited(_recheckRiskAfterSettle());
      }
    } catch (_) {
      _pageReady = false;
      lastError.value = '签名脚本注入失败';
      status.value = SignatureBridgeStatus.error;
    }
    _completeReadyWaiters();
  }

  /// Detect the verification intermediate page before trusting the page
  /// context. Requests made from that page cannot be signed correctly.
  Future<bool> _looksLikeRiskPage([String? url]) async {
    if (url != null) {
      final lowerUrl = url.toLowerCase();
      if (lowerUrl.contains('/verify') || lowerUrl.contains('captcha')) {
        return true;
      }
    }
    return _currentPageLooksLikeRisk();
  }

  Future<bool> _currentPageLooksLikeRisk() async {
    try {
      final title = await _controller?.runJavaScriptReturningResult(
        'document.title',
      );
      final text = title?.toString().toLowerCase() ?? '';
      return text.contains('验证') ||
          text.contains('captcha') ||
          text.contains('verify');
    } catch (_) {
      return false;
    }
  }

  /// The captcha page can replace the normal page without a new
  /// `onPageFinished` event. Check again shortly after the page settles and
  /// before every request so the UI fails fast instead of waiting 25 seconds.
  Future<void> _recheckRiskAfterSettle() async {
    await Future<void>.delayed(const Duration(seconds: 2));
    if (_disposed || !_pageReady) return;
    if (await _currentPageLooksLikeRisk()) _markRiskPage();
  }

  void _markRiskPage() {
    _pageReady = false;
    lastError.value = '需要完成抖音安全验证，请重新加载签名页';
    status.value = SignatureBridgeStatus.error;
    _completeReadyWaiters();
  }

  void _handlePageError() {
    _pageReady = false;
    lastError.value = '页面加载失败，请检查网络或登录态';
    status.value = SignatureBridgeStatus.error;
    _completeReadyWaiters();
  }

  void _completeReadyWaiters() {
    final completer = _readyCompleter;
    _readyCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  Future<void> _installHelper() async {
    final controller = _controller;
    if (controller == null) throw StateError('WebView 尚未初始化');
    await controller.runJavaScript(_helperScript);
  }

  @override
  Future<SignatureResponse> get(
    String path, [
    Map<String, String> params = const <String, String>{},
  ]) {
    return _enqueue('GET', path, params, null, 'xhr');
  }

  @override
  Future<SignatureResponse> post(
    String path, {
    Map<String, String> params = const <String, String>{},
    String? body,
  }) {
    return _enqueue('POST', path, params, body, 'xhr');
  }

  /// Experimental transport for diagnosing endpoints that hang under the
  /// webmssdk XHR wrapper. Not used by the normal comment/detail paths.
  Future<SignatureResponse> getWithFetch(
    String path, [
    Map<String, String> params = const <String, String>{},
  ]) {
    return _enqueue('GET', path, params, null, 'fetch');
  }

  Future<SignatureResponse> _enqueue(
    String method,
    String path,
    Map<String, String> params,
    String? body,
    String transport,
  ) {
    final result = Completer<SignatureResponse>();
    _queue = _queue.then((_) async {
      await _runRequest(method, path, params, body, transport, result);
    });
    return result.future;
  }

  Future<void> _runRequest(
    String method,
    String path,
    Map<String, String> params,
    String? body,
    String transport,
    Completer<SignatureResponse> result,
  ) async {
    if (_disposed) {
      result.complete(_error('签名桥已关闭'));
      return;
    }
    if (!_allowedPaths.contains(path)) {
      result.complete(_error('接口不在签名桥白名单内'));
      return;
    }

    final lastFinished = _lastRequestFinishedAt;
    if (lastFinished != null) {
      final elapsed = DateTime.now().difference(lastFinished);
      if (elapsed < _minRequestGap) {
        await Future<void>.delayed(_minRequestGap - elapsed);
      }
    }

    final started = DateTime.now();
    try {
      final ready = await _waitForReady();
      if (!ready) {
        result.complete(_error(lastError.value ?? '签名页面未就绪（等待超时）'));
        return;
      }

      final controller = _controller;
      if (controller == null) {
        result.complete(_error('WebView 尚未初始化'));
        return;
      }

      // Re-inject on each request; the helper is idempotent and covers SPA
      // navigations that do not emit another onPageFinished.
      await _installHelper();

      final id = ++_nextId;
      final responseCompleter = Completer<SignatureResponse>();
      _pending[id] = responseCompleter;

      final payload = jsonEncode(<String, dynamic>{
        'id': id,
        'method': method,
        'path': path,
        'params': <String, String>{...kDouyinBaseParams, ...params},
        'body': body,
        'transport': transport,
      });
      await controller.runJavaScript('window.__dpBridgeRequest($payload);');

      final response = await responseCompleter.future.timeout(
        _requestTimeout,
        onTimeout: () {
          _pending.remove(id);
          return _error('签名桥请求超时');
        },
      );
      final duration = DateTime.now().difference(started);
      final withDuration = SignatureResponse(
        statusCode: response.statusCode,
        body: response.body,
        error: response.error,
        duration: duration,
      );
      if (!withDuration.isSuccess) {
        lastError.value = withDuration.failureReason;
      }
      debugPrint(
        'SignatureBridge $method $path '
        'status=${withDuration.statusCode} '
        'bytes=${withDuration.body.length} '
        'ms=${duration.inMilliseconds}',
      );
      result.complete(withDuration);
    } catch (_) {
      result.complete(_error('签名桥请求失败'));
    } finally {
      _lastRequestFinishedAt = DateTime.now();
    }
  }

  Future<bool> _waitForReady() async {
    if (_pageReady) return true;
    final completer = _readyCompleter ??= Completer<void>();
    try {
      await completer.future.timeout(_readyTimeout);
    } on TimeoutException {
      return false;
    }
    return _pageReady;
  }

  void _handleMessage(JavaScriptMessage message) {
    try {
      final raw = message.message.trim();
      if (raw.isEmpty || raw.length > 2 * 1024 * 1024) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final id = (decoded['id'] as num?)?.toInt();
      if (id == null) return;
      final completer = _pending.remove(id);
      if (completer == null || completer.isCompleted) return;
      completer.complete(
        SignatureResponse(
          statusCode: (decoded['status'] as num?)?.toInt() ?? -1,
          body: decoded['body']?.toString() ?? '',
          error: decoded['error']?.toString(),
        ),
      );
    } catch (_) {
      // Malformed bridge message; callers will time out.
    }
  }

  SignatureResponse _error(String message) {
    return SignatureResponse(statusCode: -1, body: '', error: message);
  }

  Future<void> reloadPage() async {
    if (_disposed) return;
    final controller = _controller;
    if (controller == null) return;
    _pageReady = false;
    status.value = SignatureBridgeStatus.loading;
    await controller.loadRequest(Uri.parse(pageUrl));
  }

  void dispose() {
    _disposed = true;
    final error = _error('签名桥已关闭');
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.complete(error);
    }
    _pending.clear();
    _completeReadyWaiters();
    status.dispose();
    lastError.dispose();
    _controller = null;
    _attachFuture = null;
  }

  static const _helperScript = r'''
(function () {
  if (window.__dpBridgeRequest) return;
  window.__dpBridgeRequest = function (req) {
    var post = function (status, body, error) {
      try {
        window.DpBridge.postMessage(JSON.stringify({
          id: req.id,
          status: status,
          body: body || '',
          error: error || null
        }));
      } catch (_) {}
    };
    try {
      var params = req.params || {};
      var parts = [];
      for (var key in params) {
        if (Object.prototype.hasOwnProperty.call(params, key)) {
          parts.push(encodeURIComponent(key) + '=' + encodeURIComponent(params[key]));
        }
      }
      var url = req.path + (parts.length ? (req.path.indexOf('?') >= 0 ? '&' : '?') + parts.join('&') : '');
      if (req.transport === 'fetch') {
        fetch(url, { credentials: 'include' }).then(function (response) {
          return response.text().then(function (text) {
            post(response.status, text, null);
          });
        }).catch(function (error) {
          post(-1, '', 'network: ' + String(error));
        });
        return;
      }
      var xhr = new XMLHttpRequest();
      xhr.open(req.method || 'GET', url, true);
      xhr.withCredentials = true;
      if ((req.method || 'GET') === 'POST') {
        xhr.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded');
      }
      xhr.timeout = 20000;
      xhr.onload = function () {
        post(xhr.status, xhr.responseText, null);
      };
      xhr.onerror = function () {
        post(-1, '', 'network');
      };
      xhr.ontimeout = function () {
        post(-2, '', 'timeout');
      };
      xhr.send(req.body || null);
    } catch (e) {
      post(-3, '', String(e));
    }
  };
  try {
    document.querySelectorAll('video').forEach(function (v) {
      v.muted = true;
      v.pause();
    });
  } catch (_) {}
})();
''';
}

/// Hosts the hidden WebView. The controller must stay attached for the page
/// context and `webmssdk` to remain alive.
class SignatureBridgeHost extends StatefulWidget {
  const SignatureBridgeHost({
    super.key,
    required this.bridge,
    this.expanded = false,
    this.expandedSize = const Size(320, 480),
  });

  final SignatureBridge bridge;
  final bool expanded;
  final Size expandedSize;

  @override
  State<SignatureBridgeHost> createState() => _SignatureBridgeHostState();
}

class _SignatureBridgeHostState extends State<SignatureBridgeHost> {
  WebViewController? _controller;

  @override
  void initState() {
    super.initState();
    unawaited(_attach());
  }

  Future<void> _attach() async {
    try {
      final controller = await widget.bridge.attach();
      if (!mounted) return;
      setState(() => _controller = controller);
    } catch (_) {
      // The bridge exposes the error through lastError/status.
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final size = widget.expanded ? widget.expandedSize : const Size.square(1);
    return SizedBox(
      width: size.width,
      height: size.height,
      child: controller == null
          ? const ColoredBox(color: Color(0xFF05060D))
          : WebViewWidget(controller: controller),
    );
  }
}
