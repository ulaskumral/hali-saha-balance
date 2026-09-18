import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

class PlayerRecords extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get pace => integer()();
  IntColumn get shooting => integer()();
  IntColumn get passing => integer()();
  IntColumn get technical => integer()();
  IntColumn get defending => integer()();
  IntColumn get physical => integer()();
  IntColumn get goalkeeping => integer().nullable()();
  TextColumn get primaryPosition => text()();
  TextColumn get secondaryPosition => text().nullable()();
  TextColumn get photoPath => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class MatchSnapshots extends Table {
  TextColumn get id => text()();
  DateTimeColumn get confirmedAt => dateTime()();
  IntColumn get teamSize => integer()();
  TextColumn get payloadJson => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

@DriftDatabase(tables: [PlayerRecords, MatchSnapshots, AppSettings])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'hali_saha'));
  AppDatabase.forTesting(QueryExecutor executor) : super(executor);

  @override
  int get schemaVersion => 1;

  Stream<List<PlayerRecord>> watchPlayers() =>
      (select(playerRecords)..orderBy([(t) => OrderingTerm.asc(t.name)])).watch();

  Future<List<PlayerRecord>> getAllPlayers() =>
      (select(playerRecords)..orderBy([(t) => OrderingTerm.asc(t.name)])).get();

  Future<void> upsertPlayer(PlayerRecordsCompanion companion) async {
    await into(playerRecords).insertOnConflictUpdate(companion);
  }

  Future<void> deletePlayerById(String id) async {
    await (delete(playerRecords)..where((t) => t.id.equals(id))).go();
  }

  Stream<List<MatchSnapshot>> watchMatches() =>
      (select(matchSnapshots)..orderBy([(t) => OrderingTerm.desc(t.confirmedAt)])).watch();

  Future<void> insertSnapshot(MatchSnapshotsCompanion companion) async {
    await into(matchSnapshots).insert(companion);
  }

  Stream<bool> watchShowNumericScores() {
    return (select(appSettings)..where((t) => t.key.equals('showNumericScores')))
        .watchSingleOrNull()
        .map((row) => row?.value == 'true');
  }

  Future<void> setShowNumericScores(bool value) async {
    await into(appSettings).insertOnConflictUpdate(
      AppSettingsCompanion.insert(key: 'showNumericScores', value: value.toString()),
    );
  }

  Future<Map<String, dynamic>> exportPortableJson() async {
    final players = await getAllPlayers();
    final matches = await select(matchSnapshots).get();
    final settings = await select(appSettings).get();
    return {
      'schemaVersion': schemaVersion,
      'players': players
          .map((p) => {
                'id': p.id,
                'name': p.name,
                'pace': p.pace,
                'shooting': p.shooting,
                'passing': p.passing,
                'technical': p.technical,
                'defending': p.defending,
                'physical': p.physical,
                'goalkeeping': p.goalkeeping,
                'primaryPosition': p.primaryPosition,
                'secondaryPosition': p.secondaryPosition,
                'photoPath': p.photoPath,
                'createdAt': p.createdAt.toIso8601String(),
                'updatedAt': p.updatedAt.toIso8601String(),
              })
          .toList(),
      'matches': matches
          .map((m) => {
                'id': m.id,
                'confirmedAt': m.confirmedAt.toIso8601String(),
                'teamSize': m.teamSize,
                'payloadJson': m.payloadJson,
              })
          .toList(),
      'settings': settings.map((s) => {'key': s.key, 'value': s.value}).toList(),
    };
  }

  Future<void> importPortableJsonAtomic(Map<String, dynamic> data) async {
    if (data['schemaVersion'] != 1) {
      throw const FormatException('Desteklenmeyen backup şema sürümü.');
    }
    final rawPlayers = (data['players'] as List? ?? const []);
    final rawMatches = (data['matches'] as List? ?? const []);
    final rawSettings = (data['settings'] as List? ?? const []);

    // Validate everything before the transaction touches live data.
    final playerCompanions = rawPlayers.map((raw) {
      final p = Map<String, dynamic>.from(raw as Map);
      for (final key in ['pace', 'shooting', 'passing', 'technical', 'defending', 'physical']) {
        final value = p[key] as int;
        if (value < 1 || value > 99) throw FormatException('Geçersiz stat: $key=$value');
      }
      final gk = p['goalkeeping'] as int?;
      if (gk != null && (gk < 1 || gk > 99)) throw const FormatException('Geçersiz kaleci statı.');
      return PlayerRecordsCompanion.insert(
        id: p['id'] as String,
        name: p['name'] as String,
        pace: p['pace'] as int,
        shooting: p['shooting'] as int,
        passing: p['passing'] as int,
        technical: p['technical'] as int,
        defending: p['defending'] as int,
        physical: p['physical'] as int,
        goalkeeping: Value(gk),
        primaryPosition: p['primaryPosition'] as String,
        secondaryPosition: Value(p['secondaryPosition'] as String?),
        photoPath: Value(p['photoPath'] as String?),
        createdAt: DateTime.parse(p['createdAt'] as String),
        updatedAt: DateTime.parse(p['updatedAt'] as String),
      );
    }).toList();

    final matchCompanions = rawMatches.map((raw) {
      final m = Map<String, dynamic>.from(raw as Map);
      jsonDecode(m['payloadJson'] as String); // payload integrity check
      return MatchSnapshotsCompanion.insert(
        id: m['id'] as String,
        confirmedAt: DateTime.parse(m['confirmedAt'] as String),
        teamSize: m['teamSize'] as int,
        payloadJson: m['payloadJson'] as String,
      );
    }).toList();

    final settingCompanions = rawSettings.map((raw) {
      final s = Map<String, dynamic>.from(raw as Map);
      return AppSettingsCompanion.insert(key: s['key'] as String, value: s['value'] as String);
    }).toList();

    await transaction(() async {
      await delete(matchSnapshots).go();
      await delete(playerRecords).go();
      await delete(appSettings).go();
      await batch((batch) {
        batch.insertAll(playerRecords, playerCompanions);
        batch.insertAll(matchSnapshots, matchCompanions);
        batch.insertAll(appSettings, settingCompanions);
      });
    });
  }
}
