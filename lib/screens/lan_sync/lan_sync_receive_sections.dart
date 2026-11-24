import 'package:flutter/material.dart';

import '../../services/lan_sync/lan_sync_receive_controller.dart';
import 'lan_sync_shared.dart';

/// 展示收到传入传输请求的确认弹窗
Future<bool?> showLanIncomingTransferApprovalDialog(
  BuildContext context,
  LanIncomingTransferRequest req,
) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('收到传输请求'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('文件：${req.fileName}'),
          Text('大小：${formatLanBytes(req.sizeBytes)}'),
          if (req.senderName.isNotEmpty) Text('发送方：${req.senderName}'),
          Text('模式：${req.syncMode == "delta" ? "增量" : "全量"}'),
          if (req.scopeSummary.isNotEmpty) Text('范围：${req.scopeSummary}'),
          if (req.scopeMapKeys.isNotEmpty)
            Text('地图：${req.scopeMapKeys.join("、")}'),
          if (req.remoteAddress != null) Text('来源IP：${req.remoteAddress}'),
          const SizedBox(height: 8),
          const Text('是否允许对方开始传输？'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('拒绝'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('同意'),
        ),
      ],
    ),
  );
}

/// 局域网同步接收配置与待审批请求分区
class LanSyncReceiveSection extends StatelessWidget {
  final LanSyncReceiveController receiveController;
  final bool silentImportEnabled;
  final VoidCallback onRefreshLocalIps;
  final ValueChanged<bool> onToggleReceiveMode;
  final ValueChanged<bool> onSetSilentImportEnabled;
  final ValueChanged<String> onRejectIncomingRequest;
  final ValueChanged<String> onApproveIncomingRequest;

  const LanSyncReceiveSection({
    super.key,
    required this.receiveController,
    required this.silentImportEnabled,
    required this.onRefreshLocalIps,
    required this.onToggleReceiveMode,
    required this.onSetSilentImportEnabled,
    required this.onRejectIncomingRequest,
    required this.onApproveIncomingRequest,
  });

  @override
  Widget build(BuildContext context) {
    final pendingIncomingRequests = receiveController.incomingRequests
        .where((e) => e.status == LanIncomingTransferRequestStatus.pending)
        .toList(growable: false);

    return LanSectionCard(
      icon: Icons.download,
      title: '接收',
      action: TextButton.icon(
        onPressed: receiveController.isStarting ? null : onRefreshLocalIps,
        icon: const Icon(Icons.refresh),
        label: const Text('刷新地址'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            value: receiveController.isRunning,
            contentPadding: EdgeInsets.zero,
            title: const Text('接收模式'),
            subtitle:
                receiveController.isStarting ? const Text('正在启动...') : null,
            onChanged:
                receiveController.isStarting ? null : onToggleReceiveMode,
          ),
          SwitchListTile(
            value: silentImportEnabled,
            contentPadding: EdgeInsets.zero,
            title: const Text('静默导入'),
            subtitle: const Text('接收后跳过预览自动导入，发生冲突时会弹窗确认'),
            onChanged: onSetSilentImportEnabled,
          ),
          if (pendingIncomingRequests.isNotEmpty) ...[
            Text(
              '待确认请求（${pendingIncomingRequests.length}）',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            ...pendingIncomingRequests.take(4).map(
                  (req) => _PendingIncomingRequestCard(
                    request: req,
                    onReject: () => onRejectIncomingRequest(req.id),
                    onApprove: () => onApproveIncomingRequest(req.id),
                  ),
                ),
            const SizedBox(height: 8),
          ],
          LanReceiveEndpointPanel(receiveController: receiveController),
        ],
      ),
    );
  }
}

/// 本机局域网接收端点信息面板
class LanReceiveEndpointPanel extends StatelessWidget {
  final LanSyncReceiveController receiveController;

  const LanReceiveEndpointPanel({super.key, required this.receiveController});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final running = receiveController.isRunning;
    final port = receiveController.port;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            running ? '接收服务已启动' : '接收服务未启动',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: running ? Colors.green : colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          if (running && port != null) ...[
            Text(
              '本机名称：${receiveController.localDeviceName}',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Text(
              '本机地址：',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            if (receiveController.localIps.isEmpty)
              Text(
                '未获取到局域网 IP（可点击右上角刷新）',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: receiveController.localIps
                    .map((ip) => Chip(label: Text('http://$ip:$port')))
                    .toList(),
              ),
          ] else
            Text(
              '开启接收模式后，本页会显示本机端口与可访问地址。',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          if (receiveController.lastError != null) ...[
            const SizedBox(height: 8),
            Text(
              receiveController.lastError!,
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _PendingIncomingRequestCard extends StatelessWidget {
  final LanIncomingTransferRequest request;
  final VoidCallback onReject;
  final VoidCallback onApprove;

  const _PendingIncomingRequestCard({
    required this.request,
    required this.onReject,
    required this.onApprove,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              request.fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              '${formatLanBytes(request.sizeBytes)}'
              ' · ${request.syncMode == "delta" ? "增量" : "全量"}'
              '${request.scopeSummary.isEmpty ? '' : ' · ${request.scopeSummary}'}'
              '${request.senderName.isEmpty ? '' : ' · ${request.senderName}'}',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                TextButton(onPressed: onReject, child: const Text('拒绝')),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: onApprove,
                  child: const Text('同意'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
