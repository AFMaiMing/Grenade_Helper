import 'package:isar_community/isar.dart';

part 'map_area.g.dart';

@collection
class MapArea {
  Id id = Isar.autoIncrement;

  @Index()
  String name;

  int colorValue;

  /// 手绘区域笔画的 JSON 字符串
  String strokes;

  @Index()
  int mapId;

  /// 关联的楼层 ID，null 表示适用所有楼层
  int? layerId;

  int tagId;

  DateTime createdAt;
  DateTime updatedAt;

  MapArea({
    required this.name,
    required this.colorValue,
    required this.strokes,
    required this.mapId,
    this.layerId,
    required this.tagId,
    required this.createdAt,
    DateTime? updated,
  }) : updatedAt = updated ?? createdAt;
}
