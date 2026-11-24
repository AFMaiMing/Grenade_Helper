import 'package:flutter/material.dart';

import '../../models.dart';
import '../../widgets/grenade_type_icon.dart';
import '../../widgets/map_icon.dart';
import '../../widgets/selectable_grenade_list_item.dart';
import '../grenade_detail_screen.dart';

/// 局域网发送按道具多选页面
class LanSyncGrenadePickerScreen extends StatefulWidget {
  final List<Grenade> grenades;
  final Set<int> initialSelectedIds;

  const LanSyncGrenadePickerScreen({
    super.key,
    required this.grenades,
    required this.initialSelectedIds,
  });

  @override
  State<LanSyncGrenadePickerScreen> createState() =>
      _LanSyncGrenadePickerScreenState();
}

class _LanSyncGrenadePickerScreenState
    extends State<LanSyncGrenadePickerScreen> {
  late final Set<int> _selectedIds;
  int? _filterType;
  String? _filterMapName;

  @override
  void initState() {
    super.initState();
    _selectedIds = {...widget.initialSelectedIds};
  }

  List<Grenade> get _visibleGrenades {
    return widget.grenades.where((grenade) {
      if (_filterType != null && grenade.type != _filterType) {
        return false;
      }
      if (_filterMapName == null) return true;
      grenade.layer.loadSync();
      final layer = grenade.layer.value;
      layer?.map.loadSync();
      final mapName = layer?.map.value?.name.trim() ?? '';
      return mapName == _filterMapName;
    }).toList(growable: false);
  }

  List<_LanSyncMapFilterOption> get _availableMaps {
    final optionsByName = <String, _LanSyncMapFilterOption>{};
    for (final grenade in widget.grenades) {
      grenade.layer.loadSync();
      final layer = grenade.layer.value;
      layer?.map.loadSync();
      final map = layer?.map.value;
      final mapName = map?.name.trim() ?? '';
      if (mapName.isEmpty || optionsByName.containsKey(mapName)) continue;
      optionsByName[mapName] = _LanSyncMapFilterOption(
        name: mapName,
        iconPath: map?.iconPath.trim() ?? '',
      );
    }

    final options = optionsByName.values.toList(growable: false);
    options.sort((a, b) => a.name.compareTo(b.name));
    return options;
  }

  void _toggleSelection(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _toggleSelectAllVisible() {
    final visibleIds = _visibleGrenades.map((e) => e.id).toSet();
    final allSelected =
        visibleIds.isNotEmpty && visibleIds.every(_selectedIds.contains);
    setState(() {
      if (allSelected) {
        _selectedIds.removeAll(visibleIds);
      } else {
        _selectedIds.addAll(visibleIds);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final visibleGrenades = _visibleGrenades;
    final selectedInVisible =
        visibleGrenades.where((e) => _selectedIds.contains(e.id)).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('选择道具'),
        actions: [
          if (widget.grenades.isNotEmpty)
            TextButton.icon(
              onPressed: _toggleSelectAllVisible,
              icon: Icon(
                visibleGrenades.isNotEmpty &&
                        selectedInVisible == visibleGrenades.length
                    ? Icons.deselect
                    : Icons.select_all,
                size: 18,
              ),
              label: Text(
                visibleGrenades.isNotEmpty &&
                        selectedInVisible == visibleGrenades.length
                    ? '取消全选'
                    : '全选',
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          _buildMapDropdown(),
          _buildTypeFilter(),
          _buildSelectionBar(selectedInVisible, visibleGrenades.length),
          Expanded(
            child: visibleGrenades.isEmpty
                ? const Center(
                    child: Text(
                      '当前筛选下没有道具',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: visibleGrenades.length,
                    itemBuilder: (context, index) {
                      final grenade = visibleGrenades[index];
                      final isSelected = _selectedIds.contains(grenade.id);
                      return SelectableGrenadeListItem(
                        grenade: grenade,
                        selected: isSelected,
                        onChanged: (_) => _toggleSelection(grenade.id),
                        onTap: () => _toggleSelection(grenade.id),
                        onPreview: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => GrenadeDetailScreen(
                                grenadeId: grenade.id,
                                isEditing: false,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 6,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: FilledButton.icon(
            onPressed: () => Navigator.pop(context, _selectedIds.toList()),
            icon: const Icon(Icons.check),
            label: Text('确认选择 (${_selectedIds.length})'),
          ),
        ),
      ),
    );
  }

  Widget _buildMapDropdown() {
    final maps = _availableMaps;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: DropdownButtonFormField<String?>(
        initialValue: _filterMapName,
        decoration: const InputDecoration(
          labelText: '选择地图',
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        items: [
          const DropdownMenuItem<String?>(
            value: null,
            child: _LanSyncMapDropdownLabel(
              icon: Icon(Icons.public, size: 20, color: Colors.orange),
              text: '全部地图',
            ),
          ),
          ...maps.map(
            (map) => DropdownMenuItem<String?>(
              value: map.name,
              child: _LanSyncMapDropdownLabel(
                icon: _LanSyncMapIcon(iconPath: map.iconPath, size: 20),
                text: map.name,
              ),
            ),
          ),
        ],
        onChanged: (value) => setState(() => _filterMapName = value),
      ),
    );
  }

  Widget _buildTypeFilter() {
    const types = [
      (null, '全部'),
      (GrenadeType.smoke, '烟雾'),
      (GrenadeType.flash, '闪光'),
      (GrenadeType.molotov, '燃烧'),
      (GrenadeType.he, '手雷'),
      (GrenadeType.wallbang, '穿点'),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: types.map((item) {
            final isSelected = _filterType == item.$1;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                selected: isSelected,
                onSelected: (_) => setState(() => _filterType = item.$1),
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GrenadeFilterIcon(
                      type: item.$1,
                      size: 16,
                      color: isSelected ? Colors.white : Colors.grey,
                    ),
                    const SizedBox(width: 4),
                    Text(item.$2),
                  ],
                ),
                selectedColor: Colors.orange,
                checkmarkColor: Colors.white,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildSelectionBar(int selected, int total) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Checkbox(
            value: total > 0 && selected == total,
            tristate: selected > 0 && selected < total,
            onChanged: (_) => _toggleSelectAllVisible(),
            activeColor: Colors.orange,
          ),
          Text(
            '当前筛选全选 ($selected/$total)',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          Text(
            '总计已选 ${_selectedIds.length} 个',
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _LanSyncMapFilterOption {
  final String name;
  final String iconPath;

  const _LanSyncMapFilterOption({required this.name, required this.iconPath});
}

class _LanSyncMapIcon extends StatelessWidget {
  final String iconPath;
  final double size;

  const _LanSyncMapIcon({required this.iconPath, this.size = 18});

  @override
  Widget build(BuildContext context) {
    return MapIcon(path: iconPath, size: size);
  }
}

class _LanSyncMapDropdownLabel extends StatelessWidget {
  final Widget icon;
  final String text;

  const _LanSyncMapDropdownLabel({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        icon,
        const SizedBox(width: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}
