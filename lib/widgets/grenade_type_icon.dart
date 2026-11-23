import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models.dart';

/// 统一的道具类型图标，避免不同页面使用不同图标表现。
class GrenadeTypeIcon extends StatelessWidget {
  final int type;
  final double size;
  final Color? color;

  const GrenadeTypeIcon({
    super.key,
    required this.type,
    this.size = 22,
    this.color,
  });

  // 由设置“使用旧版图标”控制，启动及切换时同步。
  static bool useLegacy = false;

  static IconData legacyIconForType(int type) => switch (type) {
        GrenadeType.smoke => Icons.cloud,
        GrenadeType.flash => Icons.flash_on,
        GrenadeType.molotov => Icons.local_fire_department,
        GrenadeType.he => Icons.trip_origin,
        GrenadeType.wallbang => Icons.apps,
        _ => Icons.circle,
      };

  static String assetForType(int type) => switch (type) {
        GrenadeType.smoke => 'assets/icons/grenade_smoke.svg',
        GrenadeType.flash => 'assets/icons/grenade_flash.svg',
        GrenadeType.molotov => 'assets/icons/grenade_molotov.svg',
        GrenadeType.he => 'assets/icons/grenade_he.svg',
        GrenadeType.wallbang => 'assets/icons/grenade_wallbang.svg',
        _ => 'assets/icons/grenade_unknown.svg',
      };

  String get _label => switch (type) {
        GrenadeType.smoke => '烟雾弹',
        GrenadeType.flash => '闪光弹',
        GrenadeType.molotov => '燃烧弹',
        GrenadeType.he => '手雷',
        GrenadeType.wallbang => '穿点',
        _ => '未知道具',
      };

  Color _defaultColor(BuildContext context) => switch (type) {
        GrenadeType.smoke => Colors.blueGrey,
        GrenadeType.flash => Colors.amber.shade700,
        GrenadeType.molotov => Colors.deepOrange,
        GrenadeType.he => Colors.redAccent,
        GrenadeType.wallbang => Theme.of(context).colorScheme.primary,
        _ => Colors.grey,
      };

  @override
  Widget build(BuildContext context) {
    final resolvedColor = color ?? _defaultColor(context);
    if (useLegacy) {
      return Icon(
        legacyIconForType(type),
        size: size,
        color: resolvedColor,
        semanticLabel: _label,
      );
    }
    // 使用紧致 Center 确保父级为固定尺寸无对齐容器时仍保持图标尺寸并居中。
    return Center(
      widthFactor: 1,
      heightFactor: 1,
      child: SvgPicture.asset(
        assetForType(type),
        width: size,
        height: size,
        colorFilter: ColorFilter.mode(resolvedColor, BlendMode.srcIn),
        semanticsLabel: _label,
      ),
    );
  }
}

/// 用于“全部 + 道具类型”筛选器的统一 SVG 图标。
class GrenadeFilterIcon extends StatelessWidget {
  final int? type;
  final double size;
  final Color? color;

  const GrenadeFilterIcon({
    super.key,
    required this.type,
    this.size = 18,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    if (type != null) {
      return GrenadeTypeIcon(type: type!, size: size, color: color);
    }
    return SvgPicture.asset(
      'assets/icons/grenade_all.svg',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(
        color ?? IconTheme.of(context).color ?? Colors.grey,
        BlendMode.srcIn,
      ),
      semanticsLabel: '全部道具类型',
    );
  }
}
