import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../models.dart';
import '../models/overlay_snapshot.dart';
import '../services/overlay_state_service.dart';
import '../services/settings_service.dart';
import 'grenade_detail_screen.dart' show VideoPlayerWidgetState;
import 'overlay/overlay_footer.dart';
import 'overlay/overlay_hotkey_helper.dart';
import 'overlay/overlay_media_preview.dart';
import 'overlay/overlay_radar_and_prompts.dart';
import 'overlay/overlay_title_bar.dart';

/// 悬浮窗主组件。
class OverlayWindow extends StatefulWidget {
  final Map<HotkeyAction, HotkeyConfig> initialHotkeys;
  final OverlayStateService overlayState;
  final bool isVisible;
  final AsyncCallback onClose;
  final AsyncCallback onMinimize;
  final VoidCallback onStartDrag;

  const OverlayWindow({
    super.key,
    required this.initialHotkeys,
    required this.overlayState,
    this.isVisible = true,
    required this.onClose,
    required this.onMinimize,
    required this.onStartDrag,
  });

  @override
  State<OverlayWindow> createState() => OverlayWindowState();
}

class OverlayWindowState extends State<OverlayWindow> {
  final FocusNode _focusNode = FocusNode();
  late Map<HotkeyAction, HotkeyConfig> _hotkeys;
  final GlobalKey<VideoPlayerWidgetState> _videoPlayerKey = GlobalKey();
  final ScrollController _scrollController = ScrollController();
  bool _isMediaFullscreenPreview = false;
  bool _isTogglingMediaFullscreenPreview = false;
  Rect? _normalWindowBoundsBeforePreview;

  @override
  void initState() {
    super.initState();
    _hotkeys = Map<HotkeyAction, HotkeyConfig>.from(widget.initialHotkeys);
    widget.overlayState.addListener(_onStateChanged);
    widget.overlayState.setVideoTogglePlayPauseCallback(_handleVideoToggle);
  }

  void _handleVideoToggle() {
    _videoPlayerKey.currentState?.togglePlayPause();
  }

  void _onStateChanged() {
    if (mounted && widget.isVisible) setState(() {});
  }

  void reloadHotkeys(Map<HotkeyAction, HotkeyConfig> newHotkeys) {
    setState(() {
      _hotkeys = Map<HotkeyAction, HotkeyConfig>.from(newHotkeys);
    });
  }

