import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../services/settings_service.dart';
import '../../theme/app_design_system.dart';

/// 通用设置分区卡片容器
class SettingsSectionCard extends StatelessWidget {
  final String iconAsset;
  final String title;
  final String? subtitle;
  final bool danger;
  final List<Widget> children;

  const SettingsSectionCard({
    super.key,
    required this.iconAsset,
    required this.title,
    this.subtitle,
    this.danger = false,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final accentColor = danger
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.primary;

    return Card(
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: SvgPicture.asset(
                    iconAsset,
                    colorFilter: ColorFilter.mode(accentColor, BlendMode.srcIn),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: danger
                              ? Theme.of(context).colorScheme.error
                              : null,
                        ),
                      ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            subtitle!,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

/// 桌面端热键配置分区
class DesktopHotkeySection extends StatelessWidget {
  final Map<HotkeyAction, HotkeyConfig> hotkeys;
  final void Function(HotkeyAction action, String label) onEditHotkey;
  final VoidCallback onResetHotkeys;

  const DesktopHotkeySection({
    super.key,
    required this.hotkeys,
    required this.onEditHotkey,
    required this.onResetHotkeys,
  });

  static const List<List<(HotkeyAction, String)>> _hotkeyGroups = [
    [
      (HotkeyAction.toggleOverlay, '显示/隐藏悬浮窗'),
      (HotkeyAction.navigateUp, '向上导航点位'),
      (HotkeyAction.navigateDown, '向下导航点位'),
      (HotkeyAction.navigateLeft, '向左导航点位'),
      (HotkeyAction.navigateRight, '向右导航点位'),
    ],
    [
      (HotkeyAction.prevGrenade, '上一个道具'),
      (HotkeyAction.nextGrenade, '下一个道具'),
      (HotkeyAction.prevStep, '上一个步骤'),
      (HotkeyAction.nextStep, '下一个步骤'),
    ],
    [
      (HotkeyAction.toggleSmoke, '烟雾弹过滤开关'),
      (HotkeyAction.toggleFlash, '闪光弹过滤开关'),
      (HotkeyAction.toggleMolotov, '燃烧弹过滤开关'),
      (HotkeyAction.toggleHE, '手雷过滤开关'),
      (HotkeyAction.toggleWallbang, '穿点过滤开关'),
    ],
    [
      (HotkeyAction.togglePlayPause, '悬浮窗播放/暂停视频'),
      (HotkeyAction.toggleMediaFullscreenPreview, '媒体全屏预览'),
    ],
    [
      (HotkeyAction.increaseNavSpeed, '增加导航速度'),
      (HotkeyAction.decreaseNavSpeed, '减少导航速度'),
    ],
  ];

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var groupIndex = 0; groupIndex < _hotkeyGroups.length; groupIndex++) {
      if (groupIndex > 0) {
        children.add(const Divider(height: 1));
      }
      for (final (action, label) in _hotkeyGroups[groupIndex]) {
        children.add(_buildHotkeyTile(context, action, label));
      }
    }
    children.add(const Divider(height: 1));
    children.add(
      Padding(
        padding: const EdgeInsets.all(12),
        child: OutlinedButton.icon(
          onPressed: onResetHotkeys,
          icon: const Icon(Icons.restore, size: 18),
          label: const Text('恢复默认快捷键'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.orange,
            side: const BorderSide(color: Colors.orange),
          ),
        ),
      ),
    );

    return SettingsSectionCard(
      iconAsset: 'assets/icons/settings_hotkeys.svg',
      title: '快捷键配置',
      subtitle: '点击可自定义快捷键',
      children: children,
    );
  }

  Widget _buildHotkeyTile(
      BuildContext context, HotkeyAction action, String label) {
    final config = hotkeys[action];
    final displayStr = config?.toDisplayString() ?? '未设置';

    return ListTile(
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: context.appTheme.subtleBorder),
            ),
            child: Text(
              displayStr,
              style: TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.edit, size: 20),
            onPressed: () => onEditHotkey(action, label),
          ),
        ],
      ),
    );
  }
}

/// 桌面端悬浮窗设置分区
class DesktopOverlaySection extends StatelessWidget {
  final double overlayOpacity;
  final int overlaySize;
  final int overlayNavSpeed;
  final ValueChanged<double> onOverlayOpacityChanged;
  final ValueChanged<int> onOverlaySizeChanged;
  final ValueChanged<int> onOverlayNavSpeedChanged;

