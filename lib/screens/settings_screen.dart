import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../main.dart' show sendOverlayCommand;
import '../providers.dart';
import '../services/settings_service.dart';
import '../theme/app_design_system.dart';
import '../widgets/grenade_type_icon.dart';
import 'grenade_select_delete_screen.dart';
import 'settings/hotkey_editor_dialog.dart';
import 'settings/lan_sync_debug_section.dart';
import 'settings/settings_data_dialogs.dart';
import 'settings/settings_sections.dart';

/// 应用设置主界面
class SettingsScreen extends ConsumerStatefulWidget {
  final SettingsService? settingsService;
  final Future<void> Function(HotkeyAction, HotkeyConfig)? onHotkeyChanged;
  final Future<void> Function()? onHotkeysReset;

  const SettingsScreen({
    super.key,
    this.settingsService,
    this.onHotkeyChanged,
    this.onHotkeysReset,
  });

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  int _selectedCategory = 0;

  static const Map<HotkeyAction, String> _hotkeyActionLabels = {
    HotkeyAction.toggleOverlay: '显示/隐藏悬浮窗',
    HotkeyAction.navigateUp: '向上导航点位',
    HotkeyAction.navigateDown: '向下导航点位',
    HotkeyAction.navigateLeft: '向左导航点位',
    HotkeyAction.navigateRight: '向右导航点位',
    HotkeyAction.prevGrenade: '上一个道具',
    HotkeyAction.nextGrenade: '下一个道具',
    HotkeyAction.prevStep: '上一个步骤',
    HotkeyAction.nextStep: '下一个步骤',
    HotkeyAction.toggleSmoke: '烟雾弹过滤开关',
    HotkeyAction.toggleFlash: '闪光弹过滤开关',
    HotkeyAction.toggleMolotov: '燃烧弹过滤开关',
    HotkeyAction.toggleHE: '手雷过滤开关',
    HotkeyAction.toggleWallbang: '穿点过滤开关',
    HotkeyAction.hideOverlay: '隐藏悬浮窗',
    HotkeyAction.togglePlayPause: '悬浮窗播放/暂停视频',
    HotkeyAction.toggleMediaFullscreenPreview: '媒体全屏预览',
    HotkeyAction.increaseNavSpeed: '增加导航速度',
    HotkeyAction.decreaseNavSpeed: '减少导航速度',
    HotkeyAction.scrollUp: '向上滚动',
    HotkeyAction.scrollDown: '向下滚动',
  };

  late Map<HotkeyAction, HotkeyConfig> _hotkeys;
  late double _overlayOpacity;
  late int _overlaySize;
  late bool _closeToTray;
  late int _overlayNavSpeed;
  late int _mapLineColor;
  late double _mapLineOpacity;
  late double _impactAreaOpacity;
  late int _markerMoveMode;
  late int _grenadeCreateMode;
  late bool _showMapGrenadeList;
  late bool _highDensityClusterMode;
  late bool _mapMarkerUseEmoji;
  late double _joystickOpacity;
  late int _joystickSpeed;
  String _currentDataPath = '';
  String _defaultDataPath = '';

  bool get _isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void didUpdateWidget(SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 切换页面激活时重新加载持久化配置
    _loadSettings();
  }

