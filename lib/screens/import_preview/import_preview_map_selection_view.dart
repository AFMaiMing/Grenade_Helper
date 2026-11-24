import 'package:flutter/material.dart';
import 'package:isar_community/isar.dart';

import '../../models.dart';
import '../../services/data_service.dart';
import '../../widgets/map_icon.dart';
import 'import_preview_items.dart';

/// 多地图导入预览的地图选择子视图
class ImportPreviewMapSelectionView extends StatelessWidget {
  final PackagePreviewResult preview;
  final Isar isar;
  final ValueChanged<String> onSelectMap;
  final Widget bottomBar;

  const ImportPreviewMapSelectionView({
    super.key,
    required this.preview,
    required this.isar,
    required this.onSelectMap,
    required this.bottomBar,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('选择地图')),
      body: Column(
        children: [
          LegacyPackageNoticeBanner(visible: preview.isLegacyPackage),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: preview.mapNames.length,
              itemBuilder: (context, index) {
                final mapName = preview.mapNames[index];
                final count = preview.grenadesByMap[mapName]?.length ?? 0;
                final tombstoneCount = preview.grenadeTombstones
                    .where((item) => item.mapName.trim() == mapName.trim())
                    .length;
                final entityTombstoneCount = preview.entityTombstones
                    .where((item) => item.mapName.trim() == mapName.trim())
                    .length;
                final gameMap =
                    isar.gameMaps.filter().nameEqualTo(mapName).findFirstSync();
                var packageIconPath = '';
                for (final mapData in preview.maps) {
                  if (mapData.mapName.trim() == mapName.trim()) {
                    packageIconPath = mapData.iconPath;
                    break;
                  }
                }

                final subtitleParts = <String>['$count 个道具'];
                if (tombstoneCount > 0) {
                  subtitleParts.add('删除 $tombstoneCount 条');
                }
                if (entityTombstoneCount > 0) {
                  subtitleParts.add('其他删除 $entityTombstoneCount 条');
                }

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: MapIcon(
                      path: gameMap?.iconPath ?? packageIconPath,
                      size: 40,
                    ),
                    title: Text(
                      mapName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(subtitleParts.join(' · ')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => onSelectMap(mapName),
                  ),
                );
              },
            ),
          ),
          bottomBar,
        ],
      ),
    );
  }
}
