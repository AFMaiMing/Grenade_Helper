import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../../spawn_point_data.dart';
import '../../widgets/app_svg_icon.dart';
import 'map_providers.dart';

void showSpawnPointBottomSheet({
  required BuildContext context,
  required WidgetRef ref,
  required SpawnPoint spawn,
  required bool isCT,
  required int layerId,
  required void Function(Offset ratioPosition, int layerId) onCreateAtSpawn,
  bool isCasual = false,
}) {
  final color = isCT ? Colors.blueAccent : Colors.amber;
  final teamName = isCT ? "CT" : "T";
  final label = isCasual ? 'C${spawn.id}' : '${spawn.id}';
  final title = isCasual ? "$teamName 休闲出生点 $label" : "$teamName 出生点 #$label";
  final isEditMode = ref.read(isEditModeProvider);

  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF1E2126),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                constraints: const BoxConstraints(minWidth: 32),
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Center(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: label.length >= 3 ? 12 : 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            "坐标: (${spawn.x.toStringAsFixed(3)}, ${spawn.y.toStringAsFixed(3)})",
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 20),
          if (isEditMode)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  onCreateAtSpawn(Offset(spawn.x, spawn.y), layerId);
                },
                icon: const Icon(Icons.add, size: 20),
                label: const Text("在此位置创建道具"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AppSvgIcon(
                    asset: 'assets/icons/ui_hint.svg',
                    size: 17,
                    color: Colors.grey,
                    semanticsLabel: '提示',
                  ),
                  SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '开启编辑模式可在此位置创建道具',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
        ],
      ),
    ),
  );
}

class DesktopSpawnPointCard extends ConsumerWidget {
  final MapSpawnConfig config;
  final int layerId;
  final bool showCasual;
  final double maxHeight;
  final bool isExpanded;
  final String selectedTab;
  final ValueNotifier<String?> hoveredSpawnKey;
  final ValueChanged<bool> onExpandedChanged;
  final ValueChanged<String> onTabChanged;
  final void Function(SpawnPoint spawn, bool isCT, bool isCasual) onSelectSpawn;

  const DesktopSpawnPointCard({
    super.key,
    required this.config,
    required this.layerId,
    required this.showCasual,
    required this.maxHeight,
    required this.isExpanded,
    required this.selectedTab,
    required this.hoveredSpawnKey,
    required this.onExpandedChanged,
    required this.onTabChanged,
    required this.onSelectSpawn,
  });

  Widget _buildDesktopSpawnChip({
    required String label,
    required String tooltip,
    required bool enabled,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: enabled
                  ? activeColor.withValues(alpha: 0.24)
                  : Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: enabled
                    ? activeColor.withValues(alpha: 0.8)
                    : Colors.white.withValues(alpha: 0.14),
                width: 1,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: enabled ? activeColor : Colors.white54,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopSpawnGrid(List<Widget> cells) {
    final rows = <Widget>[];
    for (var i = 0; i < cells.length; i += 3) {
      final rowChildren = <Widget>[];
      for (var c = 0; c < 3; c++) {
        if (c > 0) rowChildren.add(const SizedBox(width: 4));
        rowChildren.add(
          Expanded(
            child:
                i + c < cells.length ? cells[i + c] : const SizedBox.shrink(),
          ),
        );
      }
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 4));
      rows.add(Row(children: rowChildren));
    }
    return Column(mainAxisSize: MainAxisSize.min, children: rows);
  }

