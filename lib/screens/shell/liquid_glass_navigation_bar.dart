import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../theme/app_design_system.dart';

// 移动端液态玻璃底部导航栏
class LiquidGlassNavigationBar extends StatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  const LiquidGlassNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  @override
  State<LiquidGlassNavigationBar> createState() =>
      _LiquidGlassNavigationBarState();
}

class _LiquidGlassNavigationBarState extends State<LiquidGlassNavigationBar> {
  Future<ui.FragmentProgram>? _glassProgram;
  ui.FragmentShader? _barShader;
  ui.FragmentShader? _indicatorShader;
  ui.ImageFilter? _barFilter;
  ui.ImageFilter? _indicatorFilter;

  @override
  void initState() {
    super.initState();
    if (ui.ImageFilter.isShaderFilterSupported) {
      _glassProgram = ui.FragmentProgram.fromAsset('shaders/liquid_glass.frag');
    } else {
      _barFilter = ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14);
      _indicatorFilter = ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10);
    }
  }

  @override
  void dispose() {
    _barShader?.dispose();
    _indicatorShader?.dispose();
    super.dispose();
  }

  static const _items = [
    (Icons.map_outlined, Icons.map_rounded, '地图库'),
    (Icons.swap_horiz_rounded, Icons.sync_alt_rounded, '传输'),
    (Icons.tune_outlined, Icons.tune_rounded, '设置'),
  ];

  @override
  Widget build(BuildContext context) {
    if (!ui.ImageFilter.isShaderFilterSupported) {
      return _buildBar(context);
    }
    return FutureBuilder<ui.FragmentProgram>(
      future: _glassProgram,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ErrorWidget.withDetails(
            message: 'Liquid glass shader failed to load',
            error: FlutterError('${snapshot.error}'),
          );
        }
        final program = snapshot.data;
        if (program == null) {
          // 着色器加载期间维持占位高度防止界面跳动
          return const SizedBox(
            height: AppBreakpoints.mobileBottomBarHeight +
                AppBreakpoints.mobileBottomBarMinimumSafeArea,
          );
        }
        _prepareFilters(program);
        return _buildBar(context);
      },
    );
  }

  void _prepareFilters(ui.FragmentProgram program) {
    if (_barFilter != null && _indicatorFilter != null) return;

    _barShader = program.fragmentShader()
      ..setFloat(2, -118)
      ..setFloat(3, 10)
      ..setFloat(4, 0.055)
      ..setFloat(5, 0.085);
    _indicatorShader = program.fragmentShader()
      ..setFloat(2, -82)
      ..setFloat(3, 7)
      ..setFloat(4, 0.075)
      ..setFloat(5, 0.105);
    _barFilter = ui.ImageFilter.shader(_barShader!);
    _indicatorFilter = ui.ImageFilter.shader(_indicatorShader!);
  }

  Widget _buildBar(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;

    return SafeArea(
      minimum: EdgeInsets.fromLTRB(
        12,
        0,
        12,
        AppBreakpoints.mobileBottomBarMinimumSafeArea,
      ),
      child: Align(
        alignment: Alignment.bottomCenter,
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 390),
          child: SizedBox(
            height: AppBreakpoints.mobileBottomBarHeight,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(25),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  BackdropFilter(
                    filter: _barFilter!,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: (isDark ? const Color(0xFF101418) : Colors.white)
                            .withValues(alpha: isDark ? 0.24 : 0.11),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white
                                .withValues(alpha: isDark ? 0.10 : 0.26),
                            primary.withValues(alpha: isDark ? 0.06 : 0.035),
                            Colors.black
                                .withValues(alpha: isDark ? 0.10 : 0.025),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black
                                .withValues(alpha: isDark ? 0.34 : 0.16),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _LiquidGlassRimPainter(
                          primary: primary,
                          isDark: isDark,
                        ),
                      ),
                    ),
                  ),
                  AnimatedAlign(
                    alignment: Alignment(-1.0 + widget.selectedIndex, 0),
                    duration: AppMotion.panel,
                    curve: AppMotion.enter,
                    child: FractionallySizedBox(
                      widthFactor: 1 / _items.length,
                      heightFactor: 1,
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: _LiquidGlassIndicator(
                          filter: _indicatorFilter!,
                          primary: primary,
                          isDark: isDark,
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (var index = 0; index < _items.length; index++)
                        Expanded(
                          child: _LiquidGlassNavigationItem(
                            icon: _items[index].$1,
                            selectedIcon: _items[index].$2,
                            label: _items[index].$3,
                            selected: widget.selectedIndex == index,
                            primary: primary,
                            onTap: () => widget.onDestinationSelected(index),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LiquidGlassIndicator extends StatelessWidget {
  final ui.ImageFilter filter;
  final Color primary;
  final bool isDark;

  const _LiquidGlassIndicator({
    required this.filter,
    required this.primary,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        fit: StackFit.expand,
        children: [
          BackdropFilter(
            filter: filter,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: primary.withValues(alpha: isDark ? 0.08 : 0.045),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: isDark ? 0.18 : 0.34),
                    primary.withValues(alpha: isDark ? 0.12 : 0.08),
                    Colors.black.withValues(alpha: isDark ? 0.12 : 0.035),
                  ],
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: CustomPaint(
              painter: _LiquidGlassRimPainter(
                primary: primary,
                isDark: isDark,
                indicator: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiquidGlassNavigationItem extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final Color primary;
  final VoidCallback onTap;

  const _LiquidGlassNavigationItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.primary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const muted = Colors.white;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          height: AppBreakpoints.mobileBottomBarHeight,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(selected ? selectedIcon : icon,
                  size: 22, color: selected ? primary : muted),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  height: 1,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? primary : muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LiquidGlassRimPainter extends CustomPainter {
  final Color primary;
  final bool isDark;
  final bool indicator;

  const _LiquidGlassRimPainter({
    required this.primary,
    required this.isDark,
    this.indicator = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final radius = Radius.circular(size.height * (indicator ? 0.38 : 0.36));
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = indicator ? 1.1 : 1.0
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(
              alpha:
                  indicator ? (isDark ? 0.40 : 0.56) : (isDark ? 0.30 : 0.46)),
          const Color(0xFF78E7FF).withValues(alpha: isDark ? 0.22 : 0.17),
          primary.withValues(alpha: isDark ? 0.23 : 0.15),
          const Color(0xFFFF8FC8).withValues(alpha: isDark ? 0.16 : 0.10),
          Colors.white.withValues(alpha: isDark ? 0.08 : 0.14),
        ],
      ).createShader(rect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(0.5), radius),
      edge,
    );

    final topRim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = indicator ? 1.0 : 0.9
      ..color = Colors.white.withValues(
          alpha: indicator ? (isDark ? 0.24 : 0.38) : (isDark ? 0.16 : 0.28));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect.deflate(indicator ? 2.0 : 1.5),
        Radius.circular(size.height * (indicator ? 0.32 : 0.31)),
      ),
      topRim,
    );

    final bottomRim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = Colors.black.withValues(alpha: isDark ? 0.30 : 0.10);
    canvas.drawArc(
      Rect.fromLTWH(
        size.width * 0.08,
        size.height * 0.25,
        size.width * 0.84,
        size.height * 1.30,
      ),
      0.25,
      2.65,
      false,
      bottomRim,
    );
  }

  @override
  bool shouldRepaint(covariant _LiquidGlassRimPainter oldDelegate) =>
      oldDelegate.primary != primary ||
      oldDelegate.isDark != isDark ||
      oldDelegate.indicator != indicator;
}
