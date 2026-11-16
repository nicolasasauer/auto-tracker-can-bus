import 'dart:async';

import 'package:can_link/can_link.dart';
import 'package:flutter/material.dart';

import 'bus_screen.dart';
import 'profile_screen.dart';
import 'recordings_screen.dart';
import 'workbench.dart';

/// Startseite: CAN-Leser suchen oder die Simulation starten.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.workbench});

  /// Profil, Pins und Mitschnitte. Ohne Angabe ein leerer Stand im Speicher.
  final Workbench? workbench;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  StreamSubscription<List<CanLinkDevice>>? _scan;
  List<CanLinkDevice> _devices = const [];
  bool _connecting = false;
  late final Workbench _workbench = widget.workbench ?? Workbench();

  @override
  void dispose() {
    _scan?.cancel();
    super.dispose();
  }

  void _toggleScan() {
    if (_scan != null) {
      _stopScan();
      return;
    }
    setState(() {
      _devices = const [];
      _scan = BleCanLinkConnection.scan().listen(
        (d) => setState(() => _devices = d),
        onError: (Object e) {
          _stopScan();
          _showError('Suche fehlgeschlagen: $e');
        },
      );
    });
  }

  void _stopScan() {
    _scan?.cancel();
    setState(() => _scan = null);
  }

  void _showError(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _connect(CanLinkDevice device) async {
    _stopScan();
    setState(() => _connecting = true);
    try {
      final connection = await BleCanLinkConnection.connect(device);
      if (!mounted) {
        await connection.close();
        return;
      }
      _open(connection);
    } catch (e) {
      _showError('Verbinden fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  void _open(CanLinkConnection connection) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            BusScreen(connection: connection, workbench: _workbench),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scanning = _scan != null;
    return Scaffold(
      appBar: AppBar(title: const Text('CAN-Werkbank')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('CAN-Leser', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Zum ersten Koppeln den Leser per USB an den PC anschließen, in '
            'der seriellen Konsole „pair“ eingeben und den angezeigten Code '
            'am Handy eingeben. Danach verbindet er sich ohne Code.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _connecting ? null : _toggleScan,
            icon: Icon(scanning ? Icons.stop : Icons.bluetooth_searching),
            label: Text(scanning ? 'Suche beenden' : 'CAN-Leser suchen'),
          ),
          if (_connecting) const LinearProgressIndicator(),
          for (final d in _devices)
            ListTile(
              leading: const Icon(Icons.memory),
              title: Text(d.name),
              subtitle: Text(d.rssi == null ? d.id : '${d.id} · ${d.rssi} dBm'),
              onTap: _connecting ? null : () => _connect(d),
            ),
          if (scanning && _devices.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Suche läuft …'),
            ),
          const Divider(height: 32),
          Text('Ohne Hardware', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _open(DemoConnection()),
            icon: const Icon(Icons.science_outlined),
            label: const Text('Simulation starten'),
          ),
          const Divider(height: 32),
          Text('Werkbank', style: theme.textTheme.titleMedium),
          ListenableBuilder(
            listenable: _workbench,
            builder: (context, _) {
              final p = _workbench.profile;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.tune),
                title: const Text('Profil'),
                subtitle: Text(
                  p.isEmpty
                      ? 'Noch keine Signale'
                      : [
                          if (p.vehicleLabel.isNotEmpty) p.vehicleLabel,
                          '${p.signalCount} Signale',
                        ].join(' · '),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ProfileScreen(workbench: _workbench),
                  ),
                ),
              );
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.folder_outlined),
            title: const Text('Mitschnitte'),
            subtitle: const Text('Teilen, für die KI-Analyse, abspielen'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => RecordingsScreen(workbench: _workbench),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
