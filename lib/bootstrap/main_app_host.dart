import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers.dart';
import '../screens/app_shell.dart';
import '../services/media_handle_service.dart';
import '../services/settings_service.dart';
import '../services/update_service.dart';
import '../theme/app_design_system.dart';
import 'app_globals.dart';

// 主窗口根组件
class MainApp extends ConsumerStatefulWidget {
  const MainApp({super.key});

  @override
  ConsumerState<MainApp> createState() => _MainAppState();
}

class _MainAppState extends ConsumerState<MainApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _initDesktopServices();
    // 延迟检查更新以确保 MaterialApp 已完成挂载
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) _checkForUpdates();
    });
    // 延迟2秒检查赞助提醒以避免与更新弹窗冲突
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) _checkDonationReminder();
    });
    // 延后到首帧后读取全局设置以避开 build 生命周期修改 provider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadGlobalSettings();
      }
    });
  }

  Future<void> _checkDonationReminder() async {
    if (globalSettingsService == null) return;

    final launchCount = await globalSettingsService!.incrementLaunchCount();
    if (launchCount >= 10 && !globalSettingsService!.isDonationDialogShown()) {
      await globalSettingsService!.setDonationDialogShown();
      _showDonationDialog();
    }
  }

  void _showDonationDialog() {
    final navContext = _navigatorKey.currentContext;
    if (navContext == null) return;

    showDialog(
      context: navContext,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.favorite, color: Colors.pink[400]),
            const SizedBox(width: 8),
            const Text('支持我们'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '感谢你使用 Grenade Helper！',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              '如果这个应用对你有帮助，欢迎在爱发电支持我们的开发工作，你的支持是我们持续更新的动力！',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.8),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.purple.withValues(alpha: 0.1),
                    Colors.pink.withValues(alpha: 0.1),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.volunteer_activism,
                      color: Colors.pink[400], size: 24),
                  const SizedBox(width: 8),
                  const Text(
                    '爱发电 · 支持作者',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('下次再说'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              _launchUrl('https://afdian.com/a/Invis1ble');
            },
            icon: const Icon(Icons.favorite, size: 18),
            label: const Text('前往支持'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.pink[400],
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadGlobalSettings() async {
    if (globalSettingsService != null) {
      final savedTheme = globalSettingsService!.getThemeMode();
      ref.read(themeModeProvider.notifier).state = savedTheme;
      ref.read(mapLineColorProvider.notifier).state =
          globalSettingsService!.getMapLineColor();
      ref.read(mapLineOpacityProvider.notifier).state =
          globalSettingsService!.getMapLineOpacity();
    }
  }

  Future<void> _initDesktopServices() async {
    if (!SettingsService.isDesktop) return;

    await globalWindowService?.init();
    globalWindowService?.onShowOverlay = _showOverlay;
    globalWindowService?.onHideOverlay = _hideOverlay;
    globalWindowService?.onExitApp = _onExitApp;

    await globalHotkeyService?.init();
    globalHotkeyService?.registerHandler(
      HotkeyAction.toggleOverlay,
      _toggleOverlay,
    );
  }

  Future<void> _toggleOverlay() async {
    await globalWindowService?.toggleOverlay();
  }

  Future<void> _showOverlay() async {
    try {
      await globalOverlayServer?.showOverlay();
    } catch (e) {
      debugPrint('[Main] Failed to show overlay: $e');
      await globalWindowService?.hideOverlay();
      return;
    }
    if (globalWindowService != null) {
      globalWindowService!.isOverlayVisible = true;
    }
    await globalHotkeyService?.registerOverlayHotkeys();
  }

  void _hideOverlay() {
    globalOverlayServer?.hideOverlay();
  }

  Future<void> _onExitApp() async {
    MediaHandleService.externalReleaser = null;
    await globalOverlayServer?.dispose();
    globalOverlayServer = null;
    globalHotkeyService?.dispose();
  }

  @override
  void dispose() {
    _hideOverlay();
    globalHotkeyService?.dispose();
    globalWindowService?.dispose();
    super.dispose();
  }

  Future<void> _checkForUpdates() async {
    final updateService = UpdateService();
    final updateInfo = await updateService.checkForUpdate();
    if (updateInfo != null && mounted) {
      _showUpdateDialog(updateInfo, updateService.currentPlatform);
    }
  }

  void _showUpdateDialog(UpdateInfo updateInfo, String platform) {
    final navContext = _navigatorKey.currentContext;
    if (navContext == null) return;

    showDialog(
      context: navContext,
      barrierDismissible: !updateInfo.forceUpdate,
      builder: (context) => PopScope(
        canPop: !updateInfo.forceUpdate,
        child: AlertDialog(
          title: Row(
            children: [
              Icon(Icons.system_update,
                  color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              const Text('发现新版本'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '新版本: ${updateInfo.versionName}',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 12),
              const Text('更新内容:',
                  style: TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  updateInfo.content.isEmpty ? '优化和修复' : updateInfo.content,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              const SizedBox(height: 16),
              const Text('请选择下载方式:',
                  style: TextStyle(fontSize: 13, color: Colors.grey)),
            ],
          ),
          actions: [
            if (!updateInfo.forceUpdate)
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('稍后提醒'),
              ),
            PopupMenuButton<String>(
              onSelected: _launchUrl,
              itemBuilder: (context) => DownloadLinks.panLinks.entries
                  .map((e) => PopupMenuItem(
                        value: e.value,
                        child: Text(e.key),
                      ))
                  .toList(),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey[800],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_download, size: 18),
                    SizedBox(width: 4),
                    Text('网盘下载'),
                    Icon(Icons.arrow_drop_down, size: 18),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 4),
            ElevatedButton.icon(
              onPressed: () {
                _launchUrl(DownloadLinks.getOfficialUrl(platform));
              },
              icon: const Icon(Icons.download, size: 18),
              label: const Text('官方下载'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);

    return ExcludeSemantics(
      excluding: !kIsWeb && Platform.isWindows,
      child: MaterialApp(
        navigatorKey: _navigatorKey,
        title: 'Grenade Helper',
        debugShowCheckedModeBanner: false,
        themeMode: intToThemeMode(themeMode),
        darkTheme: AppTheme.dark(),
        theme: AppTheme.light(),
        home: AppShell(
          settingsService: globalSettingsService,
          onHotkeyChanged: (action, config) async {
            await globalHotkeyService?.updateHotkey(action, config);
          },
          onHotkeysReset: () async {
            await globalHotkeyService?.reloadFromSettings();
          },
        ),
      ),
    );
  }
}
