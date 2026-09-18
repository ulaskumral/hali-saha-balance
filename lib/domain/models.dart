import 'dart:math' as math;

enum Position { kl, def, os, forw }

enum MatchForm {
  bad(-0.15),
  normal(0.0),
  inForm(0.10);

  const MatchForm(this.modifier);
  final double modifier;
}

enum TeamSide { a, b }

enum BalanceErrorCode {
  infeasibleConstraints,
  invalidPlayerCount,
  noValidPartition,
}

Position positionFromCode(String value) => switch (value) {
      'KL' => Position.kl,
      'DEF' => Position.def,
      'OS' => Position.os,
      'FOR' => Position.forw,
      _ => throw ArgumentError.value(value, 'value', 'Unknown position code'),
    };

String positionCode(Position value) => switch (value) {
      Position.kl => 'KL',
      Position.def => 'DEF',
      Position.os => 'OS',
      Position.forw => 'FOR',
    };

class Player {
  const Player({
    required this.id,
    required this.name,
    required this.pace,
    required this.shooting,
    required this.passing,
    required this.technical,
    required this.defending,
    required this.physical,
    required this.primaryPosition,
    this.secondaryPosition,
    this.goalkeeping,
    this.photoPath,
  });

  final String id;
  final String name;
  final int pace;
  final int shooting;
  final int passing;
  final int technical;
  final int defending;
  final int physical;
  final int? goalkeeping;
  final Position primaryPosition;
  final Position? secondaryPosition;
  final String? photoPath;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'pace': pace,
        'shooting': shooting,
        'passing': passing,
        'technical': technical,
        'defending': defending,
        'physical': physical,
        'goalkeeping': goalkeeping,
        'primaryPosition': positionCode(primaryPosition),
        'secondaryPosition': secondaryPosition == null ? null : positionCode(secondaryPosition!),
        'photoPath': photoPath,
      };

  factory Player.fromJson(Map<String, dynamic> json) => Player(
        id: json['id'] as String,
        name: json['name'] as String,
        pace: json['pace'] as int,
        shooting: json['shooting'] as int,
        passing: json['passing'] as int,
        technical: json['technical'] as int,
        defending: json['defending'] as int,
        physical: json['physical'] as int,
        goalkeeping: json['goalkeeping'] as int?,
        primaryPosition: positionFromCode(json['primaryPosition'] as String),
        secondaryPosition: json['secondaryPosition'] == null
            ? null
            : positionFromCode(json['secondaryPosition'] as String),
        photoPath: json['photoPath'] as String?,
      );

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, math.min(2, parts.first.length)).toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}

class MatchPlayer {
  const MatchPlayer({
    required this.player,
    this.form = MatchForm.normal,
    this.temporaryGoalkeeping,
  });

  final Player player;
  final MatchForm form;
  final int? temporaryGoalkeeping;

  double _eff(int value) => (value * (1 + form.modifier)).clamp(1.0, 99.0);

  double get pace => _eff(player.pace);
  double get shooting => _eff(player.shooting);
  double get passing => _eff(player.passing);
  double get technical => _eff(player.technical);
  double get defending => _eff(player.defending);
  double get physical => _eff(player.physical);
  double? get goalkeeping => player.goalkeeping == null ? null : _eff(player.goalkeeping!);
  double? get tempGoalkeeping => temporaryGoalkeeping == null ? null : _eff(temporaryGoalkeeping!);

  bool get isNaturalGoalkeeper =>
      (player.primaryPosition == Position.kl || player.secondaryPosition == Position.kl) &&
      player.goalkeeping != null;

  bool get canGoalkeep => isNaturalGoalkeeper || temporaryGoalkeeping != null;

  double roleOverall(Position role) => switch (role) {
        Position.def =>
          0.12 * pace + 0.04 * shooting + 0.16 * passing + 0.13 * technical + 0.33 * defending + 0.22 * physical,
        Position.os =>
          0.12 * pace + 0.10 * shooting + 0.27 * passing + 0.28 * technical + 0.10 * defending + 0.13 * physical,
        Position.forw =>
          0.19 * pace + 0.28 * shooting + 0.11 * passing + 0.24 * technical + 0.04 * defending + 0.14 * physical,
        Position.kl => 0.03 * pace +
            0.07 * passing +
            0.07 * technical +
            0.13 * physical +
            0.70 * (goalkeeping ?? tempGoalkeeping ?? 1.0),
      };

  double preferredOverall() {
    final primary = roleOverall(player.primaryPosition);
    if (player.secondaryPosition == null) return primary;
    return math.max(primary, 0.95 * roleOverall(player.secondaryPosition!));
  }

  double fitFor(Position role) {
    if (player.primaryPosition == role) return 1.0;
    if (player.secondaryPosition == role) return 0.95;
    if (role == Position.kl && temporaryGoalkeeping != null) return 0.82;
    return 0.82;
  }

