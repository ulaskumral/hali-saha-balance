import 'package:hali_saha_balance/domain/balance_engine.dart';
import 'package:hali_saha_balance/domain/models.dart';
import 'package:test/test.dart';

Player player(
  String id, {
  int value = 60,
  Position primary = Position.os,
  Position? secondary,
  int? gk,
}) =>
    Player(
      id: id,
      name: 'Oyuncu $id',
      pace: value,
      shooting: value,
      passing: value,
      technical: value,
      defending: value,
      physical: value,
      goalkeeping: gk,
      primaryPosition: primary,
      secondaryPosition: secondary,
    );

List<MatchPlayer> standard7v7() {
  final positions = [
    Position.kl,
    Position.kl,
    Position.def,
    Position.def,
    Position.def,
    Position.def,
    Position.os,
    Position.os,
    Position.os,
    Position.os,
    Position.forw,
    Position.forw,
    Position.forw,
    Position.forw,
  ];
  return List.generate(14, (i) {
    final pos = positions[i];
    return MatchPlayer(
      player: player(
        'p${i.toString().padLeft(2, '0')}',
        value: 50 + (i % 7) * 5,
        primary: pos,
        gk: pos == Position.kl ? 70 + i : null,
      ),
    );
  });
}

void main() {
  group('Derived overall', () {
    test('DEF formula matches specification', () {
      final p = MatchPlayer(
        player: Player(
          id: 'x',
          name: 'X',
          pace: 80,
          shooting: 50,
          passing: 70,
          technical: 65,
          defending: 90,
          physical: 85,
          primaryPosition: Position.def,
        ),
      );
      final expected = 0.12 * 80 + 0.04 * 50 + 0.16 * 70 + 0.13 * 65 + 0.33 * 90 + 0.22 * 85;
      expect(p.roleOverall(Position.def), closeTo(expected, 1e-9));
    });

    test('form modifier clamps effective stats to 1..99', () {
      final p = MatchPlayer(player: player('x', value: 99), form: MatchForm.inForm);
      expect(p.pace, 99);
      final low = MatchPlayer(player: player('y', value: 1), form: MatchForm.bad);
      expect(low.pace, 1);
    });
  });

  group('Constraints and search', () {
    test('same + separate contradiction returns INFEASIBLE_CONSTRAINTS', () {
      final players = standard7v7();
      final result = TeamBalancer().generate(
        BalanceRequest(
          teamSize: 7,
          players: players,
          sameTeamPairs: const [IdPair('p02', 'p03')],
          separateTeamPairs: const [IdPair('p02', 'p03')],
        ),
      );
      expect(result.errorCode, BalanceErrorCode.infeasibleConstraints);
    });

    test('pinned players remain on requested teams', () {
      final players = standard7v7();
      final result = TeamBalancer().generate(
        BalanceRequest(
          teamSize: 7,
          players: players,
          pinned: const [
            PinnedPlayer('p00', TeamSide.a),
            PinnedPlayer('p01', TeamSide.b),
          ],
        ),
      );
      expect(result.isSuccess, isTrue);
      final best = result.solutions.first;
      expect(best.teamAIds, contains('p00'));
      expect(best.teamBIds, contains('p01'));
    });

    test('7v7 is deterministic and alternatives satisfy diversity threshold', () {
      final request = BalanceRequest(teamSize: 7, players: standard7v7());
      final first = TeamBalancer().generate(request);
      final second = TeamBalancer().generate(request);
      expect(first.isSuccess, isTrue);
      expect(second.isSuccess, isTrue);
      expect(first.solutions.first.lexicographicalKey, second.solutions.first.lexicographicalKey);
      expect(first.solutions.first.loss.finalBalanceLoss, second.solutions.first.loss.finalBalanceLoss);

      final solutions = first.solutions;
      for (var i = 0; i < solutions.length; i++) {
        for (var j = i + 1; j < solutions.length; j++) {
          final a = solutions[i].teamAIds.toSet();
          final b = solutions[j].teamAIds.toSet();
          final diff = a.difference(b).length + b.difference(a).length;
          expect(diff, greaterThanOrEqualTo(4));
        }
      }
    });

    test('joker is excluded by caller and engine requires exactly 2N players', () {
      final players = standard7v7();
      final result = TeamBalancer().generate(
        BalanceRequest(
          teamSize: 7,
          players: [...players, MatchPlayer(player: player('joker'))],
        ),
      );
      expect(result.errorCode, BalanceErrorCode.invalidPlayerCount);
    });

    test('missing two goalkeeper candidates yields no valid partition', () {
      final players = standard7v7();
      final onlyOne = [
        for (var i = 0; i < players.length; i++)
          if (i == 1)
            MatchPlayer(
              player: Player(
                id: players[i].player.id,
                name: players[i].player.name,
                pace: players[i].player.pace,
                shooting: players[i].player.shooting,
                passing: players[i].player.passing,
                technical: players[i].player.technical,
                defending: players[i].player.defending,
                physical: players[i].player.physical,
                primaryPosition: Position.def,
              ),
            )
          else
            players[i],
      ];
      final result = TeamBalancer().generate(BalanceRequest(teamSize: 7, players: onlyOne));
      expect(result.errorCode, BalanceErrorCode.noValidPartition);
    });
  });
}