  const DesktopOverlaySection({
    super.key,
    required this.overlayOpacity,
    required this.overlaySize,
    required this.overlayNavSpeed,
    required this.onOverlayOpacityChanged,
    required this.onOverlaySizeChanged,
    required this.onOverlayNavSpeedChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SettingsSectionCard(
      iconAsset: 'assets/icons/settings_overlay.svg',
      title: '悬浮窗设置',
      children: [
        ListTile(
          title: const Text('透明度'),
          subtitle: Text('${(overlayOpacity * 100).toInt()}%'),
          trailing: SizedBox(
            width: 200,
            child: Slider(
              value: overlayOpacity,
              min: 0.3,
              max: 1.0,
              divisions: 14,
              onChanged: onOverlayOpacityChanged,
            ),
          ),
        ),
        ListTile(
          title: const Text('窗口尺寸'),
          subtitle:
              Text(['小 (500×800)', '中 (550×850)', '大 (600×950)'][overlaySize]),
          trailing: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('小')),
              ButtonSegment(value: 1, label: Text('中')),
              ButtonSegment(value: 2, label: Text('大')),
            ],
            selected: {overlaySize},
            onSelectionChanged: (value) => onOverlaySizeChanged(value.first),
          ),
        ),
        ListTile(
          title: const Text('导航速度'),
          subtitle: Text('$overlayNavSpeed 档'),
          trailing: SizedBox(
            width: 200,
            child: Slider(
              value: overlayNavSpeed.toDouble(),
              min: 1,
              max: 5,
              divisions: 4,
              label: '$overlayNavSpeed 档',
              onChanged: (value) => onOverlayNavSpeedChanged(value.round()),
            ),
          ),
        ),
      ],
    );
  }
}

/// 通用外观设置分区
class GeneralAppearanceSection extends StatelessWidget {
  final bool isDesktop;
  final int themeMode;
  final bool closeToTray;
  final ValueChanged<int> onThemeModeChanged;
  final ValueChanged<bool> onCloseToTrayChanged;

  const GeneralAppearanceSection({
    super.key,
    required this.isDesktop,
    required this.themeMode,
    required this.closeToTray,
    required this.onThemeModeChanged,
    required this.onCloseToTrayChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SettingsSectionCard(
      iconAsset: 'assets/icons/settings_general.svg',
      title: isDesktop ? '通用设置' : '外观设置',
      children: [
        ListTile(
          title: const Text('主题模式'),
          trailing: SegmentedButton<int>(
            segments: const [
              ButtonSegment(
                value: 0,
                icon: Icon(Icons.brightness_auto),
                label: Text('自动'),
              ),
              ButtonSegment(
                value: 1,
                icon: Icon(Icons.light_mode),
                label: Text('浅色'),
              ),
              ButtonSegment(
                value: 2,
                icon: Icon(Icons.dark_mode),
                label: Text('深色'),
              ),
            ],
            selected: {themeMode},
            onSelectionChanged: (value) => onThemeModeChanged(value.first),
          ),
        ),
        if (isDesktop)
          SwitchListTile(
            title: const Text('关闭按钮最小化到托盘'),
            subtitle: const Text('关闭时隐藏到系统托盘，不退出程序'),
            value: closeToTray,
            onChanged: onCloseToTrayChanged,
          ),
      ],
    );
  }
}

/// 地图显示设置分区
class MapDisplaySection extends StatelessWidget {
  final bool isDesktop;
  final int mapLineColor;
  final double mapLineOpacity;
  final double impactAreaOpacity;
  final bool mapMarkerUseEmoji;
  final ValueChanged<int> onMapLineColorChanged;
  final ValueChanged<double> onMapLineOpacityChanged;
  final ValueChanged<double> onImpactAreaOpacityChanged;
  final ValueChanged<bool> onMapMarkerUseEmojiChanged;

  const MapDisplaySection({
    super.key,
    required this.isDesktop,
    required this.mapLineColor,
    required this.mapLineOpacity,
    required this.impactAreaOpacity,
    required this.mapMarkerUseEmoji,
    required this.onMapLineColorChanged,
    required this.onMapLineOpacityChanged,
    required this.onImpactAreaOpacityChanged,
    required this.onMapMarkerUseEmojiChanged,
  });

  static const List<int> _presetLineColors = [
    0xFFE040FB,
    0xFF448AFF,
    0xFF18FFFF,
    0xFF69F0AE,
    0xFFFFAB40,
    0xFFFF5252,
    0xFFFFFFFF,
  ];

