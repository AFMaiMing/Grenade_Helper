import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';

import '../../models.dart';
import '../../providers.dart';
import '../../widgets/grenade_type_icon.dart';
import '../grenade_detail_screen.dart';

// 首页全局道具搜索委托
class GlobalSearchDelegate extends SearchDelegate {
  final WidgetRef ref;

  GlobalSearchDelegate(this.ref);

  @override
  List<Widget>? buildActions(BuildContext context) =>
      [IconButton(onPressed: () => query = '', icon: const Icon(Icons.clear))];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
        onPressed: () => close(context, null),
        icon: const Icon(Icons.arrow_back),
      );

  @override
  Widget buildResults(BuildContext context) => _buildList(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildList(context);

  Widget _buildList(BuildContext context) {
    if (query.isEmpty) return const SizedBox();

    final isar = ref.read(isarProvider);
    final results = isar.grenades
        .filter()
        .titleContains(query, caseSensitive: false)
        .findAllSync();

    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (ctx, index) {
        final grenade = results[index];
        grenade.layer.loadSync();
        grenade.layer.value?.map.loadSync();
        final mapName = grenade.layer.value?.map.value?.name ?? '';
        return ListTile(
          leading: GrenadeTypeIcon(type: grenade.type),
          title: Text(grenade.title),
          subtitle: Text(mapName, style: const TextStyle(color: Colors.orange)),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => GrenadeDetailScreen(
                  grenadeId: grenade.id,
                  isEditing: false,
                ),
              ),
            );
          },
        );
      },
    );
  }
}
