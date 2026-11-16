import 'package:can_link/can_link.dart';
import 'package:flutter/material.dart';

import 'signal_chart.dart';
import 'workbench.dart';

/// Ein Signal bearbeiten und dabei live beobachten: Rohwert, umgerechneter
/// Wert und Verlauf. Startbit, Länge, Faktor und Offset wirken sofort auf
/// Anzeige und Graph (auch rückwirkend auf den Verlauf), ins Profil kommt
/// der Stand erst mit „Speichern“.
class SignalScreen extends StatefulWidget {
  const SignalScreen({
    super.key,
    required this.workbench,
    required this.rawId,
    required this.signal,
    this.existingName,
    this.dlc,
    this.history,
    this.ticker,
  });

  final Workbench workbench;
  final int rawId;

  /// Ausgangswerte (bestehendes Signal oder Vorschlag aus dem Bitraster).
  final SignalDef signal;

  /// Name des Signals im Profil, null bei einem neuen.
  final String? existingName;

  /// Datenlänge der Botschaft, falls bekannt.
  final int? dlc;

  /// Verlauf der Nutzdaten; ohne Verbindung null.
  final FrameHistory? history;

  /// Meldet neue Daten im Verlauf.
  final Listenable? ticker;

  @override
  State<SignalScreen> createState() => _SignalScreenState();
}

const _windows = [30000, 120000, 600000];

double? parseNumber(String text) =>
    double.tryParse(text.trim().replaceAll(',', '.'));

String numberText(double v) => v == v.roundToDouble() && v.abs() < 1e15
    ? v.toInt().toString()
    : v.toString().replaceAll('.', ',');

class _SignalScreenState extends State<SignalScreen> {
  late final _name = TextEditingController(text: widget.signal.name);
  late final _start = TextEditingController(text: '${widget.signal.start}');
  late final _length = TextEditingController(text: '${widget.signal.length}');
  late final _factor = TextEditingController(
    text: numberText(widget.signal.factor),
  );
  late final _offset = TextEditingController(
    text: numberText(widget.signal.offset),
  );
  late final _unit = TextEditingController(text: widget.signal.unit);
  late final _note = TextEditingController(text: widget.signal.note);
  late bool _signed = widget.signal.signed;
  late SignalByteOrder _order = widget.signal.byteOrder;
  late SignalConfidence _confidence = widget.signal.confidence;
  int _windowMs = _windows.first;
  bool _dirty = false;

  /// Name im Profil; ändert sich nach dem ersten Speichern eines neuen
  /// Signals.
  late String? _savedName = widget.existingName;

  @override
  void initState() {
    super.initState();
    _dirty = widget.existingName == null;
  }

