import 'dart:async';

import 'package:can_link/can_link.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import 'diagnostics_screen.dart';
import 'diagnostics_text.dart';
import 'id_detail_screen.dart';
import 'obd_text.dart';
import 'profile_screen.dart';
import 'recorder.dart';
import 'signal_chart.dart';
import 'signal_screen.dart';
import 'workbench.dart';

/// Sniff-Ansicht: alle CAN-IDs mit ihren letzten Daten. Bytes, die sich
/// gerade geändert haben, leuchten auf. Signale aus dem Profil stehen als
/// Wert unter den Bytes, angepinnte oben mit Verlauf. Der rote Punkt nimmt
/// einen Mitschnitt auf.
class BusScreen extends StatefulWidget {
  const BusScreen({super.key, required this.connection, this.workbench});

  /// Wird beim Verlassen der Ansicht geschlossen.
  final CanLinkConnection connection;

  /// Profil, Pins und Mitschnitte. Ohne Angabe ein leerer Stand im Speicher.
  final Workbench? workbench;

  @override
  State<BusScreen> createState() => _BusScreenState();
}

/// So lange leuchtet ein geändertes Byte nach.
const highlightDuration = Duration(milliseconds: 1500);

/// Vorschläge für Marken während der Aufnahme.
const markSuggestions = [
  'Blinker links',
  'Blinker rechts',
  'Bremse',
  'Licht',
  'Tür',
  'Motor an',
];

enum _Menu { diagnostics, profile, reset }

class _BusScreenState extends State<BusScreen> {
  final _view = BusView();
  final _history = FrameHistory();
  late final Workbench _workbench = widget.workbench ?? Workbench();
  final List<StreamSubscription<Object?>> _subs = [];
  StatusMessage? _status;
  final _diagnostics = ValueNotifier<DiagnosticsMessage?>(null);
  bool _connected = true;
  String _query = '';
  Timer? _repaint;

  @override
  void initState() {
    super.initState();
    final c = widget.connection;
    _subs
      ..add(
        // Auch beim Anhalten weiterreichen: BusView verwirft die Daten dann
        // selbst, zählt aber die laufende Nummer mit.
        c.monitor.listen((m) {
          _view.add(m);
          // Angehalten bleibt auch der Verlauf stehen; die Aufnahme läuft
          // weiter.
          if (!_view.paused) _history.add(m);
          _workbench.recorder.add(m);
        }),
      )
      ..add(c.status.listen((s) => setState(() => _status = s)))
      ..add(c.diagnostics.listen((d) => _diagnostics.value = d))
      ..add(c.connected.listen((v) => setState(() => _connected = v)));
    // Nachleuchten ausblenden, auch wenn keine neuen Daten kommen.
    _repaint = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _repaint?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _workbench.recorder.stop();
    widget.connection.close();
    _view.dispose();
    _diagnostics.dispose();
    super.dispose();
  }

