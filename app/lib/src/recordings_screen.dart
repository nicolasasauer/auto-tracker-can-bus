import 'package:can_link/can_link.dart';
import 'package:flutter/material.dart';

import 'bus_screen.dart';
import 'recorder.dart';
import 'workbench.dart';

enum _Action { ai, share, play, delete }

/// Gespeicherte Mitschnitte: teilen (auch als Paket für die KI-Analyse),
/// abspielen, löschen.
class RecordingsScreen extends StatefulWidget {
  const RecordingsScreen({super.key, required this.workbench});

  final Workbench workbench;

  @override
  State<RecordingsScreen> createState() => _RecordingsScreenState();
}

class _RecordingsScreenState extends State<RecordingsScreen> {
  late Future<List<RecordingInfo>> _list = widget.workbench.recordings.list();

  void _reload() => setState(() => _list = widget.workbench.recordings.list());

  void _show(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _run(_Action action, String name) async {
    final w = widget.workbench;
    try {
      switch (action) {
        case _Action.ai:
          await w.shareForAi(name);
        case _Action.share:
          await w.shareRecording(name);
        case _Action.play:
          final log = CanLog.parse(await w.recordings.read(name));
          if (!mounted) return;
          if (log.messages.isEmpty) {
            _show('Der Mitschnitt ist leer.');
            return;
          }
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => BusScreen(
                connection: ReplayConnection(log, name: 'Wiedergabe'),
                workbench: w,
              ),
            ),
          );
          // Während der Wiedergabe kann ein neuer Mitschnitt entstanden sein.
          if (mounted) _reload();
        case _Action.delete:
          await w.recordings.delete(name);
          _reload();
      }
    } on Exception catch (e) {
      if (mounted) _show('Fehlgeschlagen: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mitschnitte')),
      body: FutureBuilder(
        future: _list,
        builder: (context, snapshot) {
          final list = snapshot.data;
          if (list == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (list.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Noch keine Mitschnitte. In der Sniff-Ansicht startet der '
                  'rote Punkt eine Aufnahme.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView(
            children: [
              for (final r in list)
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: Text(r.name),
                  subtitle: Text(sizeText(r.bytes)),
                  trailing: PopupMenuButton<_Action>(
                    tooltip: 'Aktionen',
                    onSelected: (a) => _run(a, r.name),
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: _Action.ai,
                        child: Text('Für KI-Analyse teilen'),
                      ),
                      PopupMenuItem(
                        value: _Action.share,
                        child: Text('Nur Mitschnitt teilen'),
                      ),
                      PopupMenuItem(
                        value: _Action.play,
                        child: Text('Abspielen'),
                      ),
                      PopupMenuItem(
                        value: _Action.delete,
                        child: Text('Löschen'),
                      ),
                    ],
                  ),
                  onTap: () => _run(_Action.play, r.name),
                ),
            ],
          );
        },
      ),
    );
  }
}

String sizeText(int bytes) => bytes < 1024 * 1024
    ? '${(bytes / 1024).ceil()} kB'
    : '${(bytes / 1024 / 1024).toStringAsFixed(1).replaceAll('.', ',')} MB';
