import 'dart:isolate';
import 'dart:math' as math;

import 'models.dart';

const double statTolerance = 2.0;

Future<BalanceResult> generateBalancedTeamsInBackground(BalanceRequest request) async {
  final raw = await Isolate.run(() => generateBalanceJson(request.toJson()));
  return BalanceResult.fromJson(raw);
}

Map<String, dynamic> generateBalanceJson(Map<String, dynamic> json) {
  final request = BalanceRequest.fromJson(json);
  return TeamBalancer().generate(request).toJson();
}

class TeamBalancer {
  BalanceResult generate(BalanceRequest request) {
    if (request.teamSize < 5 || request.teamSize > 11 || request.players.length != request.teamSize * 2) {
      return const BalanceResult.failure(
        BalanceErrorCode.invalidPlayerCount,
        'Takım boyutu 5-11 olmalı ve algoritmaya tam olarak 2 x takım boyutu oyuncu verilmelidir.',
      );
    }

    final sortedPlayers = [...request.players]..sort((a, b) => a.player.id.compareTo(b.player.id));
    final ids = sortedPlayers.map((e) => e.player.id).toList();
    if (ids.toSet().length != ids.length) {
      return const BalanceResult.failure(
        BalanceErrorCode.infeasibleConstraints,
        'Aynı oyuncu birden fazla kez seçilmiş.',
      );
    }

    final planner = _ConstraintPlanner(request, sortedPlayers);
    final planResult = planner.build();
    if (planResult.error != null) {
      return BalanceResult.failure(BalanceErrorCode.infeasibleConstraints, planResult.error);
    }
    final plan = planResult.plan!;

    final evaluator = _SolutionEvaluator(sortedPlayers, request.teamSize, plan.hasPinnedTeams);
    final bounded = request.teamSize >= 10;

    final best = _searchBest(
      plan: plan,
      players: sortedPlayers,
      teamSize: request.teamSize,
      evaluator: evaluator,
      bounded: bounded,
      mustDifferFrom: const [],
    );
    if (best == null) {
      return const BalanceResult.failure(
        BalanceErrorCode.noValidPartition,
        'Kısıtlar sağlansa da iki takım için geçerli kaleci/rol yerleşimi bulunamadı.',
      );
    }

    final threshold = request.teamSize >= 7 ? 4 : 2;
    final second = _searchBest(
      plan: plan,
      players: sortedPlayers,
      teamSize: request.teamSize,
      evaluator: evaluator,
      bounded: bounded,
      mustDifferFrom: [(best, threshold)],
    );

    final third = second == null
        ? null
        : _searchBest(
            plan: plan,
            players: sortedPlayers,
            teamSize: request.teamSize,
            evaluator: evaluator,
            bounded: bounded,
            mustDifferFrom: [(best, threshold), (second, threshold)],
          );

    return BalanceResult.success([
      best,
      if (second != null) second,
      if (third != null) third,
    ]);
  }

  BalanceSolution? _searchBest({
    required _SearchPlan plan,
    required List<MatchPlayer> players,
    required int teamSize,
    required _SolutionEvaluator evaluator,
    required bool bounded,
    required List<(BalanceSolution, int)> mustDifferFrom,
  }) {
    BalanceSolution? best;
    final playerCount = players.length;
    final allMask = (1 << playerCount) - 1;

    final diversityMasks = [
      for (final item in mustDifferFrom) (_maskForIds(item.$1.teamAIds, players), item.$2),
    ];

    bool diversityOk(BalanceSolution solution) {
      final solutionMask = _maskForIds(solution.teamAIds, players);
      for (final item in diversityMasks) {
        final diff = _bitCount(solutionMask ^ item.$1);
        if (diff < item.$2) return false;
      }
      return true;
    }

    void walk(int index, int mask, int countA, List<double> sumA) {
      if (countA > teamSize) return;
      final needed = teamSize - countA;
      if (!plan.suffixReachable[index].contains(needed)) return;

      if (bounded && best != null) {
        final rawLowerBound = _rawStatLowerBound(
          plan: plan,
          startIndex: index,
          currentASums: sumA,
          totalSums: plan.totalStatSums,
          outfieldCount: teamSize - 1,
        );
        final finalLowerBound = 0.385 * rawLowerBound;
        if (finalLowerBound > best!.loss.finalBalanceLoss) return;
      }

      if (index == plan.components.length) {
        if (countA != teamSize) return;
        final maskB = allMask ^ mask;
        final solution = evaluator.evaluate(mask, maskB);
        if (solution == null || !diversityOk(solution)) return;
        if (best == null || _compareSolutions(solution, best!) < 0) best = solution;
        return;
      }

      final component = plan.components[index];
      for (final option in component.options) {
        final nextSums = List<double>.generate(
          6,
          (i) => sumA[i] + option.aStatSums[i],
          growable: false,
        );
        walk(index + 1, mask | option.aMask, countA + option.aCount, nextSums);
      }
    }

    walk(0, 0, 0, List<double>.filled(6, 0));
    return best;
  }

