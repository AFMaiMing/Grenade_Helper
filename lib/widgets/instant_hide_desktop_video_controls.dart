// ignore_for_file: implementation_imports

import 'dart:async';

import 'package:chewie/src/chewie_player.dart';
import 'package:chewie/src/helpers/utils.dart';
import 'package:chewie/src/material/widgets/options_dialog.dart';
import 'package:chewie/src/material/widgets/playback_speed_dialog.dart';
import 'package:chewie/src/models/option_item.dart';
import 'package:chewie/src/notifiers/index.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import 'video_controls/desktop_video_bottom_bar.dart';
import 'video_controls/desktop_video_overlays.dart';

/// 开始播放时立即隐藏上下控制栏的定制桌面视频控件。
class InstantHideDesktopVideoControls extends StatefulWidget {
  const InstantHideDesktopVideoControls({
    this.showPlayButton = true,
    super.key,
  });

  final bool showPlayButton;

  @override
  State<StatefulWidget> createState() {
    return _InstantHideDesktopVideoControlsState();
  }
}

class _InstantHideDesktopVideoControlsState
    extends State<InstantHideDesktopVideoControls>
    with SingleTickerProviderStateMixin {
  static const double _barHeight = 48.0 * 1.5;
  static const double _marginSize = 5.0;

  late PlayerNotifier notifier;
  late VideoPlayerValue _latestValue;
  double? _latestVolume;
  Timer? _hideTimer;
  Timer? _initTimer;
  Duration _subtitlesPosition = Duration.zero;
  bool _subtitleOn = false;
  Timer? _showAfterExpandCollapseTimer;
  bool _dragging = false;
  bool _displayTapped = false;
  Timer? _bufferingDisplayTimer;
  bool _displayBufferingIndicator = false;
  bool _wasPlaying = false;

  late VideoPlayerController controller;
  ChewieController? _chewieController;
  late final FocusNode _focusNode;

  ChewieController get chewieController => _chewieController!;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.requestFocus();
    notifier = Provider.of<PlayerNotifier>(context, listen: false);
  }

  @override
  void didChangeDependencies() {
    final oldController = _chewieController;
    _chewieController = ChewieController.of(context);
    controller = chewieController.videoPlayerController;

    if (oldController != chewieController) {
      _dispose();
      _initialize();
    }

    super.didChangeDependencies();
  }

  @override
  void dispose() {
    _dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _dispose() {
    controller.removeListener(_updateState);
    _hideTimer?.cancel();
    _initTimer?.cancel();
    _showAfterExpandCollapseTimer?.cancel();
  }

  void _handleKeyPress(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.space:
        _playPause();
      case LogicalKeyboardKey.arrowRight:
        _seekRelative(const Duration(seconds: 10));
      case LogicalKeyboardKey.arrowLeft:
        _seekRelative(const Duration(seconds: -10));
      case LogicalKeyboardKey.escape:
        if (chewieController.isFullScreen) {
          _onExpandCollapse();
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_latestValue.hasError) {
      return chewieController.errorBuilder?.call(
            context,
            chewieController.videoPlayerController.value.errorDescription!,
          ) ??
          const Center(child: Icon(Icons.error, color: Colors.white, size: 42));
    }

    final isFinished = _latestValue.position >= _latestValue.duration &&
        _latestValue.duration.inSeconds > 0;
    final showPlayButton =
        widget.showPlayButton && !_dragging && !notifier.hideStuff;

    return KeyboardListener(
      focusNode: _focusNode,
      onKeyEvent: _handleKeyPress,
      child: MouseRegion(
        onHover: (_) {
          _focusNode.requestFocus();
          _cancelAndRestartTimer();
        },
        child: GestureDetector(
          onTap: () {
            final wasPlaying = controller.value.isPlaying;
            _playPause();
            if (wasPlaying) {
              _cancelAndRestartTimer();
            }
          },
          child: AbsorbPointer(
            absorbing: notifier.hideStuff,
            child: Stack(
              children: [
                if (_displayBufferingIndicator)
                  _chewieController?.bufferingBuilder?.call(context) ??
                      const Center(child: CircularProgressIndicator())
                else
                  DesktopVideoHitArea(
                    isPlaying: controller.value.isPlaying,
                    isFinished: isFinished,
                    showPlayButton: showPlayButton,
                    onTap: _onHitAreaTap,
                    onPressed: _playPause,
                  ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    if (_subtitleOn)
                      Transform.translate(
                        offset: Offset(
                          0.0,
                          notifier.hideStuff ? _barHeight * 0.8 : 0.0,
                        ),
                        child: DesktopVideoSubtitleOverlay(
                          subtitles: chewieController.subtitle!,
                          position: _subtitlesPosition,
                          marginSize: _marginSize,
                          subtitleBuilder: chewieController.subtitleBuilder,
                        ),
                      ),
                    DesktopVideoBottomBar(
                      barHeight: _barHeight,
                      hideStuff: notifier.hideStuff,
                      chewieController: chewieController,
                      controller: controller,
                      latestValue: _latestValue,
                      subtitleOn: _subtitleOn,
                      onPlayPause: _playPause,
                      onToggleMute: _onToggleMute,
                      onToggleSubtitle: _onSubtitleTap,
                      onOpenOptions: _onOpenOptions,
                      onExpandCollapse: _onExpandCollapse,
                      onDragStart: () {
                        setState(() => _dragging = true);
                        _hideTimer?.cancel();
                      },
                      onDragUpdate: () => _hideTimer?.cancel(),
                      onDragEnd: () {
                        setState(() => _dragging = false);
                        _startHideTimer();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onHitAreaTap() {
    if (!_latestValue.isPlaying) {
      _playPause();
      setState(() => notifier.hideStuff = true);
      return;
    }
    if (_chewieController?.pauseOnBackgroundTap ?? false) {
      _playPause();
      _cancelAndRestartTimer();
      return;
    }
    if (_displayTapped) {
      setState(() => notifier.hideStuff = true);
    } else {
      _cancelAndRestartTimer();
    }
  }

  void _onToggleMute() {
    _cancelAndRestartTimer();
    if (_latestValue.volume == 0) {
      controller.setVolume(_latestVolume ?? 0.5);
    } else {
      _latestVolume = controller.value.volume;
      controller.setVolume(0.0);
    }
  }

  void _onSubtitleTap() {
    setState(() => _subtitleOn = !_subtitleOn);
  }

  Future<void> _onOpenOptions() async {
    final options = <OptionItem>[
      OptionItem(
        onTap: (context) async {
          Navigator.pop(context);
          _onSpeedButtonTap();
        },
        iconData: Icons.speed,
        title: chewieController.optionsTranslation?.playbackSpeedButtonText ??
            'Playback speed',
      ),
    ];

    final extraOptions = chewieController.additionalOptions?.call(context);
    if (extraOptions != null && extraOptions.isNotEmpty) {
      options.addAll(extraOptions);
    }

    _hideTimer?.cancel();
    if (chewieController.optionsBuilder != null) {
      await chewieController.optionsBuilder!(context, options);
    } else {
      await showModalBottomSheet<OptionItem>(
        context: context,
        isScrollControlled: true,
        useRootNavigator: chewieController.useRootNavigator,
        builder: (context) => OptionsDialog(
          options: options,
          cancelButtonText:
              chewieController.optionsTranslation?.cancelButtonText,
        ),
      );
    }

    if (_latestValue.isPlaying) {
      _startHideTimer();
    }
  }

  Future<void> _onSpeedButtonTap() async {
    _hideTimer?.cancel();

    final chosenSpeed = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: chewieController.useRootNavigator,
      builder: (context) => PlaybackSpeedDialog(
        speeds: chewieController.playbackSpeeds,
        selected: _latestValue.playbackSpeed,
      ),
    );

    if (chosenSpeed != null) {
      controller.setPlaybackSpeed(chosenSpeed);
    }

    if (_latestValue.isPlaying) {
      _startHideTimer();
    }
  }

  void _cancelAndRestartTimer() {
    _hideTimer?.cancel();
    _startHideTimer();

    setState(() {
      notifier.hideStuff = false;
      _displayTapped = true;
    });
  }

  Future<void> _initialize() async {
    _subtitleOn = chewieController.showSubtitles &&
        (chewieController.subtitle?.isNotEmpty ?? false);
    _wasPlaying = controller.value.isPlaying;
    controller.addListener(_updateState);

    _updateState();

    if (controller.value.isPlaying || chewieController.autoPlay) {
      notifier.hideStuff = true;
      _hideTimer?.cancel();
    }

    if (chewieController.showControlsOnInitialize) {
      _initTimer = Timer(const Duration(milliseconds: 200), () {
        if (!mounted || controller.value.isPlaying) return;
        setState(() => notifier.hideStuff = false);
      });
    }
  }

  void _onExpandCollapse() {
    setState(() => notifier.hideStuff = true);
    chewieController.toggleFullScreen();

    _showAfterExpandCollapseTimer = Timer(
      const Duration(milliseconds: 300),
      () => setState(_cancelAndRestartTimer),
    );
  }

  void _playPause() {
    if (controller.value.isPlaying) {
      setState(() => notifier.hideStuff = false);
      _hideTimer?.cancel();
      controller.pause();
      return;
    }

    _hideTimer?.cancel();
    setState(() {
      notifier.hideStuff = true;
      _displayTapped = false;
    });

    if (!controller.value.isInitialized) {
      controller.initialize().then((_) {
        if (!mounted) return;
        controller.play();
      });
    } else {
      controller.play();
    }
  }

  void _startHideTimer() {
    final hideControlsTimer = chewieController.hideControlsTimer.isNegative
        ? ChewieController.defaultHideControlsTimer
        : chewieController.hideControlsTimer;
    _hideTimer = Timer(hideControlsTimer, () {
      setState(() => notifier.hideStuff = true);
    });
  }

  void _bufferingTimerTimeout() {
    _displayBufferingIndicator = true;
    if (mounted) {
      setState(() {});
    }
  }

  void _updateState() {
    if (!mounted) return;

    final buffering = getIsBuffering(controller);
    final isPlaying = controller.value.isPlaying;
    final startedPlaying = !_wasPlaying && isPlaying;

    if (chewieController.progressIndicatorDelay != null) {
      if (buffering) {
        _bufferingDisplayTimer ??= Timer(
          chewieController.progressIndicatorDelay!,
          _bufferingTimerTimeout,
        );
      } else {
        _bufferingDisplayTimer?.cancel();
        _bufferingDisplayTimer = null;
        _displayBufferingIndicator = false;
      }
    } else {
      _displayBufferingIndicator = buffering;
    }

    _wasPlaying = isPlaying;

    setState(() {
      _latestValue = controller.value;
      _subtitlesPosition = controller.value.position;
      // 刚起播时立即隐藏控制栏，避免桌面端停留遮挡画面。
      if (startedPlaying) {
        notifier.hideStuff = true;
      }
    });
  }

  void _seekRelative(Duration relativeSeek) {
    _cancelAndRestartTimer();
    final position = _latestValue.position + relativeSeek;
    final duration = _latestValue.duration;

    if (position < Duration.zero) {
      controller.seekTo(Duration.zero);
    } else if (position > duration) {
      controller.seekTo(duration);
    } else {
      controller.seekTo(position);
    }
  }
}
