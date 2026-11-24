import 'package:flutter/material.dart';

import 'area_draw_models.dart';

/// 爆点绘制模式下的地图参考点位标记
class ImpactReferenceMarker extends StatelessWidget {
  final DrawImageBounds imageBounds;
  final double markerScale;
  final double impactX;
  final double impactY;

  const ImpactReferenceMarker({
    super.key,
    required this.imageBounds,
    required this.markerScale,
    required this.impactX,
    required this.impactY,
  });

  @override
  Widget build(BuildContext context) {
    const double baseHalfSize = 10.0;
    final left =
        imageBounds.offsetX + impactX * imageBounds.width - baseHalfSize;
    final top =
        imageBounds.offsetY + impactY * imageBounds.height - baseHalfSize;

    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: Transform.scale(
          scale: markerScale,
          alignment: Alignment.center,
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.purpleAccent, width: 2),
            ),
            child: const Icon(
              Icons.close,
              size: 12,
              color: Colors.purpleAccent,
            ),
          ),
        ),
      ),
    );
  }
}

/// 区域绘制页面底部工具栏与笔刷参数面板
class AreaDrawBottomToolbar extends StatelessWidget {
  final bool compact;
  final Color drawColor;
  final bool isImpactAreaMode;
  final DrawTool activeTool;
  final double brushRatio;
  final bool squareBrush;
  final int penPointCount;
  final double shapeSize;
  final bool hasActiveShape;
  final ValueChanged<DrawTool> onSelectTool;
  final VoidCallback onSave;
  final ValueChanged<bool> onSquareBrushChanged;
  final ValueChanged<double> onBrushRatioChanged;
  final VoidCallback onCommitPen;
  final VoidCallback onClearPen;
  final ValueChanged<double> onShapeSizeChanged;
  final VoidCallback onStartNewShape;

