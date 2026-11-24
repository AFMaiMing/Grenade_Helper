import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// 关于页面
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _version = '';
  String _buildNumber = '';

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
  }

  Future<void> _loadPackageInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _version = info.version;
        _buildNumber = info.buildNumber;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _version = '未知';
        _buildNumber = '';
      });
    }
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  BoxDecoration _cardDecoration(bool isDark, double radius) {
    return BoxDecoration(
      color: isDark
          ? Colors.white.withValues(alpha: 0.05)
          : Colors.black.withValues(alpha: 0.03),
      borderRadius: BorderRadius.circular(radius),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: _cardDecoration(isDark, 20),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.asset(
                      'assets/icons/app_icon.webp',
                      width: 100,
                      height: 100,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Grenade Helper',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '版本 $_version${_buildNumber.isNotEmpty ? ' ($_buildNumber)' : ''}',
                    style: TextStyle(
                      fontSize: 16,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'CS2 道具投掷点位助手',
                    style: TextStyle(
                      fontSize: 16,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _buildSection(
              context,
              isDark: isDark,
              icon: Icons.link,
              title: '相关链接',
              children: [
                _LinkItem(
                  icon: Icons.code,
                  text: 'GitHub 仓库',
                  onTap: () => _launchUrl(
                    'https://github.com/Invis1ble-2/Grenade_Helper',
                  ),
                ),
                _LinkItem(
                  icon: Icons.bug_report,
                  text: '问题反馈',
                  onTap: () => _launchUrl(
                    'https://github.com/Invis1ble-2/Grenade_Helper/issues',
                  ),
                ),
                _LinkItem(
                  icon: Icons.download,
                  text: '下载最新版本',
                  onTap: () => _launchUrl(
                    'https://github.com/Invis1ble-2/Grenade_Helper/releases',
                  ),
                ),
                _LinkItem(
                  icon: Icons.web,
                  text: '官方网站',
                  onTap: () => _launchUrl('https://grenade-helper.top/'),
                ),
                _LinkItem(
                  icon: Icons.web,
                  text: '哔哩哔哩',
                  onTap: () =>
                      _launchUrl('https://space.bilibili.com/39354678'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildSection(
              context,
              isDark: isDark,
              icon: Icons.group,
              title: '加入社区',
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      Text(
                        '加入 QQ 群，获取最新动态、分享道具包、交流反馈',
                        style: TextStyle(
                          fontSize: 14,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.8),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      const _QrCodeCard(
                        assetPath: 'assets/icons/qq_qrcode.webp',
                        size: 200,
                        fallbackLabel: 'QQ 群二维码',
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '群号：2156059848',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildSection(
              context,
              isDark: isDark,
              icon: Icons.person,
              title: '开发者',
              children: [
                const _DeveloperTile(name: 'Invis1ble', role: '独立开发者'),
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  height: 1,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.1),
                ),
                const _DeveloperTile(name: 'MaiMing', role: '独立开发者'),
              ],
            ),
            const SizedBox(height: 16),
            _buildSection(
              context,
              isDark: isDark,
              icon: Icons.favorite,
              title: '支持开发者',
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      Text(
                        '如果这个应用对你有帮助，欢迎在爱发电支持我们！',
                        style: TextStyle(
                          fontSize: 14,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.8),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      const _QrCodeCard(
                        assetPath: 'assets/icons/afdian.webp',
                        size: 300,
                        fallbackLabel: '二维码占位符',
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
                _LinkItem(
                  icon: Icons.volunteer_activism,
                  text: '前往爱发电支持',
                  onTap: () => _launchUrl('https://afdian.com/a/Invis1ble'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              '© 2025 Grenade Helper. MIT License.',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Made with ❤️ using Flutter',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required bool isDark,
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(isDark, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _QrCodeCard extends StatelessWidget {
  final String assetPath;
  final double size;
  final String fallbackLabel;

  const _QrCodeCard({
    required this.assetPath,
    required this.size,
    required this.fallbackLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Image.asset(
        assetPath,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.qr_code, size: 50, color: Colors.grey[400]),
              const SizedBox(height: 8),
              Text(
                fallbackLabel,
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeveloperTile extends StatelessWidget {
  final String name;
  final String role;

  const _DeveloperTile({
    required this.name,
    required this.role,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: theme.colorScheme.primary,
            child: const Icon(Icons.person, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              Text(
                role,
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LinkItem extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback onTap;

  const _LinkItem({
    required this.icon,
    required this.text,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, size: 18, color: primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: TextStyle(fontSize: 14, color: primary),
              ),
            ),
            Icon(
              Icons.open_in_new,
              size: 16,
              color: primary.withValues(alpha: 0.6),
            ),
          ],
        ),
      ),
    );
  }
}
