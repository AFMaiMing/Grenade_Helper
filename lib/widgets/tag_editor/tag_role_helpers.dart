import '../../models.dart';
import '../../models/tag.dart';

const List<int> _tagDimensionDisplayOrder = <int>[
  TagDimension.role,
  TagDimension.phase,
  TagDimension.spawn,
  TagDimension.purpose,
  TagDimension.area,
  TagDimension.custom,
];

int _tagDimensionRank(int dimension) {
  final index = _tagDimensionDisplayOrder.indexOf(dimension);
  return index >= 0 ? index : _tagDimensionDisplayOrder.length + dimension;
}

/// 将阵营标签映射为对应的 [TeamType] 值；非阵营或未识别标签返回 null。
int? roleTagToTeamType(Tag tag) {
  if (tag.dimension != TagDimension.role) return null;
  switch (tag.name.trim().toUpperCase()) {
    case '通用':
      return TeamType.all;
    case 'CT方':
    case 'CT':
      return TeamType.ct;
    case 'T方':
    case 'T':
      return TeamType.t;
    default:
      return null;
  }
}

/// 将阵营值规范化为有效值，非 CT/T 均回退为通用阵营。
int normalizeRoleTeam(int? team) {
  return (team == TeamType.ct || team == TeamType.t) ? team! : TeamType.all;
}

int _roleTagDisplayPriority(Tag tag) {
  return switch (roleTagToTeamType(tag)) {
    TeamType.all => 0,
    TeamType.ct => 1,
    TeamType.t => 2,
    _ => 3,
  };
}

/// 在阵营标签列表中查找匹配目标阵营的标签。
Tag? findRoleTagByTeam(List<Tag> roleTags, int team) {
  final normalizedTeam = normalizeRoleTeam(team);
  for (final tag in roleTags) {
    if (roleTagToTeamType(tag) == normalizedTeam) return tag;
  }
  return null;
}

/// 按维度优先级、阵营顺序、sortOrder 与名称排序标签以供展示。
List<Tag> sortTagsForDisplay(List<Tag> tags) {
  final sorted = List<Tag>.from(tags);
  sorted.sort((a, b) {
    final rankCompare = _tagDimensionRank(a.dimension)
        .compareTo(_tagDimensionRank(b.dimension));
    if (rankCompare != 0) return rankCompare;
    if (a.dimension == TagDimension.role) {
      final roleCompare =
          _roleTagDisplayPriority(a).compareTo(_roleTagDisplayPriority(b));
      if (roleCompare != 0) return roleCompare;
    }

    final orderCompare = a.sortOrder.compareTo(b.sortOrder);
    if (orderCompare != 0) return orderCompare;

    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return sorted;
}

/// 当数据库缺少阵营标签关联时，仅在界面回退显示与道具阵营一致的标签。
Set<int> resolveDisplayedTagSelection({
  required List<Tag> allTags,
  required Set<int> selectedIds,
  required int? grenadeTeam,
}) {
  final roleTags =
      allTags.where((t) => t.dimension == TagDimension.role).toList();
  if (roleTags.isEmpty) return Set<int>.from(selectedIds);

  final roleById = {for (final tag in roleTags) tag.id: tag};
  final selectedRoleIds = selectedIds.where(roleById.containsKey).toSet();
  final expectedTeam = normalizeRoleTeam(grenadeTeam);
  final singleRole =
      selectedRoleIds.length == 1 ? roleById[selectedRoleIds.first] : null;
  if (singleRole != null && roleTagToTeamType(singleRole) == expectedTeam) {
    return Set<int>.from(selectedIds);
  }

  final adjusted = Set<int>.from(selectedIds)..removeAll(roleById.keys);
  final targetRoleTag = findRoleTagByTeam(roleTags, expectedTeam);
  if (targetRoleTag != null) {
    adjusted.add(targetRoleTag.id);
  }
  return adjusted;
}
