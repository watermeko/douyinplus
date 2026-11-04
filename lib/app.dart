import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'core/widgets/glass.dart';
import 'core/widgets/liquid_background.dart';
import 'data/app_controller.dart';
import 'features/feed/feed_page.dart';
import 'features/login/login_page.dart';

class DouyinPlusApp extends StatelessWidget {
  const DouyinPlusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppController()..bootstrap(),
      child: MaterialApp(
        title: 'DouyinPlus',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: const RootGate(),
      ),
    );
  }
}

class RootGate extends StatelessWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final Widget child;
    switch (app.status) {
      case AuthStatus.checking:
        child = const _SplashPage(key: ValueKey('splash'));
      case AuthStatus.loggedOut:
        child = const LoginPage(key: ValueKey('login'));
      case AuthStatus.loggedIn:
        child = const FeedPage(key: ValueKey('feed'));
      case AuthStatus.error:
        child = _AuthErrorPage(
          key: const ValueKey('error'),
          message: app.error,
        );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 460),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: child,
    );
  }
}

class _SplashPage extends StatefulWidget {
  const _SplashPage({super.key});

  @override
  State<_SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<_SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LiquidBackground(
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ScaleTransition(
                  scale: Tween(begin: 0.94, end: 1.04).animate(
                    CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
                  ),
                  child: const GlassSurface(
                    radius: 34,
                    blur: 24,
                    glow: true,
                    opacity: 0.2,
                    child: SizedBox(
                      width: 96,
                      height: 96,
                      child: Icon(
                        Icons.graphic_eq_rounded,
                        size: 46,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'DouyinPlus',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '正在唤醒你的推荐流',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.55),
                  ),
                ),
                const SizedBox(height: 26),
                const GlassLoading(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthErrorPage extends StatelessWidget {
  const _AuthErrorPage({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppController>();
    return Scaffold(
      body: LiquidBackground(
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: GlassSurface(
                radius: 30,
                blur: 24,
                glow: true,
                opacity: 0.16,
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.pink.withValues(alpha: 0.18),
                        border: Border.all(
                          color: AppColors.pink.withValues(alpha: 0.45),
                        ),
                      ),
                      child: const Icon(
                        Icons.cloud_off_rounded,
                        color: AppColors.rose,
                        size: 28,
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      '连接失败',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      message ?? '无法连接到抖音服务，请检查网络后重试。',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.5,
                        color: Colors.white.withValues(alpha: 0.62),
                      ),
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: 220,
                      child: GlassButton(
                        label: '重试',
                        icon: Icons.refresh_rounded,
                        primary: true,
                        onTap: () => app.refreshProfile(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: app.logout,
                      child: Text(
                        '重新登录',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