  void _show(String text, {SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), action: action));
  }

  Future<void> _toggleRecording() async {
    final recorder = _workbench.recorder;
    try {
      if (!recorder.recording) {
        await recorder.start(widget.connection.name);
        return;
      }
      final name = await recorder.stop();
      if (name == null) return;
      _show(
        'Mitschnitt gespeichert: $name',
        action: SnackBarAction(
          label: 'Für KI teilen',
          onPressed: () async {
            try {
              await _workbench.shareForAi(name);
            } on Exception catch (e) {
              _show('Teilen fehlgeschlagen: $e');
            }
          },
        ),
      );
    } on Exception catch (e) {
      _show('Aufnahme fehlgeschlagen: $e');
    }
  }

  /// Marke in den Mitschnitt schreiben: Vorschlag antippen oder Text
  /// eingeben.
  Future<void> _mark() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Marke setzen'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              children: [
                for (final s in markSuggestions)
                  ActionChip(
                    label: Text(s),
                    onPressed: () => Navigator.of(context).pop(s),
                  ),
              ],
            ),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Eigener Text',
                hintText: 'z. B. Tacho 50',
              ),
              onSubmitted: (v) => Navigator.of(context).pop(v),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Setzen'),
          ),
        ],
      ),
    );
    if (text == null || text.trim().isEmpty) return;
    _workbench.recorder.mark(text);
  }

  void _openSignal(SignalRef ref) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => SignalScreen(
        workbench: _workbench,
        rawId: ref.message.rawId,
        signal: ref.signal,
        existingName: ref.signal.name,
        dlc: ref.message.dlc,
        history: _history,
        ticker: _view,
      ),
    ),
  );

  void _menu(_Menu item) {
    switch (item) {
      case _Menu.diagnostics:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => DiagnosticsScreen(diagnostics: _diagnostics),
          ),
        );
      case _Menu.profile:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ProfileScreen(
              workbench: _workbench,
              history: _history,
              ticker: _view,
            ),
          ),
        );
      case _Menu.reset:
        _reset();
    }
  }

  Future<void> _reset() async {
    _view.clear();
    _history.clear();
    try {
      await widget.connection.send(CanLinkCommands.resetStats());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Zurücksetzen fehlgeschlagen: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final paused = _view.paused;
    final marked = _view.marked;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.connection.name),
        actions: [
          IconButton(
            tooltip: paused ? 'Weiter' : 'Anhalten',
            icon: Icon(paused ? Icons.play_arrow : Icons.pause),
            onPressed: () => setState(() => _view.paused = !paused),
          ),
          IconButton(
            tooltip: marked ? 'Neu markieren' : 'Änderungen suchen',
            icon: Icon(marked ? Icons.flag : Icons.flag_outlined),
            onPressed: () => setState(_view.mark),
          ),
          ListenableBuilder(
            listenable: _workbench.recorder,
            builder: (context, _) {
              final recording = _workbench.recorder.recording;
              return IconButton(
                tooltip: recording ? 'Aufnahme beenden' : 'Aufnehmen',
                icon: Icon(
                  recording ? Icons.stop_circle : Icons.fiber_manual_record,
                  color: Theme.of(context).colorScheme.error,
                ),
                onPressed: _toggleRecording,
              );
            },
          ),
          PopupMenuButton<_Menu>(
            tooltip: 'Mehr',
            onSelected: _menu,
            itemBuilder: (context) => const [
              PopupMenuItem(value: _Menu.profile, child: Text('Profil')),
              PopupMenuItem(value: _Menu.diagnostics, child: Text('Diagnose')),
              PopupMenuItem(value: _Menu.reset, child: Text('Zurücksetzen')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (!_connected)
            MaterialBanner(
              content: const Text('Verbindung zum Leser getrennt.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Zurück'),
                ),
              ],
            ),
          ValueListenableBuilder(
            valueListenable: _diagnostics,
            builder: (context, d, _) => _StatusBar(
              status: _status,
              lost: _view.lostMessages,
              diagnostics: d,
            ),
          ),
          ListenableBuilder(
            listenable: _workbench.recorder,
            builder: (context, _) => _workbench.recorder.recording
                ? _RecordBar(
                    recorder: _workbench.recorder,
                    onMark: _mark,
                    onStop: _toggleRecording,
                  )
                : const SizedBox.shrink(),
          ),
          ListenableBuilder(
            listenable: Listenable.merge([_view, _workbench]),
            builder: (context, _) {
              final pinned = _workbench.pinnedSignals;
              return pinned.isEmpty
                  ? const SizedBox.shrink()
                  : _PinnedBar(
                      signals: pinned,
                      history: _history,
                      onTap: _openSignal,
                    );
            },
          ),
          if (marked)
            ListenableBuilder(
              listenable: _view,
              builder: (context, _) => _MarkBar(
                view: _view,
                onRestart: () => setState(_view.mark),
                onEnd: () => setState(_view.clearMark),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'CAN-ID (hex), z. B. 7E8',
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v.trim().toUpperCase()),
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: Listenable.merge([_view, _workbench]),
              builder: (context, _) {
                final marked = _view.marked;
                final ids = (marked ? _view.changedSinceMark : _view.ids)
                    .where((s) => _query.isEmpty || s.label.contains(_query))
                    .toList();
                if (ids.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        marked
                            ? 'Seit der Markierung hat sich nichts geändert. '
                                  'Jetzt am Auto etwas tun, z. B. blinken.'
                            : 'Noch keine Botschaften.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: ids.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) => _IdTile(
                    state: ids[i],
                    message: _workbench.profile.message(ids[i].rawId),
                    marked: marked,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => IdDetailScreen(
                          view: _view,
                          rawId: ids[i].rawId,
                          workbench: _workbench,
                          history: _history,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

String busStateText(BusState s) => switch (s) {
  BusState.ok => 'Botschaften kommen',
  BusState.silent => 'still',
  BusState.error => 'Busfehler',
  BusState.busOff => 'Bus aus',
  BusState.noController => 'CAN-Controller fehlt',
  BusState.unknown => 'unbekannt',
};

class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.status,
    required this.lost,
    required this.diagnostics,
  });

  final StatusMessage? status;
  final int lost;
  final DiagnosticsMessage? diagnostics;

  @override
  Widget build(BuildContext context) {
    final s = status;
    final theme = Theme.of(context);
    final text = s == null
        ? 'Warte auf Status …'
        : [
            busStateText(s.state),
            if (s.mode == BusMode.listenOnly) 'nur mithören',
            if (diagnostics != null) 'Last ${pct(diagnostics!.loadNowPct)}',
            if (diagnostics != null &&
                diagnosticsHints(diagnostics!).isNotEmpty)
              '⚠ siehe Diagnose',
            '${s.framesTotal} Botschaften',
            '${s.idsSeen} IDs',
            if (s.framesDropped > 0) '${s.framesDropped} verloren (Leser)',
            if (lost > 0) '$lost Übersichten verloren (BLE)',
          ].join(' · ');
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Text(text, style: theme.textTheme.bodySmall),
    );
  }
}

/// Leiste der Änderungssuche: wie lange sie läuft, wie viele IDs sich
/// geändert haben, neu beginnen oder beenden.
class _MarkBar extends StatelessWidget {
  const _MarkBar({
    required this.view,
    required this.onRestart,
    required this.onEnd,
  });

  final BusView view;
  final VoidCallback onRestart;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final seconds = clock.now().difference(view.markedAt!).inSeconds;
    final changed = view.changedSinceMark.length;
    return Container(
      width: double.infinity,
      color: theme.colorScheme.tertiaryContainer,
      padding: const EdgeInsets.only(left: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Änderungen seit $seconds s: $changed von ${view.ids.length} IDs',
              style: theme.textTheme.bodySmall!.copyWith(
                color: theme.colorScheme.onTertiaryContainer,
              ),
            ),
          ),
          TextButton(onPressed: onRestart, child: const Text('Neu')),
          TextButton(onPressed: onEnd, child: const Text('Beenden')),
        ],
      ),
    );
  }
}

