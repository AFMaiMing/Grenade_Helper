import 'dart:async';

import 'package:isar_community/isar.dart';

import '../models.dart';
import 'lan_sync/lan_sync_local_store.dart';

enum FavoriteFolderDeleteStrategy {
  moveToDefault,
  unfavorite,
}

class FolderWithGrenades {
  final FavoriteFolder folder;
  final List<Grenade> grenades;

  const FolderWithGrenades({
    required this.folder,
    required this.grenades,
  });
}

class FavoriteFolderService {
  static const String defaultFolderName = '默认收藏夹';

  final Isar isar;

  const FavoriteFolderService(this.isar);

  String normalizeFolderName(String value) => value.trim().toLowerCase();

  bool isDefaultFolder(FavoriteFolder folder) =>
      normalizeFolderName(folder.name) ==
      normalizeFolderName(defaultFolderName);

  Future<List<FavoriteFolder>> getFoldersByMap(int mapId) async {
    final folders =
        await isar.favoriteFolders.filter().mapIdEqualTo(mapId).findAll();
    folders.sort((a, b) {
      final byOrder = a.sortOrder.compareTo(b.sortOrder);
      return byOrder != 0 ? byOrder : a.createdAt.compareTo(b.createdAt);
    });
    return folders;
  }

  Future<FavoriteFolder?> _findByNameKey(int mapId, String nameKey) async {
    final folders =
        await isar.favoriteFolders.filter().mapIdEqualTo(mapId).findAll();
    for (final folder in folders) {
      if (folder.nameKey == nameKey) return folder;
    }
    return null;
  }

  Future<FavoriteFolder?> getFolderById(int folderId) {
    return isar.favoriteFolders.get(folderId);
  }

  Future<FavoriteFolder> getOrCreateDefaultFolder(int mapId) async {
    final defaultKey = normalizeFolderName(defaultFolderName);
    final existing = await _findByNameKey(mapId, defaultKey);
    if (existing != null) return existing;
    return createFolder(mapId, defaultFolderName);
  }

  ({String displayName, String nameKey}) _validateFolderName(String rawName) {
    final displayName = rawName.trim();
    if (displayName.isEmpty) {
      throw StateError('收藏夹名称不能为空');
    }
    return (
      displayName: displayName,
      nameKey: normalizeFolderName(displayName),
    );
  }

  Future<void> _ensureUniqueNameKey(
    int mapId,
    String nameKey, {
    int? excludeFolderId,
  }) async {
    final duplicated = await _findByNameKey(mapId, nameKey);
    if (duplicated != null && duplicated.id != excludeFolderId) {
      throw StateError('收藏夹名称已存在');
    }
  }

  Future<FavoriteFolder> createFolder(int mapId, String name) async {
    final parsed = _validateFolderName(name);
    await _ensureUniqueNameKey(mapId, parsed.nameKey);

    final existing = await getFoldersByMap(mapId);
    final sortOrder = existing.isEmpty ? 0 : existing.last.sortOrder + 1;
    final now = DateTime.now();
    final folder = FavoriteFolder(
      mapId: mapId,
      name: parsed.displayName,
      nameKey: parsed.nameKey,
      sortOrder: sortOrder,
      created: now,
      updated: now,
    );

    await isar.writeTxn(() async {
      await isar.favoriteFolders.put(folder);
    });
    return folder;
  }

  Future<void> renameFolder(int folderId, String newName) async {
    final folder = await isar.favoriteFolders.get(folderId);
    if (folder == null) return;

    final parsed = _validateFolderName(newName);
    if (parsed.nameKey == folder.nameKey) return;
    await _ensureUniqueNameKey(
      folder.mapId,
      parsed.nameKey,
      excludeFolderId: folder.id,
    );

    folder.name = parsed.displayName;
    folder.nameKey = parsed.nameKey;
    folder.updatedAt = DateTime.now();

    await isar.writeTxn(() async {
      await isar.favoriteFolders.put(folder);
    });
  }

  Future<List<Grenade>> _getFavoriteGrenadesInFolder(int folderId) {
    return isar.grenades
        .filter()
        .isFavoriteEqualTo(true)
        .favoriteFolderIdEqualTo(folderId)
        .findAll();
  }

  Future<int> _resolveGrenadeMapId(Grenade grenade) async {
    await grenade.layer.load();
    final layer = grenade.layer.value;
    if (layer == null) {
      throw StateError('道具未关联楼层');
    }
    await layer.map.load();
    final map = layer.map.value;
    if (map == null) {
      throw StateError('楼层未关联地图');
    }
    return map.id;
  }

  Future<List<Grenade>> getMapFavoriteGrenades(int mapId) {
    return isar.grenades
        .filter()
        .isFavoriteEqualTo(true)
        .layer((q) => q.map((m) => m.idEqualTo(mapId)))
        .findAll();
  }

  Future<List<FolderWithGrenades>> loadMapFavorites(int mapId) async {
    final folders = await getFoldersByMap(mapId);
    final favorites = await getMapFavoriteGrenades(mapId);
    final grouped = <int, List<Grenade>>{};

    for (final grenade in favorites) {
      final folderId = grenade.favoriteFolderId;
      if (folderId == null) continue;
      grouped.putIfAbsent(folderId, () => <Grenade>[]).add(grenade);
    }

    for (final list in grouped.values) {
      list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    }

    return folders
        .map(
          (f) => FolderWithGrenades(
            folder: f,
            grenades: grouped[f.id] ?? const [],
          ),
        )
        .toList();
  }