  static int _maskForIds(List<String> ids, List<MatchPlayer> players) {
    final wanted = ids.toSet();
    var mask = 0;
    for (var i = 0; i < players.length; i++) {
      if (wanted.contains(players[i].player.id)) mask |= 1 << i;
    }
    return mask;
  }
}

class _ConstraintPlanner {
  _ConstraintPlanner(this.request, this.players);
  final BalanceRequest request;
  final List<MatchPlayer> players;

  _PlanBuildResult build() {
    final indexById = <String, int>{for (var i = 0; i < players.length; i++) players[i].player.id: i};

    String? validatePair(IdPair pair) {
      if (!indexById.containsKey(pair.left) || !indexById.containsKey(pair.right)) {
        return 'Kısıt, seçili olmayan bir oyuncuya referans veriyor.';
      }
      if (pair.left == pair.right) return 'Bir oyuncu kendisiyle eşleştirilemez.';
      return null;
    }

    for (final pair in [...request.sameTeamPairs, ...request.separateTeamPairs]) {
      final error = validatePair(pair);
      if (error != null) return _PlanBuildResult.error(error);
    }
    for (final pin in request.pinned) {
      if (!indexById.containsKey(pin.playerId)) {
        return _PlanBuildResult.error('Pinned kısıtı seçili olmayan bir oyuncuya referans veriyor.');
      }
    }

    final uf = _UnionFind(players.length);
    for (final pair in request.sameTeamPairs) {
      uf.union(indexById[pair.left]!, indexById[pair.right]!);
    }

    final groups = <int, List<int>>{};
    for (var i = 0; i < players.length; i++) {
      groups.putIfAbsent(uf.find(i), () => []).add(i);
    }
    if (groups.values.any((g) => g.length > request.teamSize)) {
      return _PlanBuildResult.error('Same-Team grubu takım kapasitesinden büyük.');
    }

    final roots = groups.keys.toList()..sort();
    final rootToNode = <int, int>{for (var i = 0; i < roots.length; i++) roots[i]: i};
    final graph = List.generate(roots.length, (_) => <int>{});

    for (final pair in request.separateTeamPairs) {
      final leftRoot = uf.find(indexById[pair.left]!);
      final rightRoot = uf.find(indexById[pair.right]!);
      if (leftRoot == rightRoot) {
        return _PlanBuildResult.error('Aynı Same-Team grubunda bulunan oyuncular Separate-Team yapılamaz.');
      }
      final a = rootToNode[leftRoot]!;
      final b = rootToNode[rightRoot]!;
      graph[a].add(b);
      graph[b].add(a);
    }

    final pinByRoot = <int, TeamSide>{};
    for (final pin in request.pinned) {
      final root = uf.find(indexById[pin.playerId]!);
      final previous = pinByRoot[root];
      if (previous != null && previous != pin.team) {
        return _PlanBuildResult.error('Aynı Same-Team grubunda Team A ve Team B pin çakışması var.');
      }
      pinByRoot[root] = pin.team;
    }

    final color = List<int>.filled(roots.length, -1);
    final components = <_SearchComponent>[];

    for (var start = 0; start < roots.length; start++) {
      if (color[start] != -1) continue;
      final queue = <int>[start];
      color[start] = 0;
      final sideNodes = [<int>[], <int>[]];
      var q = 0;
      while (q < queue.length) {
        final node = queue[q++];
        sideNodes[color[node]].add(node);
        for (final next in graph[node]) {
          if (color[next] == -1) {
            color[next] = 1 - color[node];
            queue.add(next);
          } else if (color[next] == color[node]) {
            return _PlanBuildResult.error('Separate-Team kısıtları iki takımlı yerleşimde çelişiyor.');
          }
        }
      }

      final sidePlayers = [<int>[], <int>[]];
      for (var c = 0; c < 2; c++) {
        for (final node in sideNodes[c]) {
          sidePlayers[c].addAll(groups[roots[node]]!);
        }
      }

      int? forcedOrientation;
      for (var c = 0; c < 2; c++) {
        for (final node in sideNodes[c]) {
          final pin = pinByRoot[roots[node]];
          if (pin == null) continue;
          final orientation = pin == TeamSide.a ? c : 1 - c;
          if (forcedOrientation != null && forcedOrientation != orientation) {
            return _PlanBuildResult.error('Pinned ve Separate-Team kısıtları birbiriyle çelişiyor.');
          }
          forcedOrientation = orientation;
        }
      }

      _ComponentOption optionFor(int orientation) {
        final aSide = sidePlayers[orientation];
        var mask = 0;
        final sums = List<double>.filled(6, 0);
        for (final playerIndex in aSide) {
          mask |= 1 << playerIndex;
          final p = players[playerIndex];
          sums[0] += p.pace;
          sums[1] += p.shooting;
          sums[2] += p.passing;
          sums[3] += p.technical;
          sums[4] += p.defending;
          sums[5] += p.physical;
        }
        return _ComponentOption(aMask: mask, aCount: aSide.length, aStatSums: sums);
      }

      final options = forcedOrientation == null
          ? [optionFor(0), optionFor(1)]
          : [optionFor(forcedOrientation)];
      components.add(_SearchComponent(options));
    }

    // When A/B are unlabeled, fixing one free component removes mirror duplicates.
    final hasPins = request.pinned.isNotEmpty;
    if (!hasPins && components.isNotEmpty && components.first.options.length == 2) {
      components[0] = _SearchComponent([components.first.options.first]);
    }

    final suffixReachable = List.generate(components.length + 1, (_) => <int>{});
    suffixReachable[components.length].add(0);
    for (var i = components.length - 1; i >= 0; i--) {
      for (final option in components[i].options) {
        for (final tail in suffixReachable[i + 1]) {
          suffixReachable[i].add(option.aCount + tail);
        }
      }
    }
    if (!suffixReachable[0].contains(request.teamSize)) {
      return _PlanBuildResult.error('Kısıtlar altında eşit takım mevcudu oluşturulamıyor.');
    }

    final totalSums = List<double>.filled(6, 0);
    for (final p in players) {
      totalSums[0] += p.pace;
      totalSums[1] += p.shooting;
      totalSums[2] += p.passing;
      totalSums[3] += p.technical;
      totalSums[4] += p.defending;
      totalSums[5] += p.physical;
    }

    return _PlanBuildResult.ok(
      _SearchPlan(
        components: components,
        suffixReachable: suffixReachable,
        totalStatSums: totalSums,
        hasPinnedTeams: hasPins,
      ),
    );
  }
}

