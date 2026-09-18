import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/models.dart';
import 'player_avatar.dart';
import 'player_editor_screen.dart';
import 'player_media_service.dart';

final playersProvider = StreamProvider<List<Player>>((ref) => ref.watch(playerRepositoryProvider).watchAll());

class PlayersScreen extends ConsumerWidget {
  const PlayersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final players = ref.watch(playersProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Oyuncular')),
      body: players.when(
        data: (items) => items.isEmpty
            ? const Center(child: Text('Henüz oyuncu yok. İlk kadroyu ekleyin.'))
            : ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final player = items[index];
                  return Card(
                    child: ListTile(
                      leading: PlayerAvatar(player: player),
                      title: Text(player.name),
                      subtitle: Text(
                        '${positionCode(player.primaryPosition)}'
                        '${player.secondaryPosition == null ? '' : ' / ${positionCode(player.secondaryPosition!)}'}',
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) async {
                          if (value == 'edit') {
                            await Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => PlayerEditorScreen(initial: player)),
                            );
                          } else if (value == 'delete') {
                            final photo = await PlayerMediaService().resolve(player.photoPath);
                            await ref.read(playerRepositoryProvider).delete(player.id);
                            if (photo != null && await photo.exists()) await photo.delete();
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('Düzenle')),
                          PopupMenuItem(value: 'delete', child: Text('Sil')),
                        ],
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => PlayerEditorScreen(initial: player)),
                      ),
                    ),
                  );
                },
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Oyuncular yüklenemedi: $error')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const PlayerEditorScreen()),
        ),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Oyuncu ekle'),
      ),
    );
  }
}
