import 'package:flutter/material.dart';

import '../../models.dart';
import '../../theme/app_design_system.dart';
import '../../widgets/grenade_type_icon.dart';

/// 获取道具类型显示名称。
String grenadeTypeLabel(int type) => switch (type) {
      GrenadeType.smoke => '烟雾弹',
      GrenadeType.flash => '闪光弹',
      GrenadeType.molotov => '燃烧弹',
      GrenadeType.he => '高爆手雷',
      GrenadeType.wallbang => '穿点',
      _ => '道具',
    };

/// 获取阵营显示名称。
String grenadeTeamLabel(int team) => switch (team) {
      TeamType.ct => 'CT',
      TeamType.t => 'T',
      _ => '通用',
    };

/// 道具类型下拉菜单项标签。
class GrenadeTypeMenuLabel extends StatelessWidget {
  final int type;
  final String label;

  const GrenadeTypeMenuLabel({
    super.key,
    required this.type,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GrenadeTypeIcon(type: type, size: 18),
        const SizedBox(width: 8),
        Text(label),
      ],
    );
  }
}

/// 详情页顶部通用信息徽章。
class DetailBadge extends StatelessWidget {
  final String label;
  final IconData? icon;

  const DetailBadge({
    super.key,
    required this.label,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: context.appTheme.subtleBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: context.appTheme.mutedText),
            const SizedBox(width: 5),
          ],
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

/// 道具类型信息徽章。
class GrenadeTypeBadge extends StatelessWidget {
  final int type;
  final String label;

  const GrenadeTypeBadge({
    super.key,
    required this.type,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: context.appTheme.subtleBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GrenadeTypeIcon(type: type, size: 16),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

/// 详情页顶部属性栏，编辑态仅展示道具类型与步骤数。
class GrenadeDetailHeader extends StatelessWidget {
  final bool isEditing;
  final int grenadeType;
  final int grenadeTeam;
  final int stepCount;
  final ValueChanged<int?> onTypeChanged;

  const GrenadeDetailHeader({
    super.key,
    required this.isEditing,
    required this.grenadeType,
    required this.grenadeTeam,
    required this.stepCount,
    required this.onTypeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: context.appTheme.subtleBorder),
        ),
      ),
      child: Row(
        children: [
          if (isEditing)
            Expanded(
              child: Wrap(
                spacing: 14,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  DropdownButton<int>(
                    value: grenadeType,
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(
                        value: GrenadeType.smoke,
                        child: GrenadeTypeMenuLabel(
                          type: GrenadeType.smoke,
                          label: '烟雾',
                        ),
                      ),
                      DropdownMenuItem(
                        value: GrenadeType.flash,
                        child: GrenadeTypeMenuLabel(
                          type: GrenadeType.flash,
                          label: '闪光',
                        ),
                      ),
                      DropdownMenuItem(
                        value: GrenadeType.molotov,
                        child: GrenadeTypeMenuLabel(
                          type: GrenadeType.molotov,
                          label: '燃烧',
                        ),
                      ),
                      DropdownMenuItem(
                        value: GrenadeType.he,
                        child: GrenadeTypeMenuLabel(
                          type: GrenadeType.he,
                          label: '手雷',
                        ),
                      ),
                      DropdownMenuItem(
                        value: GrenadeType.wallbang,
                        child: GrenadeTypeMenuLabel(
                          type: GrenadeType.wallbang,
                          label: '穿点',
                        ),
                      ),
                    ],
                    onChanged: onTypeChanged,
                  ),
                  Text(
                    '$stepCount 个步骤',
                    style: TextStyle(color: context.appTheme.mutedText),
                  ),
                ],
              ),
            )
          else
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  GrenadeTypeBadge(
                    type: grenadeType,
                    label: grenadeTypeLabel(grenadeType),
                  ),
                  DetailBadge(
                    label: grenadeTeamLabel(grenadeTeam),
                    icon: Icons.groups_outlined,
                  ),
                  DetailBadge(
                    label: '$stepCount 个步骤',
                    icon: Icons.format_list_numbered_rounded,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
