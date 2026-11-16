import 'dart:typed_data';

import 'package:can_link/can_link.dart';
import 'package:flutter/material.dart';

import 'obd_text.dart';
import 'signal_screen.dart';
import 'workbench.dart';

/// Eine CAN-ID im Detail: Bytes als Hex und dezimal, dazu ein Bitraster.
/// Bits, die sich seit Beginn je geändert haben, sind markiert. So lässt sich
/// eingrenzen, wo ein Signal liegt (z. B. Blinker an/aus → genau ein Bit).
///
/// Bits lassen sich antippen: erstes und letztes Bit eines Bereichs wählen,
/// dann „Signal anlegen“.
class IdDetailScreen extends StatefulWidget {
  const IdDetailScreen({
    super.key,
    required this.view,
    required this.rawId,
    required this.workbench,
    required this.history,
  });

  final BusView view;
  final int rawId;
  final Workbench workbench;
  final FrameHistory history;

  @override
  State<IdDetailScreen> createState() => _IdDetailScreenState();
}

class _IdDetailScreenState extends State<IdDetailScreen> {
  /// Auswahl im Bitraster als Abstand vom höchstwertigen Bit von Byte 0.
  int? _anchor;
  int? _end;
  bool _rangeDone = false;

  void _tapBit(int position) => setState(() {
    if (_anchor == null || _rangeDone) {
      _anchor = position;
      _end = position;
      _rangeDone = false;
    } else {
      _end = position;
      _rangeDone = true;
    }
  });

  ({int start, int length})? get _selection {
    final a = _anchor;
    final e = _end;
    if (a == null || e == null) return null;
    final from = a < e ? a : e;
    return (start: from, length: (a - e).abs() + 1);
  }