  @override
  Widget build(BuildContext context) {
    final colorPicker = Row(
      mainAxisSize: MainAxisSize.min,
      children: _presetLineColors.map((colorValue) {
        final isSelected = mapLineColor == colorValue;
        return GestureDetector(
          onTap: () => onMapLineColorChanged(colorValue),
          child: Container(
            margin: const EdgeInsets.only(right: 12),
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Color(colorValue),
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? Colors.white : Colors.transparent,
                width: 2,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: Color(colorValue).withValues(alpha: 0.5),
                        blurRadius: 6,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: isSelected
                ? const Icon(Icons.check, size: 16, color: Colors.black54)
                : null,
          ),
        );
      }).toList(),
    );

    return SettingsSectionCard(
      iconAsset: 'assets/icons/settings_map.svg',
      title: '地图显示',
      children: [
        ListTile(
          title: const Text('连接线颜色'),
          subtitle: isDesktop
              ? Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: colorPicker,
                )
              : colorPicker,
        ),
        ListTile(
          title: const Text('连接线透明度'),
          subtitle: Text('${(mapLineOpacity * 100).toInt()}%'),
          trailing: SizedBox(
            width: isDesktop ? 200 : 150,
            child: Slider(
              value: mapLineOpacity,
              min: 0.1,
              max: 1.0,
              divisions: 9,
              onChanged: onMapLineOpacityChanged,
            ),
          ),
        ),
        if (isDesktop)
          ListTile(
            title: const Text('爆点区域透明度'),
            subtitle: Text('${(impactAreaOpacity * 100).toInt()}%'),
            trailing: SizedBox(
              width: 200,
              child: Slider(
                value: impactAreaOpacity,
                min: 0.1,
                max: 1.0,
                divisions: 9,
                onChanged: onImpactAreaOpacityChanged,
              ),
            ),
          ),
        SwitchListTile(
          title: const Text('使用旧版道具图标'),
          subtitle: const Text('所有界面的道具类型图标统一切换为旧版'),
          value: mapMarkerUseEmoji,
          onChanged: onMapMarkerUseEmojiChanged,
        ),
      ],
    );
  }
}

/// 标点操作设置分区
class MarkerOperationSection extends StatelessWidget {
  final bool isDesktop;
  final int grenadeCreateMode;
  final bool showMapGrenadeList;
  final bool highDensityClusterMode;
  final int markerMoveMode;
  final double joystickOpacity;
  final int joystickSpeed;
  final ValueChanged<int> onGrenadeCreateModeChanged;
  final ValueChanged<bool> onShowMapGrenadeListChanged;
  final ValueChanged<bool> onHighDensityClusterModeChanged;
  final ValueChanged<int> onMarkerMoveModeChanged;
  final ValueChanged<double> onJoystickOpacityChanged;
  final ValueChanged<int> onJoystickSpeedChanged;

