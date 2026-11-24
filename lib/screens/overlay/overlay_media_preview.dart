import 'dart:io';

import 'package:flutter/material.dart';

import '../../models.dart';
import '../../models/overlay_snapshot.dart';
import '../../services/overlay_state_service.dart';
import '../../services/settings_service.dart';
import '../grenade_detail_screen.dart'
    show VideoPlayerWidget, VideoPlayerWidgetState;
import 'overlay_hotkey_helper.dart';
import 'overlay_radar_and_prompts.dart';
import 'overlay_window_shared.dart';

/// 悬浮窗当前步骤媒体列表展示区。
class OverlayMediaArea extends StatelessWidget {
  final List<OverlayMediaItem>? medias;
  final bool isFullscreenPreview;
  final GlobalKey<VideoPlayerWidgetState> videoPlayerKey;

  const OverlayMediaArea({
    super.key,
    required this.medias,
    required this.isFullscreenPreview,
    required this.videoPlayerKey,
  });

  @override
  Widget build(BuildContext context) {
    if (medias == null) {
      return Container(
        height: 200,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Text('该道具暂无步骤', style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    if (medias!.isEmpty) {
      return Container(
        height: 350,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Icon(Icons.image_not_supported, size: 48, color: Colors.grey),
        ),
      );
    }

    var primaryVideoAssigned = false;
    return Column(
      children: medias!.asMap().entries.map((entry) {
        final index = entry.key;
        final media = entry.value;
        final isPrimaryVideo =
            media.type == MediaType.video && !primaryVideoAssigned;
        if (isPrimaryVideo) {
          primaryVideoAssigned = true;
        }
        return Padding(
          padding: EdgeInsets.only(bottom: index < medias!.length - 1 ? 8 : 0),
          child: OverlaySingleMediaItem(
            media: media,
            isFullscreenPreview: isFullscreenPreview,
            videoPlayerKey: videoPlayerKey,
            usePrimaryVideoKey: isPrimaryVideo,
          ),
        );
      }).toList(),
    );
  }
}

/// 单个媒体项容器，负责异步识别图片宽高比并应用非全屏裁剪缩放。
class OverlaySingleMediaItem extends StatefulWidget {
  final OverlayMediaItem media;
  final bool isFullscreenPreview;
  final double? preferredHeight;
  final GlobalKey<VideoPlayerWidgetState> videoPlayerKey;
  final bool usePrimaryVideoKey;

  const OverlaySingleMediaItem({
    super.key,
    required this.media,
    required this.isFullscreenPreview,
    this.preferredHeight,
    required this.videoPlayerKey,
    this.usePrimaryVideoKey = true,
  });

  @override
  State<OverlaySingleMediaItem> createState() => _OverlaySingleMediaItemState();
}

class _OverlaySingleMediaItemState extends State<OverlaySingleMediaItem> {
  Future<Size?>? _imageSizeFuture;

  @override
  void initState() {
    super.initState();
    _syncImageSizeFuture();
  }

  @override
  void didUpdateWidget(covariant OverlaySingleMediaItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.media.localPath != widget.media.localPath ||
        oldWidget.media.type != widget.media.type) {
      _syncImageSizeFuture();
    }
  }

  void _syncImageSizeFuture() {
    _imageSizeFuture = widget.media.type == MediaType.image
        ? _loadImageSize(widget.media.localPath)
        : null;
  }

  Future<Size?> _loadImageSize(String path) async {
    try {
      final file = File(path);
      if (!file.existsSync()) return null;

      final bytes = await file.readAsBytes();
      final image = await decodeImageFromList(bytes);
      return Size(image.width.toDouble(), image.height.toDouble());
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final loadingHeight =
        widget.preferredHeight ?? (widget.isFullscreenPreview ? 560.0 : 400.0);
    final defaultHeight =
        widget.preferredHeight ?? (widget.isFullscreenPreview ? 560.0 : 400.0);
    final portraitHeight =
        widget.preferredHeight ?? (widget.isFullscreenPreview ? 760.0 : 450.0);

    if (widget.media.type == MediaType.image) {
      return FutureBuilder<Size?>(
        future: _imageSizeFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Container(
              height: loadingHeight,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: CircularProgressIndicator(
                  color: Colors.orange,
                  strokeWidth: 2,
                ),
              ),
            );
          }

          var height = defaultHeight;
          // 0: 正方形/近似方形, 1: 竖屏, 2: 横屏
          var imageType = 0;

          if (widget.preferredHeight == null &&
              snapshot.hasData &&
              snapshot.data != null) {
            final size = snapshot.data!;
            final diff = (size.height - size.width).abs();

            if (diff <= 400) {
              imageType = 0;
            } else if (size.height > size.width) {
              imageType = 1;
              height = portraitHeight;
            } else {
              imageType = 2;
            }
          }

          return Container(
            height: height,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: _buildMediaContent(imageType: imageType),
          );
        },
      );
    }

    return Container(
      height: defaultHeight,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: _buildMediaContent(),
    );
  }

  Widget _buildMediaContent({int imageType = 0}) {
    final file = File(widget.media.localPath);
    if (!file.existsSync()) {
      return const Center(
        child: Icon(Icons.broken_image, size: 48, color: Colors.grey),
      );
    }

    if (widget.media.type == MediaType.image) {
      final needsScale = !widget.isFullscreenPreview && imageType != 0;

      Widget imageWidget = Image.file(
        file,
        fit: BoxFit.contain,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => const Center(
          child: Icon(Icons.broken_image, size: 48, color: Colors.grey),
        ),
      );

      if (needsScale) {
        final scale = imageType == 1 ? 1.5 : 1.3;
        imageWidget = Transform.scale(
          scale: scale,
          child: imageWidget,
        );
      }

      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: imageWidget,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: VideoPlayerWidget(
        key: widget.usePrimaryVideoKey
            ? widget.videoPlayerKey
            : ValueKey(widget.media.localPath),
        file: file,
      ),
    );
  }
}

