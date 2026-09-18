import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/balance_engine.dart';
import '../../domain/models.dart';
import '../balance_analysis/balance_result_screen.dart';
import '../players/players_screen.dart';
import 'constraints_editor.dart';

enum OddPlayerMode { reserve, joker }

class TeamGeneratorScreen extends ConsumerStatefulWidget {
  const TeamGeneratorScreen({super.key});

  @override
  ConsumerState<TeamGeneratorScreen> createState() => _TeamGeneratorScreenState();
}

class _TeamGeneratorScreenState extends ConsumerState<TeamGeneratorScreen> {
  var teamSize = 7;
  final selectedIds = <String>{};
  final forms = <String, MatchForm>{};
  final tempGoalkeeping = <String, int>{};
  ConstraintDraft constraints = ConstraintDraft();
  OddPlayerMode oddMode = OddPlayerMode.reserve;
  String? oddPlayerId;
  bool generating = false;

  int get normalPlayerCount => teamSize * 2;
  int get maxSelection => normalPlayerCount + 1;

  Future<void> editEmergencyGk(Player player) async {
    final controller = TextEditingController(text: tempGoalkeeping[player.id]?.toString() ?? '60');
    final value = await showDialog<int?>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${player.name} • Emergency GK'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Maça özel kalecilik (1-99)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, -1), child: const Text('Temizle')),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
          FilledButton(
            onPressed: () {
              final parsed = int.tryParse(controller.text);
              if (parsed == null || parsed < 1 || parsed > 99) return;
              Navigator.pop(context, parsed);
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;
    setState(() {
      if (value == -1) {
        tempGoalkeeping.remove(player.id);
      } else {
        tempGoalkeeping[player.id] = value;
      }
    });
  }

  List<MatchPlayer> buildAlgorithmPlayers(List<Player> all) {
    final byId = {for (final p in all) p.id: p};
    final excluded = selectedIds.length.isOdd ? oddPlayerId : null;
    return selectedIds
        .where((id) => id != excluded)
        .map(
          (id) => MatchPlayer(
            player: byId[id]!,
            form: forms[id] ?? MatchForm.normal,
            temporaryGoalkeeping: tempGoalkeeping[id],
          ),
        )
        .toList();
  }

  Future<void> openConstraints(List<Player> all) async {
    final algorithmPlayers = buildAlgorithmPlayers(all);
    final validIds = algorithmPlayers.map((p) => p.player.id).toSet();
    constraints.pinned.removeWhere((e) => !validIds.contains(e.playerId));
    constraints.sameTeamPairs.removeWhere((e) => !validIds.contains(e.left) || !validIds.contains(e.right));
    constraints.separateTeamPairs.removeWhere((e) => !validIds.contains(e.left) || !validIds.contains(e.right));
    final result = await Navigator.of(context).push<ConstraintDraft>(
      MaterialPageRoute(
        builder: (_) => ConstraintsEditorScreen(players: algorithmPlayers, initial: constraints),
      ),
    );
    if (result != null) setState(() => constraints = result);
  }

  Future<void> generate(List<Player> all) async {
    if (selectedIds.length != normalPlayerCount && selectedIds.length != maxSelection) {
      _message('Tam $normalPlayerCount oyuncu seçin; isterseniz bir ekstra oyuncuyu Yedek/Joker yapabilirsiniz.');
      return;
    }
    if (selectedIds.length == maxSelection && (oddPlayerId == null || !selectedIds.contains(oddPlayerId))) {
      _message('Ekstra oyuncu için Yedek/Joker oyuncusunu seçin.');
      return;
    }
    final algorithmPlayers = buildAlgorithmPlayers(all);
    final gkCandidates = algorithmPlayers.where((p) => p.canGoalkeep).length;
    if (gkCandidates < 2) {
      _message('İki takım için en az 2 kaleci adayı gerekir. Natural KL yetersizse Emergency GK puanı girin.');
      return;
    }

    setState(() => generating = true);
    final validIds = algorithmPlayers.map((p) => p.player.id).toSet();
    final request = BalanceRequest(
      teamSize: teamSize,
      players: algorithmPlayers,
      pinned: constraints.pinned.where((e) => validIds.contains(e.playerId)).toList(),
      sameTeamPairs: constraints.sameTeamPairs.where((e) => validIds.contains(e.left) && validIds.contains(e.right)).toList(),
      separateTeamPairs: constraints.separateTeamPairs.where((e) => validIds.contains(e.left) && validIds.contains(e.right)).toList(),
    );
    final result = await generateBalancedTeamsInBackground(request);
    if (!mounted) return;
    setState(() => generating = false);
    if (!result.isSuccess) {
      _message('${result.errorCode?.name ?? 'HATA'}: ${result.message ?? ''}');
      return;
    }
    final byId = {for (final p in all) p.id: p};
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BalanceResultScreen(
          request: request,
          result: result,
          playerById: byId,
          jokerPlayerId: selectedIds.length == maxSelection && oddMode == OddPlayerMode.joker ? oddPlayerId : null,
          reservePlayerId: selectedIds.length == maxSelection && oddMode == OddPlayerMode.reserve ? oddPlayerId : null,
        ),
      ),
    );
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final playersAsync = ref.watch(playersProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Akıllı takım dengeleme')),
      body: playersAsync.when(
        data: (players) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: teamSize,
                      decoration: const InputDecoration(labelText: 'Takım boyutu', border: OutlineInputBorder()),
                      items: [for (var n = 5; n <= 11; n++) DropdownMenuItem(value: n, child: Text('${n}v$n'))],
                      onChanged: generating
                          ? null
                          : (value) => setState(() {
                                teamSize = value!;
                                selectedIds.clear();
                                oddPlayerId = null;
                                constraints = ConstraintDraft();
                              }),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.tonalIcon(
                    onPressed: selectedIds.length >= 2 ? () => openConstraints(players) : null,
                    icon: const Icon(Icons.rule),
                    label: Text('Kısıt (${constraints.pinned.length + constraints.sameTeamPairs.length + constraints.separateTeamPairs.length})'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text('${selectedIds.length}/$normalPlayerCount seçili${selectedIds.length == maxSelection ? ' + 1 özel oyuncu' : ''}'),
            ),
            if (selectedIds.length == maxSelection)
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      SegmentedButton<OddPlayerMode>(
                        segments: const [
                          ButtonSegment(value: OddPlayerMode.reserve, label: Text('Yedek'), icon: Icon(Icons.event_seat_outlined)),
                          ButtonSegment(value: OddPlayerMode.joker, label: Text('Joker'), icon: Icon(Icons.auto_awesome)),
                        ],
                        selected: {oddMode},
                        onSelectionChanged: (v) => setState(() => oddMode = v.first),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: oddPlayerId,
                        decoration: const InputDecoration(labelText: 'Özel oyuncu', border: OutlineInputBorder()),
                        items: selectedIds
                            .map((id) => players.firstWhere((p) => p.id == id))
                            .map((p) => DropdownMenuItem(value: p.id, child: Text(p.name)))
                            .toList(),
                        onChanged: (v) => setState(() => oddPlayerId = v),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 100),
                itemCount: players.length,
                itemBuilder: (context, index) {
                  final player = players[index];
                  final selected = selectedIds.contains(player.id);
                  return Card(
                    child: Column(
                      children: [
                        CheckboxListTile(
                          value: selected,
                          onChanged: (checked) {
                            setState(() {
                              if (checked == true) {
                                if (selectedIds.length < maxSelection) selectedIds.add(player.id);
                              } else {
                                selectedIds.remove(player.id);
                                forms.remove(player.id);
                                tempGoalkeeping.remove(player.id);
                                if (oddPlayerId == player.id) oddPlayerId = null;
                              }
                            });
                          },
                          secondary: CircleAvatar(child: Text(player.initials)),
                          title: Text(player.name),
                          subtitle: Text('${positionCode(player.primaryPosition)}${player.goalkeeping == null ? '' : ' • KAL ${player.goalkeeping}'}'),
                        ),
                        if (selected)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<MatchForm>(
                                    initialValue: forms[player.id] ?? MatchForm.normal,
                                    decoration: const InputDecoration(labelText: 'Maç formu', isDense: true),
                                    items: const [
                                      DropdownMenuItem(value: MatchForm.bad, child: Text('Kötü (-15%)')),
                                      DropdownMenuItem(value: MatchForm.normal, child: Text('Normal')),
                                      DropdownMenuItem(value: MatchForm.inForm, child: Text('Formda (+10%)')),
                                    ],
                                    onChanged: (v) => setState(() => forms[player.id] = v!),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                TextButton.icon(
                                  onPressed: () => editEmergencyGk(player),
                                  icon: const Icon(Icons.sports_handball),
                                  label: Text(tempGoalkeeping[player.id] == null ? 'Emergency GK' : 'GK ${tempGoalkeeping[player.id]}'),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Oyuncular yüklenemedi: $e')),
      ),
      floatingActionButton: playersAsync.value == null
          ? null
          : FloatingActionButton.extended(
              onPressed: generating ? null : () => generate(playersAsync.value!),
              icon: generating
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.balance),
              label: Text(generating ? 'Hesaplanıyor' : 'Takımları üret'),
            ),
    );
  }
}
