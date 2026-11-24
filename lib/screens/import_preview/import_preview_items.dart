import 'package:flutter/material.dart';

import '../../models.dart';
import '../../models/tag.dart';
import '../../services/data_service.dart';
import '../../services/lan_sync/lan_sync_local_store.dart';
import '../../widgets/grenade_type_icon.dart';

String _formatDeletedAt(int millis) {
  final deletedAt = DateTime.fromMillisecondsSinceEpoch(millis);
  return '${deletedAt.year}-${deletedAt.month.toString().padLeft(2, '0')}-${deletedAt.day.toString().padLeft(2, '0')} '
      '${deletedAt.hour.toString().padLeft(2, '0')}:${deletedAt.minute.toString().padLeft(2, '0')}';
}

/// 旧版道具包提示横幅
class LegacyPackageNoticeBanner extends StatelessWidget {
  final bool visible;

  const LegacyPackageNoticeBanner({
    super.key,
    required this.visible,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.35)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '这是旧版道具包，未包含新版完整性校验。建议仅在信任来源下导入。',
              style: TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// 道具类型筛选栏
class ImportPreviewTypeFilterBar extends StatelessWidget {
  final int? selectedType;
  final ValueChanged<int?> onTypeChanged;

  const ImportPreviewTypeFilterBar({
    super.key,
    required this.selectedType,
    required this.onTypeChanged,
  });

  static const _types = [
    (null, '全部'),
    (GrenadeType.smoke, '烟雾'),
    (GrenadeType.flash, '闪光'),
    (GrenadeType.molotov, '燃烧'),
    (GrenadeType.he, '手雷'),
    (GrenadeType.wallbang, '穿点'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _types.map((t) {
            final isSelected = selectedType == t.$1;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GrenadeFilterIcon(
                      type: t.$1,
                      size: 16,
                      color: isSelected ? Colors.white : Colors.grey,
                    ),
                    const SizedBox(width: 4),
                    Text(t.$2),
                  ],
                ),
                selected: isSelected,
                onSelected: (_) => onTypeChanged(t.$1),
                selectedColor: Colors.orange,
                checkmarkColor: Colors.white,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

/// 道具全选控制栏
class ImportPreviewSelectAllBar extends StatelessWidget {
  final int selectedInCurrent;
  final int currentTotal;
  final int totalSelectedCount;
  final VoidCallback onToggleSelectAll;

  const ImportPreviewSelectAllBar({
    super.key,
    required this.selectedInCurrent,
    required this.currentTotal,
    required this.totalSelectedCount,
    required this.onToggleSelectAll,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Row(
        children: [
          Checkbox(
            value: currentTotal > 0 && selectedInCurrent == currentTotal,
            tristate: selectedInCurrent > 0 && selectedInCurrent < currentTotal,
            onChanged: (_) => onToggleSelectAll(),
            activeColor: Colors.orange,
          ),
          Text(
            '全选 ($selectedInCurrent/$currentTotal)',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          Text(
            '已选 $totalSelectedCount 个',
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// 待导入道具列表项
class ImportPreviewGrenadeTile extends StatelessWidget {
  final GrenadePreviewItem grenade;
  final bool isSelected;
  final ValueChanged<bool> onChanged;
  final VoidCallback onPreview;

  const ImportPreviewGrenadeTile({
    super.key,
    required this.grenade,
    required this.isSelected,
    required this.onChanged,
    required this.onPreview,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Checkbox(
          value: isSelected,
          onChanged: (val) => onChanged(val == true),
          activeColor: Colors.orange,
        ),
        title: Row(
          children: [
            GrenadeTypeIcon(type: grenade.type, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                grenade.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _ImportStatusBadge(status: grenade.status),
          ],
        ),
        subtitle: grenade.author != null
            ? Text(
                'by: ${grenade.author}',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              )
            : null,
        trailing: IconButton(
          icon: const Icon(Icons.visibility, color: Colors.blueAccent),
          tooltip: '预览道具',
          onPressed: onPreview,
        ),
        dense: true,
        onTap: () => onChanged(!isSelected),
      ),
    );
  }
}

class _ImportStatusBadge extends StatelessWidget {
  final ImportStatus status;

  const _ImportStatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      ImportStatus.newItem => ('新增', Colors.green),
      ImportStatus.update => ('更新', Colors.orange),
      ImportStatus.skip => ('跳过', Colors.grey),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, color: color),
      ),
    );
  }
}

/// 道具删除墓碑列表项
class ImportPreviewTombstoneTile extends StatelessWidget {
  final PackageGrenadeTombstoneData item;
  final GrenadePreviewItem? localGrenade;
  final VoidCallback? onPreviewLocal;

  const ImportPreviewTombstoneTile({
    super.key,
    required this.item,
    required this.localGrenade,
    this.onPreviewLocal,
  });

  @override
  Widget build(BuildContext context) {
    final deletedAtText = _formatDeletedAt(item.deletedAt);
    final local = localGrenade;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: local != null
            ? GrenadeTypeIcon(type: local.type, size: 20)
            : const Icon(Icons.delete_outline, size: 20, color: Colors.grey),
        title: Text(local?.title ?? item.uniqueId),
        subtitle: Text(
          local != null
              ? '${local.mapName} - ${local.layerName} · $deletedAtText'
              : '${item.mapName} · $deletedAtText',
        ),
        trailing: local == null
            ? null
            : IconButton(
                icon: const Icon(Icons.visibility, color: Colors.blueAccent),
                tooltip: '预览本地道具',
                onPressed: onPreviewLocal,
              ),
      ),
    );
  }
}

/// 非道具实体删除墓碑列表项
class ImportPreviewEntityTombstoneTile extends StatelessWidget {
  final PackageEntityTombstoneData item;

  const ImportPreviewEntityTombstoneTile({
    super.key,
    required this.item,
  });

  @override
  Widget build(BuildContext context) {
    final deletedAtText = _formatDeletedAt(item.deletedAt);
    final (icon, title, subtitle) = switch (item.entityType) {
      LanSyncEntityTombstoneType.tag => (
          Icons.sell_outlined,
          '标签：${(item.payload['tagName'] as String? ?? item.entityKey).trim()}',
          '${item.mapName} · ${TagDimension.getName(item.payload['dimension'] as int? ?? TagDimension.custom)} · $deletedAtText',
        ),
      LanSyncEntityTombstoneType.area => (
          Icons.polyline_outlined,
          '区域：${(item.payload['tagName'] as String? ?? item.entityKey).trim()}',
          '${item.mapName} / ${(item.payload['layerName'] as String? ?? 'Default').trim()} · $deletedAtText',
        ),
      LanSyncEntityTombstoneType.favoriteFolder => (
          Icons.folder_delete_outlined,
          '收藏夹：${(item.payload['name'] as String? ?? item.entityKey).trim()}',
          '${item.mapName} · $deletedAtText',
        ),
      LanSyncEntityTombstoneType.impactGroup => (
          Icons.scatter_plot_outlined,
          '爆点分组：${(item.payload['name'] as String? ?? item.entityKey).trim()}',
          '${item.mapName} / ${(item.payload['layerName'] as String? ?? '-').trim()} · $deletedAtText',
        ),
      _ => (
          Icons.delete_outline,
          item.entityKey,
          '${item.mapName} · $deletedAtText',
        ),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: Colors.redAccent),
        title: Text(title),
        subtitle: Text(subtitle),
      ),
    );
  }
}

/// 底部确认导入操作栏
class ImportPreviewBottomActionBar extends StatelessWidget {
  final int grenadeCount;
  final int metadataCount;
  final int tombstoneCount;
  final bool isImporting;
  final VoidCallback onImport;

  const ImportPreviewBottomActionBar({
    super.key,
    required this.grenadeCount,
    required this.metadataCount,
    required this.tombstoneCount,
    required this.isImporting,
    required this.onImport,
  });

  @override
  Widget build(BuildContext context) {
    final canImport =
        grenadeCount > 0 || metadataCount > 0 || tombstoneCount > 0;
    final labelParts = <String>[
      if (grenadeCount > 0) '$grenadeCount 个道具',
      if (metadataCount > 0) '元数据 $metadataCount 项',
      if (tombstoneCount > 0) '删除 $tombstoneCount 条',
    ];
    final label =
        labelParts.isEmpty ? '确认导入' : '确认导入 (${labelParts.join(' + ')})';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: !canImport || isImporting ? null : onImport,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            disabledBackgroundColor: Colors.grey,
          ),
          child: isImporting
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : Text(
                  label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
      ),
    );
  }
}
