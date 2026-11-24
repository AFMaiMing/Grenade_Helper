import 'dart:math' as math;

import 'package:flutter/material.dart';

// 主窗口壳层慢速平移背景组件
class ShellPanningBackground extends StatefulWidget {
  const ShellPanningBackground({super.key});

  @override
  State<ShellPanningBackground> createState() => _ShellPanningBackgroundState();
}

class _ShellPanningBackgroundState extends State<ShellPanningBackground>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const int _sourceImageWidth = 3072;
  static const double _imageAspectRatio = 3072 / 2048;
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 28),
    )..repeat(reverse: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_controller.isAnimating) {
        _controller.repeat(reverse: true);
      }
    } else if (_controller.isAnimating) {
      _controller.stop(canceled: false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final assetPath = isDark
        ? 'assets/backgrounds/home_bg_dark.png'
        : 'assets/backgrounds/home_bg_light.png';
    final dpr = MediaQuery.devicePixelRatioOf(context);

    return RepaintBoundary(
      child: IgnorePointer(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final viewportWidth = constraints.maxWidth;
            final viewportHeight = constraints.maxHeight;
            final canvasWidth = math.max(
              viewportWidth * 1.35,
              viewportHeight * _imageAspectRatio,
            );
            final canvasHeight = canvasWidth / _imageAspectRatio;
            final maxDx = canvasWidth - viewportWidth;
            final dy = (viewportHeight - canvasHeight) / 2;
            final cacheWidth = math.min(
              _sourceImageWidth,
              math.max(1, (canvasWidth * dpr).round()),
            );

            return ClipRect(
              child: AnimatedBuilder(
                animation: _controller,
                child: OverflowBox(
                  alignment: Alignment.topLeft,
                  minWidth: canvasWidth,
                  maxWidth: canvasWidth,
                  minHeight: canvasHeight,
                  maxHeight: canvasHeight,
                  child: RepaintBoundary(
                    child: Image.asset(
                      assetPath,
                      width: canvasWidth,
                      height: canvasHeight,
                      cacheWidth: cacheWidth,
                      fit: BoxFit.fill,
                      filterQuality: FilterQuality.low,
                      gaplessPlayback: true,
                    ),
                  ),
                ),
                builder: (context, child) {
                  final dx = -maxDx * _controller.value;
                  return Transform.translate(
                    offset: Offset(dx, dy),
                    child: child,
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