  @override
  void dispose() {
    for (final c in [_name, _start, _length, _factor, _offset, _unit, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Der Stand der Eingabefelder, null solange eine Zahl fehlt.
  SignalDef? get _draft {
    final start = int.tryParse(_start.text.trim());
    final length = int.tryParse(_length.text.trim());
    final factor = parseNumber(_factor.text);
    final offset = parseNumber(_offset.text);
    if (start == null ||
        length == null ||
        factor == null ||
        offset == null ||
        start < 0 ||
        length < 1 ||
        length > maxSignalLength) {
      return null;
    }
    return widget.signal.copyWith(
      name: _name.text.trim(),
      start: start,
      length: length,
      signed: _signed,
      byteOrder: _order,
      factor: factor,
      offset: offset,
      unit: _unit.text.trim(),
      confidence: _confidence,
      note: _note.text.trim(),
    );
  }

  void _edited() => setState(() => _dirty = true);

  void _step(TextEditingController c, int by, {int min = 0}) {
    final v = (int.tryParse(c.text.trim()) ?? min) + by;
    c.text = '${v < min ? min : v}';
    _edited();
  }

  void _scaleFactor(double by) {
    final f = parseNumber(_factor.text);
    if (f == null) return;
    // Auf 12 Stellen runden, sonst wird aus 0,1 × 10 ÷ 10 ein 0,1000…01.
    _factor.text = numberText(double.parse((f * by).toStringAsPrecision(12)));
    _edited();
  }

  /// Faktor so setzen, dass der aktuelle Rohwert den Wert ergibt, den der
  /// Nutzer gerade am Auto abliest.
  Future<void> _calibrate(int raw, SignalDef draft) async {
    final controller = TextEditingController();
    final target = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Faktor aus Sollwert'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Rohwert gerade: $raw. Welchen Wert zeigt das Auto in diesem '
              'Moment (Tacho, Bordcomputer)?',
            ),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: const InputDecoration(labelText: 'Sollwert'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(parseNumber(controller.text)),
            child: const Text('Übernehmen'),
          ),
        ],
      ),
    );
    if (target == null || !mounted) return;
    final factor = (target - draft.offset) / raw;
    _factor.text = numberText(double.parse(factor.toStringAsPrecision(6)));
    _edited();
  }

  bool _save() {
    final draft = _draft;
    if (draft == null) {
      _show('Start, Länge, Faktor und Offset müssen Zahlen sein.');
      return false;
    }
    try {
      widget.workbench.saveSignal(
        widget.rawId,
        draft,
        replaces: _savedName,
        dlc: widget.dlc,
      );
    } on ProfileFormatException catch (e) {
      _show(e.toString());
      return false;
    }
    setState(() {
      _savedName = draft.name;
      _dirty = false;
    });
    _show('Im Profil gespeichert.');
    return true;
  }

  void _show(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _delete() async {
    final name = _savedName;
    if (name == null) return;
    widget.workbench.deleteSignal(name);
    _leave();
  }

  /// Seite verlassen, ohne nach ungespeicherten Änderungen zu fragen.
  void _leave() {
    final navigator = Navigator.of(context);
    setState(() => _dirty = false);
    // Erst nach dem Neuaufbau lässt PopScope das Verlassen zu.
    WidgetsBinding.instance.addPostFrameCallback((_) => navigator.pop());
  }

  Future<bool> _confirmDiscard() async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Änderungen verwerfen?'),
          content: const Text('Das Signal ist noch nicht gespeichert.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Weiter bearbeiten'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Verwerfen'),
            ),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final label = formatCanId(
      widget.rawId & CanLinkProtocol.idMask,
      extended: widget.rawId & CanLinkProtocol.extendedFlag != 0,
    );
    final saved = _savedName;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && mounted) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(saved ?? 'Neues Signal'),
          actions: [
            if (saved != null)
              ListenableBuilder(
                listenable: widget.workbench,
                builder: (context, _) {
                  final pinned = widget.workbench.isPinned(saved);
                  return IconButton(
                    tooltip: pinned ? 'Lösen' : 'Anpinnen',
                    icon: Icon(
                      pinned ? Icons.push_pin : Icons.push_pin_outlined,
                    ),
                    onPressed: () => widget.workbench.togglePin(saved),
                  );
                },
              ),
            if (saved != null)
              IconButton(
                tooltip: 'Signal löschen',
                icon: const Icon(Icons.delete_outline),
                onPressed: _delete,
              ),
            IconButton(
              tooltip: 'Speichern',
              icon: const Icon(Icons.save_outlined),
              onPressed: _dirty ? _save : null,
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ListenableBuilder(
              listenable: widget.ticker ?? const AlwaysStoppedAnimation(0),
              builder: (context, _) => _live(context, label),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'z. B. engine_rpm',
              ),
              autocorrect: false,
              onChanged: (_) => _edited(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _Stepper(
                    label: 'Startbit',
                    controller: _start,
                    onStep: (by) => _step(_start, by),
                    onChanged: _edited,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Stepper(
                    label: 'Länge (Bit)',
                    controller: _length,
                    onStep: (by) => _step(_length, by, min: 1),
                    onChanged: _edited,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(_bitsText(), style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SegmentedButton<SignalByteOrder>(
                  segments: const [
                    ButtonSegment(
                      value: SignalByteOrder.big,
                      label: Text('Big Endian'),
                    ),
                    ButtonSegment(
                      value: SignalByteOrder.little,
                      label: Text('Little Endian'),
                    ),
                  ],
                  selected: {_order},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) {
                    _order = v.single;
                    _edited();
                  },
                ),
                FilterChip(
                  label: const Text('mit Vorzeichen'),
                  selected: _signed,
                  onSelected: (v) {
                    _signed = v;
                    _edited();
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _factor,
                    decoration: const InputDecoration(labelText: 'Faktor'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    onChanged: (_) => _edited(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _offset,
                    decoration: const InputDecoration(labelText: 'Offset'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    onChanged: (_) => _edited(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _unit,
                    decoration: const InputDecoration(labelText: 'Einheit'),
                    autocorrect: false,
                    onChanged: (_) => _edited(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final (text, by) in const [
                  ('÷ 10', 0.1),
                  ('÷ 2', 0.5),
                  ('× 2', 2.0),
                  ('× 10', 10.0),
                ])
                  ActionChip(
                    label: Text(text),
                    onPressed: () => _scaleFactor(by),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<SignalConfidence>(
              initialValue: _confidence,
              decoration: const InputDecoration(labelText: 'Stand'),
              items: [
                for (final c in SignalConfidence.values)
                  DropdownMenuItem(value: c, child: Text(c.label)),
              ],
              onChanged: (v) {
                if (v == null) return;
                _confidence = v;
                _edited();
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              decoration: const InputDecoration(labelText: 'Notiz'),
              maxLines: null,
              onChanged: (_) => _edited(),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _dirty ? _save : null,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Im Profil speichern'),
            ),
          ],
        ),
      ),
    );
  }

  String _bitsText() {
    final bits = _draft?.bitPositions;
    if (bits == null || bits.isEmpty) return 'Bitfeld unvollständig.';
    String at(int p) => 'Byte ${p >> 3} Bit ${7 - p % 8}';
    return bits.length == 1
        ? at(bits.first)
        : '${at(bits.first)} (höchstwertig) bis ${at(bits.last)}';
  }

  Widget _live(BuildContext context, String label) {
    final theme = Theme.of(context);
    final draft = _draft;
    final history = widget.history;
    final data = history?.latest(widget.rawId);
    final raw = draft == null || data == null ? null : draft.rawFrom(data);
    final String valueText;
    if (draft == null) {
      valueText = '–';
    } else if (history == null) {
      valueText = 'keine Verbindung';
    } else if (data == null) {
      valueText = 'ID $label kam noch nicht';
    } else if (raw == null) {
      valueText = 'passt nicht in ${data.length} Byte';
    } else {
      valueText = draft.format(draft.scale(raw));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('CAN-ID $label', style: theme.textTheme.bodySmall),
        Text(
          valueText,
          key: const ValueKey('signalwert'),
          style: theme.textTheme.headlineMedium,
        ),
        Row(
          children: [
            Expanded(
              child: Text(
                raw == null
                    ? 'Rohwert –'
                    : 'Rohwert $raw (0x${(raw < 0 ? raw + (1 << draft!.length) : raw).toRadixString(16).toUpperCase()})',
                style: theme.textTheme.bodySmall,
              ),
            ),
            if (raw != null && raw != 0)
              TextButton(
                onPressed: () => _calibrate(raw, draft!),
                child: const Text('Faktor aus Sollwert'),
              ),
          ],
        ),
        if (history != null && draft != null) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 180,
            child: SignalChart(
              samples: history.samples(
                widget.rawId,
                draft,
                windowMs: _windowMs,
              ),
              signal: draft,
              nowMs: history.nowMs,
              windowMs: _windowMs,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: [
              for (final w in _windows)
                ChoiceChip(
                  label: Text(windowText(w)),
                  selected: _windowMs == w,
                  onSelected: (_) => setState(() => _windowMs = w),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Zahlenfeld mit Knöpfen für −1 und +1: So lässt sich ein Bitfeld schnell
/// verschieben oder verlängern, während man den Wert beobachtet.
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.controller,
    required this.onStep,
    required this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final void Function(int by) onStep;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            decoration: InputDecoration(labelText: label),
            keyboardType: TextInputType.number,
            onChanged: (_) => onChanged(),
          ),
        ),
        IconButton(
          tooltip: '$label −1',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.remove),
          onPressed: () => onStep(-1),
        ),
        IconButton(
          tooltip: '$label +1',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.add),
          onPressed: () => onStep(1),
        ),
      ],
    );
  }
}
