import 'package:flutter/material.dart';

import '../../models/overlay_snapshot.dart';
import '../../services/overlay_state_service.dart';
import '../../widgets/radar_mini_map.dart';

/// 悬浮窗无地图或无道具时的空状态引导视图。
class OverlayEmptyPrompt extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const OverlayEmptyPrompt({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  const OverlayEmptyPrompt.noMap({super.key})
      : icon = Icons.map_outlined,
        title = '请先进入地图',
        subtitle = '在主界面选择一张地图后\n悬浮窗将显示该地图的道具';

  const OverlayEmptyPrompt.noGrenade({super.key})
      : icon = Icons.add_location_alt,
        title = '该地图暂无道具',
        subtitle = '请先在地图上添加道具点位';

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 80, color: Colors.grey[700]),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[500], fontSize: 14),
          ),
        ],
      ),
    );
  }
}

/// 未吸附到具体点位时的方向键移动提示卡片。
class OverlayNavigationHint extends StatelessWidget {
  const OverlayNavigationHint({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 350,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.gps_not_fixed,
              size: 48,
              color: Colors.white.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            const Text(
              '使用方向键移动准星',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '靠近点位时会自动吸附并显示道具信息',
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 悬浮窗自适应宽度的雷达缩略图包装组件。
class OverlayRadarMap extends StatelessWidget {
  final OverlayStateService overlayState;

  const OverlayRadarMap({
    super.key,
    required this.overlayState,
  });

  @override
  Widget build(BuildContext context) {
    final assetPath = overlayState.layerAssetPath;
    if (assetPath == null) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth =
            constraints.maxWidth > 0 ? constraints.maxWidth : 550.0;
        const radarHeight = 140.0;

        return RadarMiniMap(
          mapAssetPath: assetPath,
          currentGrenade: overlayState.currentGrenade,
          allGrenades: overlayState.filteredGrenades,
          crosshairX: overlayState.crosshairX,
          crosshairY: overlayState.crosshairY,
          isSnapped: overlayState.isSnapped,
          width: availableWidth,
          height: radarHeight,
          zoomLevel: 1.3,
        );
      },
    );
  }
}

/// 当前步骤的文字说明卡片。
class OverlayStepDescription extends StatelessWidget {
  final OverlayGrenadeItem? grenade;
  final int currentStepIndex;

  const OverlayStepDescription({
    super.key,
    required this.grenade,
    required this.currentStepIndex,
  });

  @override
  Widget build(BuildContext context) {
    if (grenade == null) return const SizedBox.shrink();
    final steps = grenade!.steps;
    if (steps.isEmpty) return const SizedBox.shrink();

    final currentStep =
        currentStepIndex < steps.length ? steps[currentStepIndex] : steps.first;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            currentStep.description.isNotEmpty
                ? currentStep.description
                : '(无说明)',
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
