import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/providers.dart';
import 'backup_service.dart';

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  var busy = false;

  Future<void> createBackup() async {
    setState(() => busy = true);
    try {
      final file = await BackupService(ref.read(databaseProvider)).createBackup();
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], text: 'Halı saha yedeği (.takimbackup)'),
      );
    } catch (e) {
      if (mounted) _message('Yedek oluşturulamadı: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> restoreBackup() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['takimbackup'],
      allowMultiple: false,
    );
    final path = result?.files.single.path;
    if (path == null) return;
    if (!mounted) return;
    final approved = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Yedeği geri yükle'),
            content: const Text('Mevcut oyuncular, maç geçmişi, ayarlar ve oyuncu görselleri backup içeriğiyle değiştirilecek.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('İptal')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Geri yükle')),
            ],
          ),
        ) ??
        false;
    if (!approved) return;

    setState(() => busy = true);
    try {
      await BackupService(ref.read(databaseProvider)).restoreBackup(File(path));
      if (mounted) _message('Yedek başarıyla geri yüklendi.');
    } catch (e) {
      if (mounted) _message('Restore iptal edildi ve rollback uygulandı: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _message(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Yedekleme / Geri Yükleme')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('.takimbackup = manifest.json + portable DB export + players/ görselleri. Restore staging, zip-slip koruması ve rollback ile yapılır.'),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: busy ? null : createBackup, icon: const Icon(Icons.archive_outlined), label: const Text('Yedek oluştur ve paylaş')),
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: busy ? null : restoreBackup, icon: const Icon(Icons.settings_backup_restore), label: const Text('Yedekten geri yükle')),
          if (busy) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
        ],
      ),
    );
  }
}
