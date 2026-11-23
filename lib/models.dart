import 'package:isar_community/isar.dart';

part 'models.g.dart';

abstract final class GrenadeType {
  static const int smoke = 0;
  static const int flash = 1;
  static const int molotov = 2;
  static const int he = 3;
  static const int wallbang = 4;
}

abstract final class TeamType {
  static const int all = 0;
  static const int ct = 1;
  static const int t = 2;
  static const int onlyAll = 3;
}

abstract final class MediaType {
  static const int image = 0;
  static const int video = 1;
}

@collection
class GameMap {
  Id id = Isar.autoIncrement;

  String name;
  String backgroundPath;
  String iconPath;

  final layers = IsarLinks<MapLayer>();

  GameMap({
    required this.name,
    this.backgroundPath = "",
    this.iconPath = "",
  });
}

@collection
class MapLayer {
  Id id = Isar.autoIncrement;

  String name;
  String assetPath;
  int sortOrder;

  @Backlink(to: 'layers')
  final map = IsarLink<GameMap>();

  final grenades = IsarLinks<Grenade>();

  MapLayer({
    required this.name,
    required this.assetPath,
    required this.sortOrder,
  });
}

@collection
class Grenade {
  Id id = Isar.autoIncrement;

  String title;
  int type;
  int team;
  bool isFavorite;
  @Index()
  int? favoriteFolderId;
  bool isNewImport;
  DateTime createdAt;
  DateTime updatedAt;

  double xRatio;
  double yRatio;

  String? author;
  bool hasLocalEdits;
  bool isImported;

  /// 跨设备同步与去重用的唯一标识
  @Index()
  String? uniqueId;

  String? sourceUrl;
  String? sourceNote;

  /// 爆点名称或位置描述
  String? description;

  double? impactXRatio;
  double? impactYRatio;
  String? impactAreaStrokes;

  /// 同一爆点下的自定义分组 ID
  int? impactGroupId;

  @Backlink(to: 'grenades')
  final layer = IsarLink<MapLayer>();

  final steps = IsarLinks<GrenadeStep>();

  Grenade({
    required this.title,
    required this.type,
    this.team = 0,
    this.isFavorite = false,
    this.favoriteFolderId,
    this.isNewImport = false,
    this.hasLocalEdits = false,
    this.isImported = false,
    required this.xRatio,
    required this.yRatio,
    this.uniqueId,
    DateTime? created,
    DateTime? updated,
  })  : createdAt = created ?? DateTime.now(),
        updatedAt = updated ?? DateTime.now();
}

@collection
class GrenadeStep {
  Id id = Isar.autoIncrement;

  String title;
  String description;
  int stepIndex;

  @Backlink(to: 'steps')
  final grenade = IsarLink<Grenade>();

  final medias = IsarLinks<StepMedia>();

  GrenadeStep({
    this.title = "",
    required this.description,
    required this.stepIndex,
  });
}

@collection
class StepMedia {
  Id id = Isar.autoIncrement;

  String localPath;
  int type;
  int sortOrder;

  @Backlink(to: 'medias')
  final step = IsarLink<GrenadeStep>();

  StepMedia({
    required this.localPath,
    required this.type,
    this.sortOrder = 0,
  });
}

@collection
class ImportHistory {
  Id id = Isar.autoIncrement;

  String fileName;
  DateTime importedAt;
  int newCount;
  int updatedCount;
  int skippedCount;

  final grenades = IsarLinks<Grenade>();

  ImportHistory({
    required this.fileName,
    required this.importedAt,
    this.newCount = 0,
    this.updatedCount = 0,
    this.skippedCount = 0,
  });
}

/// 同一爆点下投掷点的自定义分组
@collection
class ImpactGroup {
  Id id = Isar.autoIncrement;

  @Index()
  String name;

  int type;
  double impactXRatio;
  double impactYRatio;

  @Index()
  int layerId;

  DateTime createdAt;
  DateTime updatedAt;

  ImpactGroup({
    required this.name,
    required this.type,
    required this.impactXRatio,
    required this.impactYRatio,
    required this.layerId,
    DateTime? created,
    DateTime? updated,
  })  : createdAt = created ?? DateTime.now(),
        updatedAt = updated ?? (created ?? DateTime.now());
}

@collection
class FavoriteFolder {
  Id id = Isar.autoIncrement;

  @Index()
  int mapId;

  String name;

  /// 地图维度下用于唯一校验的规范化名称
  @Index()
  String nameKey;

  int sortOrder;
  DateTime createdAt;
  DateTime updatedAt;

  FavoriteFolder({
    required this.mapId,
    required this.name,
    required this.nameKey,
    this.sortOrder = 0,
    DateTime? created,
    DateTime? updated,
  })  : createdAt = created ?? DateTime.now(),
        updatedAt = updated ?? DateTime.now();
}
