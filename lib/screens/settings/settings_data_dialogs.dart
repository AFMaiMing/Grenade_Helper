import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';

import '../../models.dart';
import '../../providers.dart';
import '../../services/data_service.dart';
import '../../services/map_management_service.dart';
import '../../services/settings_service.dart';
import '../../services/tag_service.dart';
import 'hotkey_editor_dialog.dart';

/// 设置页数据管理与存储目录操作弹窗集合
class SettingsDataActions {
  const SettingsDataActions._();

  static Future<void> scanAndCleanupOrphanMediaFiles({
    required BuildContext context,
    required WidgetRef ref,
  }) async {
    final isar = ref.read(isarProvider);
    final dataService = DataService(isar);

    if (!context.mounted) return;
    _showBlockingProgressDialog(context, '正在扫描孤儿媒体文件...');

    late final OrphanMediaScanResult scanResult;
    try {
      scanResult = await dataService.scanOrphanMediaFiles();
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('扫描失败: $e'), backgroundColor: Colors.red),
      );
      return;
    }

    if (!context.mounted) return;
    Navigator.pop(context);

    if (!scanResult.hasAnythingToClean) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未发现可清理的孤儿媒体文件')),
      );
      return;
    }

    final previewItems = scanResult.orphanFiles.take(8).toList(growable: false);
    final summaryLines = <String>[];
    if (scanResult.orphanFiles.isNotEmpty) {
      summaryLines.add(
        '共发现 ${scanResult.orphanFiles.length} 个未被引用的媒体文件，预计可释放 ${_formatBytes(scanResult.totalSizeBytes)}。',
      );
    }
    if (scanResult.orphanRecordCount > 0) {
      summaryLines.add(
        '同时发现 ${scanResult.orphanRecordCount} 条无效残留数据库记录（步骤 ${scanResult.orphanStepIds.length} 条、媒体 ${scanResult.orphanMediaIds.length} 条），将一并清理。',
      );
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('发现孤儿媒体文件'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(summaryLines.join('\n')),
                if (previewItems.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text(
                    '示例文件：',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ...previewItems.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '${File(item.path).uri.pathSegments.isEmpty ? item.path : File(item.path).uri.pathSegments.last} · ${_formatBytes(item.sizeBytes)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                  if (scanResult.orphanFiles.length > previewItems.length)
                    Text(
                      '还有 ${scanResult.orphanFiles.length - previewItems.length} 个文件未展开显示。',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.lightBlueAccent,
              foregroundColor: Colors.black,
            ),
            child: const Text('立即清理'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;
    _showBlockingProgressDialog(context, '正在清理孤儿媒体文件...');

    late final OrphanMediaCleanupResult cleanupResult;
    try {
      cleanupResult = await dataService.cleanupOrphanMediaFiles(
        scanResult.orphanFiles,
        orphanStepIds: scanResult.orphanStepIds,
        orphanMediaIds: scanResult.orphanMediaIds,
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('清理失败: $e'), backgroundColor: Colors.red),
      );
      return;
    }

    if (!context.mounted) return;
    Navigator.pop(context);

    final failedCount = cleanupResult.failedFiles.length;
    final successCount = cleanupResult.deletedFiles.length;
    final recordCount = cleanupResult.deletedRecordCount;
    final parts = <String>[];
    if (successCount > 0 || failedCount == 0) {
      parts.add(
        '已清理 $successCount 个孤儿媒体文件，释放 ${_formatBytes(cleanupResult.deletedBytes)}',
      );
    }
    if (recordCount > 0) {
      parts.add('清除 $recordCount 条残留记录');
    }
    if (failedCount > 0) {
      parts.add('失败 $failedCount 个（文件可能被其他程序占用）');
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(parts.join('，')),
        backgroundColor: failedCount == 0 ? Colors.green : Colors.orange,
      ),
    );
  }

  static Future<void> showDeleteMapGrenadesDialog({
    required BuildContext context,
    required WidgetRef ref,
  }) async {
    final isar = ref.read(isarProvider);
    final maps = await isar.gameMaps.where().findAll();
    if (maps.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('暂无地图数据')),
        );
      }
      return;
    }

    final mapGrenadeCount = <int, int>{};
    for (final map in maps) {
      await map.layers.load();
      var count = 0;
      for (final layer in map.layers) {
        await layer.grenades.load();
        count += layer.grenades.length;
      }
      mapGrenadeCount[map.id] = count;
    }

    if (!context.mounted) return;
    GameMap? selectedMap;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.delete_sweep, color: Colors.redAccent),
              SizedBox(width: 8),
              Text('清空地图道具'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('选择要清空道具的地图：'),
              const SizedBox(height: 16),
              DropdownButtonFormField<GameMap>(
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                hint: const Text('选择地图'),
                initialValue: selectedMap,
                items: maps.map((map) {
                  final count = mapGrenadeCount[map.id] ?? 0;
                  return DropdownMenuItem(
                    value: map,
                    child: SettingsMapDropdownLabel(
                      iconPath: map.iconPath,
                      text: '${map.name} ($count 个道具)',
                    ),
                  );
                }).toList(),
                onChanged: (value) => setDialogState(() => selectedMap = value),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning, color: Colors.red[400], size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '此操作不可撤销！所有道具及其媒体文件将被永久删除。',
                        style: TextStyle(fontSize: 12, color: Colors.red[400]),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: selectedMap == null
                  ? null
                  : () async {
                      Navigator.pop(ctx);
                      await _performDeleteMapGrenades(
                        context: context,
                        ref: ref,
                        map: selectedMap!,
                      );
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('确认删除'),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> showDeleteCustomMapsDialog({
    required BuildContext context,
    required WidgetRef ref,
  }) async {
    final isar = ref.read(isarProvider);
    final allMaps = await isar.gameMaps.where().findAll();
    final customMaps =
        allMaps.where(MapManagementService.isCustomMap).toList(growable: false);
    if (customMaps.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('暂无可删除的自定义地图')),
        );
      }
      return;
    }

    final selectedMapIds = <int>{};
    if (!context.mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.map_outlined, color: Colors.red[400]),
              const SizedBox(width: 8),
              const Text('删除自定义地图'),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('勾选要删除的自定义地图：'),
                const SizedBox(height: 12),
                SizedBox(
                  height: 280,
                  child: ListView.builder(
                    itemCount: customMaps.length,
                    itemBuilder: (_, index) {
                      final map = customMaps[index];
                      final checked = selectedMapIds.contains(map.id);
                      return CheckboxListTile(
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: checked,
                        title: SettingsMapDropdownLabel(
                          iconPath: map.iconPath,
                          text: map.name,
                        ),
                        onChanged: (value) {
                          setDialogState(() {
                            if (value == true) {
                              selectedMapIds.add(map.id);
                            } else {
                              selectedMapIds.remove(map.id);
                            }
                          });
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '已选择 ${selectedMapIds.length} 张地图',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: selectedMapIds.isEmpty
                  ? null
                  : () async {
                      Navigator.pop(ctx);
                      final targets = customMaps
                          .where((m) => selectedMapIds.contains(m.id))
                          .toList(growable: false);
                      await _performDeleteCustomMaps(
                        context: context,
                        ref: ref,
                        maps: targets,
                      );
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('删除选中'),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> initializeBuiltinAreaMetadataForAllMaps({
    required BuildContext context,
    required WidgetRef ref,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重导入默认区域标签/数据？'),
        content: const Text('将为所有地图补齐内置默认区域标签与区域几何数据，不会删除你已有的自定义区域与标签。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
            ),
            child: const Text('开始导入'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;
    _showBlockingProgressDialog(context, '正在导入默认区域标签与区域数据...');

    try {
      final isar = ref.read(isarProvider);
      final tagService = TagService(isar);
      final result = await tagService.initializeBuiltinAreaMetadataForAllMaps();

      if (!context.mounted) return;
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已处理${result.processedMaps}张地图；标签预设${result.mapsWithPresets}张、区域预设${result.mapsWithAreaData}张；标签新增${result.addedTags}/更新${result.updatedTags}；区域新增${result.addedAreas}/更新${result.updatedAreas}/去重删除${result.removedDuplicateAreas}',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('重导入失败: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  static Future<void> changeDataDirectory({
    required BuildContext context,
    required SettingsService settingsService,
    required String currentDataPath,
    required ValueChanged<String> onPathUpdated,
  }) async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择数据存储目录',
    );
    if (result == null) return;

    final oldPath = currentDataPath;
    if (context.mounted && oldPath != result) {
      final shouldMigrate = await _showMigrationDialog(context);
      if (shouldMigrate == true) {
        await SettingsService.moveData(oldPath, result);
      }
    }

    await settingsService.setCustomDataPath(result);
    onPathUpdated(result);

    if (context.mounted) {
      _showRestartDialog(context);
    }
  }

  static Future<void> resetToDefaultPath({
    required BuildContext context,
    required SettingsService settingsService,
    required String currentDataPath,
    required String defaultDataPath,
    required ValueChanged<String> onPathUpdated,
  }) async {
    final oldPath = currentDataPath;
    if (context.mounted && oldPath != defaultDataPath) {
      final shouldMigrate = await _showMigrationDialog(context);
      if (shouldMigrate == true) {
        await SettingsService.moveData(oldPath, defaultDataPath);
      }
    }

    await settingsService.setCustomDataPath(null);
    onPathUpdated(defaultDataPath);

    if (context.mounted) {
      _showRestartDialog(context);
    }
  }

  static Future<void> _performDeleteMapGrenades({
    required BuildContext context,
    required WidgetRef ref,
    required GameMap map,
  }) async {
    if (!context.mounted) return;
    final isar = ref.read(isarProvider);
    final dataService = DataService(isar);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('二次确认'),
        content: Text('确定要删除「${map.name}」地图的所有道具吗？\n\n此操作无法恢复！'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('确定删除'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;
    _showBlockingProgressDialog(context, '正在删除...');

    try {
      final deletedCount = await dataService.deleteAllGrenadesForMap(map);
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已删除「${map.name}」的 $deletedCount 个道具'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  static Future<void> _performDeleteCustomMaps({
    required BuildContext context,
    required WidgetRef ref,
    required List<GameMap> maps,
  }) async {
    if (maps.isEmpty || !context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('二次确认'),
        content: Text(
          '确定删除选中的 ${maps.length} 张自定义地图吗？\n\n这会删除地图及其所有关联数据，且不可恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('确定删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    _showBlockingProgressDialog(context, '正在删除地图...');

    try {
      final isar = ref.read(isarProvider);
      final deletedCount =
          await MapManagementService(isar).deleteCustomMaps(maps);
      if (!context.mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已删除 $deletedCount 张自定义地图'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败: $e'), backgroundColor: Colors.red),
      );
    }
  }

  static Future<bool?> _showMigrationDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('迁移现有数据？'),
        content: const Text('检测到您更改了数据目录。是否将当前目录下的所有数据（数据库、设置、存档等）自动拷贝到新目录下？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('跳过'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.black,
            ),
            child: const Text('立即迁移'),
          ),
        ],
      ),
    );
  }

  static void _showRestartDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.restart_alt, color: Colors.orange),
            SizedBox(width: 8),
            Text('需要重启'),
          ],
        ),
        content: const Text('数据目录已更改，请手动重启应用以使更改生效。'),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('我知道了'),
          ),
        ],
      ),
    );
  }

  static void _showBlockingProgressDialog(
      BuildContext context, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Text(message),
          ],
        ),
      ),
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    const units = ['KB', 'MB', 'GB', 'TB'];
    var size = bytes.toDouble();
    var unitIndex = -1;
    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }
    final fractionDigits = size >= 100 ? 0 : 1;
    return '${size.toStringAsFixed(fractionDigits)} ${units[unitIndex]}';
  }
}
