import 'package:flutter/material.dart';

import 'color_picker/hsl_color_sliders.dart';

/// 预设颜色列表。
const List<int> presetColors = [
  0xFFE91E63,
  0xFFF44336,
  0xFFFF9800,
  0xFFFFEB3B,
  0xFF4CAF50,
  0xFF00BCD4,
  0xFF2196F3,
  0xFF3F51B5,
  0xFF9C27B0,
  0xFF795548,
  0xFF607D8B,
  0xFF9E9E9E,
];

/// 标签颜色选择器组件，支持预设色板与 HSL 自定义调色。
class TagColorPicker extends StatefulWidget {
  final int initialColor;
  final ValueChanged<int> onColorSelected;
  final bool showPreview;

  const TagColorPicker({
    super.key,
    required this.initialColor,
    required this.onColorSelected,
    this.showPreview = true,
  });

  @override
  State<TagColorPicker> createState() => _TagColorPickerState();
}

class _TagColorPickerState extends State<TagColorPicker> {
  late int _selectedColor;
  late double _hue;
  late double _saturation;
  late double _lightness;
  bool _showHSLPicker = false;

  @override
  void initState() {
    super.initState();
    _selectedColor = widget.initialColor;
    _initHSL();
  }

  void _initHSL() {
    final hslColor = HSLColor.fromColor(Color(_selectedColor));
    _hue = hslColor.hue;
    _saturation = hslColor.saturation;
    _lightness = hslColor.lightness;
  }

  void _updateColorFromHSL() {
    final hslColor = HSLColor.fromAHSL(1.0, _hue, _saturation, _lightness);
    setState(() {
      _selectedColor = hslColor.toColor().toARGB32();
    });
    widget.onColorSelected(_selectedColor);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showPreview) ...[
          _ColorPreviewRow(colorValue: _selectedColor),
          const SizedBox(height: 12),
        ],
        _buildPresetColors(),
        const SizedBox(height: 12),
        _buildToggleButton(),
        if (_showHSLPicker) ...[
          const SizedBox(height: 12),
          HslColorSliders(
            hue: _hue,
            saturation: _saturation,
            lightness: _lightness,
            onHueChanged: (val) {
              setState(() => _hue = val);
              _updateColorFromHSL();
            },
            onSaturationChanged: (val) {
              setState(() => _saturation = val);
              _updateColorFromHSL();
            },
            onLightnessChanged: (val) {
              setState(() => _lightness = val);
              _updateColorFromHSL();
            },
          ),
        ],
      ],
    );
  }

  Widget _buildPresetColors() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: presetColors.map((color) {
        final isSelected = color == _selectedColor;
        return GestureDetector(
          onTap: () {
            setState(() {
              _selectedColor = color;
              _initHSL();
            });
            widget.onColorSelected(color);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Color(color),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected ? Colors.white : Colors.transparent,
                width: 2,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: Color(color).withValues(alpha: 0.6),
                        blurRadius: 8,
                      ),
                    ]
                  : null,
            ),
            child: isSelected
                ? const Icon(Icons.check, color: Colors.white, size: 18)
                : null,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildToggleButton() {
    return GestureDetector(
      onTap: () => setState(() => _showHSLPicker = !_showHSLPicker),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _showHSLPicker
                ? Icons.keyboard_arrow_up
                : Icons.keyboard_arrow_down,
            size: 18,
            color: Colors.grey,
          ),
          const SizedBox(width: 4),
          Text(
            _showHSLPicker ? '收起自定义' : '自定义颜色',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

class _ColorPreviewRow extends StatelessWidget {
  final int colorValue;

  const _ColorPreviewRow({required this.colorValue});

  @override
  Widget build(BuildContext context) {
    final color = Color(colorValue);
    final hex = colorValue.toRadixString(16).padLeft(8, '0').substring(2);

    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white24, width: 1),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.4),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '当前颜色',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            Text(
              '#${hex.toUpperCase()}',
              style: const TextStyle(fontSize: 14, fontFamily: 'monospace'),
            ),
          ],
        ),
      ],
    );
  }
}

/// 弹出标签颜色选择对话框，返回选中的 ARGB 颜色值。
Future<int?> showTagColorPickerDialog(
  BuildContext context, {
  int? initialColor,
}) async {
  int selectedColor = initialColor ?? presetColors.first;
  return showDialog<int>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('选择颜色'),
      content: TagColorPicker(
        initialColor: selectedColor,
        onColorSelected: (color) => selectedColor = color,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, selectedColor),
          child: const Text('确定'),
        ),
      ],
    ),
  );
}
