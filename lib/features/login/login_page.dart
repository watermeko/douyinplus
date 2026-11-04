import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/liquid_background.dart';
import '../../data/app_controller.dart';
import 'dev_cookie_import_page.dart';
import 'login_webview_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _openingLogin = false;

  Future<void> _openLogin() async {
    if (_openingLogin) return;
    setState(() => _openingLogin = true);
    final cookies = await Navigator.of(context).push<Map<String, String>>(
      MaterialPageRoute(builder: (_) => const LoginWebViewPage()),
    );
    if (!mounted) return;
    setState(() => _openingLogin = false);
    if (cookies != null && cookies.isNotEmpty) {
      await context.read<AppController>().completeLogin(cookies);
    }
  }

  void _openDevImport() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const DevCookieImportPage()));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final size = MediaQuery.sizeOf(context);
    final cardWidth = size.width > 460 ? 420.0 : size.width - 48;

    return Scaffold(
      body: LiquidBackground(
        child: SafeArea(
          child: Stack(
            children: [
              Positioned(
                top: 14,
                left: 20,
                child: _TopChip(text: 'LIQUID GLASS · v0.1'),
              ),
              Positioned(
                top: 14,
                right: 20,
                child: GlassSurface(
                  radius: 999,
                  blur: 14,
                  opacity: 0.1,
                  shadow: false,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.cyan,
                          boxShadow: [
                            BoxShadow(color: AppColors.cyan, blurRadius: 8),
                          ],
                        ),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        'BETA',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.4,
                          color: Colors.white.withValues(alpha: 0.72),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Center(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) {
                    return Opacity(
                      opacity: value,
                      child: Transform.translate(
                        offset: Offset(0, 28 * (1 - value)),
                        child: child,
                      ),
                    );
                  },
                  child: SizedBox(
                    width: cardWidth,
                    child: GlassSurface(
                      radius: 34,
                      blur: 26,
                      opacity: 0.16,
                      borderOpacity: 0.3,
                      glow: true,
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const _AppMark(),
                          const SizedBox(height: 20),
                          const Text(
                            'DouyinPlus',
                            style: TextStyle(
                              fontSize: 29,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.8,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            '你的推荐流，换一种打开方式',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white.withValues(alpha: 0.58),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            '登录抖音账号后即可浏览推荐视频。\n账号信息仅加密保存在本机。',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.55,
                              color: Colors.white.withValues(alpha: 0.48),
                            ),
                          ),
                          if (app.error != null && app.error!.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            GlassSurface(
                              radius: 16,
                              blur: 12,
                              opacity: 0.06,
                              shadow: false,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.info_outline_rounded,
                                    size: 17,
                                    color: AppColors.rose,
                                  ),
                                  const SizedBox(width: 9),
                                  Expanded(
                                    child: Text(
                                      app.error!,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        height: 1.4,
                                        color: Colors.white.withValues(
                                          alpha: 0.66,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 24),
                          GlassButton(
                            label: '登录抖音账号',
                            icon: Icons.qr_code_scanner_rounded,
                            primary: true,
                            loading: _openingLogin,
                            onTap: _openingLogin ? null : _openLogin,
                          ),
                          const SizedBox(height: 14),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.lock_outline_rounded,
                                size: 13,
                                color: Colors.white.withValues(alpha: 0.35),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '使用抖音官方网页登录',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.white.withValues(alpha: 0.38),
                                ),
                              ),
                            ],
                          ),
                          if (kDebugMode) ...[
                            const SizedBox(height: 18),
                            Container(
                              height: 1,
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                            const SizedBox(height: 6),
                            TextButton(
                              onPressed: _openDevImport,
                              child: Text(
                                '开发调试 · 导入 Cookie',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withValues(alpha: 0.42),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 24,
                right: 24,
                bottom: 20,
                child: Text(
                  '非官方客户端 · 仅供学习研究\n视频与内容版权归原作者及抖音所有',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.6,
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopChip extends StatelessWidget {
  const _TopChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      radius: 999,
      blur: 14,
      opacity: 0.1,
      shadow: false,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: Colors.white.withValues(alpha: 0.68),
        ),
      ),
    );
  }
}

class _AppMark extends StatelessWidget {
  const _AppMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 78,
      height: 78,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.28),
            Colors.white.withValues(alpha: 0.06),
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: AppColors.pink.withValues(alpha: 0.26),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: AppColors.violet.withValues(alpha: 0.22),
            blurRadius: 40,
            spreadRadius: -8,
            offset: const Offset(-8, -4),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.white, Color(0xFFFFC2D6)],
            ).createShader(bounds),
            child: const Icon(
              Icons.graphic_eq_rounded,
              size: 40,
              color: Colors.white,
            ),
          ),
          Positioned(
            right: 17,
            bottom: 18,
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.pink,
                boxShadow: [BoxShadow(color: AppColors.pink, blurRadius: 10)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
