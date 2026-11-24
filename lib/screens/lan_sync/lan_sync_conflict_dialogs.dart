import 'package:flutter/material.dart';

import '../../models/tag.dart';
import '../../services/data_service.dart';

/// 局域网导入冲突弹窗决策结果
class LanImportConflictDialogResult<T> {
  final T resolution;
  final bool applyToRemaining;

  const LanImportConflictDialogResult({
    required this.resolution,
    required this.applyToRemaining,
  });
}

/// 展示本地版本较新时的同步冲突提示弹窗
Future<bool?> showLanImportConflictNoticeDialog(
  BuildContext context,
  ImportConflictNotice notice,
) {
  final lines = <String>[];
  for (final item in notice.newerLocalGrenades.take(6)) {
    lines.add('本地较新，将跳过更新：${item.mapName} / ${item.title}');
  }
  for (final item in notice.newerLocalDeleteConflicts.take(6)) {
    lines.add('本地较新，将跳过删除：${item.mapName} / ${item.title}');
  }
  for (final item in notice.newerLocalFavoriteFolderDeletes.take(6)) {
    lines.add('本地较新，将跳过收藏夹删除：$item');
  }
  final hiddenCount = notice.newerLocalGrenades.length +
      notice.newerLocalDeleteConflicts.length +
      notice.newerLocalFavoriteFolderDeletes.length -
      lines.length;
  if (hiddenCount > 0) {
    lines.add('还有 $hiddenCount 条冲突未展开');
  }

  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('发现同步冲突'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('以下内容会在导入时被保留为本地版本，不会被对端覆盖或删除：'),
          const SizedBox(height: 8),
          ...lines.map(
            (line) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(line),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('继续导入'),
        ),
      ],
    ),
  );
}

/// 展示标签冲突解决弹窗
Future<LanImportConflictDialogResult<ImportTagConflictResolution>?>
    showLanTagConflictDialog(
  BuildContext context,
  TagConflictItem conflict, {
  required int index,
  required int total,
}) {
  final reason = conflict.type == TagConflictType.uuidMismatch
      ? '同 UUID 标签属性不一致'
      : '本地已存在同地图同维度同名标签（UUID 不同）';
  final shared = conflict.sharedTag;
  final local = conflict.localTag;

  return _showLanResolutionConflictDialog<ImportTagConflictResolution>(
    context: context,
    title: '标签冲突 $index/$total',
    detailChildren: [
      Text(reason),
      const SizedBox(height: 8),
      Text('地图：${shared.mapName}'),
      Text('维度：${TagDimension.getName(shared.dimension)}'),
      const SizedBox(height: 8),
      Text(
        '本地：${local.name} | 颜色: 0x${local.colorValue.toRadixString(16).toUpperCase()}',
      ),
      Text(
        '分享：${shared.name} | 颜色: 0x${shared.colorValue.toRadixString(16).toUpperCase()}',
      ),
      const SizedBox(height: 8),
      const Text('请选择保留哪一侧标签数据：'),
    ],
    keepLocalValue: ImportTagConflictResolution.local,
    keepLocalLabel: '用本地',
    useSharedValue: ImportTagConflictResolution.shared,
    useSharedLabel: '用分享',
  );
}

/// 展示区域冲突解决弹窗
Future<LanImportConflictDialogResult<ImportAreaConflictResolution>?>
    showLanAreaConflictDialog(
  BuildContext context,
  AreaConflictGroup conflict, {
  required int index,
  required int total,
}) {
  final layersText = conflict.layers.join('、');

  return _showLanResolutionConflictDialog<ImportAreaConflictResolution>(
    context: context,
    title: '区域冲突 $index/$total',
    detailChildren: [
      Text('标签：${conflict.tagName}'),
      Text('地图：${conflict.mapName}'),
      Text('冲突楼层：$layersText'),
      const SizedBox(height: 8),
      const Text('请选择该标签的区域导入策略：'),
    ],
    keepLocalValue: ImportAreaConflictResolution.keepLocal,
    keepLocalLabel: '本地保留',
    useSharedValue: ImportAreaConflictResolution.overwriteShared,
    useSharedLabel: '分享覆盖',
  );
}

Future<LanImportConflictDialogResult<T>?> _showLanResolutionConflictDialog<T>({
  required BuildContext context,
  required String title,
  required List<Widget> detailChildren,
  required T keepLocalValue,
  required String keepLocalLabel,
  required T useSharedValue,
  required String useSharedLabel,
}) {
  var applyToRemaining = false;
  return showDialog<LanImportConflictDialogResult<T>>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...detailChildren,
            const SizedBox(height: 4),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              value: applyToRemaining,
              onChanged: (value) {
                setDialogState(() {
                  applyToRemaining = value ?? false;
                });
              },
              title: const Text('接下来的冲突也一样操作'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消导入'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(
              ctx,
              LanImportConflictDialogResult<T>(
                resolution: keepLocalValue,
                applyToRemaining: applyToRemaining,
              ),
            ),
            child: Text(keepLocalLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              ctx,
              LanImportConflictDialogResult<T>(
                resolution: useSharedValue,
                applyToRemaining: applyToRemaining,
              ),
            ),
            child: Text(useSharedLabel),
          ),
        ],
      ),
    ),
  );
}
