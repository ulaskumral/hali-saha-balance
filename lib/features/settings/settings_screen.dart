import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showScores = ref.watch(showNumericScoresProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Ayarlar')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Paylaşımda sayısal puanları göster'),
            subtitle: const Text('Varsayılan kapalıdır.'),
            value: showScores.value ?? false,
            onChanged: showScores.isLoading
                ? null
                : (value) => ref.read(databaseProvider).setShowNumericScores(value),
          ),
          const ListTile(
            leading: Icon(Icons.cloud_off_outlined),
            title: Text('Pure local-first'),
            subtitle: Text('Sunucu, üyelik, cloud DB, online rating veya LLM/API kullanılmaz.'),
          ),
        ],
      ),
    );
  }
}
