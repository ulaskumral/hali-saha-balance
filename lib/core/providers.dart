import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../database/repositories.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final playerRepositoryProvider = Provider<PlayerRepository>((ref) => PlayerRepository(ref.watch(databaseProvider)));
final matchRepositoryProvider = Provider<MatchRepository>((ref) => MatchRepository(ref.watch(databaseProvider)));

final showNumericScoresProvider = StreamProvider<bool>((ref) => ref.watch(databaseProvider).watchShowNumericScores());