class _SolutionEvaluator {
  _SolutionEvaluator(this.players, this.teamSize, this.hasPinnedTeams);
  final List<MatchPlayer> players;
  final int teamSize;
  final bool hasPinnedTeams;
  final Map<int, TeamProfile?> _profileCache = {};

  BalanceSolution? evaluate(int maskA, int maskB) {
    var actualA = maskA;
    var actualB = maskB;
    if (!hasPinnedTeams) {
      final aIds = _ids(maskA);
      final bIds = _ids(maskB);
      if (_signature(bIds).compareTo(_signature(aIds)) < 0) {
        actualA = maskB;
        actualB = maskA;
      }
    }

    final profileA = _profileCache.putIfAbsent(actualA, () => _evaluateTeam(actualA));
    final profileB = _profileCache.putIfAbsent(actualB, () => _evaluateTeam(actualB));
    if (profileA == null || profileB == null) return null;

    final rawStat = _rms(List.generate(6, (i) => _normalizedGap(profileA.outfieldAverages[i], profileB.outfieldAverages[i])));

    final ad = ((profileA.attack - profileB.defense) - (profileB.attack - profileA.defense)).abs() / 196.0;
    final bp = ((profileA.buildUp - profileB.pressing) - (profileB.buildUp - profileA.pressing)).abs() / 196.0;
    final pc = ((profileA.progression - profileB.containment) -
            (profileB.progression - profileA.containment))
        .abs() /
        196.0;
    final matchup = (0.50 * ad + 0.30 * bp + 0.20 * pc).clamp(0.0, 1.0);

    final roleFitGap = (profileA.roleFitQuality - profileB.roleFitQuality).abs();
    final emergencyGap = (profileA.emergencyOutfieldRoles - profileB.emergencyOutfieldRoles).abs() / teamSize;
    final roleBalance = (0.70 * roleFitGap + 0.30 * emergencyGap).clamp(0.0, 1.0);

    final goalkeeper = _normalizedGap(profileA.goalkeeperStrength, profileB.goalkeeperStrength);
    final overall = _normalizedGap(profileA.averageOverall, profileB.averageOverall);

    final tacticalA = [
      profileA.attack,
      profileA.defense,
      profileA.buildUp,
      profileA.pressing,
      profileA.progression,
      profileA.containment,
    ];
    final tacticalB = [
      profileB.attack,
      profileB.defense,
      profileB.buildUp,
      profileB.pressing,
      profileB.progression,
      profileB.containment,
    ];
    final tactical = _rms(List.generate(6, (i) => _normalizedGap(tacticalA[i], tacticalB[i])));

    final strength = _strengthCurveLoss(profileA, profileB, actualA, actualB);

    final base = 0.18 * rawStat +
        0.20 * roleBalance +
        0.24 * matchup +
        0.10 * goalkeeper +
        0.14 * strength +
        0.06 * overall +
        0.08 * tactical;
    final critical = math.max(math.max(rawStat, roleBalance), math.max(matchup, strength));
    final finalLoss = (0.75 * base + 0.25 * critical).clamp(0.0, 1.0);

    final idsA = _ids(actualA);
    final idsB = _ids(actualB);
    final loss = LossBreakdown(
      rawStatLoss: rawStat,
      roleBalanceLoss: roleBalance,
      matchupLoss: matchup,
      goalkeeperLoss: goalkeeper,
      strengthCurveLoss: strength,
      overallLoss: overall,
      tacticalProfileLoss: tactical,
      baseLoss: base,
      criticalLoss: critical,
      finalBalanceLoss: finalLoss,
    );

    return BalanceSolution(
      teamAIds: idsA,
      teamBIds: idsB,
      profileA: profileA,
      profileB: profileB,
      loss: loss,
      lexicographicalKey: '${_signature(idsA)}|${_signature(idsB)}',
    );
  }

