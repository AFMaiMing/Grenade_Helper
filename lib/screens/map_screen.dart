import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:isar_community/isar.dart';
import 'package:photo_view/photo_view.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../main.dart';
import '../models.dart';
import '../providers.dart';
import '../services/data_service.dart';
import '../services/favorite_folder_service.dart';
import '../services/tag_service.dart';
import '../spawn_point_data.dart';
import '../theme/app_design_system.dart';
import '../widgets/app_svg_icon.dart';
import '../widgets/grenade_type_icon.dart';
import '../widgets/joystick_widget.dart';
import '../widgets/path_image_provider.dart';
import 'area_draw_screen.dart';
import 'grenade_detail_screen.dart';
import 'map/map_all_grenades_panel.dart';
import 'map/map_canvas_overlays.dart';
import 'map/map_cluster_and_impact_dialogs.dart';
import 'map/map_clustering.dart';
import 'map/map_favorites_and_tags_sheets.dart';
import 'map/map_markers_and_lines.dart';
import 'map/map_painters.dart';
import 'map/map_providers.dart';
import 'map/map_spawn_widgets.dart';
import 'map/map_toolbars.dart';

export 'map/map_clustering.dart'
    show GrenadeCluster, clusterGrenades, clusterGrenadesByImpact;
export 'map/map_providers.dart'
    show isEditModeProvider, selectedLayerIndexProvider, selectedTagIdsProvider;

class MapScreen extends ConsumerStatefulWidget {
  final GameMap gameMap;

  const MapScreen({super.key, required this.gameMap});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  static const int _grenadeCreateModeTap = 0;
  static const int _grenadeCreateModeLongPress = 1;

  Offset? _tempTapPosition;
  GrenadeCluster? _draggingCluster;
  Offset? _dragOffset;
  Offset? _dragAnchorOffset;
  bool _isMovingCluster = false;
  Grenade? _movingSingleGrenade;
  late final PhotoViewController _photoViewController;
  final GlobalKey _stackKey = GlobalKey();
  bool _isSpawnSidebarExpanded = true;
  String _selectedSpawnSidebarTab = 'T';
  final ValueNotifier<String?> _hoveredSpawnKey = ValueNotifier<String?>(null);
  bool _isImpactMode = false;

  GrenadeCluster? _joystickCluster;
  Offset? _joystickOriginalOffset;

  GrenadeCluster? _joystickImpactCluster;
  Offset? _joystickImpactOriginalOffset;
  Offset? _impactJoystickDragOffset;

  GrenadeCluster? _selectedClusterForImpact;

  GrenadeCluster? _draggingImpactCluster;
  Offset? _impactDragOffset;
  Offset? _impactDragAnchorOffset;
  bool _isBatchedClusterLongPressDragActive = false;
  Grenade? _movingSingleImpactGrenade;
  int? _selectedImpactTypeFilter;
  int? _selectedImpactGroupId;
  final ValueNotifier<double> _allMapListPanelHeightNotifier =
      ValueNotifier(MapAllGrenadesPanel.defaultHeight);
  final TextEditingController _allMapListSearchController =
      TextEditingController();
  String _allMapListSearchQuery = '';
  late final FavoriteFolderService _favoriteFolderService;
  StreamSubscription<void>? _grenadeWatchSubscription;
  List<Grenade> _cachedAllMapGrenades = [];
  List<({Grenade grenade, MapLayer layer})> _cachedAllMapGrenadeEntries = [];
  List<Grenade>? _throwClusterCacheSource;
  double? _throwClusterCacheThreshold;
  List<GrenadeCluster> _throwClusterCache = const [];
  List<Grenade>? _impactClusterCacheSource;
  double? _impactClusterCacheThreshold;
  List<GrenadeCluster> _impactClusterCache = const [];
  List<GrenadeCluster>? _frozenThrowBatchClusters;
  List<GrenadeCluster>? _frozenImpactBatchClusters;
  final ValueNotifier<int> _batchedDragVisualTick = ValueNotifier<int>(0);
  final Map<int, PictureInfo> _grenadeTypePictures = {};
  bool _isLoadingGrenadeTypePictures = false;

  bool get _useLegacyMapMarkers => GrenadeTypeIcon.useLegacy;

