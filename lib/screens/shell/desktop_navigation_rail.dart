import 'dart:ui' as ui;

import 'package:flutter/material.dart';

// 桌面端半透明毛玻璃侧边导航栏
class DesktopNavigationRail extends StatelessWidget {
  final int selectedIndex;
  final bool expanded;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onOpenAbout;

  const DesktopNavigationRail({
    super.key,
    required this.selectedIndex,
    required this.expanded,
    required this.onDestinationSelected,
    required this.onOpenAbout,
  });

  static const _destinations = [
    NavigationRailDestination(
      icon: Icon(Icons.map_outlined),
      selectedIcon: Icon(Icons.map_rounded),
      label: Text('地图库'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.swap_horiz_rounded),
      selectedIcon: Icon(Icons.sync_alt_rounded),
      label: Text('数据传输'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.tune_outlined),
      selectedIcon: Icon(Icons.tune_rounded),
      label: Text('设置'),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 3, sigmaY: 3),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: (isDark ? const Color(0xFF14181D) : Colors.white)
                .withValues(alpha: isDark ? 0.16 : 0.1),
          ),
          child: NavigationRail(
            backgroundColor: Colors.transparent,
            extended: expanded,
            selectedIndex: selectedIndex,
            onDestinationSelected: onDestinationSelected,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: expanded
                  ? const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _AppLogo(size: 30),
                        SizedBox(width: 10),
                        Text(
                          'Grenade Helper',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    )
                  : const Tooltip(
                      message: 'Grenade Helper',
                      child: _AppLogo(size: 32),
                    ),
            ),
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: IconButton(
                    tooltip: '关于',
                    icon: const Icon(Icons.info_outline_rounded),
                    onPressed: onOpenAbout,
                  ),
                ),
              ),
            ),
            destinations: _destinations,
          ),
        ),
      ),
    );
  }
}

class _AppLogo extends StatelessWidget {
  final double size;

  const _AppLogo({required this.size});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(7),
      child: Image.asset(
        'assets/icons/app_icon.webp',
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );
  }
}
