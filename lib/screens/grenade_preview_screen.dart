import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/data_service.dart';
import '../widgets/grenade_type_icon.dart';

/// 道具导入预览页面。
class GrenadePreviewScreen extends StatelessWidget {
  final GrenadePreviewItem grenade;
  final Map<String, List<int>> memoryImages;
  final String? packageFilePath;
  final Map<String, String> packageFileHashes;
  final Map<String, int> packageFileSizes;

  const GrenadePreviewScreen({
    super.key,
    required this.grenade,
    required this.memoryImages,
    this.packageFilePath,
    this.packageFileHashes = const {},
    this.packageFileSizes = const {},
  });

  @override
  Widget build(BuildContext context) {
    final steps = (grenade.rawData['steps'] as List?) ?? [];

    return Scaffold(
      appBar: AppBar(
        title: Text(grenade.title),
        actions: [
          _buildStatusBadge(grenade.status),
          const SizedBox(width: 16),
        ],
      ),
      body: Column(
        children: [
          _buildInfoBar(context),
          Expanded(
            child: steps.isEmpty
                ? const Center(
                    child: Text("无教学步骤", style: TextStyle(color: Colors.grey)),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: steps.length,
                    itemBuilder: (context, index) =>
                        _buildStepCard(context, steps[index], index),
                  ),
          ),
          _buildFooter(context),
        ],
      ),
    );
  }

  Widget _buildInfoBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          GrenadeTypeIcon(type: grenade.type, size: 26),
          const SizedBox(width: 8),
          Text(
            _getTypeName(grenade.type),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          Icon(Icons.map, size: 16, color: Colors.grey[600]),
          const SizedBox(width: 4),
          Text(
            "${grenade.mapName} - ${grenade.layerName}",
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildStepCard(BuildContext context, dynamic stepData, int index) {
    final title = stepData['title'] as String? ?? '';
    final description = stepData['description'] as String? ?? '';
    final medias = (stepData['medias'] as List?) ?? [];

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    "#${index + 1}",
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title.isNotEmpty ? title : "步骤 ${index + 1}",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Theme.of(context)
                          .textTheme
                          .bodyLarge
                          ?.color
                          ?.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                description,
                style: TextStyle(fontSize: 14, color: Colors.grey[400]),
              ),
            ),
          ...medias.map(_buildMediaItem),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildMediaItem(dynamic mediaData) {
    final path = mediaData['path'] as String? ?? '';
    final type = mediaData['type'] as int? ?? 0;
    final imageBytes = memoryImages[path];

    if (imageBytes == null) {
      if (type != MediaType.video && path.isNotEmpty) {
        final file = File(path);
        if (file.existsSync()) {
          return _buildImageContainer(
            Image.file(
              file,
              fit: BoxFit.contain,
              width: double.infinity,
              errorBuilder: _buildBrokenImageError,
            ),
          );
        }
        if (packageFilePath != null) {
          return FutureBuilder<List<int>?>(
            future: DataService.readPackageMediaBytes(
              packageFilePath: packageFilePath!,
              packageMediaPath: path,
              expectedSha256: packageFileHashes[path],
              expectedSizeBytes: packageFileSizes[path],
            ),
            builder: (context, snapshot) {
              final packageImageBytes = snapshot.data;
              if (packageImageBytes != null && packageImageBytes.isNotEmpty) {
                return _buildImageContainer(
                  Image.memory(
                    Uint8List.fromList(packageImageBytes),
                    fit: BoxFit.contain,
                    width: double.infinity,
                    errorBuilder: _buildBrokenImageError,
                  ),
                );
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return _buildMediaBox(
                  backgroundColor: Colors.grey[850],
                  child: const Center(child: CircularProgressIndicator()),
                );
              }
              return _buildUnavailableMediaPlaceholder();
            },
          );
        }
      }
      return _buildUnavailableMediaPlaceholder();
    }

    if (type == MediaType.video) {
      return _buildMediaPlaceholder(
        icon: Icons.videocam,
        iconColor: Colors.orange,
        text: "视频预览（导入后可播放）",
      );
    }

    return _buildImageContainer(
      Image.memory(
        Uint8List.fromList(imageBytes),
        fit: BoxFit.contain,
        width: double.infinity,
        errorBuilder: _buildBrokenImageError,
      ),
    );
  }

  Widget _buildImageContainer(Widget image) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: image,
      ),
    );
  }

  Widget _buildBrokenImageError(
    BuildContext context,
    Object error,
    StackTrace? stackTrace,
  ) {
    return Container(
      height: 200,
      color: Colors.grey[800],
      child: const Center(
        child: Icon(Icons.broken_image, size: 48, color: Colors.grey),
      ),
    );
  }

  Widget _buildUnavailableMediaPlaceholder() {
    return _buildMediaPlaceholder(
      icon: Icons.image_not_supported,
      iconColor: Colors.grey,
      text: "无法加载媒体",
    );
  }

  Widget _buildMediaPlaceholder({
    required IconData icon,
    required Color iconColor,
    required String text,
  }) {
    return _buildMediaBox(
      backgroundColor: Colors.grey[800],
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: iconColor),
            const SizedBox(height: 8),
            Text(text, style: const TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaBox({
    required Color? backgroundColor,
    required Widget child,
  }) {
    return Container(
      height: 200,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }

  Widget _buildFooter(BuildContext context) {
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.person, size: 14, color: Colors.grey),
          const SizedBox(width: 4),
          Text(
            "作者: ${grenade.author ?? '匿名作者'}",
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(ImportStatus status) {
    final (color, text) = switch (status) {
      ImportStatus.newItem => (Colors.green, "新增"),
      ImportStatus.update => (Colors.orange, "更新"),
      ImportStatus.skip => (Colors.grey, "跳过"),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: TextStyle(fontSize: 12, color: color)),
    );
  }

  String _getTypeName(int type) {
    return switch (type) {
      GrenadeType.smoke => "烟雾弹",
      GrenadeType.flash => "闪光弹",
      GrenadeType.molotov => "燃烧弹",
      GrenadeType.he => "手雷",
      GrenadeType.wallbang => "穿点",
      _ => "未知",
    };
  }
}
