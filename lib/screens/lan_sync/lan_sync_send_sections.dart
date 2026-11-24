import 'package:flutter/material.dart';

import '../../models.dart';
import '../../services/lan_sync/lan_sync_discovery_service.dart';
import 'lan_sync_shared.dart';

/// 局域网手动输入发送目标弹窗
Future<(String, int)?> showLanManualSendDialog(
  BuildContext context, {
  required String initialHost,
  required String initialPort,
}) async {
  final hostController = TextEditingController(text: initialHost);
  final portController = TextEditingController(
    text: initialPort.isEmpty ? '39527' : initialPort,
  );
  try {
    return await showDialog<(String, int)>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('手动输入IP地址和端口'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: hostController,
              decoration: const InputDecoration(labelText: 'IP / 主机'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: portController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '端口'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final host = hostController.text.trim();
              final port = int.tryParse(portController.text.trim());
              if (host.isEmpty || port == null || port <= 0 || port > 65535) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('请输入有效的 IP 和端口')));
                return;
              }
              Navigator.pop(ctx, (host, port));
            },
            child: const Text('连接并发送'),
          ),
        ],
      ),
    );
  } finally {
    hostController.dispose();
    portController.dispose();
  }
}

/// 局域网发送按地图选择弹窗
Future<GameMap?> showLanMapPickerDialog(
  BuildContext context,
  List<GameMap> maps,
) {
  return showDialog<GameMap>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('选择地图'),
      children: maps
          .map(
            (m) => SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, m),
              child: Text(m.name),
            ),
          )
          .toList(),
    ),
  );
}

/// 展示全量与增量同步模式说明弹窗
Future<void> showLanSendModeHelpDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('同步模式说明'),
      content: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('全量模式', style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(height: 4),
          Text('发送当前范围内的完整数据，适合首次同步或大范围更新。'),
          SizedBox(height: 12),
          Text('增量模式', style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(height: 4),
          Text('发送前会先获取接收端当前状态，再只传输本次真正缺失或较新的内容。'),
          SizedBox(height: 12),
          Text('注意：增量模式暂不支持按道具发送，且要求接收端支持新的 manifest 协议。'),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('我知道了'),
        ),
      ],
    ),
  );
}

/// 局域网同步发送配置与设备扫描分区
class LanSyncSendSection extends StatelessWidget {
  final bool isLoadingLocal;
  final bool isScanningDevices;
  final bool isSendingAll;
  final bool isWaitingForApproval;
  final double? sendProgress;
  final String sendProgressLabel;
  final LanSyncMode sendMode;
  final LanSendScope sendScope;
  final int selectedGrenadesCount;
  final String scopeSummary;
  final List<LanDiscoveryDevice> discoveredDevices;
  final VoidCallback onScanDevices;
  final VoidCallback onShowManualSendDialog;
  final ValueChanged<LanSyncMode> onSendModeChanged;
  final VoidCallback onShowSendModeHelp;
  final ValueChanged<LanSendScope> onSendScopeChanged;
  final VoidCallback onPickMapForSend;
  final VoidCallback onPickGrenadesForSend;
  final void Function(String host, int port) onSendToHostPort;