  TeamProfile? _evaluateTeam(int mask) {
    final team = <MatchPlayer>[];
    for (var i = 0; i < players.length; i++) {
      if ((mask & (1 << i)) != 0) team.add(players[i]);
    }
    if (team.length != teamSize) return null;
    team.sort((a, b) => a.player.id.compareTo(b.player.id));

    _FormationEval? bestFormation;
    for (var gkIndex = 0; gkIndex < team.length; gkIndex++) {
      final candidate = team[gkIndex];
      if (!candidate.canGoalkeep) continue;
      final formation = _bestFormationWithGoalkeeper(team, gkIndex, teamSize);
      if (formation == null) continue;
      if (bestFormation == null || formation.compareTo(bestFormation) < 0) {
        bestFormation = formation;
      }
    }
    if (bestFormation == null) return null;

    final assigned = bestFormation.assignedRoles;
    final goalkeeperId = bestFormation.goalkeeperId;
    final outfield = team.where((p) => p.player.id != goalkeeperId).toList();
    final n = outfield.length.toDouble();
    if (n <= 0) return null;

    double avg(double Function(MatchPlayer) pick) => outfield.fold<double>(0, (sum, p) => sum + pick(p)) / n;
    final pace = avg((p) => p.pace);
    final shooting = avg((p) => p.shooting);
    final passing = avg((p) => p.passing);
    final technical = avg((p) => p.technical);
    final defending = avg((p) => p.defending);
    final physical = avg((p) => p.physical);

    final gk = team.firstWhere((p) => p.player.id == goalkeeperId);
    final gkValue = gk.goalkeeping ?? gk.tempGoalkeeping;
    if (gkValue == null) return null;
    final goalkeeperStrength = 0.72 * gkValue + 0.10 * gk.passing + 0.08 * gk.technical + 0.06 * gk.physical + 0.04 * gk.pace;

    final attack = 0.28 * shooting + 0.22 * technical + 0.18 * pace + 0.18 * passing + 0.14 * physical;
    final outfieldDefense = 0.46 * defending + 0.22 * physical + 0.14 * pace + 0.10 * technical + 0.08 * passing;
    final defense = 0.88 * outfieldDefense + 0.12 * goalkeeperStrength;
    final buildUp = 0.42 * passing + 0.30 * technical + 0.12 * pace + 0.08 * defending + 0.08 * physical;
    final pressing = 0.42 * defending + 0.24 * physical + 0.18 * pace + 0.10 * technical + 0.06 * passing;
    final progression = 0.40 * technical + 0.24 * passing + 0.20 * pace + 0.10 * physical + 0.06 * shooting;
    final containment = 0.44 * defending + 0.22 * physical + 0.18 * pace + 0.10 * technical + 0.06 * passing;

    var overallSum = 0.0;
    for (final p in team) {
      overallSum += p.roleOverall(assigned[p.player.id]!);
    }

    return TeamProfile(
      attack: attack,
      defense: defense,
      buildUp: buildUp,
      pressing: pressing,
      progression: progression,
      containment: containment,
      goalkeeperStrength: goalkeeperStrength,
      averageOverall: overallSum / team.length,
      formationQuality: bestFormation.formationQuality,
      roleFitQuality: bestFormation.roleFitQuality,
      emergencyOutfieldRoles: bestFormation.emergencyOutfieldRoles,
      outfieldAverages: [pace, shooting, passing, technical, defending, physical],
      assignedRoles: assigned,
    );
  }

