import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'data_package_models.dart';

const int _cs2PackagePasswordXorKey = 73;
const List<int> _obfuscatedCs2PackagePassword = [
  14,
  59,
  44,
  39,
  40,
  45,
  44,
  1,
  44,
  37,
  57,
  44,
  59,
  100,
  10,
  26,
  123,
  25,
  34,
  46,
];
final String _cs2PackagePassword = String.fromCharCodes(
  _obfuscatedCs2PackagePassword
      .map((value) => value ^ _cs2PackagePasswordXorKey),
);
final List<int> _cs2PackageIntegrityKey =
    sha256.convert(utf8.encode(_cs2PackagePassword)).bytes;

const int exportArchiveCompressionLevel = DeflateLevel.bestCompression;
const Set<String> alreadyCompressedArchiveExtensions = {
  '.jpg',
  '.jpeg',
  '.png',
  '.gif',
  '.webp',
  '.heic',
  '.heif',
  '.mp4',
  '.mov',
  '.m4v',
  '.avi',
  '.mkv',
  '.webm',
};

const Set<String> trackedImageExtensions = {
  '.jpg',
  '.jpeg',
  '.png',
  '.gif',
  '.webp',
  '.bmp',
  '.svg',
  '.heic',
  '.heif',
  '.avif',
};

const Set<String> trackedVideoExtensions = {
  '.mp4',
  '.mov',
  '.m4v',
  '.avi',
  '.mkv',
  '.webm',
  '.wmv',
  '.flv',
  '.ts',
  '.3gp',
};

const Set<String> trackedMediaExtensions = {
  ...trackedImageExtensions,
  ...trackedVideoExtensions,
};

String formatPackageBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  double size = bytes.toDouble();
  var unitIndex = -1;
  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024;
    unitIndex++;
  }
  final fractionDigits = size >= 100 ? 0 : 1;
  return '${size.toStringAsFixed(fractionDigits)} ${units[unitIndex]}';
}

int compressionLevelForArchiveEntry(String filePath) {
  final extension = p.extension(filePath).toLowerCase();
  if (alreadyCompressedArchiveExtensions.contains(extension)) {
    return DeflateLevel.none;
  }
  return exportArchiveCompressionLevel;
}

Object? canonicalizePackageJsonValue(Object? value) {
  if (value is Map) {
    final entries = value.entries.toList()
      ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
    final normalized = <String, Object?>{};
    for (final entry in entries) {
      normalized[entry.key.toString()] =
          canonicalizePackageJsonValue(entry.value);
    }
    return normalized;
  }
  if (value is List) {
    return value.map(canonicalizePackageJsonValue).toList(growable: false);
  }
  return value;
}

String sha256BytesHex(List<int> bytes) {
  return sha256.convert(bytes).toString();
}

Future<String> sha256FileHex(String localPath) async {
  final normalized = localPath.trim();
  if (normalized.isEmpty) return '';
  final file = File(normalized);
  if (!await file.exists()) return '';
  return sha256BytesHex(await file.readAsBytes());
}

String computePackageContentHmac({
  required int schemaVersion,
  required String packageType,
  required int createdAtMs,
  required List<Map<String, dynamic>> files,
}) {
  final canonical = canonicalizePackageJsonValue({
    'manifestVersion': packageManifestVersion,
    'schemaVersion': schemaVersion,
    'packageType': packageType,
    'createdAt': createdAtMs,
    'files': files,
  });
  final encoded = utf8.encode(jsonEncode(canonical));
  return Hmac(sha256, _cs2PackageIntegrityKey).convert(encoded).toString();
}

Future<T> withOpenedCs2PackageArchive<T>(
  String filePath,
  Future<T> Function(Archive? archive) action,
) async {
  InputFileStream? openedInput;
  Archive? openedArchive;
  for (final password in [_cs2PackagePassword, null]) {
    final input = InputFileStream(filePath);
    try {
      openedArchive = ZipDecoder().decodeStream(input, password: password);
      openedInput = input;
      break;
    } catch (_) {
      input.closeSync();
    }
  }
  try {
    return await action(openedArchive);
  } finally {
    openedArchive?.clearSync();
    openedInput?.closeSync();
  }
}

ArchiveFile? findArchiveFileByNameOrBasename(Archive archive, String fileName) {
  final direct = archive.find(fileName);
  if (direct != null) {
    return direct;
  }
  for (final entry in archive) {
    if (!entry.isFile) continue;
    if (p.basename(entry.name) == fileName) {
      return entry;
    }
  }
  return null;
}