  const MarkerOperationSection({
    super.key,
    required this.isDesktop,
    required this.grenadeCreateMode,
    required this.showMapGrenadeList,
    required this.highDensityClusterMode,
    required this.markerMoveMode,
    required this.joystickOpacity,
    required this.joystickSpeed,
    required this.onGrenadeCreateModeChanged,
    required this.onShowMapGrenadeListChanged,
    required this.onHighDensityClusterModeChanged,
    required this.onMarkerMoveModeChanged,
    required this.onJoystickOpacityChanged,
    required this.onJoystickSpeedChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SettingsSectionCard(
      iconAsset: 'assets/icons/settings_marker.svg',
      title: '标点操作',
      children: [
        ListTile(
          title: const Text('新增方式'),
          subtitle: Text(
            grenadeCreateMode == 0
                ? '单点地图立即新增道具'
                : (isDesktop ? '长按地图新增道具（鼠标左键按住）' : '长按地图新增道具'),
          ),
          trailing: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('单点新增')),
              ButtonSegment(value: 1, label: Text('长按新增')),
            ],
            selected: {grenadeCreateMode},
            onSelectionChanged: (value) =>
                onGrenadeCreateModeChanged(value.first),
          ),
        ),
        SwitchListTile(
          title: const Text('地图界面显示道具列表'),
          subtitle: const Text('显示当前地图全部道具列表，便于管理和删除'),
          value: showMapGrenadeList,
          onChanged: onShowMapGrenadeListChanged,
        ),
        SwitchListTile(
          title: const Text('高密度模式/强聚合模式'),
          subtitle: const Text('仅增大地图页聚合范围'),
          value: highDensityClusterMode,
          onChanged: onHighDensityClusterModeChanged,
        ),
        if (!isDesktop) ...[
          ListTile(
            title: const Text('移动模式'),
            subtitle: Text(markerMoveMode == 0 ? '长按选定后点击目标位置' : '长按选定后使用摇杆'),
            trailing: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('长按选定')),
                ButtonSegment(value: 1, label: Text('摇杆移动')),
              ],
              selected: {markerMoveMode},
              onSelectionChanged: (value) =>
                  onMarkerMoveModeChanged(value.first),
            ),
          ),
          if (markerMoveMode == 1) ...[
            ListTile(
              title: const Text('摇杆透明度'),
              subtitle: Text('${(joystickOpacity * 100).toInt()}%'),
              trailing: SizedBox(
                width: 150,
                child: Slider(
                  value: joystickOpacity,
                  min: 0.1,
                  max: 1.0,
                  divisions: 9,
                  onChanged: onJoystickOpacityChanged,
                ),
              ),
            ),
            ListTile(
              title: const Text('移动速度'),
              subtitle: Text('$joystickSpeed 档'),
              trailing: SizedBox(
                width: 150,
                child: Slider(
                  value: joystickSpeed.toDouble(),
                  min: 1,
                  max: 5,
                  divisions: 4,
                  onChanged: (value) => onJoystickSpeedChanged(value.toInt()),
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }
}

/// 桌面端数据存储目录分区
class DesktopDataStorageSection extends StatelessWidget {
  final String currentDataPath;
  final String defaultDataPath;
  final VoidCallback onResetToDefaultPath;
  final VoidCallback onChangeDataDirectory;

  const DesktopDataStorageSection({
    super.key,
    required this.currentDataPath,
    required this.defaultDataPath,
    required this.onResetToDefaultPath,
    required this.onChangeDataDirectory,
  });

  @override
  Widget build(BuildContext context) {
    return SettingsSectionCard(
      iconAsset: 'assets/icons/settings_storage.svg',
      title: '数据存储',
      subtitle: '更改数据目录需要重启应用',
      children: [
        ListTile(
          title: const Text('当前数据目录'),
          subtitle: Text(
            currentDataPath.isEmpty ? '加载中...' : currentDataPath,
            style: TextStyle(
              fontSize: 12,
              color: currentDataPath == defaultDataPath
                  ? Colors.grey
                  : Colors.orange,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (currentDataPath != defaultDataPath &&
                  currentDataPath.isNotEmpty)
                TextButton.icon(
                  onPressed: onResetToDefaultPath,
                  icon: const Icon(Icons.restore, size: 18),
                  label: const Text('恢复默认'),
                  style: TextButton.styleFrom(foregroundColor: Colors.grey),
                ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: onChangeDataDirectory,
                icon: const Icon(Icons.folder_open, size: 18),
                label: const Text('更改目录'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.black,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.amber[700], size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '更改目录后需要手动重启应用。您可以选择自动将现有数据迁移到新目录。\n\n注意：更改目录后卸载应用需要手动删除更改过后数据目录的所有数据。',
                    style: TextStyle(fontSize: 12, color: Colors.amber[700]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 数据管理危险操作分区
class DataManagementSection extends StatelessWidget {
  final VoidCallback onInitializeBuiltinAreaMetadata;
  final VoidCallback onDeleteMapGrenades;
  final VoidCallback onDeleteCustomMaps;
  final VoidCallback onBatchSelectDelete;
  final VoidCallback onCleanupOrphanMediaFiles;

  const DataManagementSection({
    super.key,
    required this.onInitializeBuiltinAreaMetadata,
    required this.onDeleteMapGrenades,
    required this.onDeleteCustomMaps,
    required this.onBatchSelectDelete,
    required this.onCleanupOrphanMediaFiles,
  });

  @override
  Widget build(BuildContext context) {
    return SettingsSectionCard(
      iconAsset: 'assets/icons/settings_data.svg',
      title: '危险操作',
      subtitle: '这些操作可能删除或覆盖本地数据',
      danger: true,
      children: [
        ListTile(
          leading: const Icon(Icons.playlist_add_check, color: Colors.teal),
          title: const Text('重导入默认区域标签/数据'),
          subtitle: const Text('一键补齐内置默认区域标签与区域几何数据'),
          trailing: const Icon(Icons.chevron_right),
          onTap: onInitializeBuiltinAreaMetadata,
        ),
        ListTile(
          leading: const Icon(Icons.delete_sweep, color: Colors.redAccent),
          title: const Text('清空地图道具'),
          subtitle: const Text('删除选定地图的所有道具数据'),
          trailing: const Icon(Icons.chevron_right),
          onTap: onDeleteMapGrenades,
        ),
        ListTile(
          leading: const Icon(Icons.delete_forever, color: Colors.red),
          title: const Text('删除自定义地图'),
          subtitle: const Text('支持多选删除自定义地图及其关联数据'),
          trailing: const Icon(Icons.chevron_right),
          onTap: onDeleteCustomMaps,
        ),
        ListTile(
          leading: const Icon(Icons.checklist, color: Colors.orange),
          title: const Text('批量选择删除'),
          subtitle: const Text('精确选择要删除的道具，支持预览'),
          trailing: const Icon(Icons.chevron_right),
          onTap: onBatchSelectDelete,
        ),
        ListTile(
          leading: const Icon(
            Icons.cleaning_services,
            color: Colors.lightBlueAccent,
          ),
          title: const Text('清理孤儿媒体文件'),
          subtitle: const Text('扫描并清理未被道具和自定义地图引用的媒体与残留记录'),
          trailing: const Icon(Icons.chevron_right),
          onTap: onCleanupOrphanMediaFiles,
        ),
      ],
    );
  }
}