  double _strengthCurveLoss(TeamProfile a, TeamProfile b, int maskA, int maskB) {
    List<double> curve(int mask, TeamProfile profile) {
      final values = <double>[];
      for (var i = 0; i < players.length; i++) {
        if ((mask & (1 << i)) == 0) continue;
        final p = players[i];
        values.add(p.roleOverall(profile.assignedRoles[p.player.id]!));
      }
      values.sort((x, y) => y.compareTo(x));
      return values;
    }

    final ca = curve(maskA, a);
    final cb = curve(maskB, b);
    var weighted = 0.0;
    var weightSum = 0.0;
    for (var i = 0; i < ca.length; i++) {
      final percentile = ca.length == 1 ? 0.0 : i / (ca.length - 1);
      final weight = percentile <= 0.25
          ? 1.35
          : percentile >= 0.75
              ? 1.15
              : 1.00;
      weighted += weight * _normalizedGap(ca[i], cb[i]);
      weightSum += weight;
    }
    return weightSum == 0 ? 0 : weighted / weightSum;
  }

  List<String> _ids(int mask) {
    final result = <String>[];
    for (var i = 0; i < players.length; i++) {
      if ((mask & (1 << i)) != 0) result.add(players[i].player.id);
    }
    result.sort();
    return result;
  }

  static String _signature(List<String> ids) => ids.join(',');
}

