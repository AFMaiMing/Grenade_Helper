import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';

import '../models.dart';
import '../providers.dart';
import 'export_select_screen.dart';

/// 道具导出与分享入口页
class ShareScreen extends ConsumerStatefulWidget {
  const ShareScreen({super.key});

  @override
  ConsumerState<ShareScreen> createState() => _ShareScreenState();
}

class _ShareScreenState extends ConsumerState<ShareScreen> {
  List<GameMap> _maps = [];
  List<Grenade> _grenades = [];
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadData();
    });
  }

  void _loadData() {
    final isar = ref.read(isarProvider);
    setState(() {
      _maps = isar.gameMaps.where().findAllSync();
      _grenades = isar.grenades.where().findAllSync();
      _isInitialized = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Scaffold(
        appBar: AppBar(title: const Text('分享')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('分享'),
          bottom: const TabBar(
            indicatorColor: Colors.orange,
            labelColor: Colors.orange,
            unselectedLabelColor: Colors.grey,
            tabs: [
              Tab(text: '选择道具'),
              Tab(text: '选择地图'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildSingleGrenadeTab(context),
            _buildMapTab(context),
          ],
        ),
      ),
    );
  }

  Widget _buildSingleGrenadeTab(BuildContext context) {
    if (_grenades.isEmpty) {
      return const Center(
        child: Text('暂无道具数据', style: TextStyle(color: Colors.grey)),
      );
    }

    final mapStats = <String, int>{};
    for (final g in _grenades) {
      g.layer.loadSync();
      g.layer.value?.map.loadSync();
      final mapName = g.layer.value?.map.value?.name ?? '未知';
      mapStats[mapName] = (mapStats[mapName] ?? 0) + 1;
    }

    return _buildModeTab(
      context,
      icon: Icons.checklist,
      accentColor: Colors.blueAccent,
      headline: '数据库中共有 ${_grenades.length} 个道具',
      subline: '分布在 ${mapStats.length} 张地图中',
      buttonLabel: '选择要分享的道具',
      helperText: '可以按地图筛选，选择具体要分享的道具',
      exportMode: 0,
    );
  }

  Widget _buildMapTab(BuildContext context) {
    var mapsWithDataCount = 0;
    for (final map in _maps) {
      map.layers.loadSync();
      for (final layer in map.layers) {
        layer.grenades.loadSync();
        if (layer.grenades.isNotEmpty) {
          mapsWithDataCount++;
          break;
        }
      }
    }

    return _buildModeTab(
      context,
      icon: Icons.map,
      accentColor: Colors.orange,
      headline: '共有 $mapsWithDataCount 张地图包含道具',
      subline: '总计 ${_grenades.length} 个道具',
      buttonLabel: '选择要分享的地图',
      helperText: '选择地图后，将导出所选地图的全部道具',
      exportMode: 1,
    );
  }

  Widget _buildModeTab(
    BuildContext context, {
    required IconData icon,
    required Color accentColor,
    required String headline,
    required String subline,
    required String buttonLabel,
    required String helperText,
    required int exportMode,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 80, color: accentColor),
          const SizedBox(height: 20),
          Text(headline, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 8),
          Text(subline, style: TextStyle(color: Colors.grey[600])),
          const SizedBox(height: 40),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ExportSelectScreen(mode: exportMode),
                ),
              );
            },
            icon: const Icon(Icons.check_box),
            label: Text(buttonLabel, style: const TextStyle(fontSize: 16)),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
              backgroundColor: accentColor,
              foregroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              helperText,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}
