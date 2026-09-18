import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/models.dart';

class ShareCardRenderer {
  Future<File> render({
    required BalanceSolution solution,
    required Map<String, Player> playerById,
    required bool showNumericScores,
    String? jokerPlayerId,
  }) async {
    const width = 1080.0;
    const height = 1350.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, width, height));
    final bg = Paint()..color = const Color(0xFFF7F7F3);
    canvas.drawRect(const Rect.fromLTWH(0, 0, width, height), bg);

    _text(canvas, 'HALI SAHA KADROLARI', const Offset(64, 58), 48, FontWeight.w800);
    _text(
      canvas,
      showNumericScores ? 'Denge skoru: ${solution.loss.balanceScore.toStringAsFixed(1)}' : 'Dengeli takım dağılımı',
      const Offset(64, 126),
      28,
      FontWeight.w500,
    );

    _teamBlock(
      canvas,
      title: 'TAKIM A',
      ids: solution.teamAIds,
      roles: solution.profileA.assignedRoles,
      playerById: playerById,
      top: 210,
      jokerPlayerId: jokerPlayerId,
    );
    _teamBlock(
      canvas,
      title: 'TAKIM B',
      ids: solution.teamBIds,
      roles: solution.profileB.assignedRoles,
      playerById: playerById,
      top: 760,
      jokerPlayerId: jokerPlayerId,
    );


    final picture = recorder.endRecording();
    final image = await picture.toImage(width.toInt(), height.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) throw StateError('Paylaşım görseli üretilemedi.');
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'kadro_${DateTime.now().millisecondsSinceEpoch}.png'));
    await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
    return file;
  }

  void _teamBlock(
    Canvas canvas, {
    required String title,
    required List<String> ids,
    required Map<String, Position> roles,
    required Map<String, Player> playerById,
    required double top,
    String? jokerPlayerId,
  }) {
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(48, top, 984, 500),
      const Radius.circular(30),
    );
    canvas.drawRRect(rect, Paint()..color = Colors.white);
    _text(canvas, title, Offset(82, top + 34), 34, FontWeight.w800);
    var y = top + 100;
    final sorted = [...ids]..sort((a, b) {
        final roleCompare = positionCode(roles[a]!).compareTo(positionCode(roles[b]!));
        if (roleCompare != 0) return roleCompare;
        return playerById[a]!.name.compareTo(playerById[b]!.name);
      });
    final rowCount = sorted.length + (jokerPlayerId != null && playerById[jokerPlayerId] != null ? 1 : 0);
    final rowHeight = (380.0 / math.max(1, rowCount)).clamp(30.0, 54.0);
    final roleFont = rowHeight < 40 ? 18.0 : 23.0;
    final nameFont = rowHeight < 40 ? 21.0 : 27.0;
    for (final id in sorted) {
      final p = playerById[id]!;
      _text(canvas, positionCode(roles[id]!), Offset(82, y), roleFont, FontWeight.w800, maxWidth: 90);
      _text(canvas, p.name, Offset(190, y), nameFont, FontWeight.w600, maxWidth: 770);
      y += rowHeight;
    }
    if (jokerPlayerId != null && playerById[jokerPlayerId] != null) {
      _text(canvas, 'JOKER', Offset(82, y), roleFont, FontWeight.w800, maxWidth: 90);
      _text(canvas, playerById[jokerPlayerId]!.name, Offset(190, y), nameFont, FontWeight.w600, maxWidth: 770);
    }
  }

  void _text(
    Canvas canvas,
    String text,
    Offset offset,
    double size,
    FontWeight weight, {
    double maxWidth = 950,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: const Color(0xFF172018), fontSize: size, fontWeight: weight),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    painter.paint(canvas, offset);
  }
}
