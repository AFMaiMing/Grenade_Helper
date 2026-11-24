import 'package:flutter/material.dart';

import '../../services/lan_sync/lan_sync_local_store.dart';
import 'settings_sections.dart';

/// 局域网同步调试信息折叠面板
class LanSyncDebugSection extends StatefulWidget {
  const LanSyncDebugSection({super.key});

  @override
  State<LanSyncDebugSection> createState() => _LanSyncDebugSectionState();
}

class _LanSyncDebugSectionState extends State<LanSyncDebugSection> {
  bool _isLoading = false;
  LanSyncTombstoneStats _tombstoneStats =
      const LanSyncTombstoneStats(grenadeCount: 0, entityCount: 0);

  Future<void> _loadLanSyncDebugInfo() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final store = LanSyncLocalStore();
      await store.cleanupLegacySyncState();
      await store.cleanupSyncTombstones();
      final stats = await store.loadTombstoneStats();
      if (!mounted) return;
      setState(() {
        _tombstoneStats = stats;
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildExpandedContent() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          Chip(label: Text('道具删除 ${_tombstoneStats.grenadeCount}')),
          Chip(label: Text('其他删除 ${_tombstoneStats.entityCount}')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SettingsSectionCard(
      iconAsset: 'assets/icons/settings_debug.svg',
      title: '调试信息',
      subtitle: '仅 Debug 构建显示',
      children: [
        ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          title: const Text(
            '局域网同步删除日志',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            _isLoading
                ? '正在加载...'
                : '共 ${_tombstoneStats.grenadeCount + _tombstoneStats.entityCount} 条',
          ),
          trailing: IconButton(
            tooltip: '刷新',
            onPressed: _isLoading ? null : _loadLanSyncDebugInfo,
            icon: const Icon(Icons.refresh),
          ),
        ),
        _buildExpandedContent(),
      ],
    );
  }
}
