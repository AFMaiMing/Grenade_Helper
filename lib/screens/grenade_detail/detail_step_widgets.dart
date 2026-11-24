import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models.dart';
import '../../models/tag.dart';
import '../../services/tag_service.dart';
import '../../theme/app_design_system.dart';
import '../../widgets/grenade_tag_editor.dart';
import 'video_player_widget.dart';

/// 默认作者占位文案。
const String defaultGrenadeAuthor = '匿名作者';

/// 爆点、投掷点或穿线方位展示与编辑卡片。
class ImpactPointSectionCard extends StatelessWidget {
  final Grenade grenade;
  final bool isEditing;
  final bool pickThrowPoint;
  final VoidCallback onViewImpactPoint;
  final VoidCallback onPickThrowPoint;
  final VoidCallback onPickImpactPoint;
  final VoidCallback onClearImpactPoint;
  final VoidCallback onDrawImpactArea;

  const ImpactPointSectionCard({
    super.key,
    required this.grenade,
    required this.isEditing,
    required this.pickThrowPoint,
    required this.onViewImpactPoint,
    required this.onPickThrowPoint,
    required this.onPickImpactPoint,
    required this.onClearImpactPoint,
    required this.onDrawImpactArea,
  });

  @override
  Widget build(BuildContext context) {
    final isWallbang = grenade.type == GrenadeType.wallbang;
    final hasImpactPoint =
        grenade.impactXRatio != null && grenade.impactYRatio != null;
    final throwMode =
        !isWallbang && isEditing && pickThrowPoint && hasImpactPoint;
    // 投掷点与爆点重合视为未单独设置投掷点
    final hasThrowPoint = grenade.xRatio != grenade.impactXRatio ||
        grenade.yRatio != grenade.impactYRatio;
    final pointSet = throwMode ? hasThrowPoint : hasImpactPoint;
    final accentColor =
        isWallbang ? Colors.cyan : Theme.of(context).colorScheme.primary;
    final cardIcon =
        isWallbang ? Icons.north_east_rounded : Icons.gps_fixed_rounded;
    final sectionTitle = isWallbang ? '穿线方位' : (throwMode ? '投掷点位置' : '爆点位置');
    final sectionSubtitle = isWallbang
        ? (hasImpactPoint
            ? '方位终点 (${grenade.impactXRatio!.toStringAsFixed(3)}, ${grenade.impactYRatio!.toStringAsFixed(3)})'
            : '尚未设置穿线')
        : (throwMode
            ? (hasThrowPoint
                ? '坐标 (${grenade.xRatio.toStringAsFixed(3)}, ${grenade.yRatio.toStringAsFixed(3)})'
                : '尚未设置投掷点')
            : (hasImpactPoint
                ? '坐标 (${grenade.impactXRatio!.toStringAsFixed(3)}, ${grenade.impactYRatio!.toStringAsFixed(3)})'
                : '尚未设置爆点'));
    final editActionLabel = isWallbang
        ? (hasImpactPoint ? '修改穿线' : '设置穿线')
        : (throwMode
            ? (hasThrowPoint ? '修改投掷点' : '设置投掷点')
            : (hasImpactPoint ? '修改爆点' : '设置爆点'));
    final editButtonColor = isWallbang ? Colors.cyan : Colors.purpleAccent;
    final canClear = !throwMode &&
        (hasImpactPoint ||
            (!isWallbang &&
                grenade.impactAreaStrokes != null &&
                grenade.impactAreaStrokes!.isNotEmpty));

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.appTheme.subtleBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(cardIcon, size: 19, color: accentColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sectionTitle,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sectionSubtitle,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: context.appTheme.mutedText),
                    ),
                  ],
                ),
              ),
              if (pointSet)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    '已设置',
                    style: TextStyle(
                      color: Colors.green,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              if (!isEditing && hasImpactPoint) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: onViewImpactPoint,
                  icon: const Icon(Icons.visibility_outlined, size: 17),
                  label: const Text('查看'),
                ),
              ],
            ],
          ),
          if (isEditing) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: throwMode ? onPickThrowPoint : onPickImpactPoint,
                    icon: Icon(
                      isWallbang
                          ? Icons.north_east_rounded
                          : (pointSet
                              ? Icons.edit_location
                              : Icons.add_location),
                      size: 18,
                    ),
                    label: Text(editActionLabel),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: editButtonColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                if (canClear) ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: onClearImpactPoint,
                    icon: const Icon(Icons.clear, size: 18),
                    label: const Text('清除'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (grenade.type == GrenadeType.smoke ||
                grenade.type == GrenadeType.molotov) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: hasImpactPoint ? onDrawImpactArea : null,
                  icon: const Icon(Icons.brush, size: 18),
                  label: Text(hasImpactPoint ? '绘制爆点范围' : '请先设置爆点位置'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        hasImpactPoint ? Colors.pinkAccent : Colors.grey,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// 详情页标签展示与编辑区块。
class GrenadeTagSection extends StatelessWidget {
  final int grenadeId;
  final int mapId;
  final TagService tagService;
  final bool isEditing;
  final List<Tag>? cachedTags;
  final VoidCallback onTagsChanged;

  const GrenadeTagSection({
    super.key,
    required this.grenadeId,
    required this.mapId,
    required this.tagService,
    required this.isEditing,
    required this.cachedTags,
    required this.onTagsChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tags = cachedTags ?? const <Tag>[];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.blueAccent.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: isEditing
          ? GrenadeTagEditor(
              grenadeId: grenadeId,
              mapId: mapId,
              tagService: tagService,
              onTagsChanged: onTagsChanged,
            )
          : tags.isEmpty
              ? const Text(
                  '未绑定标签',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '标签',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    GrenadeTagDisplay(tags: tags),
                  ],
                ),
    );
  }
}

/// 单个步骤媒体项视图，支持排序、全屏图片预览与编辑删除。
class StepMediaItemRow extends StatelessWidget {
  final StepMedia media;
  final bool isEditing;
  final int mediaIndex;
  final int totalMediaCount;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback onOpenFullscreenImage;
  final VoidCallback onEditImage;
  final VoidCallback onDeleteMedia;

  const StepMediaItemRow({
    super.key,
    required this.media,
    required this.isEditing,
    required this.mediaIndex,
    required this.totalMediaCount,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onOpenFullscreenImage,
    required this.onEditImage,
    required this.onDeleteMedia,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isEditing && totalMediaCount > 1)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(
                    Icons.arrow_upward,
                    size: 20,
                    color:
                        mediaIndex > 0 ? Colors.blueAccent : Colors.grey[600],
                  ),
                  onPressed: mediaIndex > 0 ? onMoveUp : null,
                  tooltip: '上移',
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
                IconButton(
                  icon: Icon(
                    Icons.arrow_downward,
                    size: 20,
                    color: mediaIndex < totalMediaCount - 1
                        ? Colors.blueAccent
                        : Colors.grey[600],
                  ),
                  onPressed:
                      mediaIndex < totalMediaCount - 1 ? onMoveDown : null,
                  tooltip: '下移',
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
              ],
            ),
          Expanded(
            child: Stack(
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: media.type == MediaType.image
                      ? GestureDetector(
                          onTap: onOpenFullscreenImage,
                          child: Image.file(
                            File(media.localPath),
                            fit: BoxFit.contain,
                            width: double.infinity,
                          ),
                        )
                      : VideoPlayerWidget(
                          key: ValueKey('video_${media.id}_${media.localPath}'),
                          file: File(media.localPath),
                        ),
                ),
                if (isEditing) ...[
                  if (media.type == MediaType.image)
                    Positioned(
                      top: 5,
                      right: 40,
                      child: GestureDetector(
                        onTap: onEditImage,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.edit,
                            size: 14,
                            color: Colors.orangeAccent,
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    top: 5,
                    right: 5,
                    child: GestureDetector(
                      onTap: onDeleteMedia,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.delete,
                          size: 14,
                          color: Colors.redAccent,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 单个教学步骤卡片。
class GrenadeStepCard extends StatelessWidget {
  final GrenadeStep step;
  final bool isEditing;
  final VoidCallback onEditStep;
  final VoidCallback onAddImage;
  final VoidCallback onAddVideo;
  final VoidCallback onDeleteStep;
  final void Function(int fromIndex, int toIndex) onSwapMediaOrder;
  final void Function(String localPath) onOpenFullscreenImage;
  final void Function(StepMedia media) onEditImage;
  final void Function(StepMedia media) onDeleteMedia;

  const GrenadeStepCard({
    super.key,
    required this.step,
    required this.isEditing,
    required this.onEditStep,
    required this.onAddImage,
    required this.onAddVideo,
    required this.onDeleteStep,
    required this.onSwapMediaOrder,
    required this.onOpenFullscreenImage,
    required this.onEditImage,
    required this.onDeleteMedia,
  });

  @override
  Widget build(BuildContext context) {
    final sortedMedias = step.medias.toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    return Card(
      key: ValueKey(step.id),
      margin: const EdgeInsets.only(bottom: 20),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '#${step.stepIndex + 1}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    step.title.isNotEmpty
                        ? step.title
                        : '步骤 ${step.stepIndex + 1}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Theme.of(context)
                          .textTheme
                          .bodyLarge
                          ?.color
                          ?.withValues(alpha: 0.7),
                    ),
                  ),
                ),
                if (isEditing) ...[
                  IconButton(
                    icon: const Icon(
                      Icons.edit,
                      size: 20,
                      color: Colors.orangeAccent,
                    ),
                    onPressed: onEditStep,
                    tooltip: '编辑步骤',
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.add_photo_alternate,
                      size: 20,
                      color: Colors.blueAccent,
                    ),
                    onPressed: onAddImage,
                    tooltip: '追加图片',
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.video_call,
                      size: 20,
                      color: Colors.greenAccent,
                    ),
                    onPressed: onAddVideo,
                    tooltip: '追加视频',
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20, color: Colors.red),
                    onPressed: onDeleteStep,
                  ),
                ],
              ],
            ),
          ),
          Divider(color: Theme.of(context).dividerColor),
          if (sortedMedias.isNotEmpty)
            Column(
              children: [
                for (int i = 0; i < sortedMedias.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: StepMediaItemRow(
                      media: sortedMedias[i],
                      isEditing: isEditing,
                      mediaIndex: i,
                      totalMediaCount: sortedMedias.length,
                      onMoveUp: () => onSwapMediaOrder(i, i - 1),
                      onMoveDown: () => onSwapMediaOrder(i, i + 1),
                      onOpenFullscreenImage: () =>
                          onOpenFullscreenImage(sortedMedias[i].localPath),
                      onEditImage: () => onEditImage(sortedMedias[i]),
                      onDeleteMedia: () => onDeleteMedia(sortedMedias[i]),
                    ),
                  ),
              ],
            )
          else if (isEditing)
            Container(
              height: 60,
              width: double.infinity,
              color: Colors.black26,
              child: const Center(
                child: Text(
                  '暂无媒体，点击上方按钮添加',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              step.description.isEmpty ? '（暂无文字说明）' : step.description,
              style: TextStyle(
                fontSize: 15,
                height: 1.5,
                color: Theme.of(context).textTheme.bodyMedium?.color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 响应式步骤导航与主体布局壳。
class GrenadeResponsiveStepLayout extends StatelessWidget {
  final List<GrenadeStep> steps;
  final ValueChanged<GrenadeStep> onSelectStep;
  final Widget content;

  const GrenadeResponsiveStepLayout({
    super.key,
    required this.steps,
    required this.onSelectStep,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < AppBreakpoints.mobile) {
          return Column(
            children: [
              if (steps.isNotEmpty)
                SizedBox(
                  height: 58,
                  child: ListView.separated(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    scrollDirection: Axis.horizontal,
                    itemCount: steps.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, index) => ActionChip(
                      avatar: CircleAvatar(
                        radius: 11,
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                      label: Text(
                        steps[index].title.isEmpty
                            ? '步骤 ${index + 1}'
                            : steps[index].title,
                      ),
                      onPressed: () => onSelectStep(steps[index]),
                    ),
                  ),
                ),
              Expanded(child: content),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 236,
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
                      child: Text(
                        '教学步骤',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        itemCount: steps.length,
                        itemBuilder: (_, index) => ListTile(
                          dense: true,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          leading: CircleAvatar(
                            radius: 13,
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.14),
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                          title: Text(
                            steps[index].title.isEmpty
                                ? '步骤 ${index + 1}'
                                : steps[index].title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => onSelectStep(steps[index]),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            VerticalDivider(width: 1, color: context.appTheme.subtleBorder),
            Expanded(child: content),
          ],
        );
      },
    );
  }
}

/// 详情页底部作者、出处与时间戳信息栏。
class GrenadeDetailFooter extends StatelessWidget {
  final Grenade grenade;
  final bool isEditing;
  final VoidCallback onEditAuthor;
  final VoidCallback onEditSource;

  const GrenadeDetailFooter({
    super.key,
    required this.grenade,
    required this.isEditing,
    required this.onEditAuthor,
    required this.onEditSource,
  });

  String _formatSourceDisplay() {
    final hasSource = (grenade.sourceUrl?.isNotEmpty == true) ||
        (grenade.sourceNote?.isNotEmpty == true);
    if (!hasSource) return '未设置';
    if (grenade.sourceNote?.isNotEmpty == true) {
      return grenade.sourceNote!;
    }
    final url = grenade.sourceUrl!;
    return url.length > 30 ? '${url.substring(0, 30)}...' : url;
  }

  Future<void> _launchSourceUrl(BuildContext context) async {
    final url = grenade.sourceUrl;
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法打开链接: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('yyyy-MM-dd HH:mm:ss');
    final authorText = grenade.author?.isNotEmpty == true
        ? grenade.author!
        : defaultGrenadeAuthor;
    // 导入道具需有本地实质性编辑后才可修改作者
    final canEditAuthor = !grenade.isImported || grenade.hasLocalEdits;
    final hasSource = (grenade.sourceUrl?.isNotEmpty == true) ||
        (grenade.sourceNote?.isNotEmpty == true);
    final hasSourceUrl = grenade.sourceUrl?.isNotEmpty == true;
    final sourceDisplayText = _formatSourceDisplay();

    return Padding(
      padding: const EdgeInsets.only(bottom: 20, top: 10),
      child: Column(
        children: [
          GestureDetector(
            onTap: isEditing
                ? (canEditAuthor
                    ? onEditAuthor
                    : () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              '此道具为导入内容，需进行实质性编辑（修改文字、编辑图片、添加/删除媒体）后才能修改作者名',
                            ),
                            duration: Duration(seconds: 3),
                          ),
                        );
                      })
                : null,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '作者: $authorText',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
                if (isEditing) ...[
                  const SizedBox(width: 4),
                  Icon(
                    canEditAuthor ? Icons.edit : Icons.lock_outline,
                    size: 12,
                    color: canEditAuthor ? Colors.grey : Colors.grey[600],
                  ),
                ],
              ],
            ),
          ),
          if (isEditing || hasSource) ...[
            const SizedBox(height: 4),
            GestureDetector(
              onTap: isEditing
                  ? onEditSource
                  : (hasSourceUrl ? () => _launchSourceUrl(context) : null),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      hasSource ? Icons.link : Icons.link_off,
                      size: 14,
                      color: (!isEditing && hasSourceUrl)
                          ? Colors.blueAccent
                          : Colors.grey,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        '出处: $sourceDisplayText',
                        style: TextStyle(
                          color: (!isEditing && hasSourceUrl)
                              ? Colors.blueAccent
                              : Colors.grey,
                          fontSize: 12,
                          decoration: (!isEditing && hasSourceUrl)
                              ? TextDecoration.underline
                              : null,
                          decorationColor: Colors.blueAccent,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isEditing) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.edit, size: 12, color: Colors.grey),
                    ],
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '创建: ${fmt.format(grenade.createdAt)}',
                style: const TextStyle(color: Colors.grey, fontSize: 10),
              ),
              const Text(
                '  |  ',
                style: TextStyle(color: Colors.grey, fontSize: 10),
              ),
              Text(
                '最后编辑: ${fmt.format(grenade.updatedAt)}',
                style: const TextStyle(color: Colors.grey, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
