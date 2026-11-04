import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets/glass.dart';
import '../../data/models/aweme.dart';

class FeedVideoItem extends StatefulWidget {
  const FeedVideoItem({
    super.key,
    required this.aweme,
    required this.isActive,
    this.onAvatarTap,
    this.onAction,
  });

  final Aweme aweme;
  final bool isActive;
  final VoidCallback? onAvatarTap;
  final ValueChanged<String>? onAction;

  @override
  State<FeedVideoItem> createState() => _FeedVideoItemState();
}

class _FeedVideoItemState extends State<FeedVideoItem>
    with SingleTickerProviderStateMixin {
  VideoPlayerController? _controller;
  bool _initializing = false;
  bool _videoFailed = false;
  int _generation = 0;
  late final AnimationController _disc = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 9),
  );

  @override
  void initState() {
    super.initState();
    if (widget.isActive) {
      _initializeVideo();
    }
  }

  @override
  void didUpdateWidget(covariant FeedVideoItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      if (widget.isActive) {
        _initializeVideo();
      } else {
        _stopVideo();
      }
    }
  }

  @override
  void dispose() {
    _disc.dispose();
    _stopVideo(notify: false);
    super.dispose();
  }

  Future<void> _initializeVideo() async {
    if (_controller != null || _initializing) return;
    final urls = widget.aweme.video.allPlayUrls;
    if (urls.isEmpty) {
      if (mounted) setState(() => _videoFailed = true);
      return;
    }

    final generation = ++_generation;
    _initializing = true;
    if (mounted) setState(() => _videoFailed = false);

    for (final url in urls) {
      if (generation != _generation || !mounted) return;
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(url),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      try {
        await controller.initialize();
        debugPrint(
          'DouyinPlus video ${widget.aweme.id}: '
          '${controller.value.size.width.toInt()}x'
          '${controller.value.size.height.toInt()} '
          'aspect=${(controller.value.size.width / controller.value.size.height).toStringAsFixed(2)}',
        );
        await controller.setLooping(true);
        await controller.setVolume(1);
        await controller.play();
        controller.addListener(_syncDisc);
        if (!mounted || !widget.isActive || generation != _generation) {
          controller.removeListener(_syncDisc);
          await controller.dispose();
          if (generation == _generation) _initializing = false;
          return;
        }
        setState(() {
          _controller = controller;
          _videoFailed = false;
          _initializing = false;
        });
        _syncDisc();
        return;
      } catch (_) {
        await controller.dispose();
        if (generation != _generation) return;
      }
    }

    if (generation == _generation) {
      _initializing = false;
      if (mounted) setState(() => _videoFailed = true);
    }
  }

  void _syncDisc() {
    final playing = _controller?.value.isPlaying ?? false;
    if (playing && !_disc.isAnimating) {
      _disc.repeat();
    } else if (!playing && _disc.isAnimating) {
      _disc.stop();
    }
  }

  void _stopVideo({bool notify = true}) {
    _generation++;
    _initializing = false;
    _disc.stop();
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      controller.removeListener(_syncDisc);
      controller.dispose();
    }
    if (notify && mounted) setState(() {});
  }

  void _togglePlayback() {
    final controller = _controller;
    if (controller == null) {
      if (!_initializing && _videoFailed) {
        _videoFailed = false;
        _initializeVideo();
      }
      return;
    }
    final value = controller.value;
    if (value.isPlaying) {
      controller.pause();
    } else {
      controller.play();
    }
    setState(() {});
  }

  void _notifyAction(String action) {
    widget.onAction?.call(action);
  }

  @override
  Widget build(BuildContext context) {
    final aweme = widget.aweme;
    final bottomSafe = MediaQuery.paddingOf(context).bottom;

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _togglePlayback,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _VideoCanvas(
                  coverUrl: aweme.coverUrl,
                  videoWidth: aweme.video.width,
                  videoHeight: aweme.video.height,
                  controller: _controller,
                ),
                const _VideoScrims(),
                if (_initializing && _controller == null)
                  const Center(child: GlassLoading(size: 22)),
                if (_videoFailed)
                  Positioned(
                    top: 96,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: GlassSurface(
                        radius: 999,
                        blur: 16,
                        opacity: 0.12,
                        shadow: false,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        child: Text(
                          '视频加载失败 · 点击重试',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.white.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 14,
          right: 82,
          bottom: bottomSafe + 34,
          child: _DescriptionText(desc: aweme.desc),
        ),
        Positioned(
          right: 8,
          bottom: bottomSafe + 140,
          child: _ActionRail(
            aweme: aweme,
            disc: _disc,
            onAvatarTap: widget.onAvatarTap,
            onAction: _notifyAction,
          ),
        ),
        if (_controller != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: bottomSafe + 12,
            child: _ProgressBar(controller: _controller!),
          ),
        if (aweme.isImagePost)
          Positioned(
            top: 92,
            left: 16,
            child: GlassSurface(
              radius: 999,
              blur: 14,
              opacity: 0.12,
              shadow: false,
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              child: Text(
                '图文',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
            ),
          ),
        if (_controller != null)
          ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: _controller!,
            builder: (context, value, _) {
              final showPaused = !value.isPlaying;
              return Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: showPaused ? 1 : 0,
                    duration: const Duration(milliseconds: 220),
                    child: Center(
                      child: GlassSurface(
                        radius: 40,
                        blur: 20,
                        opacity: 0.16,
                        shadow: false,
                        child: const SizedBox(
                          width: 78,
                          height: 78,
                          child: Icon(
                            Icons.play_arrow_rounded,
                            size: 40,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.violet, Color(0xFF140B22), AppColors.pink],
          ),
        ),
      );
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, _, _) => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.violet, Color(0xFF140B22), AppColors.pink],
          ),
        ),
      ),
    );
  }
}