  const AreaDrawBottomToolbar({
    super.key,
    required this.compact,
    required this.drawColor,
    required this.isImpactAreaMode,
    required this.activeTool,
    required this.brushRatio,
    required this.squareBrush,
    required this.penPointCount,
    required this.shapeSize,
    required this.hasActiveShape,
    required this.onSelectTool,
    required this.onSave,
    required this.onSquareBrushChanged,
    required this.onBrushRatioChanged,
    required this.onCommitPen,
    required this.onClearPen,
    required this.onShapeSizeChanged,
    required this.onStartNewShape,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor =
        isImpactAreaMode ? theme.colorScheme.primary : drawColor;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 14,
        vertical: compact ? 8 : 10,
      ),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _ToolChip(
                        icon: Icons.pan_tool_alt_outlined,
                        label: '移动',
                        selected: activeTool == DrawTool.move,
                        color: theme.colorScheme.primary,
                        onTap: () => onSelectTool(DrawTool.move),
                      ),
                      const SizedBox(width: 6),
                      _ToolChip(
                        icon: Icons.brush_rounded,
                        label: '画笔',
                        selected: activeTool == DrawTool.brush,
                        color: accentColor,
                        onTap: () => onSelectTool(DrawTool.brush),
                      ),
                      const SizedBox(width: 6),
                      _ToolChip(
                        icon: Icons.polyline_rounded,
                        label: '钢笔',
                        selected: activeTool == DrawTool.pen,
                        color: accentColor,
                        onTap: () => onSelectTool(DrawTool.pen),
                      ),
                      const SizedBox(width: 6),
                      _ToolChip(
                        icon: Icons.auto_fix_off_rounded,
                        label: '橡皮',
                        selected: activeTool == DrawTool.eraser,
                        color: Colors.grey,
                        onTap: () => onSelectTool(DrawTool.eraser),
                      ),
                      const SizedBox(width: 6),
                      _ToolChip(
                        icon: Icons.circle_outlined,
                        label: '圆形',
                        selected: activeTool == DrawTool.circle,
                        color: accentColor,
                        onTap: () => onSelectTool(DrawTool.circle),
                      ),
                      const SizedBox(width: 6),
                      _ToolChip(
                        icon: Icons.crop_square_rounded,
                        label: '方块',
                        selected: activeTool == DrawTool.square,
                        color: accentColor,
                        onTap: () => onSelectTool(DrawTool.square),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: onSave,
                icon: Icon(
                  Icons.check_rounded,
                  color: Colors.white,
                  size: compact ? 16 : 18,
                ),
                label: Text(
                  '保存',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 12.5 : 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  visualDensity:
                      compact ? VisualDensity.compact : VisualDensity.standard,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 12 : 16,
                    vertical: compact ? 8 : 10,
                  ),
                ),
              ),
            ],
          ),
          if (activeTool == DrawTool.brush ||
              activeTool == DrawTool.eraser) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                _BrushShapeButton(
                  icon: Icons.circle,
                  tooltip: '圆形笔刷',
                  selected: !squareBrush,
                  onTap: () => onSquareBrushChanged(false),
                ),
                const SizedBox(width: 6),
                _BrushShapeButton(
                  icon: Icons.square,
                  tooltip: '方形笔刷',
                  selected: squareBrush,
                  onTap: () => onSquareBrushChanged(true),
                ),
                const SizedBox(width: 12),
                Text(
                  '粗细',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.textTheme.bodySmall?.color,
                  ),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 7),
                    ),
                    child: Slider(
                      value: brushRatio,
                      min: kMinAreaBrushRatio,
                      max: kMaxAreaBrushRatio,
                      activeColor: theme.colorScheme.primary,
                      onChanged: onBrushRatioChanged,
                    ),
                  ),
                ),
                SizedBox(
                  width: 40,
                  child: Text(
                    '${(brushRatio * 100).toStringAsFixed(1)}%',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.textTheme.bodySmall?.color,
                    ),
                  ),
                ),
              ],
            ),
          ] else if (activeTool == DrawTool.pen) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 15,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    penPointCount < 3
                        ? '点击地图依次打点（至少3个点自动围成填充区域），可拖拽调整锚点'
                        : '已打 $penPointCount 个锚点，点击起点或右侧按钮完成闭合',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.textTheme.bodySmall?.color,
                    ),
                  ),
                ),
                if (penPointCount > 0) ...[
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: penPointCount >= 3 ? onCommitPen : onClearPen,
                    icon: Icon(
                      penPointCount >= 3
                          ? Icons.done_all_rounded
                          : Icons.close_rounded,
                      size: 15,
                    ),
                    label: Text(
                      penPointCount >= 3 ? '闭合填充' : '取消锚点',
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ],
            ),
          ] else if (activeTool == DrawTool.circle ||
              activeTool == DrawTool.square) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  '形状大小: ${(shapeSize * 100).round()}%',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.textTheme.bodySmall?.color,
                  ),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 7),
                    ),
                    child: Slider(
                      value: shapeSize,
                      min: 0.02,
                      max: 0.15,
                      activeColor: accentColor,
                      onChanged: onShapeSizeChanged,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  tooltip: '新建形状',
                  iconSize: 22,
                  visualDensity: VisualDensity.compact,
                  color: accentColor,
                  onPressed: hasActiveShape ? onStartNewShape : null,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _BrushShapeButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  const _BrushShapeButton({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected
        ? theme.colorScheme.primary
        : theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6);

    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? theme.colorScheme.primary.withValues(alpha: 0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.dividerColor.withValues(alpha: 0.3),
            ),
          ),
          child: Icon(icon, size: 14, color: color),
        ),
      ),
    );
  }
}

class _ToolChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _ToolChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final activeColor = selected
        ? (isDark
            ? color
            : HSLColor.fromColor(color).withLightness(0.38).toColor())
        : theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7) ??
            Colors.grey;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? activeColor.withValues(alpha: 0.16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: selected
                ? activeColor
                : theme.dividerColor.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: activeColor),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: activeColor,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
