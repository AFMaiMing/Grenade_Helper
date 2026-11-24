import 'package:flutter/material.dart';

import '../../models.dart';
import '../../theme/app_design_system.dart';
import '../../widgets/map_icon.dart';
import '../../widgets/path_image_provider.dart';

// 首页普通地图卡片
class HomeMapCard extends StatelessWidget {
  final GameMap map;
  final int index;
  final int grenadeCount;
  final bool isCustomMap;
  final VoidCallback onTap;

  const HomeMapCard({
    super.key,
    required this.map,
    required this.index,
    required this.grenadeCount,
    required this.isCustomMap,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final imageProvider = imageProviderFromPath(map.backgroundPath);
    return _AnimatedHomeCardFrame(
      index: index,
      onTap: onTap,
      idleOverlayAlpha: 0.38,
      hoverOverlayAlpha: 0.28,
      background: imageProvider == null
          ? Container(color: const Color(0xFF30343A))
          : Image(
              image: imageProvider,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  Container(color: const Color(0xFF30343A)),
            ),
      badgeLabel: isCustomMap ? '自定义' : null,
      bottomContent: Row(
        children: [
          Hero(
            tag: 'map-icon-${map.id}',
            child: MapIcon(path: map.iconPath, size: 40),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  map.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$grenadeCount 个道具',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.76),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_rounded, color: Colors.white),
        ],
      ),
    );
  }
}

// 非现役地图池聚合文件夹卡片
class ReservePoolFolderCard extends StatelessWidget {
  final List<GameMap> maps;
  final int index;
  final int totalGrenadeCount;
  final VoidCallback onTap;

  const ReservePoolFolderCard({
    super.key,
    required this.maps,
    required this.index,
    required this.totalGrenadeCount,
    required this.onTap,
  });

  Widget _buildPreviewTile(GameMap? map) {
    final provider =
        map == null ? null : imageProviderFromPath(map.backgroundPath);
    if (provider == null) {
      return Container(color: const Color(0xFF30343A));
    }
    return Image(
      image: provider,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(color: const Color(0xFF30343A)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final previewMaps = maps.take(4).toList(growable: false);
    GameMap? tileAt(int i) => i < previewMaps.length ? previewMaps[i] : null;

    return _AnimatedHomeCardFrame(
      index: index,
      onTap: onTap,
      idleOverlayAlpha: 0.52,
      hoverOverlayAlpha: 0.42,
      background: ColoredBox(
        color: const Color(0xFF1F2328),
        child: Column(
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _buildPreviewTile(tileAt(0))),
                  const SizedBox(width: 2),
                  Expanded(child: _buildPreviewTile(tileAt(1))),
                ],
              ),
            ),
            const SizedBox(height: 2),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _buildPreviewTile(tileAt(2))),
                  const SizedBox(width: 2),
                  Expanded(child: _buildPreviewTile(tileAt(3))),
                ],
              ),
            ),
          ],
        ),
      ),
      badgeLabel: '含人质图',
      bottomContent: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.24),
              ),
            ),
            child: const Icon(
              Icons.folder_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '非现役地图池',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${maps.length} 张地图 · $totalGrenadeCount 个道具',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.78),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.arrow_forward_rounded,
            color: Colors.white,
          ),
        ],
      ),
    );
  }
}

// 统一承载入场延迟渐显与悬停缩放的卡片容器
class _AnimatedHomeCardFrame extends StatefulWidget {
  final int index;
  final VoidCallback onTap;
  final Widget background;
  final Widget bottomContent;
  final double idleOverlayAlpha;
  final double hoverOverlayAlpha;
  final String? badgeLabel;

  const _AnimatedHomeCardFrame({
    required this.index,
    required this.onTap,
    required this.background,
    required this.bottomContent,
    required this.idleOverlayAlpha,
    required this.hoverOverlayAlpha,
    this.badgeLabel,
  });

  @override
  State<_AnimatedHomeCardFrame> createState() => _AnimatedHomeCardFrameState();
}

class _AnimatedHomeCardFrameState extends State<_AnimatedHomeCardFrame> {
  bool _hovered = false;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: 35 * widget.index.clamp(0, 8)), () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      offset: _visible ? Offset.zero : const Offset(0, 0.04),
      duration: AppMotion.panel,
      curve: AppMotion.enter,
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: AppMotion.panel,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: widget.onTap,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AnimatedScale(
                    scale: _hovered ? 1.035 : 1,
                    duration: AppMotion.content,
                    curve: AppMotion.enter,
                    child: widget.background,
                  ),
                  Positioned.fill(
                    child: ColoredBox(
                      color: Colors.black.withValues(
                        alpha: _hovered
                            ? widget.hoverOverlayAlpha
                            : widget.idleOverlayAlpha,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 14,
                    child: AnimatedSlide(
                      offset: _hovered ? const Offset(0, -0.03) : Offset.zero,
                      duration: AppMotion.quick,
                      child: widget.bottomContent,
                    ),
                  ),
                  if (widget.badgeLabel != null)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.54),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          widget.badgeLabel!,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 11),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// 添加自定义地图虚线卡片
class AddCustomMapCard extends StatelessWidget {
  final VoidCallback onTap;

  const AddCustomMapCard({
    super.key,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: DashedBorderPainter(color: context.appTheme.subtleBorder),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.add_photo_alternate_outlined,
                  size: 32,
                  color: context.appTheme.mutedText,
                ),
                const SizedBox(height: 12),
                const Text(
                  '添加自定义地图',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  '导入雷达图并建立自己的点位库',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.appTheme.mutedText,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// 圆角虚线边框绘制器
class DashedBorderPainter extends CustomPainter {
  final Color color;

  const DashedBorderPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
          Offset.zero & size, const Radius.circular(8)));
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(
            distance,
            (distance + 7).clamp(0, metric.length),
          ),
          paint,
        );
        distance += 12;
      }
    }
  }

  @override
  bool shouldRepaint(covariant DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color;
}
