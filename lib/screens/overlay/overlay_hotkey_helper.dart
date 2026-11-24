import 'package:flutter/services.dart';

import '../../services/overlay_state_service.dart';
import '../../services/settings_service.dart';

/// 返回指定热键动作的展示文本。
String overlayHotkeyLabel(
  Map<HotkeyAction, HotkeyConfig> hotkeys,
  HotkeyAction action,
) {
  return hotkeys[action]?.toDisplayString() ?? '?';
}

/// 根据用户配置的热键解析方向导航动作。
NavigationDirection? resolveOverlayNavigationDirection(
  Map<HotkeyAction, HotkeyConfig> hotkeys,
  LogicalKeyboardKey key,
) {
  final mapping = <(HotkeyAction, NavigationDirection)>[
    (HotkeyAction.navigateUp, NavigationDirection.up),
    (HotkeyAction.navigateDown, NavigationDirection.down),
    (HotkeyAction.navigateLeft, NavigationDirection.left),
    (HotkeyAction.navigateRight, NavigationDirection.right),
  ];
  for (final (action, direction) in mapping) {
    final config = hotkeys[action];
    if (config != null && key.keyId == config.key.keyId) {
      return direction;
    }
  }
  return null;
}

bool isOverlayNavigationAction(HotkeyAction action) {
  return action == HotkeyAction.navigateUp ||
      action == HotkeyAction.navigateDown ||
      action == HotkeyAction.navigateLeft ||
      action == HotkeyAction.navigateRight;
}

bool isOverlayModifierKey(LogicalKeyboardKey key) {
  return key == LogicalKeyboardKey.alt ||
      key == LogicalKeyboardKey.altLeft ||
      key == LogicalKeyboardKey.altRight ||
      key == LogicalKeyboardKey.control ||
      key == LogicalKeyboardKey.controlLeft ||
      key == LogicalKeyboardKey.controlRight ||
      key == LogicalKeyboardKey.shift ||
      key == LogicalKeyboardKey.shiftLeft ||
      key == LogicalKeyboardKey.shiftRight ||
      key == LogicalKeyboardKey.meta ||
      key == LogicalKeyboardKey.metaLeft ||
      key == LogicalKeyboardKey.metaRight;
}

bool matchesOverlayHotkey(
  LogicalKeyboardKey key,
  bool hasAlt,
  bool hasCtrl,
  bool hasShift,
  HotkeyConfig config,
) {
  if (key.keyId != config.key.keyId) return false;

  final needsAlt = config.modifiers.any((m) =>
      m == LogicalKeyboardKey.alt ||
      m == LogicalKeyboardKey.altLeft ||
      m == LogicalKeyboardKey.altRight);
  final needsCtrl = config.modifiers.any((m) =>
      m == LogicalKeyboardKey.control ||
      m == LogicalKeyboardKey.controlLeft ||
      m == LogicalKeyboardKey.controlRight);
  final needsShift = config.modifiers.any((m) =>
      m == LogicalKeyboardKey.shift ||
      m == LogicalKeyboardKey.shiftLeft ||
      m == LogicalKeyboardKey.shiftRight);

  return hasAlt == needsAlt && hasCtrl == needsCtrl && hasShift == needsShift;
}

/// 解析非方向键按下事件对应的悬浮窗动作（含 Alt+P / Alt+Enter 备用组合）。
HotkeyAction? resolveOverlayKeyDownAction(
  KeyDownEvent event,
  Map<HotkeyAction, HotkeyConfig> hotkeys,
) {
  final key = event.logicalKey;
  final hasAlt = HardwareKeyboard.instance.isAltPressed;
  final hasCtrl = HardwareKeyboard.instance.isControlPressed;
  final hasShift = HardwareKeyboard.instance.isShiftPressed;

  for (final entry in hotkeys.entries) {
    if (isOverlayNavigationAction(entry.key)) continue;
    if (matchesOverlayHotkey(key, hasAlt, hasCtrl, hasShift, entry.value)) {
      return entry.key;
    }
  }

  if (hasAlt && !hasCtrl && !hasShift && key == LogicalKeyboardKey.keyP) {
    return HotkeyAction.togglePlayPause;
  }
  if (hasAlt && !hasCtrl && !hasShift && key == LogicalKeyboardKey.enter) {
    return HotkeyAction.toggleMediaFullscreenPreview;
  }
  return null;
}
