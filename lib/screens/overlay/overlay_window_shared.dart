import 'package:flutter/material.dart';

import '../../services/settings_service.dart';
import 'overlay_hotkey_helper.dart';

/// 悬浮窗标题栏及全屏预览共享的图标按钮。
class OverlayWindowButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  const OverlayWindowButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 16, color: color),
      ),
    );
  }
}

/// 生成底部快捷键提示条文案。
String buildOverlayHotkeySummaryText(
  Map<HotkeyAction, HotkeyConfig> hotkeys, {
  required bool includeFilterKeys,
}) {
  final navUpKey = overlayHotkeyLabel(hotkeys, HotkeyAction.navigateUp);
  final navDownKey = overlayHotkeyLabel(hotkeys, HotkeyAction.navigateDown);
  final navLeftKey = overlayHotkeyLabel(hotkeys, HotkeyAction.navigateLeft);
  final navRightKey = overlayHotkeyLabel(hotkeys, HotkeyAction.navigateRight);
  final prevGrenadeKey = overlayHotkeyLabel(hotkeys, HotkeyAction.prevGrenade);
  final nextGrenadeKey = overlayHotkeyLabel(hotkeys, HotkeyAction.nextGrenade);
  final prevStepKey = overlayHotkeyLabel(hotkeys, HotkeyAction.prevStep);
  final nextStepKey = overlayHotkeyLabel(hotkeys, HotkeyAction.nextStep);
  final scrollUpKey = overlayHotkeyLabel(hotkeys, HotkeyAction.scrollUp);
  final scrollDownKey = overlayHotkeyLabel(hotkeys, HotkeyAction.scrollDown);
  final fullscreenKey = overlayHotkeyLabel(
    hotkeys,
    HotkeyAction.toggleMediaFullscreenPreview,
  );

  if (!includeFilterKeys) {
    return '$navUpKey$navLeftKey$navDownKey$navRightKey 导航 | $prevGrenadeKey/$nextGrenadeKey 道具 | $prevStepKey/$nextStepKey 步骤 | $scrollUpKey/$scrollDownKey 滚动 | $fullscreenKey 全屏';
  }

  final smokeKey = overlayHotkeyLabel(hotkeys, HotkeyAction.toggleSmoke);
  final flashKey = overlayHotkeyLabel(hotkeys, HotkeyAction.toggleFlash);
  final molotovKey = overlayHotkeyLabel(hotkeys, HotkeyAction.toggleMolotov);
  final heKey = overlayHotkeyLabel(hotkeys, HotkeyAction.toggleHE);
  return '$navUpKey$navLeftKey$navDownKey$navRightKey 导航 | $smokeKey/$flashKey/$molotovKey/$heKey 过滤 | $prevGrenadeKey/$nextGrenadeKey 道具 | $prevStepKey/$nextStepKey 步骤 | $scrollUpKey/$scrollDownKey 滚动 | $fullscreenKey 全屏';
}
