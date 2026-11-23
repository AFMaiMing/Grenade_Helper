import 'package:flutter/material.dart';
import 'package:isar_community/isar.dart';

import '../models.dart';
import '../models/grenade_tag.dart';
import '../models/tag.dart';
import '../services/tag_service.dart';
import 'tag_editor/tag_editor_widgets.dart';
import 'tag_editor/tag_role_helpers.dart';

export 'tag_editor/tag_role_helpers.dart'
    show roleTagToTeamType, sortTagsForDisplay;

// 标签较多时先折叠展示，避免占用整个道具详情页。
const int _collapsedTagCount = 12;

/// 道具标签编辑器。
class GrenadeTagEditor extends StatefulWidget {
  final int grenadeId;
  final int mapId;
  final TagService tagService;
  final VoidCallback? onTagsChanged;

  const GrenadeTagEditor({
    super.key,
    required this.grenadeId,
    required this.mapId,
    required this.tagService,
    this.onTagsChanged,
  });

  @override
  State<GrenadeTagEditor> createState() => _GrenadeTagEditorState();
}

class _GrenadeTagEditorState extends State<GrenadeTagEditor> {
  List<Tag> _allTags = [];
  Set<int> _selectedTagIds = {};
  bool _isLoading = true;
  bool _showAllTags = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final allTags = await widget.tagService.getAllTags(widget.mapId);
    final selectedIds =
        await widget.tagService.getGrenadeTagIds(widget.grenadeId);
    final grenade = await widget.tagService.isar.grenades.get(widget.grenadeId);
    final resolvedSelection = resolveDisplayedTagSelection(
      allTags: allTags,
      selectedIds: selectedIds,
      grenadeTeam: grenade?.team,
    );
    if (!mounted) return;
    setState(() {
      _allTags = allTags;
      _selectedTagIds = resolvedSelection;
      _isLoading = false;
    });
  }

  Future<void> _toggleTag(Tag tag) async {
    final clickedTeam = roleTagToTeamType(tag);
    if (clickedTeam != null) {
      await _toggleRoleTag(tag, clickedTeam);
      return;
    }

    final newSelection = Set<int>.from(_selectedTagIds);
    if (newSelection.contains(tag.id)) {
      newSelection.remove(tag.id);
      await widget.tagService.removeTagFromGrenade(widget.grenadeId, tag.id);
    } else {
      newSelection.add(tag.id);
      await widget.tagService.addTagToGrenade(widget.grenadeId, tag.id);
    }
    if (!mounted) return;
    setState(() => _selectedTagIds = newSelection);
    widget.onTagsChanged?.call();
  }

  Future<void> _toggleRoleTag(Tag tag, int clickedTeam) async {
    final roleTags =
        _allTags.where((t) => t.dimension == TagDimension.role).toList();
    final isCurrentlySelected = _selectedTagIds.contains(tag.id);
    if (isCurrentlySelected && clickedTeam == TeamType.all) return;

    final int targetTeam;
    final Tag? targetTag;
    if (!isCurrentlySelected) {
      targetTeam = clickedTeam;
      targetTag = tag;
    } else {
      targetTeam = TeamType.all;
      targetTag = findRoleTagByTeam(roleTags, TeamType.all);
    }

    final roleTagIds = roleTags.map((t) => t.id).toSet();
    final isar = widget.tagService.isar;
    final now = DateTime.now();

    await isar.writeTxn(() async {
      final existingLinks = await isar.grenadeTags
          .filter()
          .grenadeIdEqualTo(widget.grenadeId)
          .findAll();
      var hasTargetLink = false;
      final deleteIds = <int>[];
      for (final link in existingLinks) {
        if (!roleTagIds.contains(link.tagId)) continue;
        if (targetTag != null && link.tagId == targetTag.id && !hasTargetLink) {
          hasTargetLink = true;
        } else {
          deleteIds.add(link.id);
        }
      }
      if (deleteIds.isNotEmpty) {
        await isar.grenadeTags.deleteAll(deleteIds);
      }
      if (targetTag != null && !hasTargetLink) {
        await isar.grenadeTags.put(
          GrenadeTag(grenadeId: widget.grenadeId, tagId: targetTag.id),
        );
      }
      final grenade = await isar.grenades.get(widget.grenadeId);
      if (grenade != null) {
        grenade.team = targetTeam;
        grenade.updatedAt = now;
        grenade.hasLocalEdits = true;
        await isar.grenades.put(grenade);
      }
    });

    final newSelection = Set<int>.from(_selectedTagIds)..removeAll(roleTagIds);
    if (targetTag != null) {
      newSelection.add(targetTag.id);
    }
    if (!mounted) return;
    setState(() => _selectedTagIds = newSelection);
    widget.onTagsChanged?.call();
  }

  Future<void> _createQuickTag() async {
    final result = await showDialog<QuickTagDraft>(
      context: context,
      builder: (_) => const QuickCreateTagDialog(),
    );
    if (result == null) return;
    final tag = await widget.tagService
        .createTag(widget.mapId, result.name, result.color);
    await widget.tagService.addTagToGrenade(widget.grenadeId, tag.id);
    await _loadData();
    widget.onTagsChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        height: 60,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    final sortedTags = sortTagsForDisplay(_allTags);
    final visibleTags = _showAllTags
        ? sortedTags
        : sortedTags.take(_collapsedTagCount).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '标签',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            if (_selectedTagIds.isNotEmpty)
              Text(
                '${_selectedTagIds.length} 个已选',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).primaryColor,
                ),
              ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline, size: 20),
              onPressed: _createQuickTag,
              tooltip: '快速创建标签',
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_allTags.isEmpty)
          const Text(
            '暂无标签，点击右上角创建',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: visibleTags
                    .map(
                      (tag) => SelectableTagChip(
                        tag: tag,
                        selected: _selectedTagIds.contains(tag.id),
                        onTap: () => _toggleTag(tag),
                      ),
                    )
                    .toList(),
              ),
              if (sortedTags.length > _collapsedTagCount)
                TagExpandToggleButton(
                  expanded: _showAllTags,
                  hiddenCount: sortedTags.length - visibleTags.length,
                  onPressed: () => setState(() => _showAllTags = !_showAllTags),
                ),
            ],
          ),
      ],
    );
  }
}

