import 'package:flutter/material.dart';

import '../../models/overlay_snapshot.dart';
import '../../services/settings_service.dart';
import 'overlay_window_shared.dart';

/// 悬浮窗底部导航条与快捷键提示区。
class OverlayFooter extends StatelessWidget {
  final bool hasMap;
  final OverlayGrenadeItem? currentGrenade;
  final int clusterIndex;
  final int clusterTotal;
  final int currentStepIndex;
  final Map<HotkeyAction, HotkeyConfig> hotkeys;
  final VoidCallback onPrevGrenade;
  final VoidCallback onNextGrenade;
  final VoidCallback onPrevStep;
  final VoidCallback onNextStep;

  const OverlayFooter({
    super.key,
    required this.hasMap,
    required this.currentGrenade,
    required this.clusterIndex,
    required this.clusterTotal,
    required this.currentStepIndex,
    required this.hotkeys,
    required this.onPrevGrenade,
    required this.onNextGrenade,
    required this.onPrevStep,
    required this.onNextStep,
  });

  @override
  Widget build(BuildContext context) {
    if (!hasMap || currentGrenade == null) {
      return Container(
        height: 60,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          borderRadius:
              const BorderRadius.vertical(bottom: Radius.circular(14)),
        ),
        child: Center(
          child: Text(
            buildOverlayHotkeySummaryText(hotkeys, includeFilterKeys: false),
            style: const TextStyle(color: Colors.grey, fontSize: 11),
          ),
        ),
      );
    }

    final steps = currentGrenade!.steps;
    final currentStep =
        currentStepIndex < steps.length ? steps[currentStepIndex] : null;
    final stepTitle = currentStep?.title ?? '';
    final stepLabel = stepTitle.isEmpty ? '步骤' : stepTitle;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _OverlayNavStepper(
                text: '道具 ${clusterIndex + 1}/$clusterTotal',
                onPrev: onPrevGrenade,
                onNext: onNextGrenade,
                color: Colors.orange,
              ),
              _OverlayNavStepper(
                text: '$stepLabel ${currentStepIndex + 1}/${steps.length}',
                onPrev: onPrevStep,
                onNext: onNextStep,
                color: Colors.blue,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  buildOverlayHotkeySummaryText(
                    hotkeys,
                    includeFilterKeys: true,
                  ),
                  style: TextStyle(color: Colors.grey[600], fontSize: 10),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OverlayNavStepper extends StatelessWidget {
  final String text;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final Color color;

  const _OverlayNavStepper({
    required this.text,
    required this.onPrev,
    required this.onNext,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left, size: 22),
          color: color,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          onPressed: onPrev,
        ),
        Text(
          text,
          style: const TextStyle(color: Colors.white, fontSize: 13),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right, size: 22),
          color: color,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          onPressed: onNext,
        ),
      ],
    );
  }
}
