import 'package:flutter/foundation.dart';
import 'package:can_link/can_link.dart';
import 'package:flutter/material.dart';

import 'diagnostics_text.dart';

/// Diagnose des Lesers: Buslast, Empfangsfehler, Pufferreserve, Neustarts.
class DiagnosticsScreen extends StatelessWidget {
  const DiagnosticsScreen({super.key, required this.diagnostics});

  /// Letzte Diagnose; null, solange keine kam (z. B. ältere Firmware).
  final ValueListenable<DiagnosticsMessage?> diagnostics;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Diagnose')),
      body: ValueListenableBuilder(
        valueListenable: diagnostics,
        builder: (context, d, _) => d == null
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Noch keine Diagnose. Ältere Firmware des Lesers schickt '
                    'keine; dann die Firmware aktualisieren.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : _Body(d: d),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.d});

  final DiagnosticsMessage d;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hints = diagnosticsHints(d);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final h in hints)
          Card(
            color: theme.colorScheme.errorContainer,
            child: ListTile(
              leading: const Icon(Icons.warning_amber),
              title: Text(h),
            ),
          ),
        _Section('Buslast', [
          _Bar(
            'Aktuell',
            d.loadNowPct / 100,
            pct(d.loadNowPct),
            warn: d.loadNowPct >= loadWarnPct,
          ),
          _Bar(
            'Mittel 10 s',
            d.loadAvgPct / 100,
            pct(d.loadAvgPct),
            warn: d.loadAvgPct >= loadWarnPct,
          ),
          _Bar(
            'Spitze',
            d.loadPeakPct / 100,
            pct(d.loadPeakPct),
            warn: d.loadPeakPct >= loadWarnPct,
          ),
        ]),
        _Section('Empfangsfehler', [
          _Row('Fehlerzähler (REC)', '${d.rxErrorCounter}'),
          _Row('Fehlerhafte Botschaften', '${d.errorEvents}'),
          _Row(
            'Fehler-Flags',
            '0x${d.errorFlags.toRadixString(16).toUpperCase().padLeft(2, '0')}',
          ),
        ]),
        _Section('Zwischenpuffer im Leser', [
          _Bar(
            'Höchststand',
            d.ringMaxShare,
            '${d.ringMaxFill} von ${d.ringCapacity}',
            warn: d.ringMaxShare >= ringWarnShare,
          ),
        ]),
        _Section('Neustarts', [
          _Row('Start Nr.', '${d.bootCount}'),
          _Row('Letzter Grund', resetReasonText(d.resetReason)),
        ]),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.children);

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar(this.label, this.share, this.value, {this.warn = false});

  final String label;
  final double share;
  final String value;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Row(label, value),
          LinearProgressIndicator(
            value: share.clamp(0, 1),
            color: warn ? scheme.error : scheme.primary,
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
          ),
        ],
      ),
    );
  }
}
