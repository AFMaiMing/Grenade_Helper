// ignore_for_file: implementation_imports

import 'package:chewie/src/animated_play_pause.dart';
import 'package:chewie/src/chewie_player.dart';
import 'package:chewie/src/chewie_progress_colors.dart';
import 'package:chewie/src/helpers/utils.dart';
import 'package:chewie/src/material/material_progress_bar.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// 桌面视频播放器底部控制栏。
class DesktopVideoBottomBar extends StatelessWidget {
  final double barHeight;
  final bool hideStuff;
  final ChewieController chewieController;
  final VideoPlayerController controller;
  final VideoPlayerValue latestValue;
  final bool subtitleOn;
  final VoidCallback onPlayPause;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleSubtitle;
  final VoidCallback onOpenOptions;
  final VoidCallback onExpandCollapse;
  final VoidCallback onDragStart;
  final VoidCallback onDragUpdate;
  final VoidCallback onDragEnd;

  const DesktopVideoBottomBar({
    super.key,
    required this.barHeight,
    required this.hideStuff,
    required this.chewieController,
    required this.controller,
    required this.latestValue,
    required this.subtitleOn,
    required this.onPlayPause,
    required this.onToggleMute,
    required this.onToggleSubtitle,
    required this.onOpenOptions,
    required this.onExpandCollapse,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    final isFullScreen = chewieController.isFullScreen;
    final hasSubtitles = chewieController.showControls &&
        chewieController.subtitle != null &&
        chewieController.subtitle!.isNotEmpty;

    return AnimatedOpacity(
      opacity: hideStuff ? 0.0 : 1.0,
      duration: const Duration(milliseconds: 300),
      child: Container(
        height: barHeight + (isFullScreen ? 20.0 : 0),
        padding: EdgeInsets.only(bottom: isFullScreen ? 10.0 : 15),
        child: SafeArea(
          bottom: isFullScreen,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            verticalDirection: VerticalDirection.up,
            children: [
              Flexible(
                child: Row(
                  children: <Widget>[
                    _PlayPauseButton(
                      barHeight: barHeight,
                      isPlaying: controller.value.isPlaying,
                      onTap: onPlayPause,
                    ),
                    if (chewieController.allowMuting)
                      _MuteButton(
                        barHeight: barHeight,
                        hideStuff: hideStuff,
                        isMuted: latestValue.volume == 0,
                        onTap: onToggleMute,
                      ),
                    if (chewieController.isLive)
                      const Expanded(child: Text('LIVE'))
                    else
                      _PositionLabel(
                        position: latestValue.position,
                        duration: latestValue.duration,
                      ),
                    const Spacer(),
                    if (hasSubtitles)
                      IconButton(
                        padding: EdgeInsets.zero,
                        icon: Icon(
                          Icons.subtitles,
                          color: subtitleOn ? Colors.white : Colors.grey[700],
                        ),
                        onPressed: onToggleSubtitle,
                      ),
                    if (chewieController.showOptions)
                      AnimatedOpacity(
                        opacity: hideStuff ? 0.0 : 1.0,
                        duration: const Duration(milliseconds: 250),
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          onPressed: onOpenOptions,
                          icon: const Icon(Icons.settings, color: Colors.white),
                        ),
                      ),
                    if (chewieController.allowFullScreen)
                      _ExpandButton(
                        barHeight: barHeight,
                        hideStuff: hideStuff,
                        isFullScreen: isFullScreen,
                        onTap: onExpandCollapse,
                      ),
                  ],
                ),
              ),
              if (!chewieController.isLive)
                Expanded(
                  child: Container(
                    padding: EdgeInsets.only(
                      right: 20,
                      left: 20,
                      bottom: isFullScreen ? 5.0 : 0,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: MaterialVideoProgressBar(
                            controller,
                            onDragStart: onDragStart,
                            onDragUpdate: onDragUpdate,
                            onDragEnd: onDragEnd,
                            colors: chewieController.materialProgressColors ??
                                ChewieProgressColors(
                                  playedColor:
                                      Theme.of(context).colorScheme.secondary,
                                  handleColor:
                                      Theme.of(context).colorScheme.secondary,
                                  bufferedColor: Theme.of(context)
                                      .colorScheme
                                      .surface
                                      .withValues(alpha: 0.5),
                                  backgroundColor: Theme.of(context)
                                      .disabledColor
                                      .withValues(alpha: 0.5),
                                ),
                            draggableProgressBar:
                                chewieController.draggableProgressBar,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  final double barHeight;
  final bool isPlaying;
  final VoidCallback onTap;

  const _PlayPauseButton({
    required this.barHeight,
    required this.isPlaying,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: barHeight,
        color: Colors.transparent,
        margin: const EdgeInsets.only(left: 8.0, right: 4.0),
        padding: const EdgeInsets.only(left: 12.0, right: 12.0),
        child: AnimatedPlayPause(
          playing: isPlaying,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _MuteButton extends StatelessWidget {
  final double barHeight;
  final bool hideStuff;
  final bool isMuted;
  final VoidCallback onTap;

  const _MuteButton({
    required this.barHeight,
    required this.hideStuff,
    required this.isMuted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        opacity: hideStuff ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 300),
        child: ClipRect(
          child: Container(
            height: barHeight,
            padding: const EdgeInsets.only(right: 15.0),
            child: Icon(
              isMuted ? Icons.volume_off : Icons.volume_up,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _PositionLabel extends StatelessWidget {
  final Duration position;
  final Duration duration;

  const _PositionLabel({
    required this.position,
    required this.duration,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      '${formatDuration(position)} / ${formatDuration(duration)}',
      style: const TextStyle(fontSize: 14.0, color: Colors.white),
    );
  }
}

class _ExpandButton extends StatelessWidget {
  final double barHeight;
  final bool hideStuff;
  final bool isFullScreen;
  final VoidCallback onTap;

  const _ExpandButton({
    required this.barHeight,
    required this.hideStuff,
    required this.isFullScreen,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        opacity: hideStuff ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 300),
        child: Container(
          height: barHeight + (isFullScreen ? 15.0 : 0),
          margin: const EdgeInsets.only(right: 12.0),
          padding: const EdgeInsets.only(left: 8.0, right: 8.0),
          child: Center(
            child: Icon(
              isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