  Map<String, dynamic> toJson() => {
        'player': player.toJson(),
        'form': form.name,
        'temporaryGoalkeeping': temporaryGoalkeeping,
      };

  factory MatchPlayer.fromJson(Map<String, dynamic> json) => MatchPlayer(
        player: Player.fromJson(Map<String, dynamic>.from(json['player'] as Map)),
        form: MatchForm.values.byName(json['form'] as String),
        temporaryGoalkeeping: json['temporaryGoalkeeping'] as int?,
      );
}

class IdPair {
  const IdPair(this.left, this.right);
  final String left;
  final String right;

  Map<String, dynamic> toJson() => {'left': left, 'right': right};
  factory IdPair.fromJson(Map<String, dynamic> json) => IdPair(json['left'] as String, json['right'] as String);
}

class PinnedPlayer {
  const PinnedPlayer(this.playerId, this.team);
  final String playerId;
  final TeamSide team;

  Map<String, dynamic> toJson() => {'playerId': playerId, 'team': team.name};
  factory PinnedPlayer.fromJson(Map<String, dynamic> json) =>
      PinnedPlayer(json['playerId'] as String, TeamSide.values.byName(json['team'] as String));
}

class BalanceRequest {
  const BalanceRequest({
    required this.teamSize,
    required this.players,
    this.pinned = const [],
    this.sameTeamPairs = const [],
    this.separateTeamPairs = const [],
  });

  final int teamSize;
  final List<MatchPlayer> players;
  final List<PinnedPlayer> pinned;
  final List<IdPair> sameTeamPairs;
  final List<IdPair> separateTeamPairs;

  Map<String, dynamic> toJson() => {
        'teamSize': teamSize,
        'players': players.map((e) => e.toJson()).toList(),
        'pinned': pinned.map((e) => e.toJson()).toList(),
        'sameTeamPairs': sameTeamPairs.map((e) => e.toJson()).toList(),
        'separateTeamPairs': separateTeamPairs.map((e) => e.toJson()).toList(),
      };

