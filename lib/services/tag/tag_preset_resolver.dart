import '../../models.dart';

final RegExp _mapIconKeyRegex = RegExp(
  r'assets[\\/]+icons[\\/]+(.+?)_icon\.svg$',
  caseSensitive: false,
);

/// 按地图名与图标路径提取稳定 key 解析预设表。
T? resolveMapPreset<T>(GameMap map, Map<String, T> presets) {
  final lowerName = map.name.trim().toLowerCase();
  if (presets.containsKey(lowerName)) {
    return presets[lowerName];
  }

  final iconMatch = _mapIconKeyRegex.firstMatch(map.iconPath);
  if (iconMatch != null && iconMatch.groupCount >= 1) {
    final key = iconMatch.group(1)?.toLowerCase();
    if (key != null && presets.containsKey(key)) {
      return presets[key];
    }
  }

  final normalized = lowerName.replaceAll(RegExp(r'[^a-z0-9]+'), '');
  return presets[normalized];
}

String normalizeTagUuid(String value) => value.trim().toLowerCase();

String buildSystemTagKey(int dimension, String name) =>
    '$dimension|${name.trim().toLowerCase()}';

String extractPathFileName(String path) {
  final normalized = path.replaceAll('\\', '/');
  final parts = normalized.split('/');
  return parts.isEmpty ? path : parts.last;
}

String stripFileExtension(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot <= 0) return fileName;
  return fileName.substring(0, dot);
}
