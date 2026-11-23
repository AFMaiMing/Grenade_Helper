// ignore_for_file: implementation_imports

import 'package:chewie/src/center_play_button.dart';
import 'package:chewie/src/models/subtitle_model.dart';
import 'package:flutter/material.dart';

/// 视频中心点击热区与播放按钮覆盖层。
class DesktopVideoHitArea extends StatelessWidget {
  final bool isPlaying;
  final bool isFinished;
  final bool showPlayButton;
  final VoidCallback onTap;
  final VoidCallback onPressed;

  const DesktopVideoHitArea({
    super.key,
    required this.isPlaying,
    required this.isFinished,
    required this.showPlayButton,
    required this.onTap,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: CenterPlayButton(
        backgroundColor: Colors.black54,
        iconColor: Colors.white,
        isFinished: isFinished,
        isPlaying: isPlaying,
        show: showPlayButton,
        onPressed: onPressed,
      ),
    );
  }
}

/// 视频底部字幕覆盖层。
class DesktopVideoSubtitleOverlay extends StatelessWidget {
  final Subtitles subtitles;
  final Duration position;
  final double marginSize;
  final Widget Function(BuildContext, dynamic)? subtitleBuilder;

  const DesktopVideoSubtitleOverlay({
    super.key,
    required this.subtitles,
    required this.position,
    required this.marginSize,
    this.subtitleBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final currentSubtitle = subtitles.getByPosition(position);
    if (currentSubtitle.isEmpty) {
      return const SizedBox();
    }

    final subtitleText = currentSubtitle.first!.text;
    if (subtitleBuilder != null) {
      return subtitleBuilder!(context, subtitleText);
    }

    return Padding(
      padding: EdgeInsets.all(marginSize),
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: const Color(0x96000000),
          borderRadius: BorderRadius.circular(10.0),
        ),
        child: Text(
          subtitleText.toString(),
          style: const TextStyle(fontSize: 18),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
