import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/settings_service.dart';
import '../../widgets/map_icon.dart';

/// 地图选项图标与名称标签
class SettingsMapDropdownLabel extends StatelessWidget {
  final String iconPath;
  final String text;

  const SettingsMapDropdownLabel({
    super.key,
    required this.iconPath,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        MapIcon(path: iconPath, size: 20),
        const SizedBox(width: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// 快捷键录制与编辑对话框
class HotkeyEditorDialog extends StatefulWidget {
  final HotkeyAction action;
  final String label;
  final HotkeyConfig? currentConfig;
  final Future<String?> Function(HotkeyConfig) onSave;

  const HotkeyEditorDialog({
    super.key,
    required this.action,
    required this.label,
    required this.currentConfig,
    required this.onSave,
  });

  @override
  State<HotkeyEditorDialog> createState() => _HotkeyEditorDialogState();
}

class _HotkeyEditorDialogState extends State<HotkeyEditorDialog> {
  HotkeyConfig? _newConfig;
  final FocusNode _focusNode = FocusNode();
  bool _isListening = false;
  bool _isSaving = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _newConfig = widget.currentConfig;
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('设置快捷键: ${widget.label}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '当前: ${widget.currentConfig?.toDisplayString() ?? "未设置"}',
            style: TextStyle(color: Colors.grey[500]),
          ),
          const SizedBox(height: 24),
          KeyboardListener(
            focusNode: _focusNode,
            autofocus: true,
            onKeyEvent: (event) {
              if (event is KeyDownEvent && _isListening) {
                // 过滤掉单独按下的修饰键
                if (_isModifierKey(event.logicalKey)) return;

                final modifiers = <LogicalKeyboardKey>{};
                if (HardwareKeyboard.instance.isAltPressed) {
                  modifiers.add(LogicalKeyboardKey.alt);
                }
                if (HardwareKeyboard.instance.isControlPressed) {
                  modifiers.add(LogicalKeyboardKey.control);
                }
                if (HardwareKeyboard.instance.isShiftPressed) {
                  modifiers.add(LogicalKeyboardKey.shift);
                }

                setState(() {
                  _newConfig = HotkeyConfig(
                    key: event.logicalKey,
                    modifiers: modifiers,
                  );
                  _isListening = false;
                  _errorText = null;
                });
              }
            },
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _isListening = true;
                  _errorText = null;
                });
                _focusNode.requestFocus();
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: _isListening
                      ? Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.1)
                      : Colors.grey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _isListening
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey,
                    width: 2,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      _isListening ? Icons.keyboard : Icons.touch_app,
                      size: 40,
                      color: _isListening
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _isListening
                          ? '请按下新的快捷键组合...'
                          : _newConfig?.toDisplayString() ?? '点击此处开始设置',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: _isListening
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_errorText != null) ...[
            const SizedBox(height: 12),
            Text(
              _errorText!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _newConfig != null && !_isSaving
              ? () async {
                  setState(() {
                    _isSaving = true;
                    _errorText = null;
                  });

                  final error = await widget.onSave(_newConfig!);
                  if (!mounted || !context.mounted) return;

                  if (error == null) {
                    Navigator.pop(context);
                    return;
                  }

                  setState(() {
                    _isSaving = false;
                    _errorText = error;
                  });
                }
              : null,
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('保存'),
        ),
      ],
    );
  }

  bool _isModifierKey(LogicalKeyboardKey key) {
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
}