_FormationEval? _bestFormationWithGoalkeeper(List<MatchPlayer> team, int goalkeeperIndex, int teamSize) {
  final counts = _outfieldRoleCounts(teamSize);
  final goalkeeper = team[goalkeeperIndex];
  final outfield = <MatchPlayer>[];
  for (var i = 0; i < team.length; i++) {
    if (i != goalkeeperIndex) outfield.add(team[i]);
  }

  final memo = <String, _RoleAssignment?>{};
  _RoleAssignment? solve(int index, int defLeft, int osLeft, int forLeft) {
    final key = '$index:$defLeft:$osLeft:$forLeft';
    if (memo.containsKey(key)) return memo[key];
    if (index == outfield.length) {
      if (defLeft == 0 && osLeft == 0 && forLeft == 0) {
        return memo[key] = const _RoleAssignment(score: 0, fitSum: 0, emergency: 0, roles: {});
      }
      return memo[key] = null;
    }

    final p = outfield[index];
    _RoleAssignment? best;
    final choices = <(Position, int)>[
      if (defLeft > 0) (Position.def, defLeft),
      if (osLeft > 0) (Position.os, osLeft),
      if (forLeft > 0) (Position.forw, forLeft),
    ];
    for (final choice in choices) {
      final role = choice.$1;
      final child = solve(
        index + 1,
        defLeft - (role == Position.def ? 1 : 0),
        osLeft - (role == Position.os ? 1 : 0),
        forLeft - (role == Position.forw ? 1 : 0),
      );
      if (child == null) continue;
      final fit = p.fitFor(role);
      final emergency = p.player.primaryPosition != role && p.player.secondaryPosition != role;
      final roleSkill = p.roleOverall(role) / 99.0;
      final score = 0.65 * fit + 0.35 * roleSkill;
      final roles = {...child.roles, p.player.id: role};
      final candidate = _RoleAssignment(
        score: child.score + score,
        fitSum: child.fitSum + fit,
        emergency: child.emergency + (emergency ? 1 : 0),
        roles: roles,
      );
      if (best == null || candidate.compareTo(best) < 0) best = candidate;
    }
    return memo[key] = best;
  }

  final assignment = solve(0, counts.$1, counts.$2, counts.$3);
  if (assignment == null) return null;

  final gkFit = goalkeeper.player.primaryPosition == Position.kl
      ? 1.0
      : goalkeeper.player.secondaryPosition == Position.kl
          ? 0.95
          : 0.82;
  final gkSkill = goalkeeper.roleOverall(Position.kl) / 99.0;
  final gkScore = 0.65 * gkFit + 0.35 * gkSkill;
  final roles = {...assignment.roles, goalkeeper.player.id: Position.kl};
  final formationQuality = (assignment.score + gkScore) / teamSize;
  final roleFitQuality = (assignment.fitSum + gkFit) / teamSize;

  return _FormationEval(
    goalkeeperId: goalkeeper.player.id,
    formationQuality: formationQuality,
    roleFitQuality: roleFitQuality,
    emergencyOutfieldRoles: assignment.emergency,
    assignedRoles: roles,
  );
}

(int, int, int) _outfieldRoleCounts(int teamSize) => switch (teamSize) {
      5 => (2, 1, 1),
      6 => (2, 2, 1),
      7 => (2, 2, 2),
      8 => (3, 2, 2),
      9 => (3, 3, 2),
      10 => (3, 3, 3),
      11 => (4, 3, 3),
      _ => throw ArgumentError.value(teamSize, 'teamSize'),
    };

class _RoleAssignment {
  const _RoleAssignment({required this.score, required this.fitSum, required this.emergency, required this.roles});
  final double score;
  final double fitSum;
  final int emergency;
  final Map<String, Position> roles;

  int compareTo(_RoleAssignment other) {
    var c = other.score.compareTo(score); // Higher score first.
    if (c != 0) return c;
    c = emergency.compareTo(other.emergency); // Fewer emergencies first.
    if (c != 0) return c;
    return _roleSignature(roles).compareTo(_roleSignature(other.roles));
  }
}

class _FormationEval {
  const _FormationEval({
    required this.goalkeeperId,
    required this.formationQuality,
    required this.roleFitQuality,
    required this.emergencyOutfieldRoles,
    required this.assignedRoles,
  });

  final String goalkeeperId;
  final double formationQuality;
  final double roleFitQuality;
  final int emergencyOutfieldRoles;
  final Map<String, Position> assignedRoles;

  int compareTo(_FormationEval other) {
    var c = other.formationQuality.compareTo(formationQuality);
    if (c != 0) return c;
    c = emergencyOutfieldRoles.compareTo(other.emergencyOutfieldRoles);
    if (c != 0) return c;
    c = goalkeeperId.compareTo(other.goalkeeperId);
    if (c != 0) return c;
    return _roleSignature(assignedRoles).compareTo(_roleSignature(other.assignedRoles));
  }
}

String _roleSignature(Map<String, Position> roles) {
  final keys = roles.keys.toList()..sort();
  return keys.map((id) => '$id:${positionCode(roles[id]!)}').join('|');
}