  factory BalanceRequest.fromJson(Map<String, dynamic> json) => BalanceRequest(
        teamSize: json['teamSize'] as int,
        players: (json['players'] as List)
            .map((e) => MatchPlayer.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        pinned: (json['pinned'] as List? ?? const [])
            .map((e) => PinnedPlayer.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        sameTeamPairs: (json['sameTeamPairs'] as List? ?? const [])
            .map((e) => IdPair.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        separateTeamPairs: (json['separateTeamPairs'] as List? ?? const [])
            .map((e) => IdPair.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

class TeamProfile {
  const TeamProfile({
    required this.attack,
    required this.defense,
    required this.buildUp,
    required this.pressing,
    required this.progression,
    required this.containment,
    required this.goalkeeperStrength,
    required this.averageOverall,
    required this.formationQuality,
    required this.roleFitQuality,
    required this.emergencyOutfieldRoles,
    required this.outfieldAverages,
    required this.assignedRoles,
  });

  final double attack;
  final double defense;
  final double buildUp;
  final double pressing;
  final double progression;
  final double containment;
  final double goalkeeperStrength;
  final double averageOverall;
  final double formationQuality;
  final double roleFitQuality;
  final int emergencyOutfieldRoles;
  final List<double> outfieldAverages;
  final Map<String, Position> assignedRoles;

  Map<String, dynamic> toJson() => {
        'attack': attack,
        'defense': defense,
        'buildUp': buildUp,
        'pressing': pressing,
        'progression': progression,
        'containment': containment,
        'goalkeeperStrength': goalkeeperStrength,
        'averageOverall': averageOverall,
        'formationQuality': formationQuality,
        'roleFitQuality': roleFitQuality,
        'emergencyOutfieldRoles': emergencyOutfieldRoles,
        'outfieldAverages': outfieldAverages,
        'assignedRoles': assignedRoles.map((k, v) => MapEntry(k, positionCode(v))),
      };

  factory TeamProfile.fromJson(Map<String, dynamic> json) => TeamProfile(
        attack: (json['attack'] as num).toDouble(),
        defense: (json['defense'] as num).toDouble(),
        buildUp: (json['buildUp'] as num).toDouble(),
        pressing: (json['pressing'] as num).toDouble(),
        progression: (json['progression'] as num).toDouble(),
        containment: (json['containment'] as num).toDouble(),
        goalkeeperStrength: (json['goalkeeperStrength'] as num).toDouble(),
        averageOverall: (json['averageOverall'] as num).toDouble(),
        formationQuality: (json['formationQuality'] as num).toDouble(),
        roleFitQuality: (json['roleFitQuality'] as num).toDouble(),
        emergencyOutfieldRoles: json['emergencyOutfieldRoles'] as int,
        outfieldAverages: (json['outfieldAverages'] as List).map((e) => (e as num).toDouble()).toList(),
        assignedRoles: (json['assignedRoles'] as Map).map(
          (k, v) => MapEntry(k as String, positionFromCode(v as String)),
        ),
      );
}

class LossBreakdown {
  const LossBreakdown({
    required this.rawStatLoss,
    required this.roleBalanceLoss,
    required this.matchupLoss,
    required this.goalkeeperLoss,
    required this.strengthCurveLoss,
    required this.overallLoss,
    required this.tacticalProfileLoss,
    required this.baseLoss,
    required this.criticalLoss,
    required this.finalBalanceLoss,
  });

  final double rawStatLoss;
  final double roleBalanceLoss;
  final double matchupLoss;
  final double goalkeeperLoss;
  final double strengthCurveLoss;
  final double overallLoss;
  final double tacticalProfileLoss;
  final double baseLoss;
  final double criticalLoss;
  final double finalBalanceLoss;

  double get balanceScore => 100 * (1 - finalBalanceLoss);

  Map<String, dynamic> toJson() => {
        'rawStatLoss': rawStatLoss,
        'roleBalanceLoss': roleBalanceLoss,
        'matchupLoss': matchupLoss,
        'goalkeeperLoss': goalkeeperLoss,
        'strengthCurveLoss': strengthCurveLoss,
        'overallLoss': overallLoss,
        'tacticalProfileLoss': tacticalProfileLoss,
        'baseLoss': baseLoss,
        'criticalLoss': criticalLoss,
        'finalBalanceLoss': finalBalanceLoss,
      };

  factory LossBreakdown.fromJson(Map<String, dynamic> json) => LossBreakdown(
        rawStatLoss: (json['rawStatLoss'] as num).toDouble(),
        roleBalanceLoss: (json['roleBalanceLoss'] as num).toDouble(),
        matchupLoss: (json['matchupLoss'] as num).toDouble(),
        goalkeeperLoss: (json['goalkeeperLoss'] as num).toDouble(),
        strengthCurveLoss: (json['strengthCurveLoss'] as num).toDouble(),
        overallLoss: (json['overallLoss'] as num).toDouble(),
        tacticalProfileLoss: (json['tacticalProfileLoss'] as num).toDouble(),
        baseLoss: (json['baseLoss'] as num).toDouble(),
        criticalLoss: (json['criticalLoss'] as num).toDouble(),
        finalBalanceLoss: (json['finalBalanceLoss'] as num).toDouble(),
      );
}

class BalanceSolution {
  const BalanceSolution({
    required this.teamAIds,
    required this.teamBIds,
    required this.profileA,
    required this.profileB,
    required this.loss,
    required this.lexicographicalKey,
  });

  final List<String> teamAIds;
  final List<String> teamBIds;
  final TeamProfile profileA;
  final TeamProfile profileB;
  final LossBreakdown loss;
  final String lexicographicalKey;

  double get combinedFormationQuality => (profileA.formationQuality + profileB.formationQuality) / 2;

  Map<String, dynamic> toJson() => {
        'teamAIds': teamAIds,
        'teamBIds': teamBIds,
        'profileA': profileA.toJson(),
        'profileB': profileB.toJson(),
        'loss': loss.toJson(),
        'lexicographicalKey': lexicographicalKey,
      };

  factory BalanceSolution.fromJson(Map<String, dynamic> json) => BalanceSolution(
        teamAIds: List<String>.from(json['teamAIds'] as List),
        teamBIds: List<String>.from(json['teamBIds'] as List),
        profileA: TeamProfile.fromJson(Map<String, dynamic>.from(json['profileA'] as Map)),
        profileB: TeamProfile.fromJson(Map<String, dynamic>.from(json['profileB'] as Map)),
        loss: LossBreakdown.fromJson(Map<String, dynamic>.from(json['loss'] as Map)),
        lexicographicalKey: json['lexicographicalKey'] as String,
      );
}

class BalanceResult {
  const BalanceResult.success(this.solutions)
      : errorCode = null,
        message = null;

  const BalanceResult.failure(this.errorCode, this.message) : solutions = const [];

  final List<BalanceSolution> solutions;
  final BalanceErrorCode? errorCode;
  final String? message;

  bool get isSuccess => errorCode == null;

  Map<String, dynamic> toJson() => {
        'solutions': solutions.map((e) => e.toJson()).toList(),
        'errorCode': errorCode?.name,
        'message': message,
      };

  factory BalanceResult.fromJson(Map<String, dynamic> json) {
    final error = json['errorCode'] as String?;
    if (error != null) {
      return BalanceResult.failure(BalanceErrorCode.values.byName(error), json['message'] as String?);
    }
    return BalanceResult.success(
      (json['solutions'] as List)
          .map((e) => BalanceSolution.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }
}
