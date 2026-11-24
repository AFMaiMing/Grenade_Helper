import 'package:flutter/services.dart';

class HotkeyConfig {
  final LogicalKeyboardKey key;
  final Set<LogicalKeyboardKey> modifiers;

  static final Map<int, String> _specialKeyLabels = {
    LogicalKeyboardKey.arrowUp.keyId: '↑',
    LogicalKeyboardKey.arrowDown.keyId: '↓',
    LogicalKeyboardKey.arrowLeft.keyId: '←',
    LogicalKeyboardKey.arrowRight.keyId: '→',
    LogicalKeyboardKey.pageUp.keyId: 'PageUp',
    LogicalKeyboardKey.pageDown.keyId: 'PageDown',
    LogicalKeyboardKey.escape.keyId: 'Esc',
    LogicalKeyboardKey.enter.keyId: 'Enter',
    LogicalKeyboardKey.bracketLeft.keyId: '[',
    LogicalKeyboardKey.bracketRight.keyId: ']',
    LogicalKeyboardKey.digit1.keyId: '1',
    LogicalKeyboardKey.digit2.keyId: '2',
    LogicalKeyboardKey.digit3.keyId: '3',
    LogicalKeyboardKey.digit4.keyId: '4',
    LogicalKeyboardKey.equal.keyId: '=',
    LogicalKeyboardKey.minus.keyId: '-',
  };

  static final List<({String label, List<LogicalKeyboardKey> keys})>
      _modifierGroups = [
    (
      label: 'Ctrl',
      keys: [
        LogicalKeyboardKey.control,
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.controlRight,
      ],
    ),
    (
      label: 'Alt',
      keys: [
        LogicalKeyboardKey.alt,
        LogicalKeyboardKey.altLeft,
        LogicalKeyboardKey.altRight,
      ],
    ),
    (
      label: 'Shift',
      keys: [
        LogicalKeyboardKey.shift,
        LogicalKeyboardKey.shiftLeft,
        LogicalKeyboardKey.shiftRight,
      ],
    ),
    (
      label: 'Meta',
      keys: [
        LogicalKeyboardKey.meta,
        LogicalKeyboardKey.metaLeft,
        LogicalKeyboardKey.metaRight,
      ],
    ),
  ];

  const HotkeyConfig({required this.key, this.modifiers = const {}});

  String toDisplayString() {
    final parts = <String>[];
    for (final group in _modifierGroups.take(3)) {
      if (group.keys.any(modifiers.contains)) {
        parts.add(group.label);
      }
    }
    parts.add(_getKeyLabel(key));
    return parts.join(' + ');
  }

  String _getKeyLabel(LogicalKeyboardKey key) {
    final mapped = _specialKeyLabels[key.keyId];
    if (mapped != null) return mapped;
    return key.keyLabel.isNotEmpty
        ? key.keyLabel.toUpperCase()
        : key.debugName ?? 'Unknown';
  }

  Map<String, dynamic> toJson() => {
        'keyId': key.keyId,
        'modifierIds': modifiers.map((m) => m.keyId).toList(),
      };

  factory HotkeyConfig.fromJson(Map<String, dynamic> json) {
    return HotkeyConfig(
      key: LogicalKeyboardKey.findKeyByKeyId(json['keyId'] as int) ??
          LogicalKeyboardKey.keyG,
      modifiers: (json['modifierIds'] as List<dynamic>)
          .map((id) => LogicalKeyboardKey.findKeyByKeyId(id as int))
          .whereType<LogicalKeyboardKey>()
          .toSet(),
    );
  }

  /// 忽略左右侧差异，判断两个热键配置是否冲突。
  bool conflictsWith(HotkeyConfig other) {
    if (key.keyId != other.key.keyId) return false;
    final currentModifiers = _normalizedModifierIds();
    final otherModifiers = other._normalizedModifierIds();
    return currentModifiers.length == otherModifiers.length &&
        currentModifiers.containsAll(otherModifiers);
  }

