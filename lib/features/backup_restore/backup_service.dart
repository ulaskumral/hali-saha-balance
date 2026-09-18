import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../database/app_database.dart';

class BackupService {
  BackupService(this.db);
  final AppDatabase db;

  Future<File> createBackup() async {
    final appDir = await getApplicationSupportDirectory();
    final tempRoot = await Directory.systemTemp.createTemp('hali_saha_backup_');
    try {
      final manifest = {
        'format': 'takimbackup',
        'formatVersion': 1,
        'databaseSchemaVersion': db.schemaVersion,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      };
      await File(p.join(tempRoot.path, 'manifest.json')).writeAsString(jsonEncode(manifest), flush: true);
      await File(p.join(tempRoot.path, 'database.json')).writeAsString(
        jsonEncode(await db.exportPortableJson()),
        flush: true,
      );

      final sourcePlayers = Directory(p.join(appDir.path, 'players'));
      final tempPlayers = Directory(p.join(tempRoot.path, 'players'));
      if (await sourcePlayers.exists()) {
        await tempPlayers.create(recursive: true);
        await for (final entity in sourcePlayers.list(followLinks: false)) {
          if (entity is! File) continue;
          final name = p.basename(entity.path);
          await entity.copy(p.join(tempPlayers.path, name));
        }
      }

      final outDir = await getTemporaryDirectory();
      final out = File(
        p.join(outDir.path, 'hali_saha_${DateTime.now().toUtc().millisecondsSinceEpoch}.takimbackup'),
      );
      final encoder = ZipFileEncoder();
      encoder.create(out.path);
      await encoder.addDirectory(tempRoot, includeDirName: false, followLinks: false);
      await encoder.close();
      return out;
    } finally {
      if (await tempRoot.exists()) await tempRoot.delete(recursive: true);
    }
  }

  Future<void> restoreBackup(File backup) async {
    final bytes = await backup.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    final stage = await Directory.systemTemp.createTemp('hali_saha_restore_');
    final appDir = await getApplicationSupportDirectory();
    final livePlayers = Directory(p.join(appDir.path, 'players'));
    final rollbackPlayers = Directory(p.join(appDir.path, '.players_rollback'));

    try {
      for (final entry in archive) {
        _validateArchivePath(entry.name);
        if (entry.isSymbolicLink) {
          throw const FormatException('Backup sembolik link içeremez.');
        }
        final normalized = p.posix.normalize(entry.name);
        final target = File(p.joinAll([stage.path, ...p.posix.split(normalized)]));
        if (entry.isDirectory) {
          await Directory(target.path).create(recursive: true);
          continue;
        }
        if (!entry.isFile) throw const FormatException('Desteklenmeyen ZIP girdisi.');
        await target.parent.create(recursive: true);
        final content = entry.readBytes();
        if (content == null) throw const FormatException('Backup girdisi okunamadı.');
        await target.writeAsBytes(content, flush: true);
      }

      final manifestFile = File(p.join(stage.path, 'manifest.json'));
      final databaseFile = File(p.join(stage.path, 'database.json'));
      if (!await manifestFile.exists() || !await databaseFile.exists()) {
        throw const FormatException('manifest.json veya database.json eksik.');
      }

      final manifest = Map<String, dynamic>.from(jsonDecode(await manifestFile.readAsString()) as Map);
      if (manifest['format'] != 'takimbackup' || manifest['formatVersion'] != 1) {
        throw const FormatException('Desteklenmeyen .takimbackup formatı.');
      }
      final databaseJson = Map<String, dynamic>.from(jsonDecode(await databaseFile.readAsString()) as Map);

      final stagedPlayers = Directory(p.join(stage.path, 'players'));
      if (await rollbackPlayers.exists()) await rollbackPlayers.delete(recursive: true);
      var oldPlayersMoved = false;
      try {
        if (await livePlayers.exists()) {
          await livePlayers.rename(rollbackPlayers.path);
          oldPlayersMoved = true;
        }
        if (await stagedPlayers.exists()) {
          await stagedPlayers.rename(livePlayers.path);
        } else {
          await livePlayers.create(recursive: true);
        }

        try {
          await db.importPortableJsonAtomic(databaseJson);
        } catch (_) {
          if (await livePlayers.exists()) await livePlayers.delete(recursive: true);
          if (oldPlayersMoved && await rollbackPlayers.exists()) {
            await rollbackPlayers.rename(livePlayers.path);
          }
          rethrow;
        }

        if (await rollbackPlayers.exists()) {
          try {
            await rollbackPlayers.delete(recursive: true);
          } catch (_) {
            // Restore is already committed; stale rollback cleanup is non-critical.
          }
        }
      } catch (_) {
        if (!await livePlayers.exists() && oldPlayersMoved && await rollbackPlayers.exists()) {
          await rollbackPlayers.rename(livePlayers.path);
        }
        rethrow;
      }
    } finally {
      archive.clearSync();
      if (await stage.exists()) await stage.delete(recursive: true);
    }
  }

  static void _validateArchivePath(String name) {
    final normalized = p.posix.normalize(name.replaceAll('\\', '/'));
    if (normalized.isEmpty || normalized == '.') return;
    if (p.posix.isAbsolute(normalized) || normalized == '..' || normalized.startsWith('../')) {
      throw const FormatException('Zip-slip girişimi engellendi.');
    }
    final segments = p.posix.split(normalized);
    if (segments.contains('..')) throw const FormatException('Zip-slip girişimi engellendi.');
  }
}
