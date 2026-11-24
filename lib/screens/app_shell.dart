import 'package:flutter/material.dart';

import '../services/settings_service.dart';
import '../theme/app_design_system.dart';
import 'about_screen.dart';
import 'data_transfer_hub_screen.dart';
import 'home_screen.dart';
import 'settings_screen.dart';
import 'shell/desktop_navigation_rail.dart';
import 'shell/liquid_glass_navigation_bar.dart';
import 'shell/shell_panning_background.dart';

// 应用主导航壳（支持桌面侧边栏与移动端底部液态玻璃栏）
class AppShell extends StatefulWidget {
  final SettingsService? settingsService;
  final Future<void> Function(HotkeyAction, HotkeyConfig)? onHotkeyChanged;
  final Future<void> Function()? onHotkeysReset;

  const AppShell({
    super.key,
    this.settingsService,
    this.onHotkeyChanged,
    this.onHotkeysReset,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  List<Widget> get _pages => [
        const HomeScreen(embedded: true),
        const DataTransferHubScreen(),
        SettingsScreen(
          settingsService: widget.settingsService,
          onHotkeyChanged: widget.onHotkeyChanged,
          onHotkeysReset: widget.onHotkeysReset,
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final mobile = AppBreakpoints.isMobile(context);
    final expanded = AppBreakpoints.isExpandedNavigation(context);
    final content = IndexedStack(index: _index, children: _pages);

    if (mobile) {
      return Scaffold(
        extendBody: true,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const Positioned.fill(
              child: ShellPanningBackground(),
            ),
            content,
          ],
        ),
        bottomNavigationBar: LiquidGlassNavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (value) => setState(() => _index = value),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned.fill(
            child: ShellPanningBackground(),
          ),
          Row(
            children: [
              DesktopNavigationRail(
                selectedIndex: _index,
                expanded: expanded,
                onDestinationSelected: (value) =>
                    setState(() => _index = value),
                onOpenAbout: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AboutScreen()),
                ),
              ),
              VerticalDivider(width: 1, color: context.appTheme.subtleBorder),
              Expanded(child: content),
            ],
          ),
        ],
      ),
    );
  }
}
