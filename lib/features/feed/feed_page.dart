import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/liquid_background.dart';
import '../../data/app_controller.dart';
import '../../data/feed_controller.dart';
import '../../data/interaction_repository.dart';
import '../../data/interactions_controller.dart';
import '../../data/models/aweme.dart';
import '../../data/signature_bridge.dart';
import '../debug/signature_bridge_debug_page.dart';
import 'comments_sheet.dart';
import 'feed_video_item.dart';

class FeedPage extends StatefulWidget {
  const FeedPage({super.key});

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  late final FeedController _feed;
  late final PageController _pageController;
  late final SignatureBridge _signatureBridge;
  late final InteractionsController _interactions;
  late final Listenable _refresh;
  int _current = 0;
  bool _commentsOpen = false;

  @override
  void initState() {
    super.initState();
    _feed = FeedController(context.read<AppController>().api)..loadInitial();
    _signatureBridge = context.read<AppController>().signatureBridge;
    _interactions = InteractionsController(
      gateway: InteractionRepository(_signatureBridge),
      enabled: kEnableInteractions,
    );
    _refresh = Listenable.merge(<Listenable>[_feed, _interactions]);
    _pageController = PageController();
    _feed.addListener(_hydrateCurrent);
  }

  @override
  void dispose() {
    _feed.removeListener(_hydrateCurrent);
    _pageController.dispose();
    _interactions.dispose();
    _feed.dispose();
    super.dispose();
  }

  /// Fetches the account's like / collect state for the visible video so the
  /// first tap sends the direction the user actually sees.
  void _hydrateCurrent() {
    if (_feed.items.isEmpty) return;
    final index = _current.clamp(0, _feed.items.length - 1);
    unawaited(_interactions.hydrate(_feed.items[index].id));
  }

  void _onPageChanged(int index) {
    setState(() => _current = index);
    _feed.setCurrentIndex(index);
    _hydrateCurrent();
    if (index >= _feed.items.length - 2) {
      _feed.loadMore();
    }
  }

  void _showActionHint(String action) {
    if (action == '评论') {
      _openComments();
      return;
    }
    showGlassToast(context, '$action功能将在下一版开放');
  }

  Future<void> _toggleLike(Aweme aweme) async {
    final error = await _interactions.toggleLike(aweme.id);
    if (error != null && mounted) showGlassToast(context, error);
  }

  Future<void> _toggleCollect(Aweme aweme) async {
    final error = await _interactions.toggleCollect(
      aweme.id,
      awemeType: aweme.awemeType,
    );
    if (error != null && mounted) showGlassToast(context, error);
  }

  Future<void> _openComments() async {
    if (_feed.items.isEmpty || _commentsOpen) return;
    final aweme = _feed.items[_current.clamp(0, _feed.items.length - 1)];
    setState(() => _commentsOpen = true);
    await showCommentsSheet(
      context,
      awemeId: aweme.id,
      bridge: _signatureBridge,
    );
    if (mounted) setState(() => _commentsOpen = false);
  }

