import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as liquid;

import '../theme.dart';

/// A frosted, liquid-glass surface: background blur, tinted gradient,
/// a hairline specular border and an optional soft shadow.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.radius = 24,
    this.blur = 18,
    this.tint = Colors.white,
    this.opacity = 0.14,
    this.borderOpacity = 0.24,
    this.padding = EdgeInsets.zero,
    this.shadow = true,
    this.glow = false,
    this.highlight = true,
  });

  final Widget child;
  final double radius;
  final double blur;
  final Color tint;
  final double opacity;
  final double borderOpacity;
  final EdgeInsetsGeometry padding;
  final bool shadow;
  final bool glow;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    final isDarkTint = tint.computeLuminance() < 0.2;
    final topColor = tint.withValues(alpha: opacity);
    final bottomColor = tint.withValues(
      alpha: opacity * (isDarkTint ? 0.55 : 0.28),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          if (shadow)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          if (glow)
            BoxShadow(
              color: AppColors.violet.withValues(alpha: 0.18),
              blurRadius: 48,
              spreadRadius: -10,
              offset: const Offset(0, 10),
            ),
        ],
      ),
      child: liquid.AdaptiveGlass(
        shape: liquid.LiquidRoundedSuperellipse(borderRadius: radius),
        useOwnLayer: true,
        allowElevation: false,
        clipBehavior: Clip.antiAlias,
        settings: liquid.LiquidGlassSettings(
          glassColor: tint.withValues(alpha: opacity * 0.78),
          blur: blur * 0.45,
          thickness: 24,
          lightIntensity: 0.66,
          saturation: 1.45,
          refractiveIndex: 1.2,
          chromaticAberration: 0.008,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [topColor, bottomColor],
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: borderOpacity),
              width: 0.8,
            ),
          ),
          child: Stack(
            children: [
              Padding(padding: padding, child: child),
              if (highlight)
                Positioned(
                  left: radius * 0.9,
                  right: radius * 0.9,
                  top: 0,
                  child: IgnorePointer(
                    child: Container(
                      height: 1,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withValues(alpha: 0),
                            Colors.white.withValues(alpha: 0.55),
                            Colors.white.withValues(alpha: 0),
                          ],
                        ),
                      ),
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

class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.size = 46,
    this.iconSize = 21,
    this.iconColor = Colors.white,
    this.active = false,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;
  final Color iconColor;
  final bool active;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final accent = active ? AppColors.pink : Colors.white;
    final visual = ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accent.withValues(alpha: active ? 0.30 : 0.22),
                accent.withValues(alpha: 0.035),
              ],
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: active ? 0.38 : 0.26),
              width: 0.8,
            ),
          ),
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(
              icon,
              size: iconSize,
              color: active
                  ? AppColors.pink
                  : iconColor.withValues(alpha: 0.92),
            ),
          ),
        ),
      ),
    );

    Widget content = liquid.GlassButton.custom(
      onTap: onTap ?? () {},
      enabled: onTap != null,
      width: size,
      height: size,
      shape: const liquid.LiquidOval(),
      style: liquid.GlassButtonStyle.transparent,
      interactionScale: 0.88,
      stretch: 0.50,
      glowColor: accent.withValues(alpha: 0.18),
      glowOpacity: 0.6,
      glowRadius: 16,
      ambientBaseLight: 0,
      label: tooltip ?? '',
      child: visual,
    );

    content = DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: content,
    );

    if (tooltip == null) return content;
    return Tooltip(message: tooltip!, child: content);
  }
}

class GlassActionButton extends StatelessWidget {
  const GlassActionButton({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassIconButton(
          icon: icon,
          size: 50,
          iconSize: 23,
          active: active,
          onTap: onTap,
        ),
        const SizedBox(height: 5),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.88),
            fontSize: 11,
            fontWeight: FontWeight.w600,
            shadows: const [
              Shadow(
                color: Colors.black54,
                blurRadius: 8,
                offset: Offset(0, 1),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class GlassButton extends StatefulWidget {
  const GlassButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.primary = false,
    this.expand = true,
    this.loading = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool primary;
  final bool expand;
  final bool loading;

  @override
  State<GlassButton> createState() => _GlassButtonState();
}

class _GlassButtonState extends State<GlassButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null && !widget.loading;
    final radius = BorderRadius.circular(999);

    final child = Stack(
      alignment: Alignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          child: Row(
            mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.loading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              else if (widget.icon != null) ...[
                Icon(widget.icon, size: 19, color: Colors.white),
                const SizedBox(width: 9),
              ],
              Flexible(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
        ),
        Positioned(
          left: 20,
          right: 20,
          top: 0,
          child: IgnorePointer(
            child: Container(
              height: 20,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(
                      alpha: widget.primary ? 0.55 : 0.40,
                    ),
                    Colors.white.withValues(alpha: 0.08),
                    Colors.white.withValues(alpha: 0),
                  ],
                  stops: const [0, 0.14, 1],
                ),
              ),
            ),
          ),
        ),
      ],
    );