  Set<int> _normalizedModifierIds() {
    final result = <int>{};
    for (final group in _modifierGroups) {
      if (group.keys.any(modifiers.contains)) {
        result.add(group.keys.first.keyId);
      }
    }
    return result;
  }
}

enum HotkeyAction {
  toggleOverlay,
  navigateUp,
  navigateDown,
  navigateLeft,
  navigateRight,
  prevGrenade,
  nextGrenade,
  prevStep,
  nextStep,
  toggleSmoke,
  toggleFlash,
  toggleMolotov,
  toggleHE,
  toggleWallbang,
  hideOverlay,
  togglePlayPause,
  toggleMediaFullscreenPreview,
  increaseNavSpeed,
  decreaseNavSpeed,
  scrollUp,
  scrollDown,
}

class HotkeyConflictException implements Exception {
  final HotkeyAction action;
  final HotkeyAction conflictingAction;
  final HotkeyConfig config;

  HotkeyConflictException({
    required this.action,
    required this.conflictingAction,
    required this.config,
  });

  @override
  String toString() =>
      'Hotkey conflict: $action conflicts with $conflictingAction (${config.toDisplayString()})';
}

Map<HotkeyAction, HotkeyConfig> defaultHotkeyBindings() {
  return {
    HotkeyAction.toggleOverlay: HotkeyConfig(
      key: LogicalKeyboardKey.keyG,
      modifiers: {LogicalKeyboardKey.alt},
    ),
    HotkeyAction.navigateUp: HotkeyConfig(key: LogicalKeyboardKey.arrowUp),
    HotkeyAction.navigateDown: HotkeyConfig(key: LogicalKeyboardKey.arrowDown),
    HotkeyAction.navigateLeft: HotkeyConfig(key: LogicalKeyboardKey.arrowLeft),
    HotkeyAction.navigateRight:
        HotkeyConfig(key: LogicalKeyboardKey.arrowRight),
    HotkeyAction.prevGrenade: HotkeyConfig(key: LogicalKeyboardKey.pageUp),
    HotkeyAction.nextGrenade: HotkeyConfig(key: LogicalKeyboardKey.pageDown),
    HotkeyAction.prevStep: HotkeyConfig(key: LogicalKeyboardKey.bracketLeft),
    HotkeyAction.nextStep: HotkeyConfig(key: LogicalKeyboardKey.bracketRight),
    HotkeyAction.toggleSmoke: HotkeyConfig(key: LogicalKeyboardKey.digit7),
    HotkeyAction.toggleFlash: HotkeyConfig(key: LogicalKeyboardKey.digit8),
    HotkeyAction.toggleMolotov: HotkeyConfig(key: LogicalKeyboardKey.digit9),
    HotkeyAction.toggleHE: HotkeyConfig(key: LogicalKeyboardKey.digit0),
    HotkeyAction.toggleWallbang: HotkeyConfig(
      key: LogicalKeyboardKey.digit0,
      modifiers: {LogicalKeyboardKey.alt},
    ),
    HotkeyAction.hideOverlay: HotkeyConfig(key: LogicalKeyboardKey.escape),
    HotkeyAction.togglePlayPause: HotkeyConfig(
      key: LogicalKeyboardKey.keyP,
      modifiers: {LogicalKeyboardKey.alt},
    ),
    HotkeyAction.toggleMediaFullscreenPreview: HotkeyConfig(
      key: LogicalKeyboardKey.enter,
      modifiers: {LogicalKeyboardKey.alt},
    ),
    HotkeyAction.increaseNavSpeed: HotkeyConfig(key: LogicalKeyboardKey.equal),
    HotkeyAction.decreaseNavSpeed: HotkeyConfig(key: LogicalKeyboardKey.minus),
    HotkeyAction.scrollUp: HotkeyConfig(
      key: LogicalKeyboardKey.pageUp,
      modifiers: {LogicalKeyboardKey.alt},
    ),
    HotkeyAction.scrollDown: HotkeyConfig(
      key: LogicalKeyboardKey.pageDown,
      modifiers: {LogicalKeyboardKey.alt},
    ),
  };
}
