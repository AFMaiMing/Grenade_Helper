import 'dart:io';

import 'package:flutter/widgets.dart';

/// 根据路径前缀返回内置资源或存在的本地文件 ImageProvider。
ImageProvider<Object>? imageProviderFromPath(String path) {
  final normalized = path.trim();
  if (normalized.isEmpty) return null;
  if (normalized.startsWith('assets/')) return AssetImage(normalized);

  final file = File(normalized);
  return file.existsSync() ? FileImage(file) : null;
}
