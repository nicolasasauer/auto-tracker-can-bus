import 'package:can_link/can_link.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'example_profiles.dart';
import 'id_detail_screen.dart';
import 'signal_screen.dart';
import 'workbench.dart';

/// Das Arbeitsprofil: importieren, exportieren, Signale ansehen und öffnen.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    super.key,
    required this.workbench,
    this.history,
    this.ticker,
  });

  final Workbench workbench;

  /// Mit Verbindung: Verlauf für Live-Werte.
  final FrameHistory? history;
  final Listenable? ticker;

  void _show(BuildContext context, String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  /// Text prüfen und als Profil übernehmen. Fehler werden vollständig
  /// angezeigt, damit man sie der KI zurückgeben kann.
  Future<void> _import(BuildContext context, String? text) async {
    if (text == null) return;
    final CanProfile profile;
    try {
      profile = CanProfile.parse(text);
    } on ProfileFormatException catch (e) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Profil nicht lesbar'),
          content: SingleChildScrollView(child: SelectableText(e.toString())),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Schließen'),
            ),
          ],
        ),
      );
      return;
    }
    if (!context.mounted || !await _confirmReplace(context)) return;
    workbench.setProfile(profile);
    if (context.mounted) {
      _show(
        context,
        'Profil geladen: ${profile.signalCount} Signale in '
        '${profile.messages.length} Botschaften.',
      );
    }
  }

  Future<bool> _confirmReplace(BuildContext context) async {
    if (workbench.profile.isEmpty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Aktuelles Profil ersetzen?'),
            content: Text(
              'Das aktuelle Profil hat ${workbench.profile.signalCount} '
              'Signale. Vorher teilen oder kopieren, wenn es noch gebraucht '
              'wird.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Abbrechen'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Ersetzen'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _replace(BuildContext context, CanProfile profile) async {
    if (!await _confirmReplace(context)) return;
    workbench.setProfile(profile);
  }

  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } on Exception catch (e) {
      if (context.mounted) _show(context, 'Fehlgeschlagen: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil'),
        actions: [
          PopupMenuButton<Future<void> Function()>(
            tooltip: 'Anderes Profil',
            onSelected: (action) => _run(context, action),
            // Der Kontext des Menüs ist nach der Auswahl weg; die Aktionen
            // nutzen den der Seite.
            itemBuilder: (_) => [
              PopupMenuItem(
                value: () => _replace(context, const CanProfile()),
                child: const Text('Neues leeres Profil'),
              ),
              PopupMenuItem(
                value: () async {
                  final profile = await loadPeugeot208Profile();
                  if (context.mounted) await _replace(context, profile);
                },
                child: const Text('Beispiel: Peugeot 208 (2016)'),
              ),
              PopupMenuItem(
                value: () => _replace(context, simulationProfile),
                child: const Text('Beispiel: Simulation'),
              ),
            ],
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([workbench, ticker]),
        builder: (context, _) {
          final profile = workbench.profile;
          final open = profile.signals
              .where((s) => s.signal.confidence != SignalConfidence.verified)
              .length;
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 16),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.vehicleLabel.isEmpty
                          ? profile.profileId
                          : profile.vehicleLabel,
                      style: theme.textTheme.titleLarge,
                    ),
                    Text(
                      [
                        if (profile.vehicleLabel.isNotEmpty) profile.profileId,
                        '${profile.signalCount} Signale',
                        '${profile.messages.length} Botschaften',
                        if (open > 0) '$open noch nicht geprüft',
                      ].join(' · '),
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: () => _run(context, () async {
                            final text = await workbench.pickText();
                            if (context.mounted) await _import(context, text);
                          }),
                          icon: const Icon(Icons.file_open_outlined),
                          label: const Text('Datei importieren'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: () => _run(context, () async {
                            final data = await Clipboard.getData(
                              Clipboard.kTextPlain,
                            );
                            final text = data?.text;
                            if (!context.mounted) return;
                            if (text == null || text.trim().isEmpty) {
                              _show(context, 'Die Zwischenablage ist leer.');
                              return;
                            }
                            await _import(context, text);
                          }),
                          icon: const Icon(Icons.content_paste),
                          label: const Text('Aus Zwischenablage'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () =>
                              _run(context, workbench.shareProfile),
                          icon: const Icon(Icons.share_outlined),
                          label: const Text('Teilen'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _run(context, () async {
                            await Clipboard.setData(
                              ClipboardData(text: profile.encode()),
                            );
                            if (context.mounted) {
                              _show(context, 'Profil kopiert.');
                            }
                          }),
                          icon: const Icon(Icons.copy),
                          label: const Text('Kopieren'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (profile.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Noch keine Signale. Ein Profil importieren, ein Beispiel '
                    'laden (Menü oben rechts) oder in der Detailansicht einer '
                    'CAN-ID Bits auswählen und „Signal anlegen“ wählen.',
                  ),
                ),
              for (final m in profile.messages)
                if (m.signals.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                    child: Text(
                      [m.label, if (m.name.isNotEmpty) m.name].join(' · '),
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  for (final s in m.signals)
                    ListTile(
                      title: Text(s.name),
                      subtitle: Text(signalSummary(s)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (history != null)
                            Text(signalValueText(s, history!.latest(m.rawId))),
                          IconButton(
                            tooltip: workbench.isPinned(s.name)
                                ? 'Lösen'
                                : 'Anpinnen',
                            icon: Icon(
                              workbench.isPinned(s.name)
                                  ? Icons.push_pin
                                  : Icons.push_pin_outlined,
                            ),
                            onPressed: () => workbench.togglePin(s.name),
                          ),
                        ],
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => SignalScreen(
                            workbench: workbench,
                            rawId: m.rawId,
                            signal: s,
                            existingName: s.name,
                            dlc: m.dlc,
                            history: history,
                            ticker: ticker,
                          ),
                        ),
                      ),
                    ),
                ],
            ],
          );
        },
      ),
    );
  }
}
