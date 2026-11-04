import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Animated, softly refracting gradient field used behind glass surfaces.
class LiquidBackground extends StatefulWidget {
  const LiquidBackground({super.key, this.child, this.animate = true});

  final Widget? child;
  final bool animate;

  @override
  State<LiquidBackground> createState() => _LiquidBackgroundState();
}

class _LiquidBackgroundState extends State<LiquidBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 26),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _controller.repeat();
    } else {
      _controller.value = 0.35;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value * math.pi * 2;
          return Stack(
            fit: StackFit.expand,
            children: [
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF05060D),
                      Color(0xFF0B0818),
                      Color(0xFF12091A),
                      Color(0xFF070A12),
                    ],
                    stops: [0, 0.38, 0.7, 1],
                  ),
                ),
              ),
              Positioned(
                left: -size.width * 0.35 + math.sin(t * 0.7) * 36,
                top: -size.height * 0.1 + math.cos(t * 0.5) * 30,
                width: size.width * 1.05,
                height: size.width * 1.05,
                child: _blob(AppColors.violet.withValues(alpha: 0.52)),
              ),
              Positioned(
                right: -size.width * 0.45 + math.cos(t * 0.6) * 42,
                top: size.height * 0.16 + math.sin(t * 0.4) * 44,
                width: size.width * 0.95,
                height: size.width * 0.95,
                child: _blob(AppColors.pink.withValues(alpha: 0.42)),
              ),
              Positioned(
                left: -size.width * 0.2 + math.cos(t * 0.5) * 50,
                bottom: -size.height * 0.16 + math.sin(t * 0.8) * 34,
                width: size.width * 0.9,
                height: size.width * 0.9,
                child: _blob(AppColors.cyan.withValues(alpha: 0.26)),
              ),
              Positioned(
                right: -size.width * 0.12 + math.sin(t * 0.9) * 26,
                bottom: size.height * 0.04 + math.cos(t * 0.3) * 30,
                width: size.width * 0.55,
                height: size.width * 0.55,
                child: _blob(AppColors.amber.withValues(alpha: 0.18)),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment.center,
                        radius: 1.05,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.28),
                          Colors.black.withValues(alpha: 0.62),
                        ],
                        stops: const [0, 0.62, 1],
                      ),
                    ),
                  ),
                ),
              ),
              if (widget.child != null) widget.child!,
            ],
          );
        },
      ),
    );
  }

  Widget _blob(Color color) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
          stops: const [0, 1],
        ),
      ),
    );
  }
}