double _normalizedGap(double a, double b) => ((math.max(0.0, (a - b).abs() - statTolerance)) / 96.0).clamp(0.0, 1.0);

double _rms(List<double> values) {
  if (values.isEmpty) return 0;
  final sumSquares = values.fold<double>(0, (sum, v) => sum + v * v);
  return math.sqrt(sumSquares / values.length);
}

int _compareSolutions(BalanceSolution a, BalanceSolution b) {
  var c = a.loss.finalBalanceLoss.compareTo(b.loss.finalBalanceLoss);
  if (c != 0) return c;
  c = a.loss.criticalLoss.compareTo(b.loss.criticalLoss);
  if (c != 0) return c;
  c = a.loss.matchupLoss.compareTo(b.loss.matchupLoss);
  if (c != 0) return c;
  c = a.loss.roleBalanceLoss.compareTo(b.loss.roleBalanceLoss);
  if (c != 0) return c;
  c = a.loss.strengthCurveLoss.compareTo(b.loss.strengthCurveLoss);
  if (c != 0) return c;
  c = b.combinedFormationQuality.compareTo(a.combinedFormationQuality);
  if (c != 0) return c;
  return a.lexicographicalKey.compareTo(b.lexicographicalKey);
}

int _bitCount(int value) {
  var v = value;
  var count = 0;
  while (v != 0) {
    v &= v - 1;
    count++;
  }
  return count;
}

double _rawStatLowerBound({
  required _SearchPlan plan,
  required int startIndex,
  required List<double> currentASums,
  required List<double> totalSums,
  required int outfieldCount,
}) {
  if (outfieldCount <= 0) return 0;
  final gaps = <double>[];
  for (var stat = 0; stat < 6; stat++) {
    var minAdd = 0.0;
    var maxAdd = 0.0;
    for (var i = startIndex; i < plan.components.length; i++) {
      final vals = plan.components[i].options.map((o) => o.aStatSums[stat]).toList();
      minAdd += vals.reduce(math.min);
      maxAdd += vals.reduce(math.max);
    }
    final minATotal = currentASums[stat] + minAdd;
    final maxATotal = currentASums[stat] + maxAdd;

    // Outfield difference numerator is 2*A_total - total - gkA + gkB.
    // Allowing gkA/gkB anywhere in [1,99] widens the interval and therefore
    // can only lower this bound, preserving admissibility.
    final low = 2 * minATotal - totalSums[stat] - 98.0;
    final high = 2 * maxATotal - totalSums[stat] + 98.0;
    final minAbs = low <= 0 && high >= 0 ? 0.0 : math.min(low.abs(), high.abs());
    final minMeanGap = minAbs / outfieldCount;
    gaps.add(_normalizedGap(minMeanGap, 0));
  }
  return _rms(gaps);
}

class _UnionFind {
  _UnionFind(int size)
      : parent = List.generate(size, (i) => i),
        rank = List.filled(size, 0);
  final List<int> parent;
  final List<int> rank;

  int find(int x) {
    if (parent[x] != x) parent[x] = find(parent[x]);
    return parent[x];
  }

  void union(int a, int b) {
    var ra = find(a);
    var rb = find(b);
    if (ra == rb) return;
    if (rank[ra] < rank[rb]) {
      final t = ra;
      ra = rb;
      rb = t;
    }
    parent[rb] = ra;
    if (rank[ra] == rank[rb]) rank[ra]++;
  }
}

class _SearchPlan {
  const _SearchPlan({
    required this.components,
    required this.suffixReachable,
    required this.totalStatSums,
    required this.hasPinnedTeams,
  });
  final List<_SearchComponent> components;
  final List<Set<int>> suffixReachable;
  final List<double> totalStatSums;
  final bool hasPinnedTeams;
}

class _SearchComponent {
  const _SearchComponent(this.options);
  final List<_ComponentOption> options;
}

class _ComponentOption {
  const _ComponentOption({required this.aMask, required this.aCount, required this.aStatSums});
  final int aMask;
  final int aCount;
  final List<double> aStatSums;
}

class _PlanBuildResult {
  const _PlanBuildResult.ok(this.plan) : error = null;
  const _PlanBuildResult.error(this.error) : plan = null;
  final _SearchPlan? plan;
  final String? error;
}