/// Stable video frame. The layout is decided from the width/height declared
/// in the feed response, so the correct aspect box exists from the very first
/// frame. The poster fills that same box and the video fades in on top of it
/// once the controller is ready — no resize after initialization.
class _VideoCanvas extends StatelessWidget {
  const _VideoCanvas({
    required this.coverUrl,
    required this.videoWidth,
    required this.videoHeight,
    required this.controller,
  });

  final String coverUrl;
  final int videoWidth;
  final int videoHeight;
  final VideoPlayerController? controller;

  double get _aspectRatio {
    if (videoWidth > 0 && videoHeight > 0) {
      final value = videoWidth / videoHeight;
      if (value.isFinite && value > 0) return value;
    }
    final size = controller?.value.size;
    if (size != null && size.width > 0 && size.height > 0) {
      return size.width / size.height;
    }
    return 9 / 16;
  }

  @override
  Widget build(BuildContext context) {
    // Portrait videos fill the screen. Landscape / square videos are shown
    // in full with a blurred backdrop, because cropping them with cover
    // hides a large part of the frame.
    final isWide = _aspectRatio > 0.9;

    if (!isWide) {
      return Stack(
        fit: StackFit.expand,
        children: [
          _Cover(url: coverUrl),
          if (controller != null)
            _FadeInVideo(
              key: ObjectKey(controller),
              controller: controller!,
              fit: BoxFit.cover,
            ),
        ],
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(child: _BlurredCover(url: coverUrl)),
        Positioned.fill(
          child: ColoredBox(color: Colors.black.withValues(alpha: 0.34)),
        ),
        Center(
          child: AspectRatio(
            aspectRatio: _aspectRatio,
            child: ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _Cover(url: coverUrl),
                  if (controller != null)
                    _FadeInVideo(
                      key: ObjectKey(controller),
                      controller: controller!,
                      fit: BoxFit.contain,
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Fades the video in over the poster without touching layout geometry.
class _FadeInVideo extends StatefulWidget {
  const _FadeInVideo({super.key, required this.controller, required this.fit});

  final VideoPlayerController controller;
  final BoxFit fit;

  @override
  State<_FadeInVideo> createState() => _FadeInVideoState();
}

class _FadeInVideoState extends State<_FadeInVideo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  )..forward();

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.controller.value.size;
    return FadeTransition(
      opacity: CurvedAnimation(parent: _fade, curve: Curves.easeOut),
      child: SizedBox.expand(
        child: FittedBox(
          fit: widget.fit,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: VideoPlayer(widget.controller),
          ),
        ),
      ),
    );
  }
}

class _BlurredCover extends StatelessWidget {
  const _BlurredCover({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return const ColoredBox(color: Colors.black);
    }
    return ClipRect(
      child: ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Transform.scale(
          scale: 1.14,
          child: Image.network(
            url,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.low,
            errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black),
          ),
        ),
      ),
    );
  }
}

class _VideoScrims extends StatelessWidget {
  const _VideoScrims();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0x99000000),
              Color(0x00000000),
              Color(0x00000000),
              Color(0xCC000000),
            ],
            stops: [0, 0.18, 0.6, 1],
          ),
        ),
      ),
    );
  }
}

