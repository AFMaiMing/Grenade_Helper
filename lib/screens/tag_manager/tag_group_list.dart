import 'package:flutter/material.dart';

import '../../models/tag.dart';

/// 按维度分组展示标签列表（隐藏角色分组）。
class TagGroupList extends StatelessWidget {
  final List<Tag> tags;
  final ValueChanged<int> onRenameGroup;
  final ValueChanged<Tag> onEditTag;
  final ValueChanged<Tag> onDeleteTag;

  const TagGroupList({
    super.key,
    required this.tags,
    required this.onRenameGroup,
    required this.onEditTag,
    required this.onDeleteTag,
  });

  @override
  Widget build(BuildContext context) {
    final grouped = <int, List<Tag>>{};
    for (final tag in tags) {
      grouped.putIfAbsent(tag.dimension, () => []).add(tag);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: grouped.entries
          .where((e) => e.key != TagDimension.role)
          .map(
            (e) => _TagGroupSection(
              dimension: e.key,
              tags: e.value,
              onRenameGroup: () => onRenameGroup(e.key),
              onEditTag: onEditTag,
              onDeleteTag: onDeleteTag,
            ),
          )
          .toList(),
    );
  }
}

class _TagGroupSection extends StatelessWidget {
  final int dimension;
  final List<Tag> tags;
  final VoidCallback onRenameGroup;
  final ValueChanged<Tag> onEditTag;
  final ValueChanged<Tag> onDeleteTag;

  const _TagGroupSection({
    required this.dimension,
    required this.tags,
    required this.onRenameGroup,
    required this.onEditTag,
    required this.onDeleteTag,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Text(
                TagDimension.getName(dimension),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${tags.length}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onRenameGroup,
                child: const Icon(Icons.edit, size: 14, color: Colors.grey),
              ),
            ],
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: tags
              .map(
                (tag) => _TagItemChip(
                  tag: tag,
                  onTap: () => onEditTag(tag),
                  onLongPress: () => onDeleteTag(tag),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _TagItemChip extends StatelessWidget {
  final Tag tag;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _TagItemChip({
    required this.tag,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final color = Color(tag.colorValue);
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(tag.name, style: TextStyle(color: color)),
            if (tag.isSystem) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.verified,
                size: 12,
                color: color.withValues(alpha: 0.6),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
