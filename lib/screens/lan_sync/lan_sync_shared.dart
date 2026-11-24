import 'package:flutter/material.dart';

/// 局域网发送范围枚举
enum LanSendScope { all, map, grenades }

/// 局域网同步模式枚举
enum LanSyncMode { full, incremental }

/// 格式化传输字节数为可读文本
String formatLanBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(kb >= 100 ? 0 : 1)} KB';
  final mb = kb / 1024;
  return '${mb.toStringAsFixed(mb >= 100 ? 0 : 1)} MB';
}

/// 局域网同步页通用功能分区卡片
class LanSectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;
  final Widget? action;

  const LanSectionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            if (action != null) ...[
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerLeft, child: action!),
            ],
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

/// 局域网同步页顶部提示横幅
class LanNoticeBanner extends StatelessWidget {
  final Color backgroundColor;
  final Color foregroundColor;
  final IconData icon;
  final String text;

  const LanNoticeBanner({
    super.key,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: foregroundColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(color: foregroundColor)),
          ),
        ],
      ),
    );
  }
}