/// Leiste während der Aufnahme: Dauer, Umfang, Marke setzen, beenden.
class _RecordBar extends StatelessWidget {
  const _RecordBar({
    required this.recorder,
    required this.onMark,
    required this.onStop,
  });

  final Recorder recorder;
  final VoidCallback onMark;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = recorder.durationMs ~/ 1000;
    final time =
        '${(s ~/ 60).toString().padLeft(2, '0')}:'
        '${(s % 60).toString().padLeft(2, '0')}';
    return Container(
      width: double.infinity,
      color: theme.colorScheme.errorContainer,
      padding: const EdgeInsets.only(left: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              [
                '● Aufnahme $time',
                '${recorder.rows} Zeilen',
                '${recorder.ids} IDs',
                if (recorder.marks > 0) '${recorder.marks} Marken',
              ].join(' · '),
              style: theme.textTheme.bodySmall!.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
          TextButton(onPressed: onMark, child: const Text('Marke')),
          TextButton(onPressed: onStop, child: const Text('Stopp')),
        ],
      ),
    );
  }
}

/// Angepinnte Signale: Name, aktueller Wert und der Verlauf der letzten
/// Minute. Antippen öffnet das Signal.
class _PinnedBar extends StatelessWidget {
  const _PinnedBar({
    required this.signals,
    required this.history,
    required this.onTap,
  });

