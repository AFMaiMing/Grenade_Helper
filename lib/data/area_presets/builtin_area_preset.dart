/// 内置地图区域预设模型，描述单个区域的名称、颜色及各楼层描边数据。
class BuiltinAreaPreset {
  final String name;
  final int colorValue;
  final String? floorKey;
  final String? strokesJson;
  final String? floorStrokesJson;

  const BuiltinAreaPreset({
    required this.name,
    required this.colorValue,
    this.floorKey,
    this.strokesJson,
    this.floorStrokesJson,
  });
}
