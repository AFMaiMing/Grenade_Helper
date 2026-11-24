import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';

import '../models.dart';
import '../providers.dart';
import '../services/data_service.dart';
import 'export_select/export_bottom_action_bar.dart';
import 'export_select/export_select_views.dart';
import 'grenade_detail_screen.dart';

/// 导出选择界面
class ExportSelectScreen extends ConsumerStatefulWidget {
  /// 0=选择道具(从所有道具), 1=选择地图, 2=从指定地图选择道具
  final int mode;
  final GameMap? singleMap;

  const ExportSelectScreen({
    super.key,
    required this.mode,
    this.singleMap,
  });

  @override
  ConsumerState<ExportSelectScreen> createState() => _ExportSelectScreenState();
}

class _ExportSelectScreenState extends ConsumerState<ExportSelectScreen> {
  bool _isLoading = true;
  bool _isExporting = false;
  bool _isEstimating = false;
  int _estimateRequestId = 0;
  ExportPackageEstimate? _exportEstimate;
  String? _estimateError;

  List<GameMap> _maps = [];
  Map<String, List<Grenade>> _grenadesByMap = {};
  Set<String> _selectedMapNames = {};
  Set<int> _selectedGrenadeIds = {};
  String? _currentMapName;
  int? _filterType;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    final isar = ref.read(isarProvider);
    final maps = isar.gameMaps.where().findAllSync();
    final grenadesByMap = <String, List<Grenade>>{};

    for (final map in maps) {
      map.layers.loadSync();
      final grenades = <Grenade>[];
      for (final layer in map.layers) {
        layer.grenades.loadSync();
        for (final g in layer.grenades) {
          g.layer.loadSync();
          g.layer.value?.map.loadSync();
          grenades.add(g);
        }
      }
      if (grenades.isNotEmpty) {
        grenadesByMap[map.name] = grenades;
      }
    }

    // 按模式初始化默认全选范围
    if (widget.mode == 1) {
      _selectedMapNames = grenadesByMap.keys.toSet();
    } else if (widget.mode == 2 && widget.singleMap != null) {
      _currentMapName = widget.singleMap!.name;
      final mapGrenades = grenadesByMap[_currentMapName] ?? const <Grenade>[];
      _selectedGrenadeIds = mapGrenades.map((g) => g.id).toSet();
    } else {
      for (final grenades in grenadesByMap.values) {
        _selectedGrenadeIds.addAll(grenades.map((g) => g.id));
      }
    }

