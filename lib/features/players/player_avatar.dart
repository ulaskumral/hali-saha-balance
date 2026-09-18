import 'dart:io';

import 'package:flutter/material.dart';

import '../../domain/models.dart';
import 'player_media_service.dart';

class PlayerAvatar extends StatelessWidget {
  const PlayerAvatar({super.key, required this.player, this.radius = 20});
  final Player player;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<File?>(
      future: PlayerMediaService().resolve(player.photoPath),
      builder: (context, snapshot) {
        final file = snapshot.data;
        return CircleAvatar(
          radius: radius,
          backgroundImage: file == null ? null : FileImage(file),
          child: file == null ? Text(player.initials) : null,
        );
      },
    );
  }
}