  bool get _supportsOverlayWindow =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    _photoViewController = PhotoViewController();
    final isar = ref.read(isarProvider);
    _favoriteFolderService = FavoriteFolderService(isar);
    _refreshAllMapGrenadeCache(notify: false);
    _grenadeWatchSubscription = isar.grenades.watchLazy().listen((_) {
      if (!mounted) return;
      _refreshAllMapGrenadeCache();
    });
    widget.gameMap.layers.loadSync();
    final defaultIndex = widget.gameMap.layers.length > 1 ? 1 : 0;
    Future.microtask(() {
      ref.read(selectedLayerIndexProvider.notifier).state = defaultIndex;
      _updateOverlayState(defaultIndex);
    });
    Future.microtask(_initializeSystemTagsForCurrentMap);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadGrenadeTypePictures();
  }

  Future<void> _loadGrenadeTypePictures() async {
    if (_isLoadingGrenadeTypePictures || _grenadeTypePictures.isNotEmpty) {
      return;
    }
    _isLoadingGrenadeTypePictures = true;
    const types = [
      GrenadeType.smoke,
      GrenadeType.flash,
      GrenadeType.molotov,
      GrenadeType.he,
      GrenadeType.wallbang,
    ];
    final loaded = <int, PictureInfo>{};
    try {
      for (final type in types) {
        loaded[type] = await vg.loadPicture(
          SvgAssetLoader(
            GrenadeTypeIcon.assetForType(type),
            colorMapper: SolidSvgColorMapper(mapTypeColor(type)),
          ),
          null,
        );
      }
      if (!mounted) {
        for (final info in loaded.values) {
          info.picture.dispose();
        }
        return;
      }
      setState(() => _grenadeTypePictures.addAll(loaded));
    } catch (error, stackTrace) {
      for (final info in loaded.values) {
        info.picture.dispose();
      }
      debugPrint('Failed to preload grenade type SVGs: $error\n$stackTrace');
    } finally {
      _isLoadingGrenadeTypePictures = false;
    }
  }

  Future<void> _initializeSystemTagsForCurrentMap() async {
    final isar = ref.read(isarProvider);
    await TagService(isar)
        .initializeSystemTags(widget.gameMap.id, widget.gameMap.name);
  }

  @override
  void dispose() {
    _grenadeWatchSubscription?.cancel();
    _allMapListPanelHeightNotifier.dispose();
    _allMapListSearchController.dispose();
    _batchedDragVisualTick.dispose();
    _hoveredSpawnKey.dispose();
    _photoViewController.dispose();
    for (final info in _grenadeTypePictures.values) {
      info.picture.dispose();
    }
    clearOverlayActiveMap();
    super.dispose();
  }

  void _showStatusSnackBar(
    String message,
    Color backgroundColor, {
    Duration duration = const Duration(seconds: 1),
    bool hideCurrent = true,
    SnackBarAction? action,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    if (hideCurrent) messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: backgroundColor,
      duration: duration,
      action: action,
    ));
  }

  double _getAdaptiveClusterThreshold({
    required double scale,
    required int grenadeCount,
  }) {
    final highDensityClusterMode =
        globalSettingsService?.getHighDensityClusterMode() ?? true;
    return computeAdaptiveClusterThreshold(
      scale: scale,
      grenadeCount: grenadeCount,
      highDensityClusterMode: highDensityClusterMode,
    );
  }

  void _refreshAllMapGrenadeCache({bool notify = true}) {
    widget.gameMap.layers.loadSync();
    final layers = widget.gameMap.layers.toList();
    final isar = ref.read(isarProvider);

    final grenades = <Grenade>[];
    final entries = <({Grenade grenade, MapLayer layer})>[];

    for (final layer in layers) {
      final layerGrenades = isar.grenades
          .filter()
          .layer((q) => q.idEqualTo(layer.id))
          .findAllSync();
      grenades.addAll(layerGrenades);
      for (final grenade in layerGrenades) {
        entries.add((grenade: grenade, layer: layer));
      }
    }

    void applyCache() {
      _throwClusterCacheSource = null;
      _throwClusterCacheThreshold = null;
      _throwClusterCache = const [];
      _impactClusterCacheSource = null;
      _impactClusterCacheThreshold = null;
      _impactClusterCache = const [];
      _cachedAllMapGrenades = grenades;
      _cachedAllMapGrenadeEntries = entries;
    }

    if (notify && mounted) {
      setState(applyCache);
    } else {
      applyCache();
    }
  }

  List<GrenadeCluster> _getThrowClusters(
    List<Grenade> grenades, {
    required double threshold,
  }) {
    if (!identical(_throwClusterCacheSource, grenades) ||
        _throwClusterCacheThreshold != threshold) {
      _throwClusterCacheSource = grenades;
      _throwClusterCacheThreshold = threshold;
      _throwClusterCache = clusterGrenades(grenades, threshold: threshold);
    }
    return _throwClusterCache;
  }

  List<GrenadeCluster> _getImpactClusters(
    List<Grenade> grenades, {
    required double threshold,
  }) {
    if (!identical(_impactClusterCacheSource, grenades) ||
        _impactClusterCacheThreshold != threshold) {
      _impactClusterCacheSource = grenades;
      _impactClusterCacheThreshold = threshold;
      _impactClusterCache = clusterGrenadesByImpact(
        grenades,
        threshold: threshold,
      );
    }
    return _impactClusterCache;
  }

  GrenadeCluster? _hitTestClusterAtGlobalPosition(
    Offset globalPosition, {
    required List<GrenadeCluster> clusters,
    required double photoScale,
    required MapImageBounds imageBounds,
  }) {
    if (clusters.isEmpty) return null;
    final RenderBox? box =
        _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;

    final local = box.globalToLocal(globalPosition);
    final safeScale = photoScale <= 0 ? 1.0 : photoScale;
    final hitRadius = 16.0 / safeScale;
    final hitRadiusSq = hitRadius * hitRadius;

    GrenadeCluster? nearest;
    var nearestDistSq = double.infinity;

    for (final cluster in clusters) {
      final cx = imageBounds.offsetX + cluster.xRatio * imageBounds.width;
      final cy = imageBounds.offsetY + cluster.yRatio * imageBounds.height;
      final dx = local.dx - cx;
      final dy = local.dy - cy;
      final distSq = dx * dx + dy * dy;
      if (distSq <= hitRadiusSq && distSq < nearestDistSq) {
        nearestDistSq = distSq;
        nearest = cluster;
      }
    }

    return nearest;
  }

  Future<bool> _shouldUseJoystickMoveOnMobile() async {
    if (!(Platform.isAndroid || Platform.isIOS)) return false;
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getInt('marker_move_mode') ?? 0) == 1;
  }

  Future<void> _startThrowClusterLongPress(
    GrenadeCluster cluster,
    Offset globalPosition, {
    List<GrenadeCluster>? batchedClustersSnapshot,
  }) async {
    if (await _shouldUseJoystickMoveOnMobile()) {
      if (batchedClustersSnapshot != null) {
        _isBatchedClusterLongPressDragActive = false;
        _frozenThrowBatchClusters = null;
      }
      _showJoystickSheet(cluster);
      return;
    }

    final touchRatio = _getLocalPosition(globalPosition);
    if (touchRatio == null) return;

    final frozenBatch = batchedClustersSnapshot
        ?.where((c) => !isSameCluster(c, cluster))
        .toList(growable: false);

    setState(() {
      if (frozenBatch != null) {
        _isBatchedClusterLongPressDragActive = true;
        _frozenThrowBatchClusters = frozenBatch;
        _frozenImpactBatchClusters = null;
      }
      _draggingCluster = cluster;
      _dragAnchorOffset = touchRatio - Offset(cluster.xRatio, cluster.yRatio);
      _dragOffset = Offset(cluster.xRatio, cluster.yRatio);
    });
  }

  Future<void> _startImpactClusterLongPress(
    GrenadeCluster cluster,
    Offset globalPosition, {
    List<GrenadeCluster>? batchedClustersSnapshot,
  }) async {
    if (await _shouldUseJoystickMoveOnMobile()) {
      if (batchedClustersSnapshot != null) {
        _isBatchedClusterLongPressDragActive = false;
        _frozenImpactBatchClusters = null;
      }
      _showJoystickSheetForImpact(cluster);
      return;
    }

    final touchRatio = _getLocalPosition(globalPosition);
    if (touchRatio == null) return;

    final frozenBatch = batchedClustersSnapshot
        ?.where((c) => !isSameCluster(c, cluster))
        .toList(growable: false);

    setState(() {
      if (frozenBatch != null) {
        _isBatchedClusterLongPressDragActive = true;
        _frozenImpactBatchClusters = frozenBatch;
        _frozenThrowBatchClusters = null;
      }
      _draggingImpactCluster = cluster;
      _impactDragAnchorOffset =
          touchRatio - Offset(cluster.xRatio, cluster.yRatio);
      _impactDragOffset = Offset(cluster.xRatio, cluster.yRatio);
    });
  }

  void _handleBatchedClusterLongPressMoveUpdate(Offset globalPosition) {
    if (_impactDragAnchorOffset != null) {
      final touchRatio = _getLocalPosition(globalPosition);
      if (touchRatio == null) return;
      final newPos = touchRatio - _impactDragAnchorOffset!;
      _impactDragOffset = Offset(
        newPos.dx.clamp(0.0, 1.0),
        newPos.dy.clamp(0.0, 1.0),
      );
      _batchedDragVisualTick.value++;
      return;
    }

    if (_dragAnchorOffset != null) {
      final touchRatio = _getLocalPosition(globalPosition);
      if (touchRatio == null) return;
      _dragOffset = touchRatio - _dragAnchorOffset!;
      _batchedDragVisualTick.value++;
    }
  }

  void _handleBatchedClusterLongPressEnd() {
    _isBatchedClusterLongPressDragActive = false;
    _frozenThrowBatchClusters = null;
    _frozenImpactBatchClusters = null;
    if (_impactDragAnchorOffset != null || _draggingImpactCluster != null) {
      _onImpactClusterDragEnd();
      return;
    }
    if (_dragAnchorOffset != null || _draggingCluster != null) {
      _onClusterDragEnd();
    }
  }

  Offset? _getLocalPosition(Offset globalPosition) {
    final RenderBox? box =
        _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;

    final localPosition = box.globalToLocal(globalPosition);
    final size = box.size;
    final bounds = computeMapImageBounds(size.width, size.height);
    final tapX = localPosition.dx - bounds.offsetX;
    final tapY = localPosition.dy - bounds.offsetY;
    return Offset(tapX / bounds.width, tapY / bounds.height);
  }

  void _updateOverlayState(int layerIndex) {
    if (!_supportsOverlayWindow) return;
    widget.gameMap.layers.loadSync();
    final layers = widget.gameMap.layers.toList();
    if (layerIndex < layers.length) {
      setOverlayActiveMap(widget.gameMap, layers[layerIndex]);
    }
  }

  int _getGrenadeCreateMode() {
    return globalSettingsService?.getGrenadeCreateMode() ??
        _grenadeCreateModeTap;
  }

  void _showGrenadeCreateModeHint(bool isEditMode) {
    if (!mounted) return;
    final createModeText =
        _getGrenadeCreateMode() == _grenadeCreateModeLongPress
            ? '长按地图新增道具'
            : '单点地图新增道具';
    final detailText =
        isEditMode ? '当前为编辑模式 · 新增方式：$createModeText' : '当前为查看模式';
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const AppSvgIcon(
              asset: 'assets/icons/ui_hint.svg',
              size: 20,
              color: Colors.white,
              semanticsLabel: '提示',
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(detailText)),
          ],
        ),
        backgroundColor: Colors.blueAccent,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _toggleAllMapListPanelCollapsed() {
    final current = _allMapListPanelHeightNotifier.value;
    final shouldExpand = current < MapAllGrenadesPanel.minExpandedHeight;
    _allMapListPanelHeightNotifier.value = shouldExpand
        ? MapAllGrenadesPanel.defaultHeight
        : MapAllGrenadesPanel.collapsedHeight;
  }

  void _resizeAllMapListPanel(double deltaDy, double maxHeight) {
    final next = (_allMapListPanelHeightNotifier.value - deltaDy)
        .clamp(MapAllGrenadesPanel.collapsedHeight, maxHeight);
    _allMapListPanelHeightNotifier.value = (next as num).toDouble();
  }

  void _snapAllMapListPanelHeight(double maxHeight) {
    final current = _allMapListPanelHeightNotifier.value;
    if (current <
        (MapAllGrenadesPanel.collapsedHeight +
                MapAllGrenadesPanel.minExpandedHeight) /
            2) {
      _allMapListPanelHeightNotifier.value =
          MapAllGrenadesPanel.collapsedHeight;
      return;
    }
    if (current < MapAllGrenadesPanel.minExpandedHeight) {
      _allMapListPanelHeightNotifier.value =
          MapAllGrenadesPanel.minExpandedHeight;
      return;
    }
    if (current > maxHeight) {
      _allMapListPanelHeightNotifier.value = maxHeight;
    }
  }

  void _tryCreateGrenadeAtGlobalPosition(Offset globalPosition, int layerId) {
    if (_isMovingCluster ||
        _movingSingleGrenade != null ||
        _movingSingleImpactGrenade != null ||
        _draggingImpactCluster != null) {
      return;
    }

    final isEditMode = ref.read(isEditModeProvider);
    if (!isEditMode || _selectedClusterForImpact != null) return;

    final localRatio = _getLocalPosition(globalPosition);
    if (localRatio == null) return;
    if (localRatio.dx < 0 ||
        localRatio.dx > 1 ||
        localRatio.dy < 0 ||
        localRatio.dy > 1) {
      return;
    }

    setState(() {
      _tempTapPosition = Offset(localRatio.dx, localRatio.dy);
    });
    _createGrenade(layerId);
  }

  void _reselectClusterAfterMove(int targetId, int layerId) {
    Future.delayed(const Duration(milliseconds: 50), () {
      if (!mounted) return;
      final grenades =
          ref.read(mapFilteredGrenadesProvider(layerId)).asData?.value;
      if (grenades == null) return;
      final clusterThreshold = _getAdaptiveClusterThreshold(
        scale: _photoViewController.scale ?? 1.0,
        grenadeCount: grenades.length,
      );
      final clusters = _isImpactMode
          ? _getImpactClusters(grenades, threshold: clusterThreshold)
          : _getThrowClusters(grenades, threshold: clusterThreshold);
      try {
        final cluster =
            clusters.firstWhere((c) => c.grenades.any((g) => g.id == targetId));
        setState(() {
          _selectedClusterForImpact = cluster;
        });
      } catch (_) {}
    });
  }

  void _persistGrenadesCoordsSync(
    Iterable<Grenade> grenades,
    double x,
    double y, {
    required bool isImpact,
    bool reloadFromDb = false,
  }) {
    final isar = ref.read(isarProvider);
    final now = DateTime.now();
    isar.writeTxnSync(() {
      for (final g in grenades) {
        final target = reloadFromDb ? isar.grenades.getSync(g.id) : g;
        if (target == null) continue;
        if (isImpact) {
          target.impactXRatio = x;
          target.impactYRatio = y;
        } else {
          target.xRatio = x;
          target.yRatio = y;
        }
        target.updatedAt = now;
        isar.grenades.putSync(target);
      }
    });
  }

  Future<void> _persistGrenadesCoordsAsync(
    Iterable<Grenade> grenades,
    double x,
    double y, {
    required bool isImpact,
  }) async {
    final isar = ref.read(isarProvider);
    final now = DateTime.now();
    await isar.writeTxn(() async {
      for (final g in grenades) {
        final freshG = await isar.grenades.get(g.id);
        if (freshG == null) continue;
        if (isImpact) {
          freshG.impactXRatio = x;
          freshG.impactYRatio = y;
        } else {
          freshG.xRatio = x;
          freshG.yRatio = y;
        }
        freshG.updatedAt = now;
        await isar.grenades.put(freshG);
      }
    });
  }

  void _handleTap(TapUpDetails details, int layerId) async {
    if (_isMovingCluster ||
        _movingSingleGrenade != null ||
        _movingSingleImpactGrenade != null ||
        _draggingImpactCluster != null) {
      final localRatio = _getLocalPosition(details.globalPosition);
      if (localRatio == null) return;

      final targetX = localRatio.dx;
      final targetY = localRatio.dy;
      if (targetX < 0 || targetX > 1 || targetY < 0 || targetY > 1) {
        return;
      }

      if (_movingSingleGrenade != null) {
        final targetId = _movingSingleGrenade!.id;
        await _persistGrenadesCoordsAsync(
          [_movingSingleGrenade!],
          targetX,
          targetY,
          isImpact: false,
        );
        if (!mounted) return;
        _showStatusSnackBar("✓ 道具位置已更新", Colors.cyan);
        _reselectClusterAfterMove(targetId, layerId);
        setState(() {
          _movingSingleGrenade = null;
        });
        return;
      }

      if (_movingSingleImpactGrenade != null) {
        await _saveSingleImpactPosition(
          _movingSingleImpactGrenade!,
          targetX,
          targetY,
          layerId: layerId,
        );
        return;
      }

      if (_draggingImpactCluster != null) {
        await _persistGrenadesCoordsAsync(
          _draggingImpactCluster!.grenades,
          targetX,
          targetY,
          isImpact: true,
        );
        if (!mounted) return;
        _showStatusSnackBar("✓ 爆点已移动", Colors.purpleAccent);
        setState(() {
          _draggingImpactCluster = null;
          _impactDragOffset = null;
          _impactDragAnchorOffset = null;
        });
        return;
      }

      if (_isMovingCluster && _draggingCluster != null) {
        _persistGrenadesCoordsSync(
          _draggingCluster!.grenades,
          targetX,
          targetY,
          isImpact: false,
          reloadFromDb: true,
        );
        if (!mounted) return;
        _showStatusSnackBar("✓ 点位已移动", Colors.green);
        setState(() {
          _isMovingCluster = false;
          _draggingCluster = null;
          _dragOffset = null;
        });
        return;
      }
      return;
    }

    final isEditMode = ref.read(isEditModeProvider);
    if (!isEditMode) return;
    if (_getGrenadeCreateMode() != _grenadeCreateModeTap) return;
    _tryCreateGrenadeAtGlobalPosition(details.globalPosition, layerId);
  }

  void _createGrenade(int layerId) async {
    final isar = ref.read(isarProvider);
    final layer = await isar.mapLayers.get(layerId);
    if (layer == null) return;
    final grenade = Grenade(
      title: "新道具",
      type: GrenadeType.smoke,
      team: TeamType.all,
      xRatio: _tempTapPosition!.dx,
      yRatio: _tempTapPosition!.dy,
      isNewImport: false,
      uniqueId: const Uuid().v4(),
    );
    int id = 0;
    await isar.writeTxn(() async {
      id = await isar.grenades.put(grenade);
      grenade.layer.value = layer;
      await grenade.layer.save();
    });
    setState(() {
      _tempTapPosition = null;
    });
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GrenadeDetailScreen(grenadeId: id, isEditing: true),
      ),
    );
  }

  void _switchToLayerById(int? targetLayerId, {String? layerName}) {
    if (targetLayerId == null) return;
    widget.gameMap.layers.loadSync();
    final layers = widget.gameMap.layers.toList();
    final targetIndex = layers.indexWhere((l) => l.id == targetLayerId);
    if (targetIndex != -1 &&
        targetIndex != ref.read(selectedLayerIndexProvider)) {
      ref.read(selectedLayerIndexProvider.notifier).state = targetIndex;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("已跳转至 ${layerName ?? layers[targetIndex].name}"),
        duration: const Duration(milliseconds: 800),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  void _onSearchResultSelected(Grenade g) {
    g.layer.loadSync();
    _switchToLayerById(g.layer.value?.id, layerName: g.layer.value?.name);
    _handleGrenadeTap(g, isEditing: false);
  }

  void _handleGrenadeTap(Grenade g, {required bool isEditing}) async {
    final isar = ref.read(isarProvider);
    if (g.isNewImport) {
      g.isNewImport = false;
      await isar.writeTxn(() async {
        await isar.grenades.put(g);
      });
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            GrenadeDetailScreen(grenadeId: g.id, isEditing: isEditing),
      ),
    );
  }

  void _handleClusterTap(GrenadeCluster cluster, int layerId) async {
    if (_movingSingleGrenade != null) {
      if (cluster.grenades.any((g) => g.id == _movingSingleGrenade!.id)) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("不能合并到自己所在的点位"),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 1),
        ));
        return;
      }

      await _persistGrenadesCoordsAsync(
        [_movingSingleGrenade!],
        cluster.grenades.first.xRatio,
        cluster.grenades.first.yRatio,
        isImpact: false,
      );
      if (!mounted) return;
      _showStatusSnackBar("✓ 已合并到既有点位", Colors.blue);
      setState(() {
        _movingSingleGrenade = null;
      });
      return;
    }

    if (_movingSingleImpactGrenade != null) {
      await _saveSingleImpactPosition(
        _movingSingleImpactGrenade!,
        cluster.xRatio,
        cluster.yRatio,
        layerId: layerId,
      );
      return;
    }

    if (_isMovingCluster && _draggingCluster != null) {
      final draggingIds = _draggingCluster!.grenades.map((g) => g.id).toSet();
      final targetIds = cluster.grenades.map((g) => g.id).toSet();
      if (draggingIds.intersection(targetIds).isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("不能合并到自己所在的点位"),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 1),
        ));
        return;
      }

      await _persistGrenadesCoordsAsync(
        _draggingCluster!.grenades,
        cluster.grenades.first.xRatio,
        cluster.grenades.first.yRatio,
        isImpact: false,
      );
      if (!mounted) return;
      _showStatusSnackBar("✓ 点位已合并", Colors.blue);
      setState(() {
        _isMovingCluster = false;
        _draggingCluster = null;
        _dragOffset = null;
      });
      return;
    }

    _showClusterBottomSheet(cluster, layerId);
  }

  Future<void> _deleteGrenadeFromMapList(Grenade g) async {
    final confirmed = await confirmDeleteGrenadeFromMapList(context, g);
    if (!confirmed) return;
    await _deleteGrenadesInBatch([g]);
    if (!mounted) return;
    setState(() {});
    _showStatusSnackBar("✓ 道具已删除", Colors.redAccent, hideCurrent: false);
  }

  void _showClusterBottomSheet(GrenadeCluster cluster, int layerId) async {
    setState(() {
      _selectedClusterForImpact = cluster;
    });

    final newImportGrenades =
        cluster.grenades.where((g) => g.isNewImport).toList();
    if (newImportGrenades.isNotEmpty) {
      final isar = ref.read(isarProvider);
      await isar.writeTxn(() async {
        for (final g in newImportGrenades) {
          g.isNewImport = false;
          await isar.grenades.put(g);
        }
      });
    }
  }

  void _closeClusterPanel() {
    setState(() {
      _selectedClusterForImpact = null;
      _selectedImpactTypeFilter = null;
      _selectedImpactGroupId = null;
    });
  }

  void _createGrenadeAtCluster(GrenadeCluster cluster, int layerId) async {
    final isar = ref.read(isarProvider);
    final layer = await isar.mapLayers.get(layerId);
    if (layer == null) return;
    // 爆点模式下先用爆点暂代投掷点坐标，再跳转详情页拾取真实投掷点
    final impactMode = _isImpactMode;
    final grenade = Grenade(
      title: "新道具",
      type: GrenadeType.smoke,
      team: TeamType.all,
      xRatio: cluster.xRatio,
      yRatio: cluster.yRatio,
      isNewImport: false,
      uniqueId: const Uuid().v4(),
    );
    if (impactMode) {
      grenade.impactXRatio = cluster.xRatio;
      grenade.impactYRatio = cluster.yRatio;
    }
    int id = 0;
    await isar.writeTxn(() async {
      id = await isar.grenades.put(grenade);
      grenade.layer.value = layer;
      await grenade.layer.save();
    });
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GrenadeDetailScreen(
          grenadeId: id,
          isEditing: true,
          pickThrowPoint: impactMode,
        ),
      ),
    );
  }

  Future<void> _deleteGrenadesInBatch(List<Grenade> grenades) async {
    if (grenades.isEmpty) return;
    await DataService(ref.read(isarProvider)).deleteGrenades(grenades);
  }

  void _startMoveCluster(GrenadeCluster cluster) {
    setState(() {
      _isMovingCluster = true;
      _draggingCluster = cluster;
      _dragOffset = Offset(cluster.xRatio, cluster.yRatio);
    });
    _showStatusSnackBar(
      "点击地图新位置以移动点位，或点击取消",
      Colors.cyan,
      duration: const Duration(seconds: 10),
      hideCurrent: false,
      action: SnackBarAction(
          label: "取消", textColor: Colors.white, onPressed: _cancelMoveCluster),
    );
  }

  void _cancelMoveCluster() {
    setState(() {
      _isMovingCluster = false;
      _draggingCluster = null;
      _dragOffset = null;
      _dragAnchorOffset = null;
    });
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
  }

  void _startMoveImpactCluster(GrenadeCluster cluster) {
    setState(() {
      _draggingImpactCluster = cluster;
      _impactDragOffset = Offset(cluster.xRatio, cluster.yRatio);
    });
    _showStatusSnackBar(
      "点击地图新位置以移动爆点，或点击取消",
      Colors.purpleAccent,
      duration: const Duration(seconds: 10),
      hideCurrent: false,
      action: SnackBarAction(
        label: "取消",
        textColor: Colors.white,
        onPressed: _cancelMoveImpactCluster,
      ),
    );
  }

  void _cancelMoveImpactCluster() {
    setState(() {
      _draggingImpactCluster = null;
      _impactDragOffset = null;
      _impactDragAnchorOffset = null;
    });
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
  }

  void _startMoveSingleGrenade(Grenade grenade) {
    setState(() {
      _movingSingleGrenade = grenade;
    });
    _showStatusSnackBar(
      '点击地图移动道具「${grenade.title}」',
      Colors.cyan,
      duration: const Duration(seconds: 10),
      hideCurrent: false,
      action: SnackBarAction(
        label: "取消",
        textColor: Colors.white,
        onPressed: _cancelMoveSingleGrenade,
      ),
    );
  }

  void _startMoveSingleGrenadeImpact(Grenade grenade) {
    final isWallbang = grenade.type == GrenadeType.wallbang;
    setState(() {
      _movingSingleImpactGrenade = grenade;
    });
    _showStatusSnackBar(
      isWallbang
          ? '点击地图设置穿线方位「${grenade.title}」'
          : '点击地图移动爆点「${grenade.title}」',
      isWallbang ? Colors.cyan : Colors.purpleAccent,
      duration: const Duration(seconds: 10),
      hideCurrent: false,
      action: SnackBarAction(
        label: "取消",
        textColor: Colors.white,
        onPressed: _cancelMoveSingleGrenadeImpact,
      ),
    );
  }

  void _cancelMoveSingleGrenadeImpact() {
    setState(() {
      _movingSingleImpactGrenade = null;
    });
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
  }

  Future<void> _updateGrenadeImpactPoint(
    Grenade grenade, {
    double? x,
    double? y,
  }) async {
    final now = DateTime.now();
    final isar = ref.read(isarProvider);
    await isar.writeTxn(() async {
      final g = await isar.grenades.get(grenade.id);
      if (g != null) {
        g.impactXRatio = x;
        g.impactYRatio = y;
        g.hasLocalEdits = true;
        g.updatedAt = now;
        await isar.grenades.put(g);
      }
    });
    grenade.impactXRatio = x;
    grenade.impactYRatio = y;
    grenade.hasLocalEdits = true;
    grenade.updatedAt = now;
    sendOverlayCommand('reload_data');
  }

  Future<void> _saveSingleImpactPosition(
    Grenade grenade,
    double targetX,
    double targetY, {
    required int layerId,
  }) async {
    final isWallbang = grenade.type == GrenadeType.wallbang;
    await _updateGrenadeImpactPoint(grenade, x: targetX, y: targetY);
    if (!mounted) return;
    _showStatusSnackBar(
      isWallbang ? '✓ 穿线方位已更新' : '✓ 爆点位置已更新',
      isWallbang ? Colors.cyan : Colors.purpleAccent,
    );
    _reselectClusterAfterMove(grenade.id, layerId);
    setState(() {
      _movingSingleImpactGrenade = null;
    });
  }

  Future<void> _clearWallbangLine(
    Grenade grenade,
    void Function(void Function()) setPanelState,
  ) async {
    await _updateGrenadeImpactPoint(grenade, x: null, y: null);
    if (!mounted) return;
    setPanelState(() {});
    setState(() {});
    _showStatusSnackBar('穿线已清除', Colors.cyan);
  }

  Future<void> _openImpactAreaDrawing(Grenade grenade, int layerId) async {
    if (grenade.impactXRatio == null || grenade.impactYRatio == null) {
      _showStatusSnackBar(
        '请先设置爆点位置',
        Colors.orange,
        duration: const Duration(seconds: 2),
        hideCurrent: false,
      );
      return;
    }

    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => AreaDrawScreen.impactArea(
          layerId: layerId,
          impactX: grenade.impactXRatio,
          impactY: grenade.impactYRatio,
          existingStrokes: grenade.impactAreaStrokes,
          grenadeType: grenade.type,
        ),
      ),
    );

    if (result != null && result['strokes'] != null) {
      final isar = ref.read(isarProvider);
      final newStrokes = result['strokes'] as String;
      await isar.writeTxn(() async {
        final g = await isar.grenades.get(grenade.id);
        if (g != null) {
          g.impactAreaStrokes = newStrokes;
          g.updatedAt = DateTime.now();
          await isar.grenades.put(g);
        }
      });
      grenade.impactAreaStrokes = newStrokes;
      grenade.updatedAt = DateTime.now();
      if (mounted) {
        setState(() {});
      }

      if (!mounted) return;
      _showStatusSnackBar('✓ 爆点区域已保存', Colors.green, hideCurrent: false);
    }
  }

  Future<void> _openGroupImpactAreaDrawing(
    ImpactGroup group,
    List<Grenade> grenades,
    int layerId,
    void Function(void Function())? setPanelState,
  ) async {
    if (grenades.isEmpty) return;

    final referenceGrenade = grenades.first;
    String? existingStrokes;
    for (final g in grenades) {
      if (g.impactAreaStrokes != null && g.impactAreaStrokes!.isNotEmpty) {
        existingStrokes = g.impactAreaStrokes;
        break;
      }
    }

    if (referenceGrenade.impactXRatio == null ||
        referenceGrenade.impactYRatio == null) {
      _showStatusSnackBar(
        '分组内道具未设置爆点位置',
        Colors.orange,
        duration: const Duration(seconds: 2),
        hideCurrent: false,
      );
      return;
    }

    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => AreaDrawScreen.impactArea(
          layerId: layerId,
          impactX: referenceGrenade.impactXRatio,
          impactY: referenceGrenade.impactYRatio,
          existingStrokes: existingStrokes,
          grenadeType: group.type == GrenadeType.molotov
              ? GrenadeType.molotov
              : GrenadeType.smoke,
        ),
      ),
    );

    if (result != null && result['strokes'] != null) {
      final isar = ref.read(isarProvider);
      final newStrokes = result['strokes'] as String;

      await isar.writeTxn(() async {
        for (final g in grenades) {
          final freshGrenade = await isar.grenades.get(g.id);
          if (freshGrenade != null) {
            freshGrenade.impactAreaStrokes = newStrokes;
            freshGrenade.updatedAt = DateTime.now();
            await isar.grenades.put(freshGrenade);
            g.impactAreaStrokes = newStrokes;
          }
        }
      });

      setState(() {});
      setPanelState?.call(() {});

      if (!mounted) return;
      _showStatusSnackBar(
        '✓ 已同步更新分组内 ${grenades.length} 个道具的爆点区域',
        Colors.green,
        hideCurrent: false,
      );
    }
  }

  void _cancelMoveSingleGrenade() {
    setState(() {
      _movingSingleGrenade = null;
    });
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
  }

  void _onClusterDragEnd() {
    if (_draggingCluster == null || _dragOffset == null) {
      setState(() {
        _draggingCluster = null;
        _dragOffset = null;
      });
      return;
    }
    _persistGrenadesCoordsSync(
      _draggingCluster!.grenades,
      _dragOffset!.dx,
      _dragOffset!.dy,
      isImpact: false,
    );
    setState(() {
      _draggingCluster = null;
      _dragOffset = null;
      _dragAnchorOffset = null;
    });
  }

  void _onImpactClusterDragEnd() {
    if (_draggingImpactCluster == null || _impactDragOffset == null) {
      setState(() {
        _draggingImpactCluster = null;
        _impactDragOffset = null;
        _impactDragAnchorOffset = null;
      });
      return;
    }
    _persistGrenadesCoordsSync(
      _draggingImpactCluster!.grenades,
      _impactDragOffset!.dx,
      _impactDragOffset!.dy,
      isImpact: true,
    );
    setState(() {
      _draggingImpactCluster = null;
      _impactDragOffset = null;
      _impactDragAnchorOffset = null;
    });
  }

  Future<void> _showJoystickSheet(GrenadeCluster cluster) async {
    final prefs = await SharedPreferences.getInstance();
    final opacity = prefs.getDouble('joystick_opacity') ?? 0.8;
    final speed = prefs.getInt('joystick_speed') ?? 3;

    setState(() {
      _joystickCluster = cluster;
      _joystickOriginalOffset = Offset(cluster.xRatio, cluster.yRatio);
      _dragOffset = Offset(cluster.xRatio, cluster.yRatio);
    });

    if (!mounted) return;

    await showJoystickBottomSheet(
      context: context,
      barrierColor: Colors.transparent,
      opacity: opacity,
      speedLevel: speed,
      clusterName:
          cluster.grenades.isNotEmpty ? cluster.grenades.first.title : null,
      onMove: (direction) => _handleJoystickMove(direction, speed),
      onConfirm: _confirmJoystickMove,
      onCancel: _cancelJoystickMove,
    );
  }

  void _handleJoystickMove(Offset direction, int speedLevel) {
    if (_joystickCluster == null || _dragOffset == null) return;

    // 速度档位步长：1档=0.0005，5档=0.0025
    final step = 0.0005 + (speedLevel - 1) * 0.0005;
    final newX = (_dragOffset!.dx + direction.dx * step).clamp(0.0, 1.0);
    final newY = (_dragOffset!.dy + direction.dy * step).clamp(0.0, 1.0);

    setState(() {
      _dragOffset = Offset(newX, newY);
    });
    _centerMapOnPoint(newX, newY);
  }

  void _centerMapOnPoint(double xRatio, double yRatio) {
    final RenderBox? renderBox =
        _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final size = renderBox.size;
    final scale = _photoViewController.scale ?? 1.0;
    final bounds = computeMapImageBounds(size.width, size.height);
    final pointX = bounds.offsetX + xRatio * bounds.width;
    final pointY = bounds.offsetY + yRatio * bounds.height;
    final viewportCenterX = size.width / 2;
    final viewportCenterY = size.height / 2;

    final targetPositionX = (viewportCenterX - pointX) * scale;
    final targetPositionY = (viewportCenterY - pointY) * scale;

    _photoViewController.position = Offset(targetPositionX, targetPositionY);
  }

  void _confirmJoystickMove() {
    if (_joystickCluster == null || _dragOffset == null) {
      _cancelJoystickMove();
      return;
    }

    _persistGrenadesCoordsSync(
      _joystickCluster!.grenades,
      _dragOffset!.dx,
      _dragOffset!.dy,
      isImpact: false,
    );
    _showStatusSnackBar("✓ 点位已移动", Colors.green, hideCurrent: false);
    setState(() {
      _joystickCluster = null;
      _joystickOriginalOffset = null;
      _dragOffset = null;
    });
  }

  void _cancelJoystickMove() {
    setState(() {
      _dragOffset = _joystickOriginalOffset;
      _joystickCluster = null;
      _joystickOriginalOffset = null;
      _dragOffset = null;
    });
  }

  Future<void> _showJoystickSheetForImpact(GrenadeCluster cluster) async {
    final prefs = await SharedPreferences.getInstance();
    final opacity = prefs.getDouble('joystick_opacity') ?? 0.8;
    final speed = prefs.getInt('joystick_speed') ?? 3;

    setState(() {
      _joystickImpactCluster = cluster;
      _joystickImpactOriginalOffset = Offset(cluster.xRatio, cluster.yRatio);
      _impactJoystickDragOffset = Offset(cluster.xRatio, cluster.yRatio);
    });

    if (!mounted) return;

    await showJoystickBottomSheet(
      context: context,
      barrierColor: Colors.transparent,
      opacity: opacity,
      speedLevel: speed,
      clusterName: cluster.grenades.isNotEmpty
          ? '爆点: ${cluster.grenades.first.title}'
          : '爆点',
      onMove: (direction) => _handleJoystickMoveForImpact(direction, speed),
      onConfirm: _confirmJoystickMoveForImpact,
      onCancel: _cancelJoystickMoveForImpact,
    );
  }

  void _handleJoystickMoveForImpact(Offset direction, int speedLevel) {
    if (_joystickImpactCluster == null || _impactJoystickDragOffset == null) {
      return;
    }

    final step = 0.0005 + (speedLevel - 1) * 0.0005;
    final newX =
        (_impactJoystickDragOffset!.dx + direction.dx * step).clamp(0.0, 1.0);
    final newY =
        (_impactJoystickDragOffset!.dy + direction.dy * step).clamp(0.0, 1.0);

    setState(() {
      _impactJoystickDragOffset = Offset(newX, newY);
    });
    _centerMapOnPoint(newX, newY);
  }

  void _confirmJoystickMoveForImpact() {
    if (_joystickImpactCluster == null || _impactJoystickDragOffset == null) {
      _cancelJoystickMoveForImpact();
      return;
    }

    _persistGrenadesCoordsSync(
      _joystickImpactCluster!.grenades,
      _impactJoystickDragOffset!.dx,
      _impactJoystickDragOffset!.dy,
      isImpact: true,
    );
    _showStatusSnackBar("✓ 爆点已移动", Colors.purpleAccent, hideCurrent: false);
    setState(() {
      _joystickImpactCluster = null;
      _joystickImpactOriginalOffset = null;
      _impactJoystickDragOffset = null;
    });
  }

  void _cancelJoystickMoveForImpact() {
    setState(() {
      _impactJoystickDragOffset = _joystickImpactOriginalOffset;
      _joystickImpactCluster = null;
      _joystickImpactOriginalOffset = null;
      _impactJoystickDragOffset = null;
    });
  }

  // 以鼠标指针为中心计算缩放补偿偏移
  void _handleMouseWheelZoom(PointerScrollEvent event) {
    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final double scrollDelta = event.scrollDelta.dy;
    if (scrollDelta == 0) return;

    final double zoomFactor = scrollDelta > 0 ? 0.9 : 1.1;
    final double currentScale = _photoViewController.scale ?? 1.0;
    final Offset currentPosition = _photoViewController.position;

    const minScale = 0.8;
    const maxScale = 5.0;
    final double newScale =
        (currentScale * zoomFactor).clamp(minScale, maxScale);

    if ((newScale - currentScale).abs() < 0.0001) return;

    final Size size = renderBox.size;
    final Offset viewportCenter = size.center(Offset.zero);
    final Offset cursorPosition = event.localPosition - viewportCenter;
    final double scaleRatio = newScale / currentScale;
    final Offset newPosition =
        cursorPosition * (1 - scaleRatio) + currentPosition * scaleRatio;

    _photoViewController.updateMultiple(
      scale: newScale,
      position: newPosition,
    );
  }

  Widget _buildImpactClusterWidget({
    required GrenadeCluster cluster,
    required bool isEditMode,
    required int layerId,
    required double markerScale,
    required MapImageBounds imageBounds,
    required bool denseStyle,
  }) {
    final isDragging = isSameCluster(_draggingImpactCluster, cluster);
    final isJoystickMoving = isSameCluster(_joystickImpactCluster, cluster);
    double? overrideX;
    double? overrideY;
    if (isDragging && _impactDragOffset != null) {
      overrideX = _impactDragOffset!.dx;
      overrideY = _impactDragOffset!.dy;
    }
    if (isJoystickMoving && _impactJoystickDragOffset != null) {
      overrideX = _impactJoystickDragOffset!.dx;
      overrideY = _impactJoystickDragOffset!.dy;
    }

    return MapImpactClusterMarker(
      cluster: cluster,
      markerScale: markerScale,
      imageBounds: imageBounds,
      denseStyle: denseStyle,
      overrideX: overrideX,
      overrideY: overrideY,
      isSelected: isSameCluster(_selectedClusterForImpact, cluster),
      isDragging: isDragging,
      isJoystickMoving: isJoystickMoving,
      onTap: () => _handleClusterTap(cluster, layerId),
      onLongPressStart: isEditMode
          ? (details) =>
              _startImpactClusterLongPress(cluster, details.globalPosition)
          : null,
      onLongPressMoveUpdate: isEditMode
          ? (details) {
              if (_impactDragAnchorOffset == null) return;
              final touchRatio = _getLocalPosition(details.globalPosition);
              if (touchRatio == null) return;
              setState(() {
                final newPos = touchRatio - _impactDragAnchorOffset!;
                _impactDragOffset = Offset(
                  newPos.dx.clamp(0.0, 1.0),
                  newPos.dy.clamp(0.0, 1.0),
                );
              });
            }
          : null,
      onLongPressEnd: isEditMode ? (_) => _onImpactClusterDragEnd() : null,
    );
  }

  Widget _buildThrowClusterWidget({
    required GrenadeCluster cluster,
    required bool isEditMode,
    required int layerId,
    required double markerScale,
    required MapImageBounds imageBounds,
    required bool denseStyle,
  }) {
    double? overrideX;
    double? overrideY;
    if ((isSameCluster(_draggingCluster, cluster) ||
            isSameCluster(_joystickCluster, cluster)) &&
        _dragOffset != null) {
      overrideX = _dragOffset!.dx;
      overrideY = _dragOffset!.dy;
    }

    return MapThrowClusterMarker(
      cluster: cluster,
      markerScale: markerScale,
      imageBounds: imageBounds,
      denseStyle: denseStyle,
      useLegacyMarkers: _useLegacyMapMarkers,
      overrideX: overrideX,
      overrideY: overrideY,
      onTap: () => _handleClusterTap(cluster, layerId),
      onLongPressStart: isEditMode
          ? (details) =>
              _startThrowClusterLongPress(cluster, details.globalPosition)
          : null,
      onLongPressMoveUpdate: isEditMode
          ? (details) {
              if (_dragAnchorOffset == null) return;
              final touchRatio = _getLocalPosition(details.globalPosition);
              if (touchRatio == null) return;
              setState(() {
                _dragOffset = touchRatio - _dragAnchorOffset!;
              });
            }
          : null,
      onLongPressEnd: isEditMode ? (_) => _onClusterDragEnd() : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditMode = ref.watch(isEditModeProvider);
    final layerIndex = ref.watch(selectedLayerIndexProvider);
    final teamFilter = ref.watch(teamFilterProvider);
    final onlyFav = ref.watch(onlyFavoritesProvider);
    final selectedTypes = ref.watch(typeFilterProvider);
    final showSpawnPoints = ref.watch(showSpawnPointsProvider);
    final showCasualSpawnPoints = ref.watch(showCasualSpawnPointsProvider);
    final showHostagePoints = ref.watch(showHostagePointsProvider);

    final mapName = widget.gameMap.name.toLowerCase();
    final spawnConfig = spawnPointData[mapName];
    final hasCasualSpawns = spawnConfig?.hasCasualSpawns ?? false;
    final hasHostageSpawns = spawnConfig?.hasHostageSpawns ?? false;
    final effectiveShowHostages = showHostagePoints && hasHostageSpawns;
    final showAnyPresetPoints = showSpawnPoints || effectiveShowHostages;

    widget.gameMap.layers.loadSync();
    final layers = widget.gameMap.layers.toList();
    final currentLayer = (layers.isNotEmpty && layerIndex < layers.length)
        ? layers[layerIndex]
        : (layers.isNotEmpty ? layers.last : null);
    if (currentLayer == null) {
      return const Scaffold(body: Center(child: Text("数据错误：无楼层信息")));
    }

    final grenadesAsync =
        ref.watch(mapFilteredGrenadesProvider(currentLayer.id));
    final filteredGrenades = grenadesAsync.value ?? const <Grenade>[];
    final spawnPartition = (showSpawnPoints && spawnConfig != null)
        ? partitionSpawnGrenades(
            spawnConfig,
            filteredGrenades,
            includeCasual: showCasualSpawnPoints && hasCasualSpawns,
          )
        : (
            occupiedKeys: const <String>{},
            regularGrenades: filteredGrenades,
            spawnEntries: const <({String key, GrenadeCluster cluster})>[],
          );
    String? selectedSpawnKey;
    if (_selectedClusterForImpact != null && !_isImpactMode) {
      for (final entry in spawnPartition.spawnEntries) {
        if (isSameCluster(entry.cluster, _selectedClusterForImpact)) {
          selectedSpawnKey = entry.key;
          break;
        }
      }
    }
    final selectedTagIds = ref.watch(selectedTagIdsProvider);
    final tagMatchedIds = selectedTagIds.isEmpty
        ? null
        : (ref.watch(tagMatchedGrenadeIdsProvider).value ?? const <int>{});
    final showMapGrenadeListPanel =
        globalSettingsService?.getShowMapGrenadeList() ?? false;
    final showFavoritesBar = !isEditMode && _selectedClusterForImpact == null;
    final isMobile = AppBreakpoints.isMobile(context);

    final folderService = _favoriteFolderService;
    final allMapGrenades = _cachedAllMapGrenades;
    final allMapGrenadeEntries = _cachedAllMapGrenadeEntries;
    final isar = ref.read(isarProvider);

    void onSpawnPointTap(SpawnPoint spawn, bool isCT, bool isCasual) {
      showSpawnPointBottomSheet(
        context: context,
        ref: ref,
        spawn: spawn,
        isCT: isCT,
        layerId: currentLayer.id,
        isCasual: isCasual,
        onCreateAtSpawn: (ratioPosition, targetLayerId) {
          setState(() {
            _tempTapPosition = ratioPosition;
          });
          _createGrenade(targetLayerId);
        },
      );
    }

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        toolbarHeight: isMobile ? 54 : kToolbarHeight,
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: context.appTheme.subtleBorder,
          ),
        ),
        title: MapAppBarTitle(
          gameMap: widget.gameMap,
          isMobile: isMobile,
          allMapGrenades: allMapGrenades,
          isar: isar,
          onSearchResultSelected: _onSearchResultSelected,
        ),
        actions: [
          if (isMobile)
            Padding(
              padding: const EdgeInsets.only(left: 8, right: 12),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  final value = !isEditMode;
                  ref.read(isEditModeProvider.notifier).state = value;
                  _showGrenadeCreateModeHint(value);
                },
                child: AnimatedContainer(
                  duration: AppMotion.quick,
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: isEditMode
                        ? Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.18)
                        : Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isEditMode
                            ? Icons.edit_rounded
                            : Icons.visibility_outlined,
                        size: 16,
                        color: isEditMode
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).iconTheme.color,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isEditMode ? '编辑' : '浏览',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isEditMode
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).textTheme.bodyMedium?.color,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                      value: false,
                      icon: Icon(Icons.visibility_outlined, size: 16),
                      label: Text('浏览')),
                  ButtonSegment(
                      value: true,
                      icon: Icon(Icons.edit_outlined, size: 16),
                      label: Text('编辑')),
                ],
                selected: {isEditMode},
                onSelectionChanged: (selection) {
                  final value = selection.first;
                  ref.read(isEditModeProvider.notifier).state = value;
                  _showGrenadeCreateModeHint(value);
                },
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(builder: (context, constraints) {
              return Stack(
                children: [
                  Positioned.fill(
                    child: Listener(
                      onPointerSignal: (event) {
                        if (event is PointerScrollEvent) {
                          _handleMouseWheelZoom(event);
                        }
                      },
                      onPointerMove: (event) {
                        if (!_isBatchedClusterLongPressDragActive) return;
                        _handleBatchedClusterLongPressMoveUpdate(
                            event.position);
                      },
                      child: PhotoView.customChild(
                        key: ValueKey(currentLayer.id),
                        controller: _photoViewController,
                        initialScale: PhotoViewComputedScale.covered,
                        minScale: PhotoViewComputedScale.contained * 0.8,
                        maxScale: PhotoViewComputedScale.covered * 5.0,
                        child: StreamBuilder<PhotoViewControllerValue>(
                          stream: _photoViewController.outputStateStream,
                          builder: (context, snapshot) {
                            final controllerValue = snapshot.data;
                            final double scale = controllerValue?.scale ?? 1.0;
                            final Offset position = controllerValue?.position ??
                                _photoViewController.position;
                            final double markerScale = 1.0 / scale;

                            final imageBounds = computeMapImageBounds(
                              constraints.maxWidth,
                              constraints.maxHeight,
                            );
                            final visibleRatioRect =
                                computeVisibleImageRatioRect(
                              constraints: constraints,
                              scale: scale,
                              position: position,
                              imageBounds: imageBounds,
                            );
                            final pointCullMarginX = 28 / imageBounds.width;
                            final pointCullMarginY = 28 / imageBounds.height;
                            final lineCullMarginX = 40 / imageBounds.width;
                            final lineCullMarginY = 40 / imageBounds.height;
                            final layerImageProvider =
                                imageProviderFromPath(currentLayer.assetPath);
                            List<GrenadeCluster> batchedTapClusters = const [];
                            List<GrenadeCluster> batchedPaintClusters =
                                const [];
                            var enableBatchedClusterHitTest = false;
                            var batchedClustersAreImpact = false;

                            final markerOverlayWidgets = grenadesAsync.when(
                              data: (list) => buildMapMarkerOverlayWidgets(
                                context: context,
                                list: list,
                                constraints: constraints,
                                scale: scale,
                                markerScale: markerScale,
                                imageBounds: imageBounds,
                                visibleRatioRect: visibleRatioRect,
                                pointCullMarginX: pointCullMarginX,
                                pointCullMarginY: pointCullMarginY,
                                lineCullMarginX: lineCullMarginX,
                                lineCullMarginY: lineCullMarginY,
                                isEditMode: isEditMode,
                                isImpactMode: _isImpactMode,
                                useLegacyMarkers: _useLegacyMapMarkers,
                                currentLayerId: currentLayer.id,
                                spawnPartition: spawnPartition,
                                selectedClusterForImpact:
                                    _selectedClusterForImpact,
                                selectedImpactTypeFilter:
                                    _selectedImpactTypeFilter,
                                selectedImpactGroupId: _selectedImpactGroupId,
                                draggingCluster: _draggingCluster,
                                joystickCluster: _joystickCluster,
                                draggingImpactCluster: _draggingImpactCluster,
                                joystickImpactCluster: _joystickImpactCluster,
                                isBatchedClusterLongPressDragActive:
                                    _isBatchedClusterLongPressDragActive,
                                frozenThrowBatchClusters:
                                    _frozenThrowBatchClusters,
                                frozenImpactBatchClusters:
                                    _frozenImpactBatchClusters,
                                batchedDragVisualTick: _batchedDragVisualTick,
                                grenadeTypePictures: _grenadeTypePictures,
                                adaptiveClusterThreshold:
                                    _getAdaptiveClusterThreshold(
                                  scale: scale,
                                  grenadeCount: list.length,
                                ),
                                getThrowClusters: _getThrowClusters,
                                getImpactClusters: _getImpactClusters,
                                buildImpactClusterWidget:
                                    (cluster, denseStyle) =>
                                        _buildImpactClusterWidget(
                                  cluster: cluster,
                                  isEditMode: isEditMode,
                                  layerId: currentLayer.id,
                                  markerScale: markerScale,
                                  imageBounds: imageBounds,
                                  denseStyle: denseStyle,
                                ),
                                buildThrowClusterWidget:
                                    (cluster, denseStyle) =>
                                        _buildThrowClusterWidget(
                                  cluster: cluster,
                                  isEditMode: isEditMode,
                                  layerId: currentLayer.id,
                                  markerScale: markerScale,
                                  imageBounds: imageBounds,
                                  denseStyle: denseStyle,
                                ),
                                setBatchState: ({
                                  required tapClusters,
                                  required paintClusters,
                                  required enableHitTest,
                                  required clustersAreImpact,
                                }) {
                                  batchedTapClusters = tapClusters;
                                  batchedPaintClusters = paintClusters;
                                  enableBatchedClusterHitTest = enableHitTest;
                                  batchedClustersAreImpact = clustersAreImpact;
                                },
                              ),
                              error: (_, __) => const <Widget>[],
                              loading: () => const <Widget>[],
                            );

                            return GestureDetector(
                              onTapUp: (d) {
                                if (enableBatchedClusterHitTest) {
                                  final hitCluster =
                                      _hitTestClusterAtGlobalPosition(
                                    d.globalPosition,
                                    clusters: batchedTapClusters,
                                    photoScale: scale,
                                    imageBounds: imageBounds,
                                  );
                                  if (hitCluster != null) {
                                    _handleClusterTap(
                                        hitCluster, currentLayer.id);
                                    return;
                                  }
                                }
                                _handleTap(d, currentLayer.id);
                              },
                              onLongPressStart: (d) {
                                if (isEditMode && enableBatchedClusterHitTest) {
                                  final hitCluster =
                                      _hitTestClusterAtGlobalPosition(
                                    d.globalPosition,
                                    clusters: batchedTapClusters,
                                    photoScale: scale,
                                    imageBounds: imageBounds,
                                  );
                                  if (hitCluster != null) {
                                    if (batchedClustersAreImpact) {
                                      _startImpactClusterLongPress(
                                        hitCluster,
                                        d.globalPosition,
                                        batchedClustersSnapshot:
                                            batchedTapClusters,
                                      );
                                    } else {
                                      _startThrowClusterLongPress(
                                        hitCluster,
                                        d.globalPosition,
                                        batchedClustersSnapshot:
                                            batchedPaintClusters,
                                      );
                                    }
                                    return;
                                  }
                                }
                                if (_getGrenadeCreateMode() !=
                                    _grenadeCreateModeLongPress) {
                                  return;
                                }
                                _tryCreateGrenadeAtGlobalPosition(
                                    d.globalPosition, currentLayer.id);
                              },
                              onLongPressMoveUpdate: (d) {
                                if (!isEditMode ||
                                    !_isBatchedClusterLongPressDragActive) {
                                  return;
                                }
                              },
                              onLongPressEnd: (d) {
                                if (!isEditMode ||
                                    !_isBatchedClusterLongPressDragActive) {
                                  return;
                                }
                                _handleBatchedClusterLongPressEnd();
                              },
                              child: Stack(
                                key: _stackKey,
                                children: [
                                  layerImageProvider == null
                                      ? Container(
                                          width: constraints.maxWidth,
                                          height: constraints.maxHeight,
                                          color: const Color(0xFF616161),
                                        )
                                      : Image(
                                          image: layerImageProvider,
                                          width: constraints.maxWidth,
                                          height: constraints.maxHeight,
                                          fit: BoxFit.contain,
                                        ),
                                  if (showAnyPresetPoints &&
                                      spawnConfig != null)
                                    Positioned.fill(
                                      child: IgnorePointer(
                                        child: RepaintBoundary(
                                          child: CustomPaint(
                                            painter: SpawnPointOverlayPainter(
                                              config: spawnConfig,
                                              imageBounds: imageBounds,
                                              photoScale: scale,
                                              markerScale: markerScale,
                                              showSpawns: showSpawnPoints,
                                              showCasual: showSpawnPoints &&
                                                  showCasualSpawnPoints &&
                                                  hasCasualSpawns,
                                              showHostages:
                                                  effectiveShowHostages,
                                              occupiedKeys:
                                                  spawnPartition.occupiedKeys,
                                              selectedKey: selectedSpawnKey,
                                              textDirection:
                                                  Directionality.of(context),
                                              hoveredKey: _hoveredSpawnKey,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ...markerOverlayWidgets,
                                  if (_movingSingleImpactGrenade != null) ...[
                                    if (_movingSingleImpactGrenade!.type ==
                                        GrenadeType.wallbang)
                                      MapWallbangLine(
                                        grenade: _movingSingleImpactGrenade!,
                                        scale: markerScale,
                                        imageBounds: imageBounds,
                                      )
                                    else ...[
                                      MapConnectionLine(
                                        grenade: _movingSingleImpactGrenade!,
                                        scale: markerScale,
                                        imageBounds: imageBounds,
                                      ),
                                      MapImpactMarker(
                                        grenade: _movingSingleImpactGrenade!,
                                        markerScale: markerScale,
                                        imageBounds: imageBounds,
                                      ),
                                    ],
                                  ],
                                  if (_isImpactMode &&
                                      _movingSingleGrenade != null)
                                    MapThrowPointMarker(
                                      grenade: _movingSingleGrenade!,
                                      markerScale: markerScale,
                                      imageBounds: imageBounds,
                                      useLegacyMarkers: _useLegacyMapMarkers,
                                    ),
                                  if (_draggingCluster != null)
                                    ValueListenableBuilder<int>(
                                      valueListenable: _batchedDragVisualTick,
                                      builder: (_, __, ___) {
                                        if (_dragOffset == null) {
                                          return const SizedBox.shrink();
                                        }
                                        return Positioned(
                                          left: imageBounds.offsetX +
                                              _dragOffset!.dx *
                                                  imageBounds.width -
                                              14.0,
                                          top: imageBounds.offsetY +
                                              _dragOffset!.dy *
                                                  imageBounds.height -
                                              14.0,
                                          child: Transform.scale(
                                            scale: markerScale,
                                            alignment: Alignment.center,
                                            child: Container(
                                              width: 28,
                                              height: 28,
                                              decoration: BoxDecoration(
                                                color: Colors.cyan
                                                    .withValues(alpha: 0.6),
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: Colors.cyan,
                                                  width: 2,
                                                ),
                                              ),
                                              child: const Icon(
                                                Icons.open_with,
                                                size: 14,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  if (_tempTapPosition != null)
                                    Positioned(
                                      left: imageBounds.offsetX +
                                          _tempTapPosition!.dx *
                                              imageBounds.width -
                                          12.0,
                                      top: imageBounds.offsetY +
                                          _tempTapPosition!.dy *
                                              imageBounds.height -
                                          12.0,
                                      child: Transform.scale(
                                        scale: markerScale,
                                        child: const Icon(
                                          Icons.add_circle,
                                          color: Colors.greenAccent,
                                          size: 24,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    left: 16,
                    right: 16,
                    child: Center(
                      child: MapTopFilterBar(
                        isMobile: isMobile,
                        useLegacyMarkers: _useLegacyMapMarkers,
                        hasHostageSpawns: hasHostageSpawns,
                        onBeforeToggleSpawns: () =>
                            _hoveredSpawnKey.value = null,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 12,
                    bottom: 16,
                    child: MapCornerToolCapsules(
                      isMobile: isMobile,
                      layerCount: layers.length,
                      layerIndex: layerIndex,
                      isImpactMode: _isImpactMode,
                      hasSelectedTags: selectedTagIds.isNotEmpty,
                      onToggleImpactMode: () {
                        setState(() {
                          _isImpactMode = !_isImpactMode;
                          _selectedClusterForImpact = null;
                        });
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content:
                              Text(_isImpactMode ? "已开启爆点浏览模式" : "已切换回标准模式"),
                          duration: const Duration(seconds: 2),
                          behavior: SnackBarBehavior.floating,
                        ));
                      },
                      onOpenTagFilter: () => showTagFilterSheet(
                        hostContext: context,
                        ref: ref,
                        gameMap: widget.gameMap,
                        layerId: currentLayer.id,
                      ),
                    ),
                  ),
                  if (showSpawnPoints &&
                      spawnConfig != null &&
                      _selectedClusterForImpact == null)
                    if (isMobile)
                      Positioned(
                        right: 12,
                        top: 62,
                        bottom: 68,
                        child: MobileSpawnPointSidebar(
                          config: spawnConfig,
                          layerId: currentLayer.id,
                          isEditMode: isEditMode,
                          showCasual: showCasualSpawnPoints,
                          isExpanded: _isSpawnSidebarExpanded,
                          onExpandedChanged: (expanded) => setState(
                              () => _isSpawnSidebarExpanded = expanded),
                          onSelectSpawn: onSpawnPointTap,
                        ),
                      )
                    else
                      Positioned(
                        right: 12,
                        top: 62,
                        child: DesktopSpawnPointCard(
                          config: spawnConfig,
                          layerId: currentLayer.id,
                          showCasual: showCasualSpawnPoints,
                          maxHeight:
                              (constraints.maxHeight - 170).clamp(160.0, 340.0),
                          isExpanded: _isSpawnSidebarExpanded,
                          selectedTab: _selectedSpawnSidebarTab,
                          hoveredSpawnKey: _hoveredSpawnKey,
                          onExpandedChanged: (expanded) => setState(
                              () => _isSpawnSidebarExpanded = expanded),
                          onTabChanged: (tab) =>
                              setState(() => _selectedSpawnSidebarTab = tab),
                          onSelectSpawn: onSpawnPointTap,
                        ),
                      ),
                  if (showFavoritesBar)
                    Positioned(
                      left: 12,
                      right: 112,
                      bottom: 16,
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: MapFavoritesBar(
                          gameMap: widget.gameMap,
                          folderService: folderService,
                          onGrenadeTap: (g) =>
                              _handleGrenadeTap(g, isEditing: false),
                        ),
                      ),
                    ),
                ],
              );
            }),
          ),
          SizedBox(
            width: double.infinity,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              reverseDuration: const Duration(milliseconds: 200),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.bottomCenter,
                children: [...previous, if (current != null) current],
              ),
              transitionBuilder: (child, animation) => ClipRect(
                child: SizeTransition(
                  sizeFactor: animation,
                  alignment: const Alignment(-1.0, 1.0),
                  child: child,
                ),
              ),
              child: _selectedClusterForImpact != null
                  ? KeyedSubtree(
                      key: const ValueKey('clusterPanel'),
                      child: MapClusterListPanel(
                        cluster: _selectedClusterForImpact!,
                        layerId: currentLayer.id,
                        isEditMode: isEditMode,
                        isImpactMode: _isImpactMode,
                        useLegacyMarkers: _useLegacyMapMarkers,
                        selectedImpactTypeFilter: _selectedImpactTypeFilter,
                        selectedImpactGroupId: _selectedImpactGroupId,
                        onClosePanel: _closeClusterPanel,
                        onSelectImpactFilter: (groupId, typeFilter) {
                          setState(() {
                            _selectedImpactGroupId = groupId;
                            _selectedImpactTypeFilter = typeFilter;
                          });
                        },
                        onStartMoveCluster: () =>
                            _startMoveCluster(_selectedClusterForImpact!),
                        onStartMoveImpactCluster: () =>
                            _startMoveImpactCluster(_selectedClusterForImpact!),
                        onCreateGrenadeAtCluster: () => _createGrenadeAtCluster(
                            _selectedClusterForImpact!, currentLayer.id),
                        onTapGrenade: (g) =>
                            _handleGrenadeTap(g, isEditing: isEditMode),
                        onStartMoveSingleGrenade: _startMoveSingleGrenade,
                        onStartMoveSingleGrenadeImpact:
                            _startMoveSingleGrenadeImpact,
                        onClearWallbangLine: _clearWallbangLine,
                        onOpenImpactAreaDrawing: (g) =>
                            _openImpactAreaDrawing(g, currentLayer.id),
                        onOpenGroupImpactAreaDrawing:
                            (group, grenades, setPanelState) =>
                                _openGroupImpactAreaDrawing(
                          group,
                          grenades,
                          currentLayer.id,
                          setPanelState,
                        ),
                        onDeleteGrenadesInBatch: _deleteGrenadesInBatch,
                        onParentRefresh: () => setState(() {}),
                      ),
                    )
                  : showMapGrenadeListPanel
                      ? KeyedSubtree(
                          key: const ValueKey('allMapPanel'),
                          child: MapAllGrenadesPanel(
                            isar: isar,
                            entries: allMapGrenadeEntries
                                .where((e) => passesGrenadeFilter(
                                    e.grenade,
                                    selectedTypes,
                                    teamFilter,
                                    onlyFav,
                                    tagMatchedIds))
                                .toList(),
                            isEditMode: isEditMode,
                            currentLayerId: currentLayer.id,
                            isImpactMode: _isImpactMode,
                            useLegacyMarkers: _useLegacyMapMarkers,
                            panelHeightNotifier: _allMapListPanelHeightNotifier,
                            searchController: _allMapListSearchController,
                            searchQuery: _allMapListSearchQuery,
                            onSearchQueryChanged: (value) =>
                                setState(() => _allMapListSearchQuery = value),
                            onToggleCollapsed: _toggleAllMapListPanelCollapsed,
                            onResize: _resizeAllMapListPanel,
                            onSnapHeight: _snapAllMapListPanelHeight,
                            onTapGrenade: (g, layer) {
                              _switchToLayerById(layer.id,
                                  layerName: layer.name);
                              _handleGrenadeTap(g, isEditing: isEditMode);
                            },
                            onDeleteGrenade: _deleteGrenadeFromMapList,
                            onTapImpactCluster: (cluster, layer) {
                              _switchToLayerById(layer.id,
                                  layerName: layer.name);
                              _showClusterBottomSheet(cluster, layer.id);
                            },
                          ),
                        )
                      : null,
            ),
          ),
        ],
      ),
    );
  }
}
