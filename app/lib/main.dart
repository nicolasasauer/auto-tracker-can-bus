import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'src/home_screen.dart';
import 'src/workbench.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Profil, Pins und Mitschnitte liegen im Ordner der App.
  final workbench = await Workbench.open(
    await getApplicationDocumentsDirectory(),
  );
  runApp(CanWerkbankApp(workbench: workbench));
}

class CanWerkbankApp extends StatelessWidget {
  const CanWerkbankApp({super.key, this.workbench});

  /// Ohne Angabe (Tests) bleibt der Arbeitsstand im Speicher.
  final Workbench? workbench;

  @override
  Widget build(BuildContext context) {
    // Indigo wie das App-Icon (tool/icon/generate_icon.mjs).
    const seed = Color(0xFF4F46E5);
    return MaterialApp(
      title: 'CAN-Werkbank',
      theme: ThemeData(colorSchemeSeed: seed),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark),
      home: HomeScreen(workbench: workbench),
    );
  }
}
