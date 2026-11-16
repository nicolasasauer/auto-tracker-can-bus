import 'package:can_link/can_link.dart';
import 'package:flutter/material.dart';

/// Verlauf eines Signals über die Zeit. Gezeichnet wird aus den Rohwerten,
/// umgerechnet mit dem übergebenen Signal: Ändert man Faktor oder Offset,
/// passt sich die Achse sofort an.
class SignalChart extends StatelessWidget {
  const SignalChart({
    super.key,
    required this.samples,
    required this.signal,
    required this.nowMs,
    required this.windowMs,
    this.compact = false,
  });

  final List<SignalSample> samples;
  final SignalDef signal;

  /// Rechter Rand der Zeitachse.
  final int nowMs;
  final int windowMs;

  /// Ohne Achsenbeschriftung (kleine Vorschau bei angepinnten Signalen).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (samples.length < 2) {
      return Center(
        child: Text(
          compact ? '' : 'Noch kein Verlauf.',
          style: theme.textTheme.bodySmall,
        ),
      );
    }
    var min = signal.scale(samples.first.raw);
    var max = min;
    for (final s in samples) {
      final v = signal.scale(s.raw);
      if (v < min) min = v;
      if (v > max) max = v;
    }
    final chart = CustomPaint(
      painter: _ChartPainter(
        samples: samples,
        signal: signal,
        nowMs: nowMs,
        windowMs: windowMs,
        min: min,
        max: max,
        line: theme.colorScheme.primary,
        grid: theme.colorScheme.outlineVariant,
      ),
      child: const SizedBox.expand(),
    );
    if (compact) return chart;
    final label = theme.textTheme.labelSmall;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('max ${signal.format(max)}', style: label),
        Expanded(child: chart),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('min ${signal.format(min)}', style: label),
            Text('letzte ${windowText(windowMs)}', style: label),
          ],
        ),
      ],
    );
  }
}

String windowText(int ms) =>
    ms < 60000 ? '${ms ~/ 1000} s' : '${ms ~/ 60000} min';

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.samples,
    required this.signal,
    required this.nowMs,
    required this.windowMs,
    required this.min,
    required this.max,
    required this.line,
    required this.grid,
  });

  final List<SignalSample> samples;
  final SignalDef signal;
  final int nowMs;
  final int windowMs;
  final double min;
  final double max;
  final Color line;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final y in [0.0, size.height / 2, size.height]) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    final span = max - min;
    final from = nowMs - windowMs;
    double x(int tMs) => (tMs - from) / windowMs * size.width;
    // Konstanter Wert: Linie in die Mitte.
    double y(int raw) => span == 0
        ? size.height / 2
        : size.height - (signal.scale(raw) - min) / span * size.height;

    // Treppe statt Schräge: Der Wert gilt bis zur nächsten Übersicht.
    final path = Path()..moveTo(x(samples.first.tMs), y(samples.first.raw));
    for (var i = 1; i < samples.length; i++) {
      path
        ..lineTo(x(samples[i].tMs), y(samples[i - 1].raw))
        ..lineTo(x(samples[i].tMs), y(samples[i].raw));
    }
    path.lineTo(x(nowMs), y(samples.last.raw));
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.nowMs != nowMs ||
      old.windowMs != windowMs ||
      old.signal != signal ||
      old.samples.length != samples.length;
}
