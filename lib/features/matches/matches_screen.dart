import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../database/app_database.dart';
import '../../domain/models.dart';

final matchesProvider = StreamProvider<List<MatchSnapshot>>((ref) => ref.watch(matchRepositoryProvider).watchAll());

class MatchesScreen extends ConsumerWidget {
  const MatchesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matches = ref.watch(matchesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Onaylanan maçlar')),
      body: matches.when(
        data: (items) => items.isEmpty
            ? const Center(child: Text('Henüz onaylanmış maç yok.'))
            : ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final row = items[index];
                  final payload = Map<String, dynamic>.from(jsonDecode(row.payloadJson) as Map);
                  final solution = BalanceSolution.fromJson(Map<String, dynamic>.from(payload['solution'] as Map));
                  return Card(
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.sports_soccer)),
                      title: Text('${row.teamSize}v${row.teamSize} • ${solution.loss.balanceScore.toStringAsFixed(1)}'),
                      subtitle: Text(_formatDate(row.confirmedAt.toLocal())),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => _SnapshotDetail(payload: payload)),
                      ),
                    ),
                  );
                },
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Maç geçmişi yüklenemedi: $e')),
      ),
    );
  }

  static String _formatDate(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year} '
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}

class _SnapshotDetail extends StatelessWidget {
  const _SnapshotDetail({required this.payload});
  final Map<String, dynamic> payload;

  @override
  Widget build(BuildContext context) {
    final request = BalanceRequest.fromJson(Map<String, dynamic>.from(payload['request'] as Map));
    final solution = BalanceSolution.fromJson(Map<String, dynamic>.from(payload['solution'] as Map));
    final players = {for (final p in request.players) p.player.id: p.player};

    Widget team(String title, List<String> ids, TeamProfile profile) => Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                const Divider(),
                for (final id in ids)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text('${positionCode(profile.assignedRoles[id]!)} • ${players[id]!.name}'),
                  ),
              ],
            ),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Maç snapshotı')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Denge skoru: ${solution.loss.balanceScore.toStringAsFixed(1)}', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          team('Takım A', solution.teamAIds, solution.profileA),
          team('Takım B', solution.teamBIds, solution.profileB),
          if (payload['jokerPlayerId'] != null)
            ListTile(leading: const Icon(Icons.auto_awesome), title: Text('Joker: ${players[payload['jokerPlayerId']]?.name ?? payload['jokerPlayerId']}')),
          if (payload['reservePlayerId'] != null)
            ListTile(leading: const Icon(Icons.event_seat_outlined), title: Text('Yedek: ${players[payload['reservePlayerId']]?.name ?? payload['reservePlayerId']}')),
          const SizedBox(height: 8),
          const Text('Bu ekran canlı oyuncu profilinden değil, maç onay anındaki immutable snapshot verisinden okunur.'),
        ],
      ),
    );
  }
}