  Widget _buildDesktopSpawnCell({
    required String pointKey,
    required String label,
    required Color color,
    required bool outlined,
    required VoidCallback onTap,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => hoveredSpawnKey.value = pointKey,
      onExit: (_) {
        if (hoveredSpawnKey.value == pointKey) {
          hoveredSpawnKey.value = null;
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          hoveredSpawnKey.value = null;
          onTap();
        },
        child: Container(
          height: 24,
          decoration: BoxDecoration(
            color:
                outlined ? Colors.transparent : color.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(6),
            border: outlined
                ? Border.all(color: color.withValues(alpha: 0.72), width: 1)
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: label.length >= 3 ? 10 : 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabBody(String activeTab) {
    if (activeTab == 'CT') {
      final mainCells = config.ctSpawns
          .map((s) => _buildDesktopSpawnCell(
                pointKey: 'ct-${s.id}',
                label: '${s.id}',
                color: Colors.blueAccent,
                outlined: false,
                onTap: () => onSelectSpawn(s, true, false),
              ))
          .toList();
      final casualCells = (showCasual && config.hasCasualSpawns)
          ? config.casualCtSpawns
              .map((s) => _buildDesktopSpawnCell(
                    pointKey: 'cct-${s.id}',
                    label: 'C${s.id}',
                    color: Colors.blueAccent,
                    outlined: true,
                    onTap: () => onSelectSpawn(s, true, true),
                  ))
              .toList()
          : const <Widget>[];
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildDesktopSpawnGrid(mainCells),
          if (casualCells.isNotEmpty) ...[
            Container(
              height: 1,
              margin: const EdgeInsets.symmetric(vertical: 6),
              color: Colors.white.withValues(alpha: 0.1),
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Text(
                'CT 休闲',
                style: TextStyle(
                  color: Colors.cyanAccent,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            _buildDesktopSpawnGrid(casualCells),
          ],
        ],
      );
    }

    final mainCells = config.tSpawns
        .map((s) => _buildDesktopSpawnCell(
              pointKey: 't-${s.id}',
              label: '${s.id}',
              color: Colors.amber,
              outlined: false,
              onTap: () => onSelectSpawn(s, false, false),
            ))
        .toList();
    final casualCells = (showCasual && config.hasCasualSpawns)
        ? config.casualTSpawns
            .map((s) => _buildDesktopSpawnCell(
                  pointKey: 'ct_c-${s.id}',
                  label: 'C${s.id}',
                  color: Colors.amber,
                  outlined: true,
                  onTap: () => onSelectSpawn(s, false, true),
                ))
            .toList()
        : const <Widget>[];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildDesktopSpawnGrid(mainCells),
        if (casualCells.isNotEmpty) ...[
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(vertical: 6),
            color: Colors.white.withValues(alpha: 0.1),
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Text(
              'T 休闲',
              style: TextStyle(
                color: Colors.orangeAccent,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          _buildDesktopSpawnGrid(casualCells),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const tabs = <({String id, String label, Color color})>[
      (id: 'CT', label: 'CT', color: Colors.blueAccent),
      (id: 'T', label: 'T', color: Colors.amber),
    ];
    final activeTab = selectedTab == 'CT' ? 'CT' : 'T';

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xD612151B),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: !isExpanded
              ? GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onExpandedChanged(true),
                  child: const MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.chevron_left_rounded,
                              color: Color(0xFFFF1744), size: 16),
                          SizedBox(height: 2),
                          Text(
                            '出\n生\n点',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFFFF1744),
                              fontSize: 10,
                              height: 1.25,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 21),
                      child: SizedBox(
                        width: 148,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(8, 7, 8, 6),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.my_location_rounded,
                                    color: Color(0xFFFF1744),
                                    size: 13,
                                  ),
                                  const SizedBox(width: 4),
                                  const Expanded(
                                    child: Text(
                                      '出生点',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  if (config.hasCasualSpawns)
                                    _buildDesktopSpawnChip(
                                      label: '休',
                                      tooltip:
                                          showCasual ? '隐藏休闲出生点' : '显示休闲出生点',
                                      enabled: showCasual,
                                      activeColor: Colors.cyanAccent,
                                      onTap: () => ref
                                          .read(showCasualSpawnPointsProvider
                                              .notifier)
                                          .state = !showCasual,
                                    ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: tabs.map((t) {
                                    final isActive = activeTab == t.id;
                                    return Expanded(
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () => onTabChanged(t.id),
                                        child: MouseRegion(
                                          cursor: SystemMouseCursors.click,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 4),
                                            decoration: BoxDecoration(
                                              color: isActive
                                                  ? Colors.white
                                                      .withValues(alpha: 0.16)
                                                  : Colors.transparent,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            alignment: Alignment.center,
                                            child: Text(
                                              t.label,
                                              style: TextStyle(
                                                color: isActive
                                                    ? t.color
                                                    : Colors.white54,
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                            Container(
                              height: 1,
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                            Flexible(
                              fit: FlexFit.loose,
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.all(8),
                                child: _buildTabBody(activeTab),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: 20,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          hoveredSpawnKey.value = null;
                          onExpandedChanged(false);
                        },
                        child: const MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: Center(
                            child: Icon(
                              Icons.chevron_right_rounded,
                              color: Color(0xFFFF1744),
                              size: 17,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 20,
                      top: 0,
                      bottom: 0,
                      width: 1,
                      child: ColoredBox(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class MobileSpawnPointSidebar extends ConsumerWidget {
  final MapSpawnConfig config;
  final int layerId;
  final bool isEditMode;
  final bool showCasual;
  final bool isExpanded;
  final ValueChanged<bool> onExpandedChanged;
  final void Function(SpawnPoint spawn, bool isCT, bool isCasual) onSelectSpawn;

  const MobileSpawnPointSidebar({
    super.key,
    required this.config,
    required this.layerId,
    required this.isEditMode,
    required this.showCasual,
    required this.isExpanded,
    required this.onExpandedChanged,
    required this.onSelectSpawn,
  });

  Widget _buildSpawnSidebarToggle({
    required IconData icon,
    required String label,
    required bool enabled,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: enabled
                ? activeColor.withValues(alpha: 0.22)
                : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: enabled
                  ? activeColor.withValues(alpha: 0.8)
                  : Colors.white.withValues(alpha: 0.12),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 12,
                color: enabled ? activeColor : Colors.white54,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: enabled ? activeColor : Colors.white60,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSpawnListItem(
    SpawnPoint spawn,
    bool isCT, {
    bool isCasual = false,
  }) {
    final color = isCT ? Colors.blueAccent : Colors.amber;
    final label = isCasual ? 'C${spawn.id}' : '${spawn.id}';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onSelectSpawn(spawn, isCT, isCasual),
      child: Container(
        width: isCasual ? 40 : 34,
        height: 24,
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: isCasual ? Colors.transparent : color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(7),
          border: isCasual
              ? Border.all(color: color.withValues(alpha: 0.75), width: 1)
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: label.length >= 3 ? 10 : 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.56),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onExpandedChanged(!isExpanded),
                child: SizedBox(
                  width: 24,
                  child: Center(
                    child: Icon(
                      isExpanded
                          ? Icons.chevron_right_rounded
                          : Icons.chevron_left_rounded,
                      color: const Color(0xFFFF1744),
                      size: 18,
                    ),
                  ),
                ),
              ),
              if (isExpanded) ...[
                Container(
                  width: 1,
                  color: Colors.white.withValues(alpha: 0.1),
                ),
                SizedBox(
                  width: 76,
                  child: Column(
                    children: [
                      const Padding(
                        padding:
                            EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.my_location_rounded,
                              color: Color(0xFFFF1744),
                              size: 13,
                            ),
                            SizedBox(width: 4),
                            Text(
                              '出生点',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (config.hasCasualSpawns) ...[
                        Container(
                          height: 1,
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
                          child: _buildSpawnSidebarToggle(
                            icon: Icons.groups_rounded,
                            label: '休闲',
                            enabled: showCasual,
                            activeColor: Colors.cyanAccent,
                            onTap: () => ref
                                .read(showCasualSpawnPointsProvider.notifier)
                                .state = !showCasual,
                          ),
                        ),
                      ],
                      Container(
                        height: 1,
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 6),
                          child: Column(
                            children: [
                              const Text(
                                "CT",
                                style: TextStyle(
                                  color: Colors.blueAccent,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              ...config.ctSpawns.map(
                                (spawn) => _buildSpawnListItem(spawn, true),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                "T",
                                style: TextStyle(
                                  color: Colors.amber,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              ...config.tSpawns.map(
                                (spawn) => _buildSpawnListItem(spawn, false),
                              ),
                              if (showCasual && config.hasCasualSpawns) ...[
                                const SizedBox(height: 8),
                                if (config.casualCtSpawns.isNotEmpty) ...[
                                  const Text(
                                    "CT 休闲",
                                    style: TextStyle(
                                      color: Colors.cyanAccent,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  ...config.casualCtSpawns.map(
                                    (spawn) => _buildSpawnListItem(
                                      spawn,
                                      true,
                                      isCasual: true,
                                    ),
                                  ),
                                ],
                                if (config.casualTSpawns.isNotEmpty) ...[
                                  if (config.casualCtSpawns.isNotEmpty)
                                    const SizedBox(height: 8),
                                  const Text(
                                    "T 休闲",
                                    style: TextStyle(
                                      color: Colors.orangeAccent,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  ...config.casualTSpawns.map(
                                    (spawn) => _buildSpawnListItem(
                                      spawn,
                                      false,
                                      isCasual: true,
                                    ),
                                  ),
                                ],
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
