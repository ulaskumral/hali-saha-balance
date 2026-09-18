import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../core/providers.dart';
import '../../domain/models.dart';
import 'player_avatar.dart';
import 'player_media_service.dart';

class PlayerEditorScreen extends ConsumerStatefulWidget {
  const PlayerEditorScreen({super.key, this.initial});
  final Player? initial;

  @override
  ConsumerState<PlayerEditorScreen> createState() => _PlayerEditorScreenState();
}

class _PlayerEditorScreenState extends ConsumerState<PlayerEditorScreen> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController nameController;
  late String id;
  late Position primary;
  Position? secondary;
  late int pace;
  late int shooting;
  late int passing;
  late int technical;
  late int defending;
  late int physical;
  int? goalkeeping;
  String? photoPath;
  File? pendingPhoto;

  @override
  void initState() {
    super.initState();
    final p = widget.initial;
    id = p?.id ?? const Uuid().v4();
    nameController = TextEditingController(text: p?.name ?? '');
    primary = p?.primaryPosition ?? Position.os;
    secondary = p?.secondaryPosition;
    pace = p?.pace ?? 60;
    shooting = p?.shooting ?? 60;
    passing = p?.passing ?? 60;
    technical = p?.technical ?? 60;
    defending = p?.defending ?? 60;
    physical = p?.physical ?? 60;
    goalkeeping = p?.goalkeeping;
    photoPath = p?.photoPath;
  }

  @override
  void dispose() {
    nameController.dispose();
    super.dispose();
  }

  Future<void> pickPhoto() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 88, maxWidth: 1600);
    if (picked == null) return;
    setState(() => pendingPhoto = File(picked.path));
  }

  Future<void> save() async {
    if (!(formKey.currentState?.validate() ?? false)) return;
    var resolvedPhotoPath = photoPath;
    if (pendingPhoto != null) {
      resolvedPhotoPath = await PlayerMediaService().persistPhoto(playerId: id, source: pendingPhoto!);
    }
    final player = Player(
      id: id,
      name: nameController.text.trim(),
      pace: pace,
      shooting: shooting,
      passing: passing,
      technical: technical,
      defending: defending,
      physical: physical,
      goalkeeping: goalkeeping,
      primaryPosition: primary,
      secondaryPosition: secondary,
      photoPath: resolvedPhotoPath,
    );
    await ref.read(playerRepositoryProvider).save(player);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.initial == null ? 'Oyuncu ekle' : 'Oyuncuyu düzenle')),
      body: Form(
        key: formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: Stack(
                children: [
                  if (pendingPhoto != null)
                    CircleAvatar(radius: 42, backgroundImage: FileImage(pendingPhoto!))
                  else if (widget.initial != null)
                    PlayerAvatar(player: widget.initial!, radius: 42)
                  else
                    const CircleAvatar(radius: 42, child: Icon(Icons.person, size: 42)),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: IconButton.filledTonal(onPressed: pickPhoto, icon: const Icon(Icons.photo_library_outlined)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Ad Soyad', border: OutlineInputBorder()),
              validator: (value) => value == null || value.trim().isEmpty ? 'Ad zorunlu.' : null,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _positionDropdown('Ana mevki', primary, (v) => setState(() => primary = v!))),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<Position?>(
                    initialValue: secondary,
                    decoration: const InputDecoration(labelText: 'İkinci mevki', border: OutlineInputBorder()),
                    items: [
                      const DropdownMenuItem<Position?>(value: null, child: Text('Yok')),
                      ...Position.values.map((p) => DropdownMenuItem<Position?>(value: p, child: Text(positionCode(p)))),
                    ],
                    onChanged: (v) => setState(() => secondary = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _stat('HIZ', pace, (v) => pace = v),
            _stat('ŞUT', shooting, (v) => shooting = v),
            _stat('PAS', passing, (v) => passing = v),
            _stat('TEKNİK', technical, (v) => technical = v),
            _stat('DEFANS', defending, (v) => defending = v),
            _stat('FİZİK', physical, (v) => physical = v),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Kalecilik puanı var'),
              value: goalkeeping != null,
              onChanged: (enabled) => setState(() => goalkeeping = enabled ? (goalkeeping ?? 60) : null),
            ),
            if (goalkeeping != null) _stat('KALECİLİK', goalkeeping!, (v) => goalkeeping = v),
            const SizedBox(height: 24),
            FilledButton.icon(onPressed: save, icon: const Icon(Icons.save_outlined), label: const Text('Kaydet')),
          ],
        ),
      ),
    );
  }

  Widget _positionDropdown(String label, Position value, ValueChanged<Position?> onChanged) {
    return DropdownButtonFormField<Position>(
      initialValue: value,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      items: Position.values.map((p) => DropdownMenuItem(value: p, child: Text(positionCode(p)))).toList(),
      onChanged: onChanged,
    );
  }

  Widget _stat(String label, int value, ValueChanged<int> onChanged) {
    return Row(
      children: [
        SizedBox(width: 72, child: Text(label)),
        Expanded(
          child: Slider(
            min: 1,
            max: 99,
            divisions: 98,
            label: value.toString(),
            value: value.toDouble(),
            onChanged: (v) => setState(() => onChanged(v.round())),
          ),
        ),
        SizedBox(width: 32, child: Text('$value', textAlign: TextAlign.end)),
      ],
    );
  }
}
