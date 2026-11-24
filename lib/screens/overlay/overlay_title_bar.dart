import 'package:flutter/material.dart';

import '../../models.dart';
import '../../services/settings_service.dart';
import '../../theme/app_design_system.dart';
import '../../widgets/grenade_type_icon.dart';
import 'overlay_hotkey_helper.dart';
import 'overlay_window_shared.dart';

/// 悬浮窗顶部标题栏，包含地图标识、道具标题、速度指示、类型过滤与关闭按钮。
class OverlayTitleBar extends StatelessWidget {
  final String mapName;
  final String grenadeTitle;
  final int navSpeedLevel;
  final Set<int> activeFilters;
  final Map<HotkeyAction, HotkeyConfig> hotkeys;
  final VoidCallback onStartDrag;
  final VoidCallback onClose;
  final ValueChanged<int> onToggleFilter;

  const OverlayTitleBar({
    super.key,
    required this.mapName,
    required this.grenadeTitle,
    required this.navSpeedLevel,
    required this.activeFilters,
    required this.hotkeys,
    required this.onStartDrag,
    required this.onClose,
    required this.onToggleFilter,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: (_) => onStartDrag(),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                mapName,
                style: const TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                grenadeTitle,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _SpeedIndicator(navSpeedLevel: navSpeedLevel, hotkeys: hotkeys),
            const SizedBox(width: 8),
            _FilterButtons(
              activeFilters: activeFilters,
              onToggleFilter: onToggleFilter,
            ),
            const SizedBox(width: 12),
            OverlayWindowButton(
              icon: Icons.remove,
              onTap: onClose,
              color: Colors.grey,
            ),
          ],
        ),
      ),
    );
  }
}

class _SpeedIndicator extends StatelessWidget {
  final int navSpeedLevel;
  final Map<HotkeyAction, HotkeyConfig> hotkeys;

  const _SpeedIndicator({
    required this.navSpeedLevel,
    required this.hotkeys,
  });

  @override
  Widget build(BuildContext context) {
    final increaseSpeedKey =
        overlayHotkeyLabel(hotkeys, HotkeyAction.increaseNavSpeed);
    final decreaseSpeedKey =
        overlayHotkeyLabel(hotkeys, HotkeyAction.decreaseNavSpeed);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: Colors.orange.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Text(
        '速度:$navSpeedLevel/5 ($decreaseSpeedKey/$increaseSpeedKey)',
        style: const TextStyle(
          color: Colors.orange,
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _FilterButtons extends StatelessWidget {
  final Set<int> activeFilters;
  final ValueChanged<int> onToggleFilter;

  const _FilterButtons({
    required this.activeFilters,
    required this.onToggleFilter,
  });

  static const AppThemeExtension _palette = AppThemeExtension.dark;

  static final List<(int type, Color color)> _filterItems = [
    (GrenadeType.smoke, _palette.smoke),
    (GrenadeType.flash, _palette.flash),
    (GrenadeType.molotov, _palette.molotov),
    (GrenadeType.he, _palette.he),
    (GrenadeType.wallbang, _palette.wallbang),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: _filterItems.map((item) {
        final (type, color) = item;
        final isActive = activeFilters.contains(type);
        return GestureDetector(
          onTap: () => onToggleFilter(type),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: GrenadeTypeIcon(
              type: type,
              size: 18,
              color: isActive ? color : Colors.grey.withValues(alpha: 0.3),
            ),
          ),
        );
      }).toList(growable: false),
    );
  }
}
