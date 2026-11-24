import 'package:flutter/material.dart';

import '../../widgets/app_svg_icon.dart';
import 'impact_picker_painters.dart';

/// 地图上的投掷点或爆点标记组件。
class ImpactPointMarker extends StatelessWidget {
  final PickerImageBounds imageBounds;
  final double markerScale;
  final Offset point;
  final Color borderColor;
  final double shadowAlpha;
  final double blurRadius;
  final double spreadRadius;
  final IconData icon;
  final Color iconColor;

  const ImpactPointMarker({
    super.key,
    required this.imageBounds,
    required this.markerScale,
    required this.point,
    required this.borderColor,
    required this.shadowAlpha,
    required this.blurRadius,
    required this.spreadRadius,
    required this.icon,
    required this.iconColor,
  });

  /// 创建投掷点/穿点标记。
  factory ImpactPointMarker.throwPoint({
    required PickerImageBounds imageBounds,
    required double markerScale,
    required Offset point,
  }) {
    return ImpactPointMarker(
      imageBounds: imageBounds,
      markerScale: markerScale,
      point: point,
      borderColor: Colors.white,
      shadowAlpha: 0.3,
      blurRadius: 4,
      spreadRadius: 1,
      icon: Icons.place,
      iconColor: Colors.white,
    );
  }

  /// 创建爆点位置标记。
  factory ImpactPointMarker.impact({
    required PickerImageBounds imageBounds,
    required double markerScale,
    required Offset point,
  }) {
    return ImpactPointMarker(
      imageBounds: imageBounds,
      markerScale: markerScale,
      point: point,
      borderColor: Colors.purpleAccent,
      shadowAlpha: 0.4,
      blurRadius: 6,
      spreadRadius: 2,
      icon: Icons.close,
      iconColor: Colors.purpleAccent,
    );
  }

  @override
  Widget build(BuildContext context) {
    const double baseHalfSize = 10.0;
    final left =
        imageBounds.offsetX + point.dx * imageBounds.width - baseHalfSize;
    final top =
        imageBounds.offsetY + point.dy * imageBounds.height - baseHalfSize;

    return Positioned(
      left: left,
      top: top,
      child: Transform.scale(
        scale: markerScale,
        alignment: Alignment.center,
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            shape: BoxShape.circle,
            border: Border.all(color: borderColor, width: 2),
            boxShadow: [
              BoxShadow(
                color: borderColor.withValues(alpha: shadowAlpha),
                blurRadius: blurRadius,
                spreadRadius: spreadRadius,
              ),
            ],
          ),
          child: Icon(icon, size: 12, color: iconColor),
        ),
      ),
    );
  }
}

/// 坐标拾取页面底部的图例与操作提示条。
class ImpactPickerFooter extends StatelessWidget {
  final bool wallbangLineMode;
  final bool hasSelection;
  final String targetName;

  const ImpactPickerFooter({
    super.key,
    required this.wallbangLineMode,
    required this.hasSelection,
    required this.targetName,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bgColor = colorScheme.surfaceContainerHighest;
    final textColor = colorScheme.onSurfaceVariant;
    final markerColor = colorScheme.onSurface;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: bgColor,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: wallbangLineMode
                    ? BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: markerColor.withValues(alpha: 0.5),
                          width: 1.5,
                        ),
                      )
                    : BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: markerColor, width: 2),
                      ),
              ),
              const SizedBox(width: 8),
              Text(
                wallbangLineMode ? '穿点' : '投掷点',
                style: TextStyle(color: textColor, fontSize: 12),
              ),
              const SizedBox(width: 24),
              if (wallbangLineMode) ...[
                const Icon(Icons.north_east_rounded,
                    size: 16, color: Colors.cyan),
                const SizedBox(width: 6),
                Text(
                  '穿线方向',
                  style: TextStyle(color: textColor, fontSize: 12),
                ),
              ] else ...[
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.purpleAccent, width: 2),
                  ),
                  child: const Icon(Icons.close,
                      size: 8, color: Colors.purpleAccent),
                ),
                const SizedBox(width: 8),
                Text(
                  '爆点',
                  style: TextStyle(color: textColor, fontSize: 12),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!hasSelection) ...[
                AppSvgIcon(
                  asset: 'assets/icons/ui_hint.svg',
                  size: 17,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  semanticsLabel: '提示',
                ),
                const SizedBox(width: 7),
              ],
              Flexible(
                child: Text(
                  hasSelection
                      ? '已选择$targetName，点击确认保存'
                      : '点击地图任意位置设置$targetName',
                  style: TextStyle(
                    color: hasSelection
                        ? theme.colorScheme.primary
                        : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
