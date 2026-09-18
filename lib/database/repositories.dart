import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../domain/models.dart' as domain;
import 'app_database.dart';

class PlayerRepository {
  PlayerRepository(this.db);
  final AppDatabase db;

  Stream<List<domain.Player>> watchAll() => db.watchPlayers().map(
        (rows) => rows.map(_fromRow).toList(growable: false),
      );

  Future<List<domain.Player>> getAll() async => (await db.getAllPlayers()).map(_fromRow).toList();

  Future<void> save(domain.Player player) async {
    _validate(player);
    final now = DateTime.now().toUtc();
    final existing = await (db.select(db.playerRecords)..where((t) => t.id.equals(player.id))).getSingleOrNull();
    await db.upsertPlayer(
      PlayerRecordsCompanion.insert(
        id: player.id,
        name: player.name.trim(),
        pace: player.pace,
        shooting: player.shooting,
        passing: player.passing,
        technical: player.technical,
        defending: player.defending,
        physical: player.physical,
        goalkeeping: Value(player.goalkeeping),
        primaryPosition: domain.positionCode(player.primaryPosition),
        secondaryPosition: Value(
          player.secondaryPosition == null ? null : domain.positionCode(player.secondaryPosition!),
        ),
        photoPath: Value(player.photoPath),
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
      ),
    );
  }

  Future<void> delete(String id) => db.deletePlayerById(id);

  static domain.Player _fromRow(PlayerRecord row) => domain.Player(
        id: row.id,
        name: row.name,
        pace: row.pace,
        shooting: row.shooting,
        passing: row.passing,
        technical: row.technical,
        defending: row.defending,
        physical: row.physical,
        goalkeeping: row.goalkeeping,
        primaryPosition: domain.positionFromCode(row.primaryPosition),
        secondaryPosition: row.secondaryPosition == null ? null : domain.positionFromCode(row.secondaryPosition!),
        photoPath: row.photoPath,
      );

  static void _validate(domain.Player p) {
    if (p.name.trim().isEmpty) throw const FormatException('Oyuncu adı boş olamaz.');
    final values = [p.pace, p.shooting, p.passing, p.technical, p.defending, p.physical, if (p.goalkeeping != null) p.goalkeeping!];
    if (values.any((v) => v < 1 || v > 99)) throw const FormatException('Tüm statlar 1-99 aralığında olmalıdır.');
  }
}

class MatchRepository {
  MatchRepository(this.db);
  final AppDatabase db;
  static const _uuid = Uuid();

  Stream<List<MatchSnapshot>> watchAll() => db.watchMatches();

  Future<String> confirm({
    required int teamSize,
    required domain.BalanceRequest request,
    required domain.BalanceSolution solution,
    String? jokerPlayerId,
    String? reservePlayerId,
  }) async {
    final id = _uuid.v4();
    final confirmedAt = DateTime.now().toUtc();
    final payload = jsonEncode({
      'snapshotVersion': 1,
      'id': id,
      'confirmedAt': confirmedAt.toIso8601String(),
      'teamSize': teamSize,
      'jokerPlayerId': jokerPlayerId,
      'reservePlayerId': reservePlayerId,
      'request': request.toJson(),
      'solution': solution.toJson(),
    });
    await db.insertSnapshot(
      MatchSnapshotsCompanion.insert(
        id: id,
        confirmedAt: confirmedAt,
        teamSize: teamSize,
        payloadJson: payload,
      ),
    );
    return id;
  }
}
