import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../core/theme.dart';
import '../../core/widgets/glass.dart';
import '../../data/cookie_bridge.dart';
import '../../data/douyin_api.dart';

class LoginWebViewPage extends StatefulWidget {
  const LoginWebViewPage({super.key});

  @override
  State<LoginWebViewPage> createState() => _LoginWebViewPageState();
}

class _LoginWebViewPageState extends State<LoginWebViewPage> {
  late final WebViewController _webViewController;
  Timer? _pollTimer;
  bool _checking = false;
  bool _finishing = false;
  int _progress = 0;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppColors.background)
      ..setUserAgent(kDouyinUserAgent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (!mounted) return;
            setState(() => _progress = progress);
          },
          onPageStarted: (_) {
            if (!mounted) return;
            setState(() => _errorText = null);
          },
          onPageFinished: (_) async {
            await _fitDesktopLoginPage();
            await _checkSession();
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame != true || !mounted) return;
            setState(() {
              _errorText = '页面加载失败：${error.description}';
            });
          },
        ),
      )
      ..loadRequest(Uri.parse('https://www.douyin.com/?recommend=1'));

    final platform = _webViewController.platform;
    if (platform is AndroidWebViewController) {
      platform
        ..enableZoom(true)
        ..setUseWideViewPort(true);
    }

    _pollTimer = Timer.periodic(
      const Duration(milliseconds: 1800),
      (_) => _checkSession(),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _fitDesktopLoginPage() async {
    try {
      await _webViewController.runJavaScript('''
      (() => {
        if (document.getElementById('douyinplus-fit-style')) return;
        const style = document.createElement('style');
        style.id = 'douyinplus-fit-style';
        style.textContent = 'html { zoom: 0.72 !important; }';
        document.documentElement.appendChild(style);
      })();
    ''');
    } catch (_) {
      // The page may not be ready yet; the next onPageFinished retries.
    }
  }

  Future<void> _checkSession() async {
    if (_checking || _finishing) return;
    _checking = true;
    try {
      final cookies = await CookieBridge.readDouyinCookies();
      if ((cookies['sessionid'] ?? '').isNotEmpty) {
        await _finish(cookies);
      }
    } finally {
      _checking = false;
    }
  }

  Future<void> _finish(Map<String, String> cookies) async {
    if (_finishing) return;
    _finishing = true;
    _pollTimer?.cancel();
    if (!mounted) return;
    Navigator.of(context).pop(cookies);
  }

  Future<void> _handleBack() async {
    if (await _webViewController.canGoBack()) {
      await _webViewController.goBack();
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final progress = _progress / 100;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Stack(
          children: [
            WebViewWidget(controller: _webViewController),
            Positioned(
              top: topPadding + 8,
              left: 14,
              right: 14,
              child: Row(
                children: [
                  GlassIconButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    size: 42,
                    iconSize: 18,
                    onTap: _handleBack,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GlassSurface(
                      radius: 999,
                      blur: 18,
                      opacity: 0.12,
                      shadow: false,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 11,
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.verified_user_outlined,
                            size: 16,
                            color: AppColors.cyan,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '抖音账号登录',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.88),
                            ),
                          ),
                          const Spacer(),
                          if (progress < 0.99)
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                value: progress,
                                strokeWidth: 1.6,
                                color: Colors.white.withValues(alpha: 0.6),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GlassIconButton(
                    icon: Icons.refresh_rounded,
                    size: 42,
                    iconSize: 19,
                    onTap: () => _webViewController.reload(),
                  ),
                ],
              ),
            ),
            if (progress < 0.99)
              Positioned(
                top: topPadding + 58,
                left: 24,
                right: 24,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 2,
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                    valueColor: const AlwaysStoppedAnimation(AppColors.pink),
                  ),
                ),
              ),
            if (_errorText != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: GlassSurface(
                    radius: 26,
                    blur: 24,
                    opacity: 0.18,
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.wifi_off_rounded,
                          color: AppColors.rose,
                          size: 30,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _errorText!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.5,
                            color: Colors.white.withValues(alpha: 0.75),
                          ),
                        ),
                        const SizedBox(height: 16),
                        GlassButton(
                          label: '重新加载',
                          icon: Icons.refresh_rounded,
                          expand: false,
                          onTap: () {
                            setState(() => _errorText = null);
                            _webViewController.reload();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 24,
              right: 24,
              bottom: bottomPadding + 16,
              child: Center(
                child: GlassSurface(
                  radius: 999,
                  blur: 18,
                  opacity: 0.12,
                  shadow: false,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.lock_outline_rounded,
                        size: 14,
                        color: Colors.white.withValues(alpha: 0.48),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        '登录成功后会自动返回',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.white.withValues(alpha: 0.56),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