String extractArchiveFileNameFromPackagePath(String rawPath) {
  final trimmed = rawPath.trim();
  if (trimmed.isEmpty) return '';
  final normalized = trimmed.replaceAll('\\', '/');
  return p.posix.basename(normalized).trim();
}

String normalizePackageMediaCacheKey(String rawPath) {
  final trimmed = rawPath.trim();
  if (trimmed.isEmpty) return '';
  return trimmed.replaceAll('\\', '/');
}

Future<List<int>?> readPackageMediaBytesFromArchive({
  required String packageFilePath,
  required String packageMediaPath,
  String? expectedSha256,
  int? expectedSizeBytes,
}) async {
  final fileName = extractArchiveFileNameFromPackagePath(packageMediaPath);
  if (fileName.isEmpty) return null;
  final extension = p.extension(fileName).toLowerCase();
  if (!trackedMediaExtensions.contains(extension)) {
    return null;
  }

  return withOpenedCs2PackageArchive(packageFilePath, (archive) async {
    if (archive == null) return null;
    final archiveFile = findArchiveFileByNameOrBasename(archive, fileName);
    if (archiveFile == null || !archiveFile.isFile) {
      return null;
    }
    if (archiveFile.size < 0 ||
        archiveFile.size > maxImportPackageEntrySizeBytes) {
      return null;
    }
    final bytes = archiveFile.content;
    if (expectedSizeBytes != null && expectedSizeBytes != bytes.length) {
      return null;
    }
    if (expectedSha256 != null &&
        expectedSha256.isNotEmpty &&
        sha256BytesHex(bytes) != expectedSha256) {
      return null;
    }
    return bytes;
  });
}

// 在独立 isolate 中复制媒体、计算哈希签名并生成加密 .cs2pkg 归档
Future<void> packageFilesInIsolate(PackageParams params) async {
  final exportDir = Directory(params.exportDirPath);
  final createdAtMs = DateTime.now().millisecondsSinceEpoch;

  if (exportDir.existsSync()) exportDir.deleteSync(recursive: true);
  exportDir.createSync(recursive: true);

  final jsonFile = File(p.join(exportDir.path, packageDataFileName));
  jsonFile.writeAsStringSync(params.jsonData);

  for (var filePath in params.filesToCopy) {
    final file = File(filePath);
    if (file.existsSync()) {
      file.copySync(p.join(exportDir.path, p.basename(filePath)));
    }
  }

  final manifestFiles = <Map<String, dynamic>>[];
  final stagedFiles = <File>[jsonFile];
  for (final filePath in params.filesToCopy) {
    final stagedFile = File(p.join(exportDir.path, p.basename(filePath)));
    if (stagedFile.existsSync()) {
      stagedFiles.add(stagedFile);
    }
  }
  stagedFiles.sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
  for (final stagedFile in stagedFiles) {
    final bytes = stagedFile.readAsBytesSync();
    final archiveName = p.basename(stagedFile.path);
    manifestFiles.add({
      'path': archiveName,
      'kind': archiveName == packageDataFileName ? 'data' : 'media',
      'sizeBytes': bytes.length,
      'sha256': sha256BytesHex(bytes),
    });
  }

  final manifest = PackageManifestData(
    manifestVersion: packageManifestVersion,
    schemaVersion: params.schemaVersion,
    packageType: params.packageType,
    createdAt: createdAtMs,
    files: manifestFiles
        .map((raw) => PackageManifestFileEntry.fromJson(raw))
        .toList(growable: false),
    contentHmac: computePackageContentHmac(
      schemaVersion: params.schemaVersion,
      packageType: params.packageType,
      createdAtMs: createdAtMs,
      files: manifestFiles,
    ),
  );
  final manifestJson =
      jsonEncode(canonicalizePackageJsonValue(manifest.toJson()));

  // archive 4.x 默认使用 bestSpeed(1)，这里显式切到最高压缩并跳过已压缩媒体
  final encoder = ZipFileEncoder(password: _cs2PackagePassword);
  encoder.create(params.zipPath, level: exportArchiveCompressionLevel);
  await encoder.addFile(
    jsonFile,
    packageDataFileName,
    exportArchiveCompressionLevel,
  );
  encoder.addArchiveFile(
      ArchiveFile.string(packageManifestFileName, manifestJson));
  for (final filePath in params.filesToCopy) {
    final archivedFile = File(p.join(exportDir.path, p.basename(filePath)));
    if (!archivedFile.existsSync()) continue;
    await encoder.addFile(
      archivedFile,
      p.basename(filePath),
      compressionLevelForArchiveEntry(filePath),
    );
  }
  await encoder.close();
}
