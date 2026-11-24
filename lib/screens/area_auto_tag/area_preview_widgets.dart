import 'package:flutter/material.dart';

import '../../models.dart';

/// 区域预览顶部筛选与统计控制栏。
class AreaPreviewHeader extends StatelessWidget {
  final int displayMatched;
  final int displayTotal;
  final bool showImpact;
  final bool tagByImpact;
  final bool showOnlyMatched;
  final ValueChanged<bool> onShowImpactChanged;
  final ValueChanged<bool> onTagByImpactChanged;
  final ValueChanged<bool> onShowOnlyMatchedChanged;

  const AreaPreviewHeader({
    super.key,
    required this.displayMatched,
    required this.displayTotal,
    required this.showImpact,
    required this.tagByImpact,
    required this.showOnlyMatched,
    required this.onShowImpactChanged,
    required this.onTagByImpactChanged,
    required this.onShowOnlyMatchedChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '当前模式命中：$displayMatched / $displayTotal',
            style: TextStyle(
              color: Theme.of(context).textTheme.bodyMedium?.color,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment<bool>(
                      value: false,
                      icon: Icon(Icons.place_outlined, size: 16),
                      label: Text('站位'),
                    ),
                    ButtonSegment<bool>(
                      value: true,
                      icon: Icon(Icons.adjust, size: 16),
                      label: Text('爆点'),
                    ),
                  ],
                  selected: {showImpact},
                  onSelectionChanged: (value) =>
                      onShowImpactChanged(value.first),
                ),
                const SizedBox(width: 8),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment<bool>(
                      value: false,
                      icon: Icon(Icons.touch_app_outlined, size: 16),
                      label: Text('按站位打标签'),
                    ),
                    ButtonSegment<bool>(
                      value: true,
                      icon: Icon(Icons.gps_fixed, size: 16),
                      label: Text('按爆点打标签'),
                    ),
                  ],
                  selected: {tagByImpact},
                  onSelectionChanged: (value) =>
                      onTagByImpactChanged(value.first),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FilterChip(
                label: const Text('仅显示命中'),
                selected: showOnlyMatched,
                onSelected: onShowOnlyMatchedChanged,
                showCheckmark: false,
              ),
              const Spacer(),
              const _LegendDot(label: '命中', color: Colors.greenAccent),
              const SizedBox(width: 10),
              const _LegendDot(label: '未命中', color: Colors.white54),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final String label;
  final Color color;

  const _LegendDot({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

/// 区域预览底部操作栏。
class AreaPreviewBottomBar extends StatelessWidget {
  final bool isLoading;
  final bool isSyncing;
  final VoidCallback onRefresh;
  final VoidCallback onSync;

  const AreaPreviewBottomBar({
    super.key,
    required this.isLoading,
    required this.isSyncing,
    required this.onRefresh,
    required this.onSync,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: isLoading ? null : onRefresh,
                icon: const Icon(Icons.refresh),
                label: const Text('重新计算'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: isSyncing ? null : onSync,
                icon: isSyncing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome),
                label: const Text('同步该区域标签'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 展示指定坐标命中的道具列表弹窗。
Future<void> showAreaMatchedGrenadesSheet(
  BuildContext context,
  List<Grenade> items,
) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '命中道具（${items.length}）',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.45,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final g = items[index];
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        g.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: g.description == null || g.description!.isEmpty
                          ? null
                          : Text(
                              g.description!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
