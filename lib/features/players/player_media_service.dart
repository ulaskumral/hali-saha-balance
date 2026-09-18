import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class PlayerMediaService {
  Future<String> persistPhoto({required String playerId, required File source}) async {
    final appDir = await getApplicationSupportDirectory();
    final playersDir = Directory(p.join(appDir.path, 'players'));
    await playersDir.create(recursive: true);
    final relative = p.posix.join('players', '$playerId.jpg');
    await source.copy(p.join(playersDir.path, '$playerId.jpg'));
    return relative;
  }

  Future<File?> resolve(String? relativePath) async {
    if (relativePath == null) return null;
    final safe = p.posix.normalize(relativePath.replaceAll('\\', '/'));
    if (p.posix.isAbsolute(safe) || safe.startsWith('../')) return null;
    final appDir = await getApplicationSupportDirectory();
    final file = File(p.joinAll([appDir.path, ...p.posix.split(safe)]));
    return await file.exists() ? file : null;
  }
}