class _DescriptionText extends StatelessWidget {
  const _DescriptionText({required this.desc});

  final String desc;

  @override
  Widget build(BuildContext context) {
    if (desc.isEmpty) return const SizedBox.shrink();
    final spans = <TextSpan>[];
    final matches = RegExp(r'#[^\s#]+').allMatches(desc);
    var cursor = 0;
    for (final match in matches) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: desc.substring(cursor, match.start)));
      }
      spans.add(
        TextSpan(
          text: match.group(0),
          style: TextStyle(
            color: AppColors.cyan.withValues(alpha: 0.95),
            fontWeight: FontWeight.w500,
          ),
        ),
      );
      cursor = match.end;
    }
    if (cursor < desc.length) {
      spans.add(TextSpan(text: desc.substring(cursor)));
    }

    return RichText(
      maxLines: 4,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: TextStyle(
          fontSize: 14,
          height: 1.42,
          fontWeight: FontWeight.w500,
          color: Colors.white.withValues(alpha: 0.94),
          shadows: const [
            Shadow(
              color: Color(0xCC000000),
              blurRadius: 10,
              offset: Offset(0, 1.5),
            ),
            Shadow(
              color: Color(0x99000000),
              blurRadius: 3,
              offset: Offset(0, 1),
            ),
          ],
        ),
        children: spans,
      ),
    );
  }
}

class _ActionRail extends StatelessWidget {
  const _ActionRail({
    required this.aweme,
    required this.disc,
    this.onAvatarTap,
    this.onAction,
  });

  final Aweme aweme;
  final AnimationController disc;
  final VoidCallback? onAvatarTap;
  final ValueChanged<String>? onAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassAvatar(
          imageUrl: aweme.author.avatarUrl,
          size: 48,
          onTap: onAvatarTap,
        ),
        const SizedBox(height: 16),
        GlassActionButton(
          icon: Icons.favorite_border_rounded,
          label: formatCount(aweme.statistics.diggCount),
          onTap: () => onAction?.call('点赞'),
        ),
        const SizedBox(height: 15),
        GlassActionButton(
          icon: Icons.mode_comment_outlined,
          label: formatCount(aweme.statistics.commentCount),
          onTap: () => onAction?.call('评论'),
        ),
        const SizedBox(height: 15),
        GlassActionButton(
          icon: Icons.star_border_rounded,
          label: formatCount(aweme.statistics.collectCount),
          onTap: () => onAction?.call('收藏'),
        ),
        const SizedBox(height: 15),
        GlassActionButton(
          icon: Icons.ios_share_rounded,
          label: formatCount(aweme.statistics.shareCount),
          onTap: () => onAction?.call('分享'),
        ),
        const SizedBox(height: 14),
        RotationTransition(
          turns: disc,
          child: GlassSurface(
            radius: 25,
            blur: 14,
            opacity: 0.13,
            shadow: false,
            child: const SizedBox(
              width: 50,
              height: 50,
              child: Icon(
                Icons.music_note_rounded,
                size: 21,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final duration = value.duration.inMilliseconds;
        final progress = duration <= 0
            ? 0.0
            : (value.position.inMilliseconds / duration).clamp(0.0, 1.0);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  formatTimer(value.position),
                  style: TextStyle(
                    fontSize: 9.5,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
                const Spacer(),
                Text(
                  formatTimer(value.duration),
                  style: TextStyle(
                    fontSize: 9.5,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: SizedBox(
                height: 3,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(color: Colors.white.withValues(alpha: 0.14)),
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: progress,
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AppColors.pink, AppColors.cyan],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