/// 显示道具标签的只读展示组件。
class GrenadeTagDisplay extends StatefulWidget {
  final List<Tag> tags;
  final bool compact;

  const GrenadeTagDisplay({
    super.key,
    required this.tags,
    this.compact = false,
  });

  @override
  State<GrenadeTagDisplay> createState() => _GrenadeTagDisplayState();
}

class _GrenadeTagDisplayState extends State<GrenadeTagDisplay> {
  bool _showAllTags = false;

  @override
  Widget build(BuildContext context) {
    if (widget.tags.isEmpty) return const SizedBox.shrink();
    final sortedTags = sortTagsForDisplay(widget.tags);
    final visibleTags = _showAllTags
        ? sortedTags
        : sortedTags.take(_collapsedTagCount).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: visibleTags.map((tag) {
            final color = Color(tag.colorValue);
            return Container(
              padding: EdgeInsets.symmetric(
                horizontal: widget.compact ? 6 : 8,
                vertical: widget.compact ? 2 : 4,
              ),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(widget.compact ? 8 : 12),
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: Text(
                tag.name,
                style: TextStyle(
                  fontSize: widget.compact ? 10 : 12,
                  color: color,
                ),
              ),
            );
          }).toList(),
        ),
        if (sortedTags.length > _collapsedTagCount)
          TagExpandToggleButton(
            expanded: _showAllTags,
            hiddenCount: sortedTags.length - visibleTags.length,
            onPressed: () => setState(() => _showAllTags = !_showAllTags),
          ),
      ],
    );
  }
}