/// 悬浮窗媒体全屏预览视图。
class OverlayFullscreenPreview extends StatelessWidget {
  final OverlayStateService overlayState;
  final Map<HotkeyAction, HotkeyConfig> hotkeys;
  final List<OverlayMediaItem>? medias;
  final GlobalKey<VideoPlayerWidgetState> videoPlayerKey;
  final ScrollController scrollController;
  final VoidCallback onToggleFullscreen;

  const OverlayFullscreenPreview({
    super.key,
    required this.overlayState,
    required this.hotkeys,
    required this.medias,
    required this.videoPlayerKey,
    required this.scrollController,
    required this.onToggleFullscreen,
  });

  @override
  Widget build(BuildContext context) {
    final title = overlayState.currentGrenade?.title ?? '媒体预览';
    final fullscreenKey = overlayHotkeyLabel(
      hotkeys,
      HotkeyAction.toggleMediaFullscreenPreview,
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onToggleFullscreen,
          child: Container(
            color: Colors.black.withValues(alpha: 0.38),
          ),
        ),
        SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 1600,
                maxHeight: 980,
              ),
              child: Container(
                margin: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xF214171C),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.35),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 40,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.fullscreen,
                            color: Colors.orange,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '$fullscreenKey 退出全屏',
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 12),
                          OverlayWindowButton(
                            icon: Icons.fullscreen_exit,
                            onTap: onToggleFullscreen,
                            color: Colors.orange,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Expanded(child: _buildContent()),
                      const SizedBox(height: 12),
                      _FullscreenHintBar(
                        overlayState: overlayState,
                        hotkeys: hotkeys,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContent() {
    final safeMedias = medias ?? const <OverlayMediaItem>[];
    final description = OverlayStepDescription(
      grenade: overlayState.currentGrenade,
      currentStepIndex: overlayState.currentStepIndex,
    );

    if (safeMedias.length == 1) {
      return Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return OverlaySingleMediaItem(
                  media: safeMedias.first,
                  isFullscreenPreview: true,
                  preferredHeight: constraints.maxHeight,
                  videoPlayerKey: videoPlayerKey,
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          description,
        ],
      );
    }

    return SingleChildScrollView(
      controller: scrollController,
      child: Column(
        children: [
          OverlayMediaArea(
            medias: medias,
            isFullscreenPreview: true,
            videoPlayerKey: videoPlayerKey,
          ),
          const SizedBox(height: 12),
          description,
        ],
      ),
    );
  }
}

class _FullscreenHintBar extends StatelessWidget {
  final OverlayStateService overlayState;
  final Map<HotkeyAction, HotkeyConfig> hotkeys;

  const _FullscreenHintBar({
    required this.overlayState,
    required this.hotkeys,
  });

  @override
  Widget build(BuildContext context) {
    final grenade = overlayState.currentGrenade;
    final grenadeTotal = overlayState.currentClusterGrenades.length;
    final grenadeIndex =
        grenade == null ? 0 : overlayState.currentClusterIndex + 1;
    final steps = grenade?.steps ?? const <OverlayStepItem>[];
    final stepTotal = steps.isEmpty ? 0 : steps.length;
    final stepIndex = steps.isEmpty ? 0 : overlayState.currentStepIndex + 1;
    final currentStep =
        steps.isNotEmpty && overlayState.currentStepIndex < steps.length
            ? steps[overlayState.currentStepIndex]
            : null;
    final stepTitle = (currentStep?.title ?? '').trim();
    final stepDisplayTitle = stepTitle.isEmpty ? '步骤' : stepTitle;

    final prevGrenadeKey =
        overlayHotkeyLabel(hotkeys, HotkeyAction.prevGrenade);
    final nextGrenadeKey =
        overlayHotkeyLabel(hotkeys, HotkeyAction.nextGrenade);
    final prevStepKey = overlayHotkeyLabel(hotkeys, HotkeyAction.prevStep);
    final nextStepKey = overlayHotkeyLabel(hotkeys, HotkeyAction.nextStep);
    final togglePlayKey =
        overlayHotkeyLabel(hotkeys, HotkeyAction.togglePlayPause);
    final fullscreenKey = overlayHotkeyLabel(
      hotkeys,
      HotkeyAction.toggleMediaFullscreenPreview,
    );
    final scrollUpKey = overlayHotkeyLabel(hotkeys, HotkeyAction.scrollUp);
    final scrollDownKey = overlayHotkeyLabel(hotkeys, HotkeyAction.scrollDown);
    final hintStyle = TextStyle(color: Colors.grey[300], fontSize: 12);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 920;

          final leftInfo = Wrap(
            spacing: 14,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '道具 $grenadeIndex/$grenadeTotal',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '$stepDisplayTitle $stepIndex/$stepTotal',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          );

          final rightHints = Wrap(
            spacing: 14,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('$prevGrenadeKey/$nextGrenadeKey 切换道具', style: hintStyle),
              Text('$prevStepKey/$nextStepKey 切换步骤', style: hintStyle),
              Text('$togglePlayKey 播放/暂停', style: hintStyle),
              Text('$scrollUpKey/$scrollDownKey 滚动', style: hintStyle),
              Text('$fullscreenKey 退出全屏', style: hintStyle),
              Text(
                '方向导航已禁用',
                style: TextStyle(
                  color: Colors.orange[300],
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                leftInfo,
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: rightHints,
                ),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: leftInfo),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: rightHints,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
