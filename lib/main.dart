import 'package:flutter/material.dart';

import 'core/game_state.dart';
import 'data/game_db.dart';
import 'ui/screens.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FootballManagerApp());
}

class FootballManagerApp extends StatelessWidget {
  const FootballManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Futbol Menajer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green, brightness: Brightness.dark),
      ),
      home: const BootScreen(),
    );
  }
}

class BootScreen extends StatefulWidget {
  const BootScreen({super.key});

  @override
  State<BootScreen> createState() => _BootScreenState();
}

class _BootScreenState extends State<BootScreen> {
  GameDb? gdb;
  GameState? saved;
  String? error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final g = await GameDb.open();
      final s = await GameState.resume(g);
      if (!mounted) return;
      setState(() {
        gdb = g;
        saved = s;
      });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (error != null) return Scaffold(body: Center(child: Text('Hata: $error')));
    if (gdb == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return StartScreen(gdb: gdb!, saved: saved);
  }
}
