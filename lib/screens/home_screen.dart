import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../data/builtin_maps.dart';
import '../models.dart';
import '../providers.dart';
import '../services/data_service.dart';
import '../services/map_management_service.dart';
import '../services/tag_service.dart';
import '../theme/app_design_system.dart';
import 'home/global_search_delegate.dart';
import 'home/home_map_cards.dart';
import 'map_screen.dart';

export 'home/global_search_delegate.dart' show GlobalSearchDelegate;

// 地图库首页（统筹现役/非现役分组网格与自定义地图管理）
class HomeScreen extends ConsumerStatefulWidget {
  final bool embedded;

  const HomeScreen({super.key, this.embedded = false});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final Set<int> _pendingDeleteMapIds = <int>{};
  bool _inReservePool = false;

  Future<bool> _deleteCustomMapQuick(Isar isar, GameMap map) async {
    if (!MapManagementService.isCustomMap(map)) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('仅支持删除自定义地图')),
      );
      return false;
    }

    try {
      final deleted = await MapManagementService(isar).deleteCustomMaps([map]);
      if (!mounted) return deleted > 0;
      if (deleted > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已删除自定义地图：${map.name}')),
        );
        return true;
      }
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败: $e'), backgroundColor: Colors.red),
      );
      return false;
    }
    return false;
  }

  Future<void> _queueCustomMapDelete(Isar isar, GameMap map) async {
    if (_pendingDeleteMapIds.contains(map.id)) return;
    setState(() {
      _pendingDeleteMapIds.add(map.id);
    });

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    var undone = false;
    final controller = messenger.showSnackBar(
      SnackBar(
        content: Text('已移除「${map.name}」'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () {
            undone = true;
            if (!mounted) return;
            setState(() {
              _pendingDeleteMapIds.remove(map.id);
            });
          },
        ),
        duration: const Duration(seconds: 4),
      ),
    );
    await Future.delayed(const Duration(seconds: 4));
    controller.close();

    if (!mounted) return;
    if (undone) return;
    if (!_pendingDeleteMapIds.contains(map.id)) return;

    await _deleteCustomMapQuick(isar, map);
    if (!mounted) return;
    setState(() {
      _pendingDeleteMapIds.remove(map.id);
    });
  }

  Future<String> _copyCustomMapFileToDataDir(
      Isar isar, String sourcePath) async {
    final normalized = sourcePath.trim();
    if (normalized.isEmpty) return '';
    if (normalized.startsWith('assets/')) return normalized;

    final sourceFile = File(normalized);
    if (!await sourceFile.exists()) {
      throw StateError('文件不存在：$normalized');
    }

    final dataPath = (isar.directory ?? '').trim();
    if (dataPath.isEmpty) {
      throw StateError('数据目录不可用');
    }

    final extension = p.extension(sourceFile.path);
    final targetPath = p.join(dataPath, '${const Uuid().v4()}$extension');
    await sourceFile.copy(targetPath);
    return targetPath;
  }

  Future<String?> _pickCustomMapAsset({
    required String dialogTitle,
    List<String>? allowedExtensions,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: allowedExtensions == null ? FileType.image : FileType.custom,
      allowedExtensions: allowedExtensions,
      allowMultiple: false,
      dialogTitle: dialogTitle,
    );
    final selectedPath = result?.files.single.path?.trim();
    if (selectedPath == null || selectedPath.isEmpty) return null;
    return selectedPath;
  }

  Widget _buildFilePickerRow({
    required String label,
    required String buttonText,
    required String? selectedPath,
    required VoidCallback onPressed,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            OutlinedButton(
              onPressed: onPressed,
              child: Text(buttonText),
            ),
          ],
        ),
        if (selectedPath != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              p.basename(selectedPath),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
      ],
    );
  }

  Future<void> _submitAddCustomMap({
    required BuildContext parentContext,
    required BuildContext dialogContext,
    required Isar isar,
    required String mapNameInput,
    required String? radarPath,
    required String? backgroundPath,
    required String? iconPath,
  }) async {
    final mapName = mapNameInput.trim();
    if (mapName.isEmpty) {
      ScaffoldMessenger.of(parentContext).showSnackBar(
        const SnackBar(content: Text('请输入地图名称')),
      );
      return;
    }
    if (radarPath == null || radarPath.isEmpty) {
      ScaffoldMessenger.of(parentContext).showSnackBar(
        const SnackBar(content: Text('请先选择雷达图')),
      );
      return;
    }

    final existed = await isar.gameMaps
        .filter()
        .nameEqualTo(mapName, caseSensitive: false)
        .findFirst();
    if (!mounted) return;
    if (!parentContext.mounted) return;
    if (existed != null) {
      ScaffoldMessenger.of(parentContext).showSnackBar(
        const SnackBar(content: Text('地图名称已存在')),
      );
      return;
    }

    final copiedFiles = <String>[];
    try {
      int? newMapId;
      final tagService = TagService(isar);
      final copiedRadarPath =
          await _copyCustomMapFileToDataDir(isar, radarPath);
      if (copiedRadarPath.isNotEmpty &&
          !copiedRadarPath.startsWith('assets/')) {
        copiedFiles.add(copiedRadarPath);
      }
      final copiedBackgroundPath = (backgroundPath?.trim().isNotEmpty ?? false)
          ? await _copyCustomMapFileToDataDir(isar, backgroundPath!)
          : copiedRadarPath;
      if (copiedBackgroundPath != copiedRadarPath &&
          copiedBackgroundPath.isNotEmpty &&
          !copiedBackgroundPath.startsWith('assets/')) {
        copiedFiles.add(copiedBackgroundPath);
      }
      final copiedIconPath = (iconPath?.trim().isNotEmpty ?? false)
          ? await _copyCustomMapFileToDataDir(isar, iconPath!)
          : '';
      if (copiedIconPath.isNotEmpty && !copiedIconPath.startsWith('assets/')) {
        copiedFiles.add(copiedIconPath);
      }

      await isar.writeTxn(() async {
        final newMap = GameMap(
          name: mapName,
          backgroundPath: copiedBackgroundPath,
          iconPath: copiedIconPath,
        );
        newMapId = await isar.gameMaps.put(newMap);

        final newLayer = MapLayer(
          name: 'Default',
          assetPath: copiedRadarPath,
          sortOrder: 0,
        );
        await isar.mapLayers.put(newLayer);
        newMap.layers.add(newLayer);
        await newMap.layers.save();
      });
      if (newMapId != null) {
        await tagService.clearDeletedSystemTagRecordsForMap(newMapId!);
        await tagService.initializeSystemTags(newMapId!, mapName);
      }
    } catch (e) {
      for (final copiedPath in copiedFiles) {
        await DataService.deleteMediaFile(copiedPath);
      }
      if (!mounted) return;
      if (!parentContext.mounted) return;
      ScaffoldMessenger.of(parentContext).showSnackBar(
        SnackBar(content: Text('添加失败：$e')),
      );
      return;
    }

    if (!mounted) return;
    if (!parentContext.mounted) return;
    if (dialogContext.mounted) {
      Navigator.pop(dialogContext);
    }
    setState(() {});
    ScaffoldMessenger.of(parentContext).showSnackBar(
      SnackBar(content: Text('已添加地图：$mapName')),
    );
  }

  Future<void> _showAddCustomMapDialog(
      BuildContext parentContext, Isar isar) async {
    var mapNameInput = '';
    String? radarPath;
    String? backgroundPath;
    String? iconPath;

    await showDialog<void>(
      context: parentContext,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('添加自定义地图'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    autofocus: true,
                    onChanged: (value) {
                      mapNameInput = value;
                    },
                    decoration: const InputDecoration(
                      labelText: '地图名称',
                      hintText: '例如：Cache',
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildFilePickerRow(
                    label: '雷达图（必选）',
                    buttonText: '选择图片',
                    selectedPath: radarPath,
                    onPressed: () async {
                      final selected = await _pickCustomMapAsset(
                        dialogTitle: '选择雷达图',
                      );
                      if (selected != null) {
                        setDialogState(() => radarPath = selected);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildFilePickerRow(
                    label: '背景图（可选）',
                    buttonText: '选择背景',
                    selectedPath: backgroundPath,
                    onPressed: () async {
                      final selected = await _pickCustomMapAsset(
                        dialogTitle: '选择地图背景图（可选）',
                      );
                      if (selected != null) {
                        setDialogState(() => backgroundPath = selected);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildFilePickerRow(
                    label: '地图图标（可选）',
                    buttonText: '选择图标',
                    selectedPath: iconPath,
                    onPressed: () async {
                      final selected = await _pickCustomMapAsset(
                        dialogTitle: '选择地图图标（可选）',
                        allowedExtensions: const [
                          'png',
                          'jpg',
                          'jpeg',
                          'webp',
                          'bmp',
                          'gif',
                          'svg',
                        ],
                      );
                      if (selected != null) {
                        setDialogState(() => iconPath = selected);
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => _submitAddCustomMap(
                    parentContext: parentContext,
                    dialogContext: dialogContext,
                    isar: isar,
                    mapNameInput: mapNameInput,
                    radarPath: radarPath,
                    backgroundPath: backgroundPath,
                    iconPath: iconPath,
                  ),
                  child: const Text('添加'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  int _mapGrenadeCount(GameMap map) {
    map.layers.loadSync();
    var grenades = 0;
    for (final layer in map.layers) {
      layer.grenades.loadSync();
      grenades += layer.grenades.length;
    }
    return grenades;
  }

  Widget _buildMapCard(
      BuildContext context, Isar isar, GameMap map, int index) {
    final isCustomMap = MapManagementService.isCustomMap(map);
    final grenadeCount = _mapGrenadeCount(map);

    Widget card = HomeMapCard(
      map: map,
      index: index,
      grenadeCount: grenadeCount,
      isCustomMap: isCustomMap,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => MapScreen(gameMap: map)),
      ).then((_) {
        if (mounted) setState(() {});
      }),
    );

    if (isCustomMap) {
      card = Dismissible(
        key: ValueKey('map-${map.id}'),
        direction: DismissDirection.endToStart,
        background: Container(
          decoration: BoxDecoration(
            color: Colors.red.shade700,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Icon(Icons.delete_forever, color: Colors.white),
              SizedBox(width: 8),
              Text(
                '删除地图',
                style:
                    TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        confirmDismiss: (_) async => true,
        onDismissed: (_) => _queueCustomMapDelete(isar, map),
        child: card,
      );
    }

    return card;
  }

  Widget _buildMapGrid({
    required Key gridKey,
    required int itemCount,
    required IndexedWidgetBuilder itemBuilder,
  }) {
    return LayoutBuilder(
      key: gridKey,
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1280
            ? 3
            : (constraints.maxWidth >= 720 ? 2 : 1);
        final gridPadding = EdgeInsets.fromLTRB(
          AppBreakpoints.isMobile(context) ? 16 : 24,
          8,
          AppBreakpoints.isMobile(context) ? 16 : 24,
          24,
        );
        return GridView.builder(
          padding: AppBreakpoints.isMobile(context)
              ? AppBreakpoints.withMobileBottomBarClearance(
                  context,
                  gridPadding,
                )
              : gridPadding,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisExtent: 220,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount: itemCount,
          itemBuilder: itemBuilder,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isar = ref.watch(isarProvider);
    final visibleMaps = isar.gameMaps
        .where()
        .findAllSync()
        .where((map) => !_pendingDeleteMapIds.contains(map.id))
        .toList(growable: false);

    final activeDutyMaps = <GameMap>[];
    final reserveMaps = <GameMap>[];
    final customMaps = <GameMap>[];
    for (final map in visibleMaps) {
      final config = findBuiltinMapConfig(map);
      if (config != null) {
        if (config.isActiveDuty) {
          activeDutyMaps.add(map);
        } else {
          reserveMaps.add(map);
        }
      } else {
        customMaps.add(map);
      }
    }
    activeDutyMaps.sort(
        (a, b) => builtinMapSortOrder(a).compareTo(builtinMapSortOrder(b)));
    reserveMaps.sort(
        (a, b) => builtinMapSortOrder(a).compareTo(builtinMapSortOrder(b)));
    customMaps.sort((a, b) => a.id.compareTo(b.id));

    final showingReserve = _inReservePool && reserveMaps.isNotEmpty;
    final hasReserveFolder = reserveMaps.isNotEmpty;
    final reserveGrenadeCount = reserveMaps.fold<int>(
      0,
      (sum, map) => sum + _mapGrenadeCount(map),
    );
    final homeItemCount = activeDutyMaps.length +
        (hasReserveFolder ? 1 : 0) +
        customMaps.length +
        1;

    return PopScope(
      canPop: !showingReserve,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && showingReserve) {
          setState(() => _inReservePool = false);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          bottom: !widget.embedded,
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  AppBreakpoints.isMobile(context) ? 16 : 24,
                  20,
                  AppBreakpoints.isMobile(context) ? 16 : 24,
                  14,
                ),
                child: Row(
                  children: [
                    if (showingReserve) ...[
                      IconButton(
                        tooltip: '返回地图库',
                        onPressed: () => setState(() => _inReservePool = false),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            showingReserve ? '非现役地图池' : '地图库',
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            showingReserve
                                ? '${reserveMaps.length} 张地图 · 含人质图'
                                : '${visibleMaps.length} 张地图',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: context.appTheme.mutedText),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: AppBreakpoints.isMobile(context) ? 220 : 360,
                      ),
                      child: TextField(
                        readOnly: true,
                        onTap: () => showSearch(
                          context: context,
                          delegate: GlobalSearchDelegate(ref),
                        ),
                        decoration: const InputDecoration(
                          fillColor: Colors.transparent,
                          prefixIcon: Icon(Icons.search_rounded),
                          hintText: '搜索全部道具',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: AppMotion.panel,
                  switchInCurve: AppMotion.enter,
                  switchOutCurve: AppMotion.enter,
                  child: showingReserve
                      ? _buildMapGrid(
                          gridKey: const ValueKey('reserve-map-grid'),
                          itemCount: reserveMaps.length,
                          itemBuilder: (ctx, index) => _buildMapCard(
                            context,
                            isar,
                            reserveMaps[index],
                            index,
                          ),
                        )
                      : _buildMapGrid(
                          gridKey: const ValueKey('home-map-grid'),
                          itemCount: homeItemCount,
                          itemBuilder: (ctx, index) {
                            if (index < activeDutyMaps.length) {
                              return _buildMapCard(
                                context,
                                isar,
                                activeDutyMaps[index],
                                index,
                              );
                            }
                            final reserveIndex = activeDutyMaps.length;
                            if (hasReserveFolder && index == reserveIndex) {
                              return ReservePoolFolderCard(
                                maps: reserveMaps,
                                index: index,
                                totalGrenadeCount: reserveGrenadeCount,
                                onTap: () =>
                                    setState(() => _inReservePool = true),
                              );
                            }
                            final customStart =
                                reserveIndex + (hasReserveFolder ? 1 : 0);
                            final customIndex = index - customStart;
                            if (customIndex < customMaps.length) {
                              return _buildMapCard(
                                context,
                                isar,
                                customMaps[customIndex],
                                index,
                              );
                            }
                            return AddCustomMapCard(
                              onTap: () =>
                                  _showAddCustomMapDialog(context, isar),
                            );
                          },
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
