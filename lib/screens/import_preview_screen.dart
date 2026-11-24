import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../services/data_service.dart';
import 'grenade_preview_screen.dart';
import 'import_preview/import_conflict_dialogs.dart';
import 'import_preview/import_preview_items.dart';
import 'import_preview/import_preview_map_selection_view.dart';

/// 导入预览页面
class ImportPreviewScreen extends ConsumerStatefulWidget {
  final String filePath;
  final ImportPackageMode importMode;
  final bool requireTrustedPackage;

  const ImportPreviewScreen({
    super.key,
    required this.filePath,
    this.importMode = ImportPackageMode.normal,
    this.requireTrustedPackage = false,
  });

  @override
  ConsumerState<ImportPreviewScreen> createState() =>
      _ImportPreviewScreenState();
}

class _ImportPreviewScreenState extends ConsumerState<ImportPreviewScreen> {
  PackagePreviewResult? _preview;
  Map<String, GrenadePreviewItem> _localTombstoneItems = const {};
  bool _isLoading = true;
  String? _error;
  String? _selectedMap;
  Set<String> _selectedIds = {};
  int? _filterType;
  bool _isImporting = false;

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    try {
      final isar = ref.read(isarProvider);
      final dataService = DataService(isar);
      final preview = await dataService.previewPackage(
        widget.filePath,
        mode: widget.importMode,
        requireTrustedPackage: widget.requireTrustedPackage,
      );

      if (preview == null) {
        if (!mounted) return;
        setState(() {
          _error =
              widget.requireTrustedPackage ? '无法解析道具包，或包未通过安全校验' : '无法解析道具包';
          _isLoading = false;
        });
        return;
      }

      if (!preview.isMultiMap && preview.mapNames.isNotEmpty) {
        _selectedMap = preview.mapNames.first;
      }

      // 默认选中非跳过状态的全部道具
      final allIds = <String>{};
      for (final grenades in preview.grenadesByMap.values) {
        for (final g in grenades) {
          if (g.status != ImportStatus.skip) {
            allIds.add(g.uniqueId);
          }
        }
      }

      final localTombstoneItems =
          widget.importMode != ImportPackageMode.lanSync ||
                  !preview.canApplyTombstones ||
                  preview.grenadeTombstones.isEmpty
              ? const <String, GrenadePreviewItem>{}
              : await dataService.loadLocalGrenadePreviewItemsByUniqueIds(
                  preview.grenadeTombstones.map((e) => e.uniqueId),
                );

      if (!mounted) return;
      setState(() {
        _preview = preview;
        _localTombstoneItems = localTombstoneItems;
        _selectedIds = allIds;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '加载失败: $e';
        _isLoading = false;
      });
    }
  }

  List<GrenadePreviewItem> _getCurrentGrenades() {
    if (_preview == null || _selectedMap == null) return [];
    final grenades = _preview!.grenadesByMap[_selectedMap] ?? [];
    if (_filterType == null) return grenades;
    return grenades.where((g) => g.type == _filterType).toList();
  }

  List<T> _filterTombstones<T>(
    List<T> source,
    String Function(T) mapNameOf,
    int Function(T) deletedAtOf,
  ) {
    if (_preview == null ||
        widget.importMode != ImportPackageMode.lanSync ||
        !_preview!.canApplyTombstones) {
      return const [];
    }
    final selectedMap = _selectedMap?.trim();
    final filtered = source.where((item) {
      if (selectedMap == null) return true;
      return mapNameOf(item).trim() == selectedMap;
    }).toList(growable: false)
      ..sort((a, b) => deletedAtOf(b).compareTo(deletedAtOf(a)));
    return filtered;
  }

  List<PackageGrenadeTombstoneData> _getCurrentTombstones() =>
      _filterTombstones(
        _preview?.grenadeTombstones ?? const [],
        (item) => item.mapName,
        (item) => item.deletedAt,
      );

  List<PackageEntityTombstoneData> _getCurrentEntityTombstones() =>
      _filterTombstones(
        _preview?.entityTombstones ?? const [],
        (item) => item.mapName,
        (item) => item.deletedAt,
      );

  int _metadataChangeCount() => _preview?.metadataChangeCount ?? 0;

  void _toggleSelectAll() {
    final currentIds = _getCurrentGrenades().map((g) => g.uniqueId).toSet();
    final allSelected = currentIds.every((id) => _selectedIds.contains(id));

    setState(() {
      if (allSelected) {
        _selectedIds.removeAll(currentIds);
      } else {
        _selectedIds.addAll(currentIds);
      }
    });
  }

  Future<void> _doImport() async {
    final preview = _preview;
    if (preview == null) return;
    if (_selectedIds.isEmpty &&
        _metadataChangeCount() == 0 &&
        (widget.importMode != ImportPackageMode.lanSync ||
            (preview.grenadeTombstones.isEmpty &&
                preview.entityTombstones.isEmpty))) {
      return;
    }

    setState(() => _isImporting = true);

    try {
      final isar = ref.read(isarProvider);
      final dataService = DataService(isar);
      final conflictNotice = await dataService.collectImportConflictNotice(
        preview,
        _selectedIds,
        mode: widget.importMode,
      );
      if (conflictNotice.hasConflicts) {
        if (!mounted) return;
        final continueImport =
            await showImportConflictNoticeDialog(context, conflictNotice);
        if (continueImport != true) {
          return;
        }
      }

      final tagResolutions = <String, ImportTagConflictResolution>{};
      final areaResolutions = <String, ImportAreaConflictResolution>{};
      ImportTagConflictResolution? tagResolutionForRemaining;
      ImportAreaConflictResolution? areaResolutionForRemaining;

      final tagConflictBundle =
          await dataService.collectTagConflicts(preview, _selectedIds);
      final tagConflicts = tagConflictBundle.tagConflicts;
      for (var i = 0; i < tagConflicts.length; i++) {
        if (!mounted) return;
        final conflict = tagConflicts[i];
        final dialogResult = tagResolutionForRemaining != null
            ? ConflictDialogResult<ImportTagConflictResolution>(
                resolution: tagResolutionForRemaining,
                applyToRemaining: true,
              )
            : await showImportTagConflictDialog(
                context,
                conflict,
                index: i + 1,
                total: tagConflicts.length,
              );
        if (dialogResult == null) {
          return;
        }
        tagResolutions[conflict.sharedTag.tagUuid] = dialogResult.resolution;
        if (dialogResult.applyToRemaining) {
          tagResolutionForRemaining = dialogResult.resolution;
        }
      }

      final areaConflicts = await dataService.collectAreaConflicts(
        preview,
        _selectedIds,
        tagResolutions: tagResolutions,
      );
      for (var i = 0; i < areaConflicts.length; i++) {
        if (!mounted) return;
        final conflict = areaConflicts[i];
        final dialogResult = areaResolutionForRemaining != null
            ? ConflictDialogResult<ImportAreaConflictResolution>(
                resolution: areaResolutionForRemaining,
                applyToRemaining: true,
              )
            : await showImportAreaConflictDialog(
                context,
                conflict,
                index: i + 1,
                total: areaConflicts.length,
              );
        if (dialogResult == null) {
          return;
        }
        areaResolutions[conflict.tagUuid] = dialogResult.resolution;
        if (dialogResult.applyToRemaining) {
          areaResolutionForRemaining = dialogResult.resolution;
        }
      }

      final result = await dataService.importFromPreview(
        preview,
        _selectedIds,
        tagResolutions: tagResolutions,
        areaResolutions: areaResolutions,
        mode: widget.importMode,
      );

      if (mounted) {
        Navigator.pop(context, result);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('加载中...')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('导入预览')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('返回'),
              ),
            ],
          ),
        ),
      );
    }

    final preview = _preview!;
    if (widget.importMode == ImportPackageMode.lanSync &&
        preview.canApplyTombstones &&
        preview.totalCount == 0 &&
        (preview.grenadeTombstones.isNotEmpty ||
            preview.entityTombstones.isNotEmpty)) {
      return _buildTombstoneOnlyScreen(preview);
    }

    if (preview.isMultiMap && _selectedMap == null) {
      return ImportPreviewMapSelectionView(
        preview: preview,
        isar: ref.read(isarProvider),
        onSelectMap: (mapName) => setState(() => _selectedMap = mapName),
        bottomBar: _buildBottomActionBar(preview),
      );
    }

    return _buildGrenadeListScreen(preview);
  }

  Widget _buildTombstoneOnlyScreen(PackagePreviewResult preview) {
    final tombstones = _getCurrentTombstones();
    final entityTombstones = _getCurrentEntityTombstones();
    return Scaffold(
      appBar: AppBar(title: const Text('删除同步预览')),
      body: Column(
        children: [
          LegacyPackageNoticeBanner(visible: preview.isLegacyPackage),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                ...tombstones.map(_buildTombstoneTile),
                ...entityTombstones.map(
                  (item) => ImportPreviewEntityTombstoneTile(item: item),
                ),
              ],
            ),
          ),
          _buildBottomActionBar(preview),
        ],
      ),
    );
  }

  Widget _buildGrenadeListScreen(PackagePreviewResult preview) {
    final grenades = _getCurrentGrenades();
    final tombstones = _getCurrentTombstones();
    final entityTombstones = _getCurrentEntityTombstones();
    final currentIds = grenades.map((g) => g.uniqueId).toSet();
    final selectedInCurrent =
        currentIds.where((id) => _selectedIds.contains(id)).length;
    final hasVisibleItems = grenades.isNotEmpty ||
        _metadataChangeCount() > 0 ||
        tombstones.isNotEmpty ||
        entityTombstones.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedMap ?? '道具列表'),
        leading: preview.isMultiMap
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _selectedMap = null),
              )
            : null,
      ),
      body: Column(
        children: [
          LegacyPackageNoticeBanner(visible: preview.isLegacyPackage),
          if (grenades.isNotEmpty)
            ImportPreviewTypeFilterBar(
              selectedType: _filterType,
              onTypeChanged: (type) => setState(() => _filterType = type),
            ),
          if (grenades.isNotEmpty)
            ImportPreviewSelectAllBar(
              selectedInCurrent: selectedInCurrent,
              currentTotal: grenades.length,
              totalSelectedCount: _selectedIds.length,
              onToggleSelectAll: _toggleSelectAll,
            ),
          Expanded(
            child: !hasVisibleItems
                ? const Center(
                    child: Text('无匹配的道具', style: TextStyle(color: Colors.grey)),
                  )
                : ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      if (grenades.isEmpty && _metadataChangeCount() > 0)
                        Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: const Icon(Icons.sync_alt),
                            title: const Text('元数据变更'),
                            subtitle: Text(
                              '标签 ${preview.changedTagCount} · 区域 ${preview.changedAreaCount} · 地图 ${preview.changedMapCount} · 收藏夹 ${preview.changedFavoriteFolderCount} · 爆点分组 ${preview.changedImpactGroupCount}',
                            ),
                          ),
                        ),
                      ...grenades.map(
                        (grenade) => ImportPreviewGrenadeTile(
                          grenade: grenade,
                          isSelected: _selectedIds.contains(grenade.uniqueId),
                          onChanged: (selected) {
                            setState(() {
                              if (selected) {
                                _selectedIds.add(grenade.uniqueId);
                              } else {
                                _selectedIds.remove(grenade.uniqueId);
                              }
                            });
                          },
                          onPreview: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => GrenadePreviewScreen(
                                  grenade: grenade,
                                  memoryImages: preview.memoryImages,
                                  packageFilePath: preview.filePath,
                                  packageFileHashes: preview.packageFileHashes,
                                  packageFileSizes: preview.packageFileSizes,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      if (tombstones.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          '删除记录',
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                        const SizedBox(height: 8),
                        ...tombstones.map(_buildTombstoneTile),
                      ],
                      if (entityTombstones.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          '其他删除记录',
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                        const SizedBox(height: 8),
                        ...entityTombstones.map(
                          (item) => ImportPreviewEntityTombstoneTile(
                            item: item,
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
          _buildBottomActionBar(preview),
        ],
      ),
    );
  }

  Widget _buildTombstoneTile(PackageGrenadeTombstoneData item) {
    final localGrenade = _localTombstoneItems[item.uniqueId];
    return ImportPreviewTombstoneTile(
      item: item,
      localGrenade: localGrenade,
      onPreviewLocal: localGrenade == null
          ? null
          : () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => GrenadePreviewScreen(
                    grenade: localGrenade,
                    memoryImages: const {},
                  ),
                ),
              );
            },
    );
  }

  Widget _buildBottomActionBar(PackagePreviewResult preview) {
    final tombstoneCount = widget.importMode == ImportPackageMode.lanSync &&
            preview.canApplyTombstones
        ? preview.grenadeTombstones.length + preview.entityTombstones.length
        : 0;
    return ImportPreviewBottomActionBar(
      grenadeCount: _selectedIds.length,
      metadataCount: _metadataChangeCount(),
      tombstoneCount: tombstoneCount,
      isImporting: _isImporting,
      onImport: _doImport,
    );
  }
}
