import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// 地图图标渲染组件，兼容 SVG/位图及内置资源/本地文件。
class MapIcon extends StatelessWidget {
  final String path;
  final double size;
  final Color fallbackColor;

  const MapIcon({
    super.key,
    required this.path,
    this.size = 20,
    this.fallbackColor = Colors.orange,
  });

  Widget _buildFallbackIcon() =>
      Icon(Icons.map_outlined, size: size, color: fallbackColor);

  @override
  Widget build(BuildContext context) {
    final normalized = path.trim();
    if (normalized.isEmpty) {
      return _buildFallbackIcon();
    }

    final isSvg = normalized.toLowerCase().endsWith('.svg');
    final isAsset = normalized.startsWith('assets/');

    if (isAsset) {
      if (isSvg) {
        return SvgPicture.asset(
          normalized,
          width: size,
          height: size,
          placeholderBuilder: (_) => _buildFallbackIcon(),
        );
      }
      return Image.asset(
        normalized,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _buildFallbackIcon(),
      );
    }

    final file = File(normalized);
    if (!file.existsSync()) {
      return _buildFallbackIcon();
    }

    if (isSvg) {
      return SvgPicture.file(
        file,
        width: size,
        height: size,
        placeholderBuilder: (_) => _buildFallbackIcon(),
      );
    }
    return Image.file(
      file,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => _buildFallbackIcon(),
    );
  }
}