  void _openProfileSheet() {
    final awemeId = _feed.items.isEmpty
        ? null
        : _feed.items[_current.clamp(0, _feed.items.length - 1)].id;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.42),
      builder: (_) => _ProfileSheet(debugAwemeId: awemeId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final topPadding = MediaQuery.paddingOf(context).top;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: Colors.black,
      body: ListenableBuilder(
        listenable: _refresh,
        builder: (context, _) {
          return Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                left: 0,
                top: 0,
                width: 1,
                height: 1,
                child: IgnorePointer(
                  child: SignatureBridgeHost(bridge: _signatureBridge),
                ),
              ),
              _buildBody(app),
              Positioned(
                top: topPadding + 8,
                right: 14,
                child: GlassAvatar(
                  imageUrl: app.profile?.avatarUrl,
                  size: 42,
                  onTap: _openProfileSheet,
                ),
              ),
              if (_feed.items.isNotEmpty && _feed.isLoadingMore)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: bottomPadding + 96,
                  child: Center(
                    child: GlassSurface(
                      radius: 999,
                      blur: 18,
                      opacity: 0.16,
                      shadow: false,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const GlassLoading(size: 14),
                          const SizedBox(width: 9),
                          Text(
                            '正在加载更多',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.white.withValues(alpha: 0.66),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (_feed.items.isNotEmpty &&
                  !_feed.isLoadingMore &&
                  _feed.error != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: bottomPadding + 96,
                  child: Center(
                    child: GestureDetector(
                      onTap: _feed.retry,
                      child: GlassSurface(
                        radius: 999,
                        blur: 18,
                        opacity: 0.16,
                        shadow: false,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 9,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.refresh_rounded,
                              size: 15,
                              color: AppColors.rose,
                            ),
                            const SizedBox(width: 7),
                            Text(
                              '加载失败 · 点击重试',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: Colors.white.withValues(alpha: 0.72),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBody(AppController app) {
    if (_feed.isLoading && _feed.items.isEmpty) {
      return const _FeedLoading();
    }
    if (_feed.items.isEmpty && _feed.error != null) {
      return _FeedError(
        message: _feed.error!,
        onRetry: _feed.loadInitial,
        onLogout: app.logout,
      );
    }
    if (_feed.items.isEmpty) {
      return _FeedEmpty(onRetry: _feed.loadInitial);
    }

    return PageView.builder(
      controller: _pageController,
      scrollDirection: Axis.vertical,
      physics: const PageScrollPhysics(),
      itemCount: _feed.items.length,
      onPageChanged: _onPageChanged,
      itemBuilder: (context, index) {
        final item = _feed.items[index];
        return FeedVideoItem(
          key: ValueKey(item.id),
          aweme: item,
          isActive: index == _current,
          paused: _commentsOpen,
          liked: _interactions.isLiked(item.id),
          collected: _interactions.isCollected(item.id),
          diggCount:
              item.statistics.diggCount + _interactions.likeDelta(item.id),
          collectCount:
              item.statistics.collectCount +
              _interactions.collectDelta(item.id),
          onAvatarTap: _openProfileSheet,
          onAction: _showActionHint,
          onLikeTap: () => _toggleLike(item),
          onCollectTap: () => _toggleCollect(item),
        );
      },
    );
  }
}

class _FeedLoading extends StatelessWidget {
  const _FeedLoading();

  @override
  Widget build(BuildContext context) {
    return LiquidBackground(
      child: Center(
        child: GlassSurface(
          radius: 30,
          blur: 24,
          opacity: 0.16,
          glow: true,
          padding: const EdgeInsets.fromLTRB(28, 26, 28, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 46,
                height: 46,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                '正在获取推荐视频',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 7),
              Text(
                '正在为你调取个性化推荐流',
                style: TextStyle(
                  fontSize: 11.5,
                  color: Colors.white.withValues(alpha: 0.46),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeedError extends StatelessWidget {
  const _FeedError({
    required this.message,
    required this.onRetry,
    required this.onLogout,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return LiquidBackground(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: GlassSurface(
            radius: 30,
            blur: 24,
            opacity: 0.16,
            glow: true,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.signal_wifi_statusbar_connected_no_internet_4_rounded,
                  color: AppColors.rose,
                  size: 34,
                ),
                const SizedBox(height: 14),
                const Text(
                  '推荐流加载失败',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: 220,
                  child: GlassButton(
                    label: '重试',
                    icon: Icons.refresh_rounded,
                    primary: true,
                    onTap: onRetry,
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: onLogout,
                  child: Text(
                    '重新登录',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FeedEmpty extends StatelessWidget {
  const _FeedEmpty({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return LiquidBackground(
      child: Center(
        child: GlassSurface(
          radius: 28,
          blur: 22,
          opacity: 0.14,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.video_library_outlined, size: 34),
              const SizedBox(height: 14),
              const Text(
                '暂时没有推荐内容',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: 200,
                child: GlassButton(
                  label: '再试一次',
                  icon: Icons.refresh_rounded,
                  onTap: onRetry,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileSheet extends StatelessWidget {
  const _ProfileSheet({this.debugAwemeId});

  final String? debugAwemeId;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final profile = app.profile;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(left: 14, right: 14, bottom: bottomPadding + 14),
      child: GlassSurface(
        radius: 32,
        blur: 28,
        tint: Colors.black,
        opacity: 0.52,
        borderOpacity: 0.22,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(99),
                  color: Colors.white.withValues(alpha: 0.22),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                GlassAvatar(imageUrl: profile?.avatarUrl, size: 62),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile?.nickname ?? '抖音用户',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        profile == null ? '抖音号 —' : '抖音号 ${profile.displayId}',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.white.withValues(alpha: 0.46),
                        ),
                      ),
                    ],
                  ),
                ),
                GlassIconButton(
                  icon: Icons.close_rounded,
                  size: 38,
                  iconSize: 18,
                  onTap: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            if (profile != null) ...[
              const SizedBox(height: 18),
              Row(
                children: [
                  _ProfileStat(
                    label: '关注',
                    value: formatCount(profile.followingCount),
                  ),
                  _ProfileStat(
                    label: '粉丝',
                    value: formatCount(profile.followerCount),
                  ),
                  _ProfileStat(
                    label: '作品',
                    value: formatCount(profile.awemeCount),
                  ),
                  _ProfileStat(
                    label: '获赞',
                    value: formatCount(profile.totalFavorited),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 18),
            FutureBuilder<Map<String, String>>(
              future: app.sessionStore.loadCookies(),
              builder: (context, snapshot) {
                final count = snapshot.data?.length ?? 0;
                return Row(
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      size: 15,
                      color: AppColors.cyan.withValues(alpha: 0.7),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      '本地加密保存 $count 项 Cookie',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.4),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: GlassButton(
                    label: '刷新登录信息',
                    icon: Icons.refresh_rounded,
                    onTap: () async {
                      await app.refreshProfile(silent: true);
                      if (context.mounted) {
                        showGlassToast(
                          context,
                          app.status == AuthStatus.loggedIn
                              ? '登录信息已刷新'
                              : (app.error ?? '刷新失败'),
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GlassButton(
                    label: '退出登录',
                    icon: Icons.logout_rounded,
                    primary: true,
                    onTap: () async {
                      await app.logout();
                      if (context.mounted) Navigator.of(context).pop();
                    },
                  ),
                ),
              ],
            ),
            if (kDebugMode) ...[
              const SizedBox(height: 10),
              GlassButton(
                label: '签名桥测试（Debug）',
                icon: Icons.terminal_rounded,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SignatureBridgeDebugPage(
                        initialAwemeId: debugAwemeId,
                      ),
                    ),
                  );
                },
              ),
            ],
            const SizedBox(height: 12),
            Text(
              '非官方客户端 · 数据仅保存在本机',
              style: TextStyle(
                fontSize: 10,
                color: Colors.white.withValues(alpha: 0.26),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileStat extends StatelessWidget {
  const _ProfileStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              color: Colors.white.withValues(alpha: 0.42),
            ),
          ),
        ],
      ),
    );
  }
}
