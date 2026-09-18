import 'package:flutter/material.dart';

import 'features/backup_restore/backup_screen.dart';
import 'features/matches/matches_screen.dart';
import 'features/players/players_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/team_generator/team_generator_screen.dart';

class HaliSahaApp extends StatelessWidget {
  const HaliSahaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Kadro Dengeleyici',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF166534)),
        useMaterial3: true,
      ),
      home: const _HomeShell(),
    );
  }
}

class _HomeShell extends StatefulWidget {
  const _HomeShell();

  @override
  State<_HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<_HomeShell> {
  var index = 0;

  static const pages = [
    PlayersScreen(),
    TeamGeneratorScreen(),
    MatchesScreen(),
    BackupScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: pages[index]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.groups_2_outlined), selectedIcon: Icon(Icons.groups_2), label: 'Oyuncular'),
          NavigationDestination(icon: Icon(Icons.balance_outlined), selectedIcon: Icon(Icons.balance), label: 'Dengele'),
          NavigationDestination(icon: Icon(Icons.history_outlined), selectedIcon: Icon(Icons.history), label: 'Maçlar'),
          NavigationDestination(icon: Icon(Icons.archive_outlined), selectedIcon: Icon(Icons.archive), label: 'Yedek'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Ayarlar'),
        ],
      ),
    );
  }
}