    final decoration = BoxDecoration(
      borderRadius: radius,
      gradient: widget.primary
          ? const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFF4D84), Color(0xFFFF2D6F), Color(0xFFD6155A)],
            )
          : null,
      border: widget.primary
          ? Border.all(color: Colors.white.withValues(alpha: 0.26), width: 0.8)
          : null,
      boxShadow: [
        if (widget.primary)
          BoxShadow(
            color: AppColors.pink.withValues(alpha: 0.32),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
      ],
    );

    final surface = widget.primary
        ? DecoratedBox(
            decoration: decoration,
            child: ClipRRect(borderRadius: radius, child: child),
          )
        : LayoutBuilder(
            builder: (context, constraints) {
              final width = widget.expand && constraints.hasBoundedWidth
                  ? constraints.maxWidth
                  : null;
              final visual = ClipRRect(
                borderRadius: radius,
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: radius,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.white.withValues(alpha: 0.30),
                          AppColors.violet.withValues(alpha: 0.16),
                        ],
                      ),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.34),
                        width: 0.8,
                      ),
                    ),
                    child: child,
                  ),
                ),
              );
              return liquid.GlassButton.custom(
                onTap: enabled ? widget.onTap! : () {},
                enabled: enabled,
                width: width,
                shape: const liquid.LiquidRoundedRectangle(borderRadius: 999),
                style: liquid.GlassButtonStyle.transparent,
                interactionScale: 0.94,
                stretch: 0.35,
                glowColor: Colors.white.withValues(alpha: 0.14),
                glowOpacity: 0.6,
                glowRadius: 22,
                ambientBaseLight: 0,
                child: visual,
              );
            },
          );

    if (!widget.primary) {
      return Opacity(
        opacity: enabled ? 1 : 0.55,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.30),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: AppColors.violet.withValues(alpha: 0.10),
                blurRadius: 26,
                spreadRadius: -10,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: surface,
        ),
      );
    }

    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _setPressed(true) : null,
        onTapCancel: enabled ? () => _setPressed(false) : null,
        onTapUp: enabled ? (_) => _setPressed(false) : null,
        onTap: enabled ? widget.onTap : null,
        child: AnimatedScale(
          scale: _pressed ? 0.94 : 1,
          duration: const Duration(milliseconds: 190),
          curve: Curves.easeOutBack,
          child: surface,
        ),
      ),
    );
  }
}

class GlassAvatar extends StatefulWidget {
  const GlassAvatar({super.key, this.imageUrl, this.size = 38, this.onTap});

  final String? imageUrl;
  final double size;
  final VoidCallback? onTap;

  @override
  State<GlassAvatar> createState() => _GlassAvatarState();
}

class _GlassAvatarState extends State<GlassAvatar> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (!mounted || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final imageUrl = widget.imageUrl;
    final avatar = ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: imageUrl != null && imageUrl.isNotEmpty
            ? Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _fallback(size),
              )
            : _fallback(size),
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null ? null : (_) => _setPressed(true),
      onTapCancel: widget.onTap == null ? null : () => _setPressed(false),
      onTapUp: widget.onTap == null ? null : (_) => _setPressed(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.88 : 1,
        duration: const Duration(milliseconds: 170),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: _pressed ? 0.85 : 0.55),
                Colors.white.withValues(alpha: _pressed ? 0.35 : 0.12),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
              if (_pressed)
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.28),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
            ],
          ),
          child: avatar,
        ),
      ),
    );
  }

  Widget _fallback(double size) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.violet, AppColors.pink],
        ),
      ),
      child: Icon(Icons.person_rounded, size: size * 0.55, color: Colors.white),
    );
  }
}

class GlassLoading extends StatelessWidget {
  const GlassLoading({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: Colors.white.withValues(alpha: 0.9),
      ),
    );
  }
}

void showGlassToast(BuildContext context, String message) {
  final overlay = Overlay.of(context, rootOverlay: true);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _GlassToast(
      message: message,
      onDone: () {
        if (entry.mounted) entry.remove();
      },
    ),
  );
  overlay.insert(entry);
}

class _GlassToast extends StatefulWidget {
  const _GlassToast({required this.message, required this.onDone});

  final String message;
  final VoidCallback onDone;

  @override
  State<_GlassToast> createState() => _GlassToastState();
}

class _GlassToastState extends State<_GlassToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller.forward();
    _timer = Timer(const Duration(milliseconds: 1600), () async {
      if (!mounted) return;
      await _controller.reverse();
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Positioned(
      left: 28,
      right: 28,
      bottom: bottom + 104,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final value = Curves.easeOutCubic.transform(_controller.value);
            return Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, 14 * (1 - value)),
                child: child,
              ),
            );
          },
          child: Center(
            child: GlassSurface(
              radius: 18,
              blur: 20,
              opacity: 0.2,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              shadow: false,
              child: Text(
                widget.message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