  Stream<List<FolderWithGrenades>> watchMapFavorites(int mapId) {
    late final StreamController<List<FolderWithGrenades>> controller;
    StreamSubscription<void>? folderSub;
    StreamSubscription<void>? grenadeSub;

    Future<void> emit() async {
      if (controller.isClosed) return;
      try {
        final data = await loadMapFavorites(mapId);
        if (!controller.isClosed) {
          controller.add(data);
        }
      } catch (e, st) {
        if (!controller.isClosed) {
          controller.addError(e, st);
        }
      }
    }

    controller = StreamController<List<FolderWithGrenades>>(
      onListen: () {
        folderSub = isar.favoriteFolders
            .filter()
            .mapIdEqualTo(mapId)
            .watchLazy(fireImmediately: true)
            .listen((_) => emit());
        grenadeSub = isar.grenades
            .filter()
            .layer((q) => q.map((m) => m.idEqualTo(mapId)))
            .watchLazy(fireImmediately: true)
            .listen((_) => emit());
      },
      onCancel: () async {
        await folderSub?.cancel();
        await grenadeSub?.cancel();
      },
    );

    return controller.stream;
  }

  Future<FavoriteFolder> _requireFolderForMap({
    required int targetFolderId,
    required int mapId,
    required String mismatchMessage,
  }) async {
    final target = await isar.favoriteFolders.get(targetFolderId);
    if (target == null) {
      throw StateError('目标收藏夹不存在');
    }
    if (target.mapId != mapId) {
      throw StateError(mismatchMessage);
    }
    return target;
  }

  Future<void> _updateGrenadesFavoriteInTxn(
    Iterable<Grenade> grenades, {
    required bool favorite,
    required int? folderId,
  }) async {
    final now = DateTime.now();
    for (final grenade in grenades) {
      grenade.isFavorite = favorite;
      grenade.favoriteFolderId = folderId;
      grenade.updatedAt = now;
      await isar.grenades.put(grenade);
    }
  }

  Future<void> setFavorite(
    int grenadeId, {
    required bool favorite,
    int? folderId,
  }) async {
    final grenade = await isar.grenades.get(grenadeId);
    if (grenade == null) return;

    if (!favorite) {
      await isar.writeTxn(() async {
        await _updateGrenadesFavoriteInTxn(
          [grenade],
          favorite: false,
          folderId: null,
        );
      });
      return;
    }

    final mapId = await _resolveGrenadeMapId(grenade);
    final folder = folderId != null
        ? await _requireFolderForMap(
            targetFolderId: folderId,
            mapId: mapId,
            mismatchMessage: '不能跨地图收藏到其他收藏夹',
          )
        : await getOrCreateDefaultFolder(mapId);

    await isar.writeTxn(() async {
      await _updateGrenadesFavoriteInTxn(
        [grenade],
        favorite: true,
        folderId: folder.id,
      );
    });
  }

  Future<void> moveFavorite(int grenadeId, int targetFolderId) async {
    final grenade = await isar.grenades.get(grenadeId);
    if (grenade == null) return;

    final targetFolder = await isar.favoriteFolders.get(targetFolderId);
    if (targetFolder == null) {
      throw StateError('目标收藏夹不存在');
    }

    final grenadeMapId = await _resolveGrenadeMapId(grenade);
    if (grenadeMapId != targetFolder.mapId) {
      throw StateError('不能移动到其他地图收藏夹');
    }

    await isar.writeTxn(() async {
      await _updateGrenadesFavoriteInTxn(
        [grenade],
        favorite: true,
        folderId: targetFolder.id,
      );
    });
  }

  Future<void> deleteFolder(
    int folderId,
    FavoriteFolderDeleteStrategy strategy, {
    bool recordSyncTombstone = true,
  }) async {
    final folder = await isar.favoriteFolders.get(folderId);
    if (folder == null) return;

    final folderGrenades = await _getFavoriteGrenadesInFolder(folder.id);
    FavoriteFolder? moveTarget;

    if (folderGrenades.isNotEmpty &&
        strategy == FavoriteFolderDeleteStrategy.moveToDefault) {
      if (isDefaultFolder(folder)) {
        throw StateError('默认收藏夹不可使用“迁移到默认收藏夹”删除');
      }
      moveTarget = await getOrCreateDefaultFolder(folder.mapId);
    }

    final map =
        recordSyncTombstone ? await isar.gameMaps.get(folder.mapId) : null;
    if (recordSyncTombstone && map != null) {
      final nameKey = folder.nameKey.trim().isEmpty
          ? normalizeFolderName(folder.name)
          : normalizeFolderName(folder.nameKey);
      final entityKey =
          '${map.name.trim().toLowerCase()}|${nameKey.trim().toLowerCase()}';
      await LanSyncLocalStore().upsertEntityTombstones([
        LanSyncEntityTombstoneEntry(
          entityType: LanSyncEntityTombstoneType.favoriteFolder,
          entityKey: entityKey,
          mapName: map.name,
          deletedAt: DateTime.now().millisecondsSinceEpoch,
          payload: {
            'name': folder.name,
            'nameKey': nameKey,
          },
        ),
      ]);
    }

    await isar.writeTxn(() async {
      if (folderGrenades.isNotEmpty) {
        if (strategy == FavoriteFolderDeleteStrategy.unfavorite) {
          await _updateGrenadesFavoriteInTxn(
            folderGrenades,
            favorite: false,
            folderId: null,
          );
        } else if (moveTarget != null) {
          await _updateGrenadesFavoriteInTxn(
            folderGrenades,
            favorite: true,
            folderId: moveTarget.id,
          );
        }
      }
      await isar.favoriteFolders.delete(folder.id);
    });
  }
}
