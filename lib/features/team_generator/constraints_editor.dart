import 'package:flutter/material.dart';

import '../../domain/models.dart';

class ConstraintDraft {
  ConstraintDraft({
    List<PinnedPlayer>? pinned,
    List<IdPair>? sameTeamPairs,
    List<IdPair>? separateTeamPairs,
  })  : pinned = pinned ?? [],
        sameTeamPairs = sameTeamPairs ?? [],
        separateTeamPairs = separateTeamPairs ?? [];

  final List<PinnedPlayer> pinned;
  final List<IdPair> sameTeamPairs;
  final List<IdPair> separateTeamPairs;

  ConstraintDraft copy() => ConstraintDraft(
        pinned: [...pinned],
        sameTeamPairs: [...sameTeamPairs],
        separateTeamPairs: [...separateTeamPairs],
      );
}

class ConstraintsEditorScreen extends StatefulWidget {
  const ConstraintsEditorScreen({super.key, required this.players, required this.initial});
  final List<MatchPlayer> players;
  final ConstraintDraft initial;

  @override
  State<ConstraintsEditorScreen> createState() => _ConstraintsEditorScreenState();
}

class _ConstraintsEditorScreenState extends State<ConstraintsEditorScreen> {
  late ConstraintDraft draft;

  @override
  void initState() {
    super.initState();
    draft = widget.initial.copy();
  }

  String nameOf(String id) => widget.players.firstWhere((p) => p.player.id == id).player.name;

  Future<void> addPair({required bool same}) async {
    if (widget.players.length < 2) return;
    String first = widget.players.first.player.id;
    String second = widget.players[1].player.id;
    final result = await showDialog<IdPair>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(same ? 'Same-Team çifti' : 'Separate-Team çifti'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: first,
                items: widget.players.map((p) => DropdownMenuItem(value: p.player.id, child: Text(p.player.name))).toList(),
                onChanged: (v) => setLocal(() => first = v!),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: second,
                items: widget.players.map((p) => DropdownMenuItem(value: p.player.id, child: Text(p.player.name))).toList(),
                onChanged: (v) => setLocal(() => second = v!),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
            FilledButton(
              onPressed: first == second ? null : () => Navigator.pop(context, IdPair(first, second)),
              child: const Text('Ekle'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    setState(() => (same ? draft.sameTeamPairs : draft.separateTeamPairs).add(result));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Takım kısıtları'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, draft), child: const Text('Bitti')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Pinned Team', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...widget.players.map((p) {
            final pin = draft.pinned.where((e) => e.playerId == p.player.id).firstOrNull;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(p.player.name),
              trailing: DropdownButton<TeamSide?>(
                value: pin?.team,
                items: const [
                  DropdownMenuItem<TeamSide?>(value: null, child: Text('Serbest')),
                  DropdownMenuItem<TeamSide?>(value: TeamSide.a, child: Text('A')),
                  DropdownMenuItem<TeamSide?>(value: TeamSide.b, child: Text('B')),
                ],
                onChanged: (value) {
                  setState(() {
                    draft.pinned.removeWhere((e) => e.playerId == p.player.id);
                    if (value != null) draft.pinned.add(PinnedPlayer(p.player.id, value));
                  });
                },
              ),
            );
          }),
          const Divider(height: 32),
          _pairSection('Same-Team', draft.sameTeamPairs, () => addPair(same: true)),
          const Divider(height: 32),
          _pairSection('Separate-Team', draft.separateTeamPairs, () => addPair(same: false)),
        ],
      ),
    );
  }

  Widget _pairSection(String title, List<IdPair> pairs, VoidCallback add) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
            IconButton(onPressed: add, icon: const Icon(Icons.add_circle_outline)),
          ],
        ),
        if (pairs.isEmpty) const Text('Kısıt yok.'),
        ...pairs.asMap().entries.map(
              (entry) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${nameOf(entry.value.left)} ↔ ${nameOf(entry.value.right)}'),
                trailing: IconButton(
                  onPressed: () => setState(() => pairs.removeAt(entry.key)),
                  icon: const Icon(Icons.delete_outline),
                ),
              ),
            ),
      ],
    );
  }
}