  void _loadSettings() {
    final service = widget.settingsService;
    if (service != null) {
      service.reload();
      _hotkeys = service.getHotkeys();
      _overlayOpacity = service.getOverlayOpacity();
      _overlaySize = service.getOverlaySize();
      _closeToTray = service.getCloseToTray();
      _overlayNavSpeed = service.getOverlayNavSpeed();
      _mapLineColor = service.getMapLineColor();
      _mapLineOpacity = service.getMapLineOpacity();
      _impactAreaOpacity = service.getImpactAreaOpacity();
      ref.read(impactAreaOpacityProvider.notifier).state = _impactAreaOpacity;
      _markerMoveMode = service.getMarkerMoveMode();
      _grenadeCreateMode = service.getGrenadeCreateMode();
      _showMapGrenadeList = service.getShowMapGrenadeList();
      _highDensityClusterMode = service.getHighDensityClusterMode();
      _mapMarkerUseEmoji = service.getMapMarkerUseEmoji();
      _joystickOpacity = service.getJoystickOpacity();
      _joystickSpeed = service.getJoystickSpeed();
      if (_isDesktop) {
        _loadDataPath();
      }
    } else {
      _hotkeys = {};
      _overlayOpacity = 0.9;
      _overlaySize = 1;
      _closeToTray = true;
      _overlayNavSpeed = 3;
      _mapLineColor = 0xFFE040FB;
      _mapLineOpacity = 0.6;
      _impactAreaOpacity = 0.4;
      _markerMoveMode = 0;
      _grenadeCreateMode = 0;
      _showMapGrenadeList = false;
      _highDensityClusterMode = true;
      _mapMarkerUseEmoji = false;
      _joystickOpacity = 0.8;
      _joystickSpeed = 3;
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadDataPath() async {
    final effectivePath = await widget.settingsService!.getEffectiveDataPath();
    final defaultPath = await SettingsService.getDefaultDataPath();
    if (mounted) {
      setState(() {
        _currentDataPath = effectivePath;
        _defaultDataPath = defaultPath;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('设置'),
      ),
      body: _buildSettingsContent(),
    );
  }

  Widget _buildSettingsContent() {
    if (_isDesktop && widget.settingsService == null) {
      return const Center(child: Text('设置服务未初始化'));
    }
    final themeMode = ref.watch(themeModeProvider);
    final categories = _buildCategories(themeMode);

    if (AppBreakpoints.isMobile(context)) {
      final bottomContentPadding = AppBreakpoints.withMobileBottomBarClearance(
        context,
        const EdgeInsets.all(16),
      );
      return ListView.separated(
        padding: bottomContentPadding,
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final category = categories[index];
          return Card(
            color: Colors.transparent,
            child: ExpansionTile(
              initiallyExpanded: index == 0,
              leading: Icon(
                category.icon,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: Text(
                category.label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              children: _spacedSettingsSections(category.content),
            ),
          );
        },
      );
    }

    final safeIndex = _selectedCategory.clamp(0, categories.length - 1);
    final selected = categories[safeIndex];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 224,
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 14),
                child: Text(
                  '设置分类',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: context.appTheme.mutedText,
                      ),
                ),
              ),
              for (var index = 0; index < categories.length; index++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: ListTile(
                    selected: safeIndex == index,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    leading: Icon(categories[index].icon, size: 21),
                    title: Text(categories[index].label),
                    onTap: () => setState(() => _selectedCategory = index),
                  ),
                ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Text(
                  'Grenade Helper',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: context.appTheme.mutedText),
                ),
              ),
            ],
          ),
        ),
        VerticalDivider(width: 1, color: context.appTheme.subtleBorder),
        Expanded(
          child: AnimatedSwitcher(
            duration: AppMotion.content,
            switchInCurve: AppMotion.enter,
            switchOutCurve: AppMotion.exit,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.025, 0),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: ListView(
              key: ValueKey(safeIndex),
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  selected.label,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 18),
                ..._spacedSettingsSections(selected.content),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<({String label, IconData icon, List<Widget> content})> _buildCategories(
    int themeMode,
  ) {
    return <({String label, IconData icon, List<Widget> content})>[
      (
        label: '外观与地图',
        icon: Icons.palette_outlined,
        content: [
          GeneralAppearanceSection(
            isDesktop: _isDesktop,
            themeMode: themeMode,
            closeToTray: _closeToTray,
            onThemeModeChanged: (value) async {
              ref.read(themeModeProvider.notifier).state = value;
              await widget.settingsService?.setThemeMode(value);
            },
            onCloseToTrayChanged: (value) async {
              setState(() => _closeToTray = value);
              await widget.settingsService!.setCloseToTray(value);
            },
          ),
          MapDisplaySection(
            isDesktop: _isDesktop,
            mapLineColor: _mapLineColor,
            mapLineOpacity: _mapLineOpacity,
            impactAreaOpacity: _impactAreaOpacity,
            mapMarkerUseEmoji: _mapMarkerUseEmoji,
            onMapLineColorChanged: (colorValue) async {
              setState(() => _mapLineColor = colorValue);
              ref.read(mapLineColorProvider.notifier).state = colorValue;
              await widget.settingsService?.setMapLineColor(colorValue);
            },
            onMapLineOpacityChanged: (value) async {
              setState(() => _mapLineOpacity = value);
              ref.read(mapLineOpacityProvider.notifier).state = value;
              await widget.settingsService?.setMapLineOpacity(value);
            },
            onImpactAreaOpacityChanged: (value) async {
              setState(() => _impactAreaOpacity = value);
              ref.read(impactAreaOpacityProvider.notifier).state = value;
              await widget.settingsService?.setImpactAreaOpacity(value);
            },
            onMapMarkerUseEmojiChanged: (value) async {
              setState(() => _mapMarkerUseEmoji = value);
              GrenadeTypeIcon.useLegacy = value;
              sendOverlayCommand('set_legacy_icons', {'value': value});
              await widget.settingsService?.setMapMarkerUseEmoji(value);
            },
          ),
          MarkerOperationSection(
            isDesktop: _isDesktop,
            grenadeCreateMode: _grenadeCreateMode,
            showMapGrenadeList: _showMapGrenadeList,
            highDensityClusterMode: _highDensityClusterMode,
            markerMoveMode: _markerMoveMode,
            joystickOpacity: _joystickOpacity,
            joystickSpeed: _joystickSpeed,
            onGrenadeCreateModeChanged: (value) async {
              setState(() => _grenadeCreateMode = value);
              await widget.settingsService?.setGrenadeCreateMode(value);
            },
            onShowMapGrenadeListChanged: (value) async {
              setState(() => _showMapGrenadeList = value);
              await widget.settingsService?.setShowMapGrenadeList(value);
            },
            onHighDensityClusterModeChanged: (value) async {
              setState(() => _highDensityClusterMode = value);
              await widget.settingsService?.setHighDensityClusterMode(value);
            },
            onMarkerMoveModeChanged: (value) async {
              setState(() => _markerMoveMode = value);
              await widget.settingsService?.setMarkerMoveMode(value);
            },
            onJoystickOpacityChanged: (value) async {
              setState(() => _joystickOpacity = value);
              await widget.settingsService?.setJoystickOpacity(value);
            },
            onJoystickSpeedChanged: (value) async {
              setState(() => _joystickSpeed = value);
              await widget.settingsService?.setJoystickSpeed(value);
            },
          ),
        ],
      ),
      if (_isDesktop)
        (
          label: '快捷键与悬浮窗',
          icon: Icons.keyboard_alt_outlined,
          content: [
            DesktopHotkeySection(
              hotkeys: _hotkeys,
              onEditHotkey: _showHotkeyEditor,
              onResetHotkeys: _resetHotkeysToDefault,
            ),
            DesktopOverlaySection(
              overlayOpacity: _overlayOpacity,
              overlaySize: _overlaySize,
              overlayNavSpeed: _overlayNavSpeed,
              onOverlayOpacityChanged: (value) async {
                setState(() => _overlayOpacity = value);
                await widget.settingsService!.setOverlayOpacity(value);
                sendOverlayCommand('update_opacity', {'opacity': value});
              },
              onOverlaySizeChanged: (newSize) async {
                setState(() => _overlaySize = newSize);
                await widget.settingsService!.setOverlaySize(newSize);
                sendOverlayCommand('update_size', {'sizeIndex': newSize});
              },
              onOverlayNavSpeedChanged: (speedLevel) async {
                setState(() => _overlayNavSpeed = speedLevel);
                await widget.settingsService!.setOverlayNavSpeed(speedLevel);
                sendOverlayCommand('update_nav_speed', {'speed': speedLevel});
              },
            ),
          ],
        ),
      (
        label: '数据管理',
        icon: Icons.storage_outlined,
        content: [
          if (_isDesktop)
            DesktopDataStorageSection(
              currentDataPath: _currentDataPath,
              defaultDataPath: _defaultDataPath,
              onResetToDefaultPath: () =>
                  SettingsDataActions.resetToDefaultPath(
                context: context,
                settingsService: widget.settingsService!,
                currentDataPath: _currentDataPath,
                defaultDataPath: _defaultDataPath,
                onPathUpdated: (path) =>
                    setState(() => _currentDataPath = path),
              ),
              onChangeDataDirectory: () =>
                  SettingsDataActions.changeDataDirectory(
                context: context,
                settingsService: widget.settingsService!,
                currentDataPath: _currentDataPath,
                onPathUpdated: (path) =>
                    setState(() => _currentDataPath = path),
              ),
            ),
          DataManagementSection(
            onInitializeBuiltinAreaMetadata: () =>
                SettingsDataActions.initializeBuiltinAreaMetadataForAllMaps(
              context: context,
              ref: ref,
            ),
            onDeleteMapGrenades: () =>
                SettingsDataActions.showDeleteMapGrenadesDialog(
              context: context,
              ref: ref,
            ),
            onDeleteCustomMaps: () =>
                SettingsDataActions.showDeleteCustomMapsDialog(
              context: context,
              ref: ref,
            ),
            onBatchSelectDelete: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const GrenadeSelectDeleteScreen(),
              ),
            ),
            onCleanupOrphanMediaFiles: () =>
                SettingsDataActions.scanAndCleanupOrphanMediaFiles(
              context: context,
              ref: ref,
            ),
          ),
        ],
      ),
      if (kDebugMode)
        (
          label: '调试',
          icon: Icons.bug_report_outlined,
          content: const [LanSyncDebugSection()],
        ),
    ];
  }

  List<Widget> _spacedSettingsSections(List<Widget> sections) {
    final result = <Widget>[];
    for (var index = 0; index < sections.length; index++) {
      if (index > 0) result.add(const SizedBox(height: 14));
      result.add(sections[index]);
    }
    return result;
  }

  Future<void> _resetHotkeysToDefault() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('恢复默认快捷键？'),
        content: const Text('这将重置所有快捷键为默认配置，确定继续吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.black,
            ),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (confirmed == true && widget.settingsService != null) {
      await widget.settingsService!.resetHotkeys();
      setState(() {
        _hotkeys = widget.settingsService!.getHotkeys();
      });
      await widget.onHotkeysReset?.call();
      _notifyOverlayReloadHotkeys(_hotkeys);
      debugPrint('[Settings] Hotkeys reset, notified overlay to reload');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('快捷键已恢复默认')),
        );
      }
    }
  }

  void _showHotkeyEditor(HotkeyAction action, String label) {
    showDialog(
      context: context,
      builder: (_) => HotkeyEditorDialog(
        action: action,
        label: label,
        currentConfig: _hotkeys[action],
        onSave: (newConfig) async {
          final conflictAction = _findConflictingAction(action, newConfig);
          if (conflictAction != null) {
            final conflictLabel = _hotkeyLabel(conflictAction);
            final conflictConfig = _hotkeys[conflictAction];
            final display = conflictConfig?.toDisplayString() ?? '';
            return display.isNotEmpty
                ? '与“$conflictLabel”（$display）冲突，请更换按键'
                : '与“$conflictLabel”冲突，请更换按键';
          }

          try {
            await widget.settingsService!.saveHotkey(action, newConfig);
            final hotkeys = widget.settingsService!.getHotkeys();

            if (mounted) {
              setState(() => _hotkeys = hotkeys);
            } else {
              _hotkeys = hotkeys;
            }

            if (widget.onHotkeyChanged != null) {
              await widget.onHotkeyChanged!(action, newConfig);
            }

            _notifyOverlayReloadHotkeys(hotkeys);
            debugPrint('[Settings] Hotkey changed, notified overlay to reload');
            return null;
          } on HotkeyConflictException catch (e) {
            return '与“${_hotkeyLabel(e.conflictingAction)}”冲突，请更换按键';
          } catch (e) {
            debugPrint('[Settings] Failed to save hotkey: $e');
            return '保存失败，请重试';
          }
        },
      ),
    );
  }

  void _notifyOverlayReloadHotkeys(Map<HotkeyAction, HotkeyConfig> hotkeys) {
    final hotkeysJson = <String, dynamic>{};
    for (final entry in hotkeys.entries) {
      hotkeysJson[entry.key.name] = entry.value.toJson();
    }
    sendOverlayCommand('reload_hotkeys', {'hotkeys': hotkeysJson});
  }

  HotkeyAction? _findConflictingAction(
    HotkeyAction currentAction,
    HotkeyConfig newConfig,
  ) {
    for (final entry in _hotkeys.entries) {
      if (entry.key == currentAction) continue;
      if (entry.value.conflictsWith(newConfig)) {
        return entry.key;
      }
    }
    return null;
  }

  String _hotkeyLabel(HotkeyAction action) {
    return _hotkeyActionLabels[action] ?? action.name;
  }
}
