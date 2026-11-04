import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets/glass.dart';
import '../../data/comment_repository.dart';
import '../../data/comments_controller.dart';
import '../../data/models/comment.dart';
import '../../data/signature_bridge.dart';

Future<void> showCommentsSheet(
  BuildContext context, {
  required String awemeId,
  required SignatureBridge bridge,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.52),
    builder: (_) => CommentsSheet(awemeId: awemeId, bridge: bridge),
  );
}

class CommentsSheet extends StatefulWidget {
  const CommentsSheet({super.key, required this.awemeId, required this.bridge});

  final String awemeId;
  final SignatureBridge bridge;

  @override
  State<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<CommentsSheet> {
  late final CommentsController _controller;
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller = CommentsController(
      repository: CommentRepository(widget.bridge),
      awemeId: widget.awemeId,
    )..loadInitial();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients || _controller.loading) return;
    final position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - 320) {
      _controller.loadMore();
    }
  }

  /// A retry is the natural place to recover a bridge stuck on a risk-control
  /// page. Reloading the hidden page is harmless and gives the next request a
  /// fresh page context.
  Future<void> _retry() async {
    if (widget.bridge.status.value == SignatureBridgeStatus.error) {
      await widget.bridge.reloadPage();
    }
    await _controller.retry();
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.74;
    return SizedBox(
      height: height,
      child: GlassSurface(
        radius: 30,
        blur: 28,
        tint: Colors.black,
        opacity: 0.76,
        borderOpacity: 0.22,
        shadow: false,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Column(
          children: [
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: Colors.white.withValues(alpha: 0.22),
              ),
            ),
            const SizedBox(height: 6),
            ListenableBuilder(
              listenable: _controller,
              builder: (context, _) =>
                  _Header(controller: _controller, onRefresh: _retry),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: ListenableBuilder(
                listenable: _controller,
                builder: (context, _) => _buildBody(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '仅浏览评论 · 发布功能暂未开放',
              style: TextStyle(
                fontSize: 10,
                color: Colors.white.withValues(alpha: 0.3),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_controller.loading && _controller.items.isEmpty) {
      return _LoadingState(message: '正在加载评论');
    }
    if (_controller.error != null && _controller.items.isEmpty) {
      return _ErrorState(message: _controller.error!, onRetry: () => _retry());
    }
    if (_controller.items.isEmpty) {
      return _EmptyState(onRefresh: () => _retry());
    }

    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            controller: _scroll,
            padding: const EdgeInsets.only(top: 4, bottom: 12),
            itemCount: _controller.items.length,
            separatorBuilder: (_, _) => Divider(
              height: 1,
              thickness: 1,
              color: Colors.white.withValues(alpha: 0.055),
            ),
            itemBuilder: (context, index) {
              final comment = _controller.items[index];
              return _CommentTile(
                key: ValueKey(comment.cid),
                comment: comment,
                onReplyTap: comment.replyCount > 0
                    ? () => showGlassToast(context, '回复列表正在接入，先看主评论')
                    : null,
              );
            },
          ),
        ),
        _LoadMoreFooter(controller: _controller),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller, required this.onRefresh});

  final CommentsController controller;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final count = controller.total;
    return Row(
      children: [
        Text(
          count > 0 ? '评论 ${formatCount(count)}' : '评论',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        if (controller.loading && controller.items.isNotEmpty) ...[
          const SizedBox(width: 10),
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.6,
              color: Colors.white54,
            ),
          ),
        ],
        const Spacer(),
        IconButton(
          tooltip: '刷新',
          visualDensity: VisualDensity.compact,
          onPressed: controller.loading ? null : onRefresh,
          icon: Icon(
            Icons.refresh_rounded,
            size: 20,
            color: Colors.white.withValues(alpha: 0.7),
          ),
        ),
        IconButton(
          tooltip: '关闭',
          visualDensity: VisualDensity.compact,
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded, size: 20),
        ),
      ],
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({super.key, required this.comment, this.onReplyTap});

  final Comment comment;
  final VoidCallback? onReplyTap;

  @override
  Widget build(BuildContext context) {
    final time = formatTimeAgo(comment.createTime);
    final meta = [
      if (time.isNotEmpty) time,
      if (comment.ipLabel.isNotEmpty) comment.ipLabel,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CommentAvatar(url: comment.user.avatarUrl),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  comment.user.nickname.isEmpty
                      ? '抖音用户'
                      : comment.user.nickname,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.58),
                  ),
                ),
                const SizedBox(height: 3),
                if (comment.text.isNotEmpty)
                  Text(
                    comment.text,
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.45,
                      color: Colors.white.withValues(alpha: 0.92),
                    ),
                  ),
                if (comment.mediaUrl != null) ...[
                  if (comment.text.isNotEmpty) const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      comment.mediaUrl!,
                      width: 120,
                      height: 120,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                ],
                if (comment.text.isEmpty && comment.mediaUrl == null)
                  Text(
                    '[评论内容不可见]',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.white.withValues(alpha: 0.35),
                    ),
                  ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: Colors.white.withValues(alpha: 0.36),
                        ),
                      ),
                    ),
                    Icon(
                      Icons.favorite_border_rounded,
                      size: 13,
                      color: Colors.white.withValues(alpha: 0.42),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      formatCount(comment.diggCount),
                      style: TextStyle(
                        fontSize: 10.5,
                        color: Colors.white.withValues(alpha: 0.42),
                      ),
                    ),
                    if (onReplyTap != null) ...[
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: onReplyTap,
                        behavior: HitTestBehavior.opaque,
                        child: Text(
                          '共 ${formatCount(comment.replyCount)} 条回复',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: AppColors.cyan.withValues(alpha: 0.85),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentAvatar extends StatelessWidget {
  const _CommentAvatar({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.45),
            Colors.white.withValues(alpha: 0.1),
          ],
        ),
      ),
      child: ClipOval(
        child: url.isEmpty
            ? _fallback()
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _fallback(),
              ),
      ),
    );
  }

  Widget _fallback() {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [AppColors.violet, AppColors.pink]),
      ),
      child: Icon(Icons.person_rounded, size: 18, color: Colors.white),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const GlassLoading(size: 22),
          const SizedBox(height: 12),
          Text(
            message,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 30,
              color: AppColors.rose,
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: Colors.white.withValues(alpha: 0.65),
              ),
            ),
            const SizedBox(height: 14),
            GlassButton(
              label: '重试',
              icon: Icons.refresh_rounded,
              expand: false,
              onTap: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.chat_bubble_outline_rounded,
            size: 30,
            color: Colors.white.withValues(alpha: 0.35),
          ),
          const SizedBox(height: 10),
          Text(
            '还没有评论',
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 14),
          GlassButton(
            label: '刷新',
            icon: Icons.refresh_rounded,
            expand: false,
            onTap: onRefresh,
          ),
        ],
      ),
    );
  }
}

class _LoadMoreFooter extends StatelessWidget {
  const _LoadMoreFooter({required this.controller});

  final CommentsController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.items.isEmpty) return const SizedBox.shrink();
    Widget child;
    if (controller.loadingMore) {
      child = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const GlassLoading(size: 14),
          const SizedBox(width: 8),
          Text(
            '加载更多评论',
            style: TextStyle(
              fontSize: 10.5,
              color: Colors.white.withValues(alpha: 0.45),
            ),
          ),
        ],
      );
    } else if (controller.loadMoreError != null) {
      child = GestureDetector(
        onTap: controller.retryLoadMore,
        behavior: HitTestBehavior.opaque,
        child: Text(
          '加载失败 · 点击重试',
          style: TextStyle(
            fontSize: 10.5,
            color: AppColors.rose.withValues(alpha: 0.9),
          ),
        ),
      );
    } else if (!controller.hasMore) {
      child = Text(
        '没有更多评论了',
        style: TextStyle(
          fontSize: 10.5,
          color: Colors.white.withValues(alpha: 0.3),
        ),
      );
    } else {
      child = const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Center(child: child),
    );
  }
}
