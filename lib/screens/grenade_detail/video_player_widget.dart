import 'dart:async';
import 'dart:io';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../services/media_handle_service.dart';
import '../../services/settings_service.dart';
import '../../widgets/instant_hide_desktop_video_controls.dart';

/// 道具与悬浮窗共用的视频播放组件。
class VideoPlayerWidget extends StatefulWidget {
  final File file;

  const VideoPlayerWidget({super.key, required this.file});

  @override
  State<VideoPlayerWidget> createState() => VideoPlayerWidgetState();
}

/// 视频播放组件状态，向外部暴露播放控制并接入文件句柄释放服务。
class VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  String? _errorMessage;
  int _initGeneration = 0;
  Future<void>? _initFuture;
  bool _released = false;

  @override
  void initState() {
    super.initState();
    MediaHandleService.register(this, widget.file.path, _releaseForDeletion);
    _initFuture = _initVideo();
  }

  @override
  void didUpdateWidget(covariant VideoPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.path != widget.file.path) {
      _released = false;
      _errorMessage = null;
      _initGeneration++;
      MediaHandleService.register(this, widget.file.path, _releaseForDeletion);
      final previousInit = _initFuture;
      _initFuture = _switchVideo(previousInit);
    }
  }

  Future<void> _switchVideo(Future<void>? previousInit) async {
    if (previousInit != null) {
      try {
        await previousInit;
      } catch (_) {}
    }
    await _disposeControllersAsync();
    if (!mounted || _released) return;
    await _initVideo();
  }

  Future<void> _disposeControllersAsync() async {
    final chewie = _chewieController;
    final video = _videoController;
    _chewieController = null;
    _videoController = null;
    chewie?.dispose();
    if (video != null) {
      await video.dispose();
    }
  }

  Future<void> _releaseForDeletion() async {
    _released = true;
    _initGeneration++;
    final pendingInit = _initFuture;
    if (pendingInit != null) {
      try {
        await pendingInit;
      } catch (_) {}
    }
    await _disposeControllersAsync();
    if (mounted) setState(() {});
  }

  Future<void> _initVideo() async {
    final generation = ++_initGeneration;
    VideoPlayerController? controller;
    try {
      controller = VideoPlayerController.file(widget.file);
      await controller.initialize();
      if (!mounted || _released || generation != _initGeneration) {
        await controller.dispose();
        return;
      }
      _videoController = controller;
      _chewieController = ChewieController(
        videoPlayerController: controller,
        autoPlay: false,
        looping: true,
        allowMuting: true,
        aspectRatio: controller.value.aspectRatio,
        customControls: SettingsService.isDesktop
            ? const InstantHideDesktopVideoControls()
            : null,
        errorBuilder: (context, errorMessage) {
          return Center(
            child: Text(
              errorMessage,
              style: const TextStyle(color: Colors.white),
            ),
          );
        },
      );
      setState(() {});
    } catch (e) {
      await controller?.dispose();
      if (!mounted || _released || generation != _initGeneration) return;
      _errorMessage = e.toString();
      setState(() {});
    }
  }

  /// 切换视频播放或暂停状态。
  void togglePlayPause() {
    if (_videoController == null || !_videoController!.value.isInitialized) {
      return;
    }
    if (_videoController!.value.isPlaying) {
      _videoController!.pause();
    } else {
      _videoController!.play();
    }
  }

  /// 若视频正在播放则暂停。
  Future<void> pauseIfPlaying() async {
    if (_videoController == null || !_videoController!.value.isInitialized) {
      return;
    }
    if (_videoController!.value.isPlaying) {
      await _videoController!.pause();
    }
  }

  @override
  void dispose() {
    MediaHandleService.unregister(this);
    _initGeneration++;
    unawaited(_disposeControllersAsync());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_released) {
      return Container(color: Colors.black, height: 200);
    }
    if (_errorMessage != null) {
      return Container(
        color: Colors.black,
        height: 200,
        child: Center(
          child: Text(
            _errorMessage!,
            style: const TextStyle(color: Colors.red),
          ),
        ),
      );
    }
    if (_chewieController == null) {
      return Container(
        color: Colors.black,
        height: 200,
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    return AspectRatio(
      aspectRatio: _videoController!.value.aspectRatio,
      child: Chewie(controller: _chewieController!),
    );
  }
}