  const LanSyncSendSection({
    super.key,
    required this.isLoadingLocal,
    required this.isScanningDevices,
    required this.isSendingAll,
    required this.isWaitingForApproval,
    required this.sendProgress,
    required this.sendProgressLabel,
    required this.sendMode,
    required this.sendScope,
    required this.selectedGrenadesCount,
    required this.scopeSummary,
    required this.discoveredDevices,
    required this.onScanDevices,
    required this.onShowManualSendDialog,
    required this.onSendModeChanged,
    required this.onShowSendModeHelp,
    required this.onSendScopeChanged,
    required this.onPickMapForSend,
    required this.onPickGrenadesForSend,
    required this.onSendToHostPort,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return LanSectionCard(
      icon: Icons.upload_file,
      title: '发送',
      action: Wrap(
        spacing: 4,
        children: [
          TextButton.icon(
            onPressed: isScanningDevices ? null : onScanDevices,
            icon: isScanningDevices
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.radar_outlined),
            label: Text(isScanningDevices ? '扫描中' : '扫描'),
          ),
          TextButton.icon(
            onPressed: isSendingAll ? null : onShowManualSendDialog,
            icon: const Icon(Icons.link),
            label: const Text('手动输入'),
          ),
        ],
      ),
      child: isLoadingLocal
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildModeSelector(),
                const SizedBox(height: 8),
                _buildScopeSelector(),
                const SizedBox(height: 8),
                _buildPickerButtons(),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('当前发送范围：$scopeSummary'),
                ),
                if (isSendingAll)
                  ..._buildProgressWidgets(context, colorScheme),
                Text('扫描结果', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                ..._buildDiscoveredDeviceList(colorScheme),
              ],
            ),
    );
  }

  Widget _buildModeSelector() {
    return Row(
      children: [
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('全量'),
                selected: sendMode == LanSyncMode.full,
                onSelected: (_) => onSendModeChanged(LanSyncMode.full),
              ),
              ChoiceChip(
                label: const Text('增量'),
                selected: sendMode == LanSyncMode.incremental,
                onSelected: (_) => onSendModeChanged(LanSyncMode.incremental),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: onShowSendModeHelp,
          tooltip: '同步模式说明',
          icon: const Icon(Icons.help_outline),
        ),
      ],
    );
  }

  Widget _buildScopeSelector() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ChoiceChip(
          label: const Text('全部'),
          selected: sendScope == LanSendScope.all,
          onSelected: (_) => onSendScopeChanged(LanSendScope.all),
        ),
        ChoiceChip(
          label: const Text('按地图'),
          selected: sendScope == LanSendScope.map,
          onSelected: (_) => onSendScopeChanged(LanSendScope.map),
        ),
        if (sendMode != LanSyncMode.incremental)
          ChoiceChip(
            label: const Text('按道具'),
            selected: sendScope == LanSendScope.grenades,
            onSelected: (_) => onSendScopeChanged(LanSendScope.grenades),
          ),
      ],
    );
  }

  Widget _buildPickerButtons() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: onPickMapForSend,
          icon: const Icon(Icons.map_outlined),
          label: const Text('选择地图'),
        ),
        if (sendMode != LanSyncMode.incremental)
          OutlinedButton.icon(
            onPressed: onPickGrenadesForSend,
            icon: const Icon(Icons.list_alt),
            label: Text(
              selectedGrenadesCount == 0
                  ? '选择道具'
                  : '已选 $selectedGrenadesCount 个道具',
            ),
          ),
      ],
    );
  }

  List<Widget> _buildProgressWidgets(
    BuildContext context,
    ColorScheme colorScheme,
  ) {
    return [
      const SizedBox(height: 10),
      LinearProgressIndicator(
        value: isWaitingForApproval ? null : sendProgress,
      ),
      const SizedBox(height: 6),
      Text(
        sendProgressLabel.isEmpty
            ? (isWaitingForApproval ? '等待接收方确认...' : '准备传输...')
            : sendProgressLabel,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: colorScheme.onSurfaceVariant),
      ),
    ];
  }

  List<Widget> _buildDiscoveredDeviceList(ColorScheme colorScheme) {
    if (discoveredDevices.isEmpty) {
      return [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text('暂无结果，点击“扫描”开始探测。'),
        ),
      ];
    }

    return discoveredDevices.map((d) {
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: const Icon(Icons.wifi_tethering),
          title: Text(d.deviceName.isEmpty ? d.host : d.deviceName),
          subtitle: Text('${d.host}:${d.port}'),
          trailing: Wrap(
            spacing: 4,
            children: [
              IconButton(
                tooltip: '发送到此设备',
                onPressed: isSendingAll
                    ? null
                    : () => onSendToHostPort(d.host, d.port),
                icon: const Icon(Icons.send),
              ),
            ],
          ),
        ),
      );
    }).toList();
  }
}
