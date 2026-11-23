import 'package:isar_community/isar.dart';

part 'tag.g.dart';

abstract final class TagDimension {
  static const int role = 0;
  static const int area = 1;
  static const int phase = 2;
  static const int spawn = 3;
  static const int purpose = 4;
  static const int custom = 99;

  /// 用户自定义的维度名称覆盖表
  static final Map<int, String> _customNames = {};

  static String _defaultName(int dimension) => switch (dimension) {
        role => '角色',
        area => '区域',
        phase => '阶段',
        spawn => '身位',
        purpose => '目的',
        custom => '自定义',
        _ => '未知',
      };

  static String getName(int dimension) =>
      _customNames[dimension] ?? _defaultName(dimension);

  static void setName(int dimension, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      _customNames.remove(dimension);
    } else {
      _customNames[dimension] = trimmed;
    }
  }

  static void loadFromMap(Map<int, String> names) {
    _customNames
      ..clear()
      ..addAll(names);
  }

  static Map<int, String> getCustomNames() =>
      Map<int, String>.from(_customNames);
}

@collection
class Tag {
  Id id = Isar.autoIncrement;

  @Index()
  String tagUuid;

  @Index()
  String name;

  int colorValue;
  int dimension;

  /// 覆盖默认分组名的可选自定义名称
  String? groupName;

  @Index()
  bool isSystem;

  int sortOrder;

  @Index()
  int mapId;

  DateTime updatedAt;

  Tag({
    this.tagUuid = '',
    required this.name,
    required this.colorValue,
    required this.dimension,
    this.groupName,
    this.isSystem = false,
    this.sortOrder = 0,
    required this.mapId,
    DateTime? updated,
  }) : updatedAt = updated ?? DateTime.now();
}
