import 'package:flutter/material.dart';

import '../../models.dart';
import '../../widgets/grenade_type_icon.dart';
import '../../widgets/map_icon.dart';

/// 通用全选控制栏
class ExportSelectAllBar extends StatelessWidget {
  final bool value;
  final bool tristate;
  final String label;
  final VoidCallback onToggle;
  final Widget? trailing;

  const ExportSelectAllBar({
    super.key,
    required this.value,
    required this.tristate,
    required this.label,
    required this.onToggle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Checkbox(
            value: value,
            tristate: tristate,
            onChanged: (_) => onToggle(),
            activeColor: Colors.orange,
          ),
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          if (trailing != null) ...[
            const Spacer(),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// 导出道具类型筛选栏
class ExportTypeFilterBar extends StatelessWidget {
  final int? selectedType;
  final ValueChanged<int?> onTypeChanged;

  const ExportTypeFilterBar({
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

/// 整图导出模式的地图选择视图
class ExportMapSelectView extends StatelessWidget {
  final List<GameMap> mapsWithGrenades;
  final Map<String, List<Grenade>> grenadesByMap;
  final Set<String> selectedMapNames;
  final VoidCallback onToggleSelectAll;
  final void Function(String mapName, bool selected) onToggleMap;
  final Widget bottomBar;

  const ExportMapSelectView({
    super.key,
    required this.mapsWithGrenades,
    required this.grenadesByMap,
    required this.selectedMapNames,
    required this.onToggleSelectAll,
    required this.onToggleMap,
    required this.bottomBar,
  });

  @override
  Widget build(BuildContext context) {
    final allSelected =
        mapsWithGrenades.every((m) => selectedMapNames.contains(m.name));
    final selectedCount = selectedMapNames.length;

    return Scaffold(
      appBar: AppBar(title: const Text('选择要分享的地图')),
      body: Column(
        children: [
          ExportSelectAllBar(
            value: mapsWithGrenades.isNotEmpty && allSelected,
            tristate: selectedCount > 0 && !allSelected,
            label: '全选 ($selectedCount/${mapsWithGrenades.length})',
            onToggle: onToggleSelectAll,
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: mapsWithGrenades.length,
              itemBuilder: (context, index) {
                final map = mapsWithGrenades[index];
                final count = grenadesByMap[map.name]?.length ?? 0;
                final isSelected = selectedMapNames.contains(map.name);

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: Checkbox(
                      value: isSelected,
                      onChanged: (val) => onToggleMap(map.name, val == true),
                      activeColor: Colors.orange,
                    ),
                    title: Row(
                      children: [
                        MapIcon(path: map.iconPath, size: 32),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            map.name,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(left: 44),
                      child: Text('$count 个道具'),
                    ),
                    onTap: () => onToggleMap(map.name, !isSelected),
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

/// 按道具导出模式下的地图目录视图
class ExportMapListForGrenadeView extends StatelessWidget {
  final List<GameMap> mapsWithGrenades;
  final Map<String, List<Grenade>> grenadesByMap;
  final Set<int> selectedGrenadeIds;
  final void Function(bool allSelected) onToggleAllMaps;
  final void Function(List<Grenade> mapGrenades, bool selectAll)
      onToggleMapGrenades;
  final ValueChanged<String> onOpenMap;
  final Widget bottomBar;

  const ExportMapListForGrenadeView({
    super.key,
    required this.mapsWithGrenades,
    required this.grenadesByMap,
    required this.selectedGrenadeIds,
    required this.onToggleAllMaps,
    required this.onToggleMapGrenades,
    required this.onOpenMap,
    required this.bottomBar,
  });

  @override
  Widget build(BuildContext context) {
    var totalGrenades = 0;
    for (final grenades in grenadesByMap.values) {
      totalGrenades += grenades.length;
    }
    final allSelected =
        totalGrenades > 0 && selectedGrenadeIds.length == totalGrenades;

    return Scaffold(
      appBar: AppBar(title: const Text('选择地图')),
      body: Column(
        children: [
          ExportSelectAllBar(
            value: allSelected,
            tristate: selectedGrenadeIds.isNotEmpty && !allSelected,
            label: '全选所有地图 (${selectedGrenadeIds.length}/$totalGrenades)',
            onToggle: () => onToggleAllMaps(allSelected),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: mapsWithGrenades.length,
              itemBuilder: (context, index) {
                final map = mapsWithGrenades[index];
                final grenades = grenadesByMap[map.name] ?? const <Grenade>[];
                final selectedInMap = grenades
                    .where((g) => selectedGrenadeIds.contains(g.id))
                    .length;
                final allInMapSelected =
                    grenades.isNotEmpty && selectedInMap == grenades.length;

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: Checkbox(
                      value: allInMapSelected,
                      tristate: selectedInMap > 0 && !allInMapSelected,
                      onChanged: (_) =>
                          onToggleMapGrenades(grenades, !allInMapSelected),
                      activeColor: Colors.orange,
                    ),
                    title: Row(
                      children: [
                        MapIcon(path: map.iconPath, size: 32),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            map.name,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(left: 44),
                      child: Text('已选 $selectedInMap / ${grenades.length} 个道具'),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => onOpenMap(map.name),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: bottomBar,
    );
  }
}

/// 待导出道具列表项
class ExportGrenadeTile extends StatelessWidget {
  final Grenade grenade;
  final bool isSelected;
  final ValueChanged<bool> onChanged;
  final VoidCallback onPreview;

  const ExportGrenadeTile({
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
