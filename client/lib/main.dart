/// Purpose: Flutter client application entrypoint.
/// Data & Logic Flow: Initializes widget tree, theme configurations, and root routing.
/// Key Components: SimkuliahApp
import 'package:flutter/material.dart';

void main() => runApp(const SimkuliahApp());

class SimkuliahApp extends StatelessWidget {
  const SimkuliahApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Simkuliah Presence Monitor',
      theme: ThemeData(useMaterial3: true),
      home: const Scaffold(),
    );
  }
}