  @override
  void dispose() {
    widget.overlayState.setVideoTogglePlayPauseCallback(null);
    widget.overlayState.removeListener(_onStateChanged);
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Offset? get persistedWindowPosition {
    if (_isMediaFullscreenPreview && _normalWindowBoundsBeforePreview != null) {
      return _normalWindowBoundsBeforePreview!.topLeft;
    }
    return null;
  }

  bool get blocksDirectionalNavigation => _isMediaFullscreenPreview;

  Future<void> pauseActiveVideoPlayback() async {
    await _videoPlayerKey.currentState?.pauseIfPlaying();
  }

  Future<void> exitFullscreenPreviewIfNeeded() async {
    if (_isMediaFullscreenPreview) {
      await toggleMediaFullscreenPreview();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isVisible) {
      return const TickerMode(enabled: false, child: SizedBox.shrink());
    }
    final state = widget.overlayState;
    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Material(
        color: Colors.transparent,
        child: _isMediaFullscreenPreview
            ? OverlayFullscreenPreview(
                overlayState: state,
                hotkeys: _hotkeys,
                medias: _getCurrentStepMedias(),
                videoPlayerKey: _videoPlayerKey,
                scrollController: _scrollController,
                onToggleFullscreen: () =>
                    unawaited(toggleMediaFullscreenPreview()),
              )
            : Opacity(
                opacity: state.overlayOpacity,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B1E23),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.orange.withValues(alpha: 0.5),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      OverlayTitleBar(
                        mapName: state.mapName ?? '未选择地图',
                        grenadeTitle: state.currentGrenade?.title ?? '',
                        navSpeedLevel: state.navSpeedLevel,
                        activeFilters: state.activeFilters,
                        hotkeys: _hotkeys,
                        onStartDrag: widget.onStartDrag,
                        onClose: () => unawaited(widget.onClose()),
                        onToggleFilter: state.toggleFilter,
                      ),
                      Expanded(child: _buildContent()),
                      OverlayFooter(
                        hasMap: state.hasMap,
                        currentGrenade: state.currentGrenade,
                        clusterIndex: state.currentClusterIndex,
                        clusterTotal: state.currentClusterGrenades.length,
                        currentStepIndex: state.currentStepIndex,
                        hotkeys: _hotkeys,
                        onPrevGrenade: state.prevGrenade,
                        onNextGrenade: state.nextGrenade,
                        onPrevStep: state.prevStep,
                        onNextStep: state.nextStep,
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildContent() {
    final state = widget.overlayState;
    if (!state.hasMap) {
      return const OverlayEmptyPrompt.noMap();
    }
    if (state.filteredGrenades.isEmpty) {
      return const OverlayEmptyPrompt.noGrenade();
    }

    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          OverlayRadarMap(overlayState: state),
          const SizedBox(height: 16),
          if (state.isSnapConfirmed && state.currentGrenade != null) ...[
            OverlayMediaArea(
              medias: _getCurrentStepMedias(),
              isFullscreenPreview: _isMediaFullscreenPreview,
              videoPlayerKey: _videoPlayerKey,
            ),
            const SizedBox(height: 12),
            OverlayStepDescription(
              grenade: state.currentGrenade,
              currentStepIndex: state.currentStepIndex,
            ),
          ] else
            const OverlayNavigationHint(),
        ],
      ),
    );
  }

  void _handleKeyEvent(KeyEvent event) {
    if (Platform.isWindows) return;
    final key = event.logicalKey;
    if (isOverlayModifierKey(key)) return;

    final navDirection = resolveOverlayNavigationDirection(_hotkeys, key);
    if (navDirection != null) {
      if (_isMediaFullscreenPreview) return;
      if (event is KeyDownEvent) {
        widget.overlayState.startNavigation(navDirection);
      } else if (event is KeyUpEvent) {
        widget.overlayState.stopNavigation(navDirection);
      }
      return;
    }

    if (event is! KeyDownEvent) return;
    final action = resolveOverlayKeyDownAction(event, _hotkeys);
    if (action != null) {
      _executeAction(action);
    }
  }

  void _executeAction(HotkeyAction action) {
    final state = widget.overlayState;

    switch (action) {
      case HotkeyAction.hideOverlay:
      case HotkeyAction.toggleOverlay:
        unawaited(widget.onClose());
      case HotkeyAction.navigateUp:
        if (!_isMediaFullscreenPreview) {
          state.navigateDirection(NavigationDirection.up);
        }
      case HotkeyAction.navigateDown:
        if (!_isMediaFullscreenPreview) {
          state.navigateDirection(NavigationDirection.down);
        }
      case HotkeyAction.navigateLeft:
        if (!_isMediaFullscreenPreview) {
          state.navigateDirection(NavigationDirection.left);
        }
      case HotkeyAction.navigateRight:
        if (!_isMediaFullscreenPreview) {
          state.navigateDirection(NavigationDirection.right);
        }
      case HotkeyAction.prevGrenade:
        state.prevGrenade();
      case HotkeyAction.nextGrenade:
        state.nextGrenade();
      case HotkeyAction.prevStep:
        state.prevStep();
      case HotkeyAction.nextStep:
        state.nextStep();
      case HotkeyAction.toggleSmoke:
        state.toggleFilter(GrenadeType.smoke);
      case HotkeyAction.toggleFlash:
        state.toggleFilter(GrenadeType.flash);
      case HotkeyAction.toggleMolotov:
        state.toggleFilter(GrenadeType.molotov);
      case HotkeyAction.toggleHE:
        state.toggleFilter(GrenadeType.he);
      case HotkeyAction.toggleWallbang:
        state.toggleFilter(GrenadeType.wallbang);
      case HotkeyAction.togglePlayPause:
        _handleVideoToggle();
      case HotkeyAction.toggleMediaFullscreenPreview:
        unawaited(toggleMediaFullscreenPreview());
      case HotkeyAction.increaseNavSpeed:
        state.increaseNavSpeed();
      case HotkeyAction.decreaseNavSpeed:
        state.decreaseNavSpeed();
      case HotkeyAction.scrollUp:
        scrollContent(-300);
      case HotkeyAction.scrollDown:
        scrollContent(300);
    }
  }

  /// 滚动内容区域（公开方法，供 IPC 调用）。
  void scrollContent(double delta) {
    if (!_scrollController.hasClients) return;
    final newOffset = (_scrollController.offset + delta).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.animateTo(
      newOffset,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
    );
  }

  List<OverlayMediaItem>? _getCurrentStepMedias() {
    final state = widget.overlayState;
    final grenade = state.currentGrenade;
    if (grenade == null) return null;

    final steps = grenade.steps;
    if (steps.isEmpty) return null;

    final currentStep = state.currentStepIndex < steps.length
        ? steps[state.currentStepIndex]
        : steps.first;

    return currentStep.medias;
  }

  Future<void> toggleMediaFullscreenPreview() async {
    if (_isTogglingMediaFullscreenPreview) return;

    final medias = _getCurrentStepMedias();
    if (!_isMediaFullscreenPreview && (medias == null || medias.isEmpty)) {
      return;
    }

    _isTogglingMediaFullscreenPreview = true;
    try {
      if (_isMediaFullscreenPreview) {
        final restoreBounds = _normalWindowBoundsBeforePreview;
        widget.overlayState.setNavigationLocked(false);
        await windowManager.setFullScreen(false);
        if (restoreBounds != null) {
          await windowManager.setBounds(restoreBounds);
        }
        if (!mounted) return;
        setState(() {
          _isMediaFullscreenPreview = false;
          _normalWindowBoundsBeforePreview = null;
        });
        return;
      }

      _normalWindowBoundsBeforePreview ??= await windowManager.getBounds();
      widget.overlayState.setNavigationLocked(true);
      await windowManager.setFullScreen(true);

      if (!mounted) return;
      setState(() {
        _isMediaFullscreenPreview = true;
      });
    } catch (e) {
      debugPrint(
        '[OverlayWindow] Failed to toggle media fullscreen preview: $e',
      );
    } finally {
      _isTogglingMediaFullscreenPreview = false;
    }
  }
}
