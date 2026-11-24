import 'package:flutter/material.dart';

import '../../services/data_service.dart';

/// 导出页面底部体积估算与操作栏
class ExportBottomActionBar extends StatelessWidget {
  final bool enabled;
  final int selectedCount;
  final bool isExporting;
  final bool isEstimating;
  final ExportPackageEstimate? exportEstimate;
  final String? estimateError;
  final VoidCallback onExport;

  const ExportBottomActionBar({
    super.key,
    required this.enabled,
    required this.selectedCount,
    required this.isExporting,
    required this.isEstimating,
    required this.exportEstimate,
    required this.estimateError,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    final isOverLimit = exportEstimate?.exceedsLimit ?? false;
    final buttonEnabled =
        enabled && !isExporting && !isEstimating && !isOverLimit;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (enabled) _buildEstimateHint(),
          if (enabled) const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: buttonEnabled ? onExport : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                disabledBackgroundColor: Colors.grey,
              ),
              child: isExporting
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      '分享 ($selectedCount 个道具)',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEstimateHint() {
    if (isEstimating) {
      return Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text(
            '正在估算导出包体...',
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
        ],
      );
    }

    if (estimateError != null) {
      return Text(
        estimateError!,
        style: TextStyle(color: Colors.orange[700], fontSize: 12),
      );
    }

    final estimate = exportEstimate;
    if (estimate == null) {
      return Text(
        '选择道具后将显示预计导出包体',
        style: TextStyle(color: Colors.grey[600], fontSize: 12),
      );
    }

    final infoColor =
        estimate.exceedsLimit ? Colors.red[700] : Colors.grey[700];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '预计导出包体 ${DataService.formatBytes(estimate.estimatedPackageBytes)}'
          ' / 上限 ${DataService.formatBytes(estimate.limitBytes)}',
          style: TextStyle(
            color: infoColor,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '包含 ${estimate.mediaFileCount} 个媒体文件，体积为预估值，实际结果可能略有波动',
          style: TextStyle(color: Colors.grey[600], fontSize: 12),
        ),
        if (estimate.exceedsLimit) ...[
          const SizedBox(height: 4),
          Text(
            '已超过导出上限，请减少媒体文件或分批导出',
            style: TextStyle(color: Colors.red[700], fontSize: 12),
          ),
        ],
      ],
    );
  }
}