  static const windowMs = 60000;

  final List<SignalRef> signals;
  final FrameHistory history;
  final void Function(SignalRef) onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
        itemCount: signals.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final ref = signals[i];
          final s = ref.signal;
          return SizedBox(
            width: 156,
            child: Card(
              key: ValueKey('pin-${s.name}'),
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => onTap(ref),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.confidence == SignalConfidence.verified
                            ? s.name
                            : '${s.name} ?',
                        style: theme.textTheme.labelSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        signalValueText(s, history.latest(ref.message.rawId)),
                        style: theme.textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Expanded(
                        child: SignalChart(
                          samples: history.samples(
                            ref.message.rawId,
                            s,
                            windowMs: windowMs,
                          ),
                          signal: s,
                          nowMs: history.nowMs,
                          windowMs: windowMs,
                          compact: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _IdTile extends StatelessWidget {
  const _IdTile({
    required this.state,
    required this.onTap,
    this.message,
    this.marked = false,
  });

  /// Botschaft aus dem Profil, falls die ID dort steht.
  final MessageDef? message;

  /// Änderungssuche läuft: seit der Markierung geänderte Bytes bleiben
  /// umrandet.
  final bool marked;
  final IdState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = theme.textTheme.bodyMedium!.copyWith(fontFamily: 'monospace');
    final now = clock.now();
    final obd = state.obd;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  state.label,
                  style: mono.copyWith(fontWeight: FontWeight.bold),
                ),
                if (message != null && message!.name.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(message!.name, style: theme.textTheme.labelSmall),
                ],
                if (marked && state.newSinceMark) ...[
                  const SizedBox(width: 8),
                  Text('neu', style: theme.textTheme.labelSmall),
                ],
                const Spacer(),
                Text(
                  [
                    if (state.periodMs > 0) '${state.periodMs} ms',
                    '${state.frames}×',
                  ].join(' · '),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              children: [
                for (var i = 0; i < state.data.length; i++)
                  _ByteBox(
                    value: state.data[i],
                    glow: _glow(state.byteChangedAt[i], now),
                    outlined: marked && state.changedSinceMark[i] != 0,
                    style: mono,
                  ),
              ],
            ),
            if (obd != null) ...[
              const SizedBox(height: 4),
              Text(obdText(obd), style: theme.textTheme.bodySmall),
            ],
            if (message != null && message!.signals.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                [
                  for (final s in message!.signals)
                    // Fragezeichen: Zuordnung noch nicht geprüft.
                    '${s.name}${s.confidence == SignalConfidence.verified ? '' : ' ?'}'
                        ' = ${signalValueText(s, state.data)}',
                ].join(' · '),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 1 direkt nach einer Änderung, dann abnehmend bis 0.
  static double _glow(DateTime? changedAt, DateTime now) {
    if (changedAt == null) return 0;
    final age = now.difference(changedAt);
    if (age >= highlightDuration) return 0;
    return 1 - age.inMilliseconds / highlightDuration.inMilliseconds;
  }
}

class _ByteBox extends StatelessWidget {
  const _ByteBox({
    required this.value,
    required this.glow,
    required this.style,
    this.outlined = false,
  });

  final int value;
  final double glow;

  /// Seit der Markierung geändert (Änderungssuche).
  final bool outlined;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: glow > 0 ? const ValueKey('geaendert') : null,
      // Ein Pixel weniger als früher: Der Rahmen braucht es.
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      decoration: BoxDecoration(
        color: Color.lerp(Colors.transparent, scheme.tertiaryContainer, glow),
        border: Border.all(
          color: outlined ? scheme.tertiary : Colors.transparent,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        value.toRadixString(16).toUpperCase().padLeft(2, '0'),
        style: style,
      ),
    );
  }
}
