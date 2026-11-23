import 'package:flutter/material.dart';

import '../../models/tag.dart';
import '../color_picker_widget.dart';

/// 快速创建标签弹窗返回的数据结构。
typedef QuickTagDraft = ({String name, int color});

/// 快速创建标签弹窗。
class QuickCreateTagDialog extends StatefulWidget {
  const QuickCreateTagDialog({super.key});

  @override
  State<QuickCreateTagDialog> createState() => _QuickCreateTagDialogState();
}

class _QuickCreateTagDialogState extends State<QuickCreateTagDialog> {
  final _nameController = TextEditingController();
  int _selectedColor = presetColors.first;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('快速创建标签'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: '标签名称',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: presetColors
                .map(
                  (c) => GestureDetector(
                    onTap: () => setState(() => _selectedColor = c),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _selectedColor == c
                              ? Colors.white
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: _selectedColor == c
                          ? const Icon(
                              Icons.check,
                              size: 14,
                              color: Colors.white,
                            )
                          : null,
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () {
            final name = _nameController.text.trim();
            if (name.isEmpty) return;
            Navigator.pop<QuickTagDraft>(
              context,
              (name: name, color: _selectedColor),
            );
          },
          child: const Text('创建'),
        ),
      ],
    );
  }
}

/// 标签展开/收起切换按钮。
class TagExpandToggleButton extends StatelessWidget {
  final bool expanded;
  final int hiddenCount;
  final VoidCallback onPressed;

  const TagExpandToggleButton({
    super.key,
    required this.expanded,
    required this.hiddenCount,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: onPressed,
        icon: Icon(
          expanded ? Icons.expand_less : Icons.expand_more,
          size: 18,
        ),
        label: Text(expanded ? '收起' : '显示更多（$hiddenCount）'),
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 4),
        ),
      ),
    );
  }
}

/// 可点击切换选中状态的标签芯片。
class SelectableTagChip extends StatelessWidget {
  final Tag tag;
  final bool selected;
  final VoidCallback onTap;

  const SelectableTagChip({
    super.key,
    required this.tag,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = Color(tag.colorValue);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? color : color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? color : color.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected)
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(Icons.check, size: 12, color: Colors.white),
              ),
            Text(
              tag.name,
              style: TextStyle(
                fontSize: 12,
                color: selected ? Colors.white : color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
