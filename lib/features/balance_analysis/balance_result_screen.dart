import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/providers.dart';
import '../../domain/models.dart';
import 'share_card_renderer.dart';

class BalanceResultScreen extends ConsumerStatefulWidget {
  const BalanceResultScreen({
    super.key,
    required this.request,
    required this.result,
    required this.playerById,
    this.jokerPlayerId,
    this.reservePlayerId,
  });

  final BalanceRequest request;
  final BalanceResult result;
  final Map<String, Player> playerById;
  final String? jokerPlayerId;
  final String? reservePlayerId;

  @override
  ConsumerState<BalanceResultScreen> createState() => _BalanceResultScreenState();
}

class _BalanceResultScreenState extends ConsumerState<BalanceResultScreen> {
  var selected = 0;
  var busy = false;

  BalanceSolution get solution => widget.result.solutions[selected];

  Future<void> confirm() async {
    setState(() => busy = true);
    try {
      await ref.read(matchRepositoryProvider).confirm(
            teamSize: widget.request.teamSize,
            request: widget.request,
            solution: solution,
            jokerPlayerId: widget.jokerPlayerId,
            reservePlayerId: widget.reservePlayerId,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Maç immutable snapshot olarak kaydedildi.')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> share() async {
    setState(() => busy = true);
    try {
      final showScores = ref.read(showNumericScoresProvider).value ?? false;
      final file = await ShareCardRenderer().render(
        solution: solution,
        playerById: widget.playerById,
        showNumericScores: showScores,
        jokerPlayerId: widget.jokerPlayerId,
      );
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], text: 'Halı saha kadroları'),
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = solution;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Denge sonuçları'),
        actions: [
          IconButton(onPressed: busy ? null : share, icon: const Icon(Icons.share_outlined)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.result.solutions.length > 1)
            SegmentedButton<int>(
              segments: [
                for (var i = 0; i < widget.result.solutions.length; i++)
                  ButtonSegment(value: i, label: Text(i == 0 ? 'En iyi' : 'Alternatif $i')),
              ],
              selected: {selected},
              onSelectionChanged: (set) => setState(() => selected = set.first),
            ),
          const SizedBox(height: 16),
          _scoreCard(s),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final a = _teamCard('Takım A', s.teamAIds, s.profileA, jokerPlayerId: widget.jokerPlayerId);
              final b = _teamCard('Takım B', s.teamBIds, s.profileB, jokerPlayerId: widget.jokerPlayerId);
              if (constraints.maxWidth < 700) {
                return Column(children: [a, const SizedBox(height: 12), b]);
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [Expanded(child: a), const SizedBox(width: 12), Expanded(child: b)],
              );
            },
          ),
          if (widget.jokerPlayerId != null) ...[
            const SizedBox(height: 12),
            Card(child: ListTile(leading: const Icon(Icons.auto_awesome), title: Text('Joker: ${widget.playerById[widget.jokerPlayerId]!.name}'))),
          ],
          if (widget.reservePlayerId != null) ...[
            const SizedBox(height: 12),
            Card(child: ListTile(leading: const Icon(Icons.event_seat_outlined), title: Text('Yedek: ${widget.playerById[widget.reservePlayerId]!.name}'))),
          ],
          const SizedBox(height: 12),
          _lossDetails(s.loss),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: busy ? null : confirm,
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Maçı Onayla'),
          ),
        ],
      ),
    );
  }

  Widget _scoreCard(BalanceSolution s) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Balance Score', style: Theme.of(context).textTheme.labelLarge),
                  Text(s.loss.balanceScore.toStringAsFixed(1), style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            Text('Final loss\n${s.loss.finalBalanceLoss.toStringAsFixed(4)}', textAlign: TextAlign.end),
          ],
        ),
      ),
    );
  }

  Widget _teamCard(String title, List<String> ids, TeamProfile profile, {String? jokerPlayerId}) {
    final sorted = [...ids]..sort((a, b) {
        final c = positionCode(profile.assignedRoles[a]!).compareTo(positionCode(profile.assignedRoles[b]!));
        return c != 0 ? c : widget.playerById[a]!.name.compareTo(widget.playerById[b]!.name);
      });
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const Divider(),
            for (final id in sorted)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text('${positionCode(profile.assignedRoles[id]!)} • ${widget.playerById[id]!.name}'),
              ),
            if (jokerPlayerId != null && widget.playerById[jokerPlayerId] != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text('JOKER • ${widget.playerById[jokerPlayerId]!.name}', style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _lossDetails(LossBreakdown l) {
    final rows = <(String, double)>[
      ('Raw stat', l.rawStatLoss),
      ('Role balance', l.roleBalanceLoss),
      ('Matchup', l.matchupLoss),
      ('Goalkeeper', l.goalkeeperLoss),
      ('Strength curve', l.strengthCurveLoss),
      ('Overall', l.overallLoss),
      ('Tactical', l.tacticalProfileLoss),
      ('Critical', l.criticalLoss),
    ];
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: const Text('Denge analizi'),
      children: rows
          .map(
            (row) => ListTile(
              dense: true,
              title: Text(row.$1),
              trailing: Text(row.$2.toStringAsFixed(4)),
            ),
          )
          .toList(),
    );
  }
}