    setState(() {
      _maps = maps;
      _grenadesByMap = grenadesByMap;
      _isLoading = false;
    });
    _refreshExportEstimate();
  }

  List<Grenade> _getCurrentGrenades() {
    if (_currentMapName == null) return [];
    final grenades = _grenadesByMap[_currentMapName] ?? [];
    if (_filterType == null) return grenades;
    return grenades.where((g) => g.type == _filterType).toList();
  }

  void _toggleSelectAllGrenades() {
    final currentIds = _getCurrentGrenades().map((g) => g.id).toSet();
    final allSelected =
        currentIds.every((id) => _selectedGrenadeIds.contains(id));

    _updateSelectionState(() {
      if (allSelected) {
        _selectedGrenadeIds.removeAll(currentIds);
      } else {
        _selectedGrenadeIds.addAll(currentIds);
      }
    });
  }

  void _toggleSelectAllMaps() {
    final allMaps = _grenadesByMap.keys.toSet();
    final allSelected =
        allMaps.every((name) => _selectedMapNames.contains(name));

    _updateSelectionState(() {
      if (allSelected) {
        _selectedMapNames.clear();
      } else {
        _selectedMapNames = allMaps;
      }
    });
  }

  void _updateSelectionState(VoidCallback change) {
    setState(change);
    _refreshExportEstimate();
  }

  List<Grenade> _getSelectedGrenadesForExport() {
    final result = <Grenade>[];
    if (widget.mode == 1) {
      for (final mapName in _selectedMapNames) {
        result.addAll(_grenadesByMap[mapName] ?? const <Grenade>[]);
      }
      return result;
    }
    for (final grenades in _grenadesByMap.values) {
      result.addAll(
        grenades.where((g) => _selectedGrenadeIds.contains(g.id)),
      );
    }
    return result;
  }

  Future<void> _refreshExportEstimate() async {
    final grenades = _getSelectedGrenadesForExport();
    final requestId = ++_estimateRequestId;

    if (grenades.isEmpty) {
      if (!mounted) return;
      setState(() {
        _isEstimating = false;
        _exportEstimate = null;
        _estimateError = null;
      });
      return;
    }

    setState(() {
      _isEstimating = true;
      _estimateError = null;
    });

    try {
      final dataService = DataService(ref.read(isarProvider));
      final estimate = await dataService.estimateExportPackage(grenades);
      if (!mounted || requestId != _estimateRequestId) return;
      setState(() {
        _isEstimating = false;
        _exportEstimate = estimate;
      });
    } catch (_) {
      if (!mounted || requestId != _estimateRequestId) return;
      setState(() {
        _isEstimating = false;
        _exportEstimate = null;
        _estimateError = '无法估算导出包体';
      });
    }
  }

  Future<void> _doExport() async {
    try {
      final grenadesToExport = _getSelectedGrenadesForExport();
      if (grenadesToExport.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('未选择任何道具'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      if ((_exportEstimate?.exceedsLimit ?? false) && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '预计导出包体 ${DataService.formatBytes(_exportEstimate!.estimatedPackageBytes)}，'
              '已超过上限 ${DataService.formatBytes(_exportEstimate!.limitBytes)}',
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      setState(() => _isExporting = true);

      // 让出主线程一帧以先渲染加载态指示器
      await Future.delayed(const Duration(milliseconds: 50));
      if (!mounted) return;

      final isar = ref.read(isarProvider);
      final dataService = DataService(isar);
      await dataService.exportSelectedGrenades(context, grenadesToExport);

      if (mounted) {
        setState(() => _isExporting = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e'), backgroundColor: Colors.red),
        );
        setState(() => _isExporting = false);
      }
    }
  }

  Widget _buildBottomActionBar(bool enabled) {
    final count = widget.mode == 1
        ? _selectedMapNames.fold<int>(
            0,
            (sum, name) => sum + (_grenadesByMap[name]?.length ?? 0),
          )
        : _selectedGrenadeIds.length;

    return ExportBottomActionBar(
      enabled: enabled,
      selectedCount: count,
      isExporting: _isExporting,
      isEstimating: _isEstimating,
      exportEstimate: _exportEstimate,
      estimateError: _estimateError,
      onExport: _doExport,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('选择要分享的内容')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final mapsWithGrenades =
        _maps.where((m) => _grenadesByMap.containsKey(m.name)).toList();

    if (widget.mode == 1) {
      return ExportMapSelectView(
        mapsWithGrenades: mapsWithGrenades,
        grenadesByMap: _grenadesByMap,
        selectedMapNames: _selectedMapNames,
        onToggleSelectAll: _toggleSelectAllMaps,
        onToggleMap: (mapName, selected) {
          _updateSelectionState(() {
            if (selected) {
              _selectedMapNames.add(mapName);
            } else {
              _selectedMapNames.remove(mapName);
            }
          });
        },
        bottomBar: _buildBottomActionBar(_selectedMapNames.isNotEmpty),
      );
    }

    if (widget.mode == 0 && _currentMapName == null) {
      return ExportMapListForGrenadeView(
        mapsWithGrenades: mapsWithGrenades,
        grenadesByMap: _grenadesByMap,
        selectedGrenadeIds: _selectedGrenadeIds,
        onToggleAllMaps: (allSelected) {
          _updateSelectionState(() {
            if (allSelected) {
              _selectedGrenadeIds.clear();
            } else {
              for (final grenades in _grenadesByMap.values) {
                _selectedGrenadeIds.addAll(grenades.map((g) => g.id));
              }
            }
          });
        },
        onToggleMapGrenades: (mapGrenades, selectAll) {
          _updateSelectionState(() {
            final ids = mapGrenades.map((g) => g.id);
            if (selectAll) {
              _selectedGrenadeIds.addAll(ids);
            } else {
              _selectedGrenadeIds.removeAll(ids);
            }
          });
        },
        onOpenMap: (mapName) => setState(() => _currentMapName = mapName),
        bottomBar: _buildBottomActionBar(_selectedGrenadeIds.isNotEmpty),
      );
    }

    return _buildGrenadeListScreen();
  }

  Widget _buildGrenadeListScreen() {
    final grenades = _getCurrentGrenades();
    final currentIds = grenades.map((g) => g.id).toSet();
    final selectedInCurrent =
        currentIds.where((id) => _selectedGrenadeIds.contains(id)).length;

    return Scaffold(
      appBar: AppBar(
        title: Text(_currentMapName ?? '选择道具'),
        leading: widget.mode == 0
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _currentMapName = null),
              )
            : null,
      ),
      body: Column(
        children: [
          ExportTypeFilterBar(
            selectedType: _filterType,
            onTypeChanged: (type) => setState(() => _filterType = type),
          ),
          ExportSelectAllBar(
            value: grenades.isNotEmpty && selectedInCurrent == grenades.length,
            tristate:
                selectedInCurrent > 0 && selectedInCurrent < grenades.length,
            label: '全选 ($selectedInCurrent/${grenades.length})',
            onToggle: _toggleSelectAllGrenades,
            trailing: Text(
              '共选 ${_selectedGrenadeIds.length} 个',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ),
          Expanded(
            child: grenades.isEmpty
                ? const Center(
                    child: Text('无匹配的道具', style: TextStyle(color: Colors.grey)),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: grenades.length,
                    itemBuilder: (context, index) {
                      final grenade = grenades[index];
                      return ExportGrenadeTile(
                        grenade: grenade,
                        isSelected: _selectedGrenadeIds.contains(grenade.id),
                        onChanged: (selected) {
                          _updateSelectionState(() {
                            if (selected) {
                              _selectedGrenadeIds.add(grenade.id);
                            } else {
                              _selectedGrenadeIds.remove(grenade.id);
                            }
                          });
                        },
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
          _buildBottomActionBar(_selectedGrenadeIds.isNotEmpty),
        ],
      ),
    );
  }
}