  void _openSignal(IdState state, SignalDef signal, {String? existingName}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SignalScreen(
          workbench: widget.workbench,
          rawId: widget.rawId,
          signal: signal,
          existingName: existingName,
          dlc: state.data.length,
          history: widget.history,
          ticker: widget.view,
        ),
      ),
    );
  }

  /// Freier Name für ein neues Signal, z. B. „sig_208_16“.
  String _newName(IdState state, int start) {
    final base = 'sig_${state.label.toLowerCase()}_$start';
    var name = base;
    for (var i = 2; widget.workbench.profile.signal(name) != null; i++) {
      name = '${base}_$i';
    }
    return name;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.view, widget.workbench]),
      builder: (context, _) {
        final state = widget.view[widget.rawId];
        final message = widget.workbench.profile.message(widget.rawId);
        final name = message?.name ?? '';
        return Scaffold(
          appBar: AppBar(
            title: Text(
              state == null
                  ? 'CAN-ID'
                  : 'CAN-ID ${state.label}${name.isEmpty ? '' : ' · $name'}',
            ),
          ),
          body: state == null
              ? const Center(child: Text('Keine Daten mehr (zurückgesetzt).'))
              : _details(context, state, message),
        );
      },
    );
  }

  Widget _details(BuildContext context, IdState state, MessageDef? message) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mono = theme.textTheme.bodyMedium!.copyWith(fontFamily: 'monospace');
    final obd = state.obd;
    final marked = widget.view.marked;
    final changed = marked ? state.changedSinceMark : state.changedEver;
    final signals = message?.signals ?? const <SignalDef>[];
    final inSignal = {for (final s in signals) ...s.bitPositions};
    final selection = _selection;
    final draft = selection == null
        ? null
        : SignalDef(
            name: '',
            start: selection.start,
            length: selection.length.clamp(1, maxSignalLength),
          );
    final selectedRaw = draft?.rawFrom(state.data);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          [
            state.extended ? '29-Bit-ID' : '11-Bit-ID',
            '${state.data.length} Byte',
            if (state.periodMs > 0) 'alle ${state.periodMs} ms',
            '${state.frames} Botschaften',
          ].join(' · '),
          style: theme.textTheme.bodySmall,
        ),
        if (obd != null) ...[
          const SizedBox(height: 8),
          Text(obdText(obd), style: theme.textTheme.titleSmall),
        ],
        const SizedBox(height: 16),
        Text(
          'Bits (links Bit 7, rechts Bit 0)',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        for (var b = 0; b < state.data.length; b++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                SizedBox(
                  width: 56,
                  child: Text('Byte $b', style: theme.textTheme.bodySmall),
                ),
                for (var bit = 7; bit >= 0; bit--)
                  _Bit(
                    key: ValueKey('bit-$b-$bit'),
                    on: state.data[b] >> bit & 1 == 1,
                    changed: changed[b] >> bit & 1 == 1,
                    inSignal: inSignal.contains(b * 8 + 7 - bit),
                    selected:
                        selection != null &&
                        b * 8 + 7 - bit >= selection.start &&
                        b * 8 + 7 - bit < selection.start + selection.length,
                    scheme: scheme,
                    onTap: () => _tapBit(b * 8 + 7 - bit),
                  ),
                const SizedBox(width: 12),
                Text(
                  '${state.data[b].toRadixString(16).toUpperCase().padLeft(2, '0')}'
                  '  ${state.data[b].toString().padLeft(3)}',
                  style: mono,
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Text(
          'Umrandet: Bit hat sich seit ${marked ? 'der Markierung' : 'Beginn'} '
          'geändert. Gefüllt: Bit ist gerade 1. Strich darunter: gehört zu '
          'einem Signal. Antippen wählt einen Bereich (erstes und letztes Bit).',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                selection == null
                    ? 'Kein Bereich gewählt.'
                    : 'Auswahl: Start ${selection.start}, '
                          '${selection.length} Bit'
                          '${selectedRaw == null ? '' : ' = $selectedRaw'}',
              ),
            ),
            FilledButton.tonal(
              onPressed: () {
                final start = selection?.start ?? 0;
                _openSignal(
                  state,
                  SignalDef(
                    name: _newName(state, start),
                    start: start,
                    length: selection?.length ?? 8,
                  ),
                );
              },
              child: const Text('Signal anlegen'),
            ),
          ],
        ),
        if (signals.isNotEmpty) ...[
          const Divider(height: 32),
          Text('Signale', style: theme.textTheme.titleSmall),
          for (final s in signals)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s.name),
              subtitle: Text(signalSummary(s)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(signalValueText(s, state.data), style: mono),
                  IconButton(
                    tooltip: widget.workbench.isPinned(s.name)
                        ? 'Lösen'
                        : 'Anpinnen',
                    icon: Icon(
                      widget.workbench.isPinned(s.name)
                          ? Icons.push_pin
                          : Icons.push_pin_outlined,
                    ),
                    onPressed: () => widget.workbench.togglePin(s.name),
                  ),
                ],
              ),
              onTap: () => _openSignal(state, s, existingName: s.name),
            ),
        ],
      ],
    );
  }
}

/// Lage und Umrechnung in einer Zeile, z. B. „Bit 0, 16 Bit · × 0,125 · geprüft“.
String signalSummary(SignalDef s) => [
  'Bit ${s.start}, ${s.length} Bit',
  if (s.byteOrder == SignalByteOrder.little) 'Little Endian',
  if (s.signed) 'mit Vorzeichen',
  if (s.factor != 1) '× ${numberText(s.factor)}',
  if (s.offset != 0)
    '${s.offset > 0 ? '+' : '−'} ${numberText(s.offset.abs())}',
  s.confidence.label,
].join(' · ');

/// Aktueller Wert eines Signals als Text, „–“ wenn die Botschaft zu kurz ist.
String signalValueText(SignalDef s, Uint8List? data) {
  final value = data == null ? null : s.valueFrom(data);
  return value == null ? '–' : s.format(value);
}

class _Bit extends StatelessWidget {
  const _Bit({
    super.key,
    required this.on,
    required this.changed,
    required this.inSignal,
    required this.selected,
    required this.scheme,
    required this.onTap,
  });

  final bool on;
  final bool changed;
  final bool inSignal;
  final bool selected;
  final ColorScheme scheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(1),
        child: Column(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: on ? scheme.primary : scheme.surfaceContainerHighest,
                border: Border.all(
                  color: selected
                      ? scheme.error
                      : changed
                      ? scheme.tertiary
                      : Colors.transparent,
                  width: selected ? 3 : 2,
                ),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            Container(
              width: 20,
              height: 3,
              margin: const EdgeInsets.only(top: 1),
              color: inSignal ? scheme.secondary : Colors.transparent,
            ),
          ],
        ),
      ),
    );
  }
}
