import 'dart:math';

import 'package:flutter/material.dart';

import '../models.dart';
import '../util.dart';

/// Anillo de progreso de calorías.
class CalorieRing extends StatelessWidget {
  final double value;
  final double max;
  final double size;
  final Widget center;
  const CalorieRing({super.key, required this.value, required this.max, required this.center, this.size = 150});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final over = value > max;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(
          fraction: max <= 0 ? 0 : value / max,
          track: cs.surfaceContainerHighest,
          color: over ? overColor : cs.primary,
          overColor: overColor,
        ),
        child: Center(child: center),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double fraction;
  final Color track, color, overColor;
  _RingPainter({required this.fraction, required this.track, required this.color, required this.overColor});

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 13.0;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    final base = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 2 * pi, false, base);
    final f = fraction.clamp(0.0, 1.0);
    if (f > 0) {
      canvas.drawArc(rect, -pi / 2, 2 * pi * f, false, base..color = color);
    }
    if (fraction > 1) {
      final extra = (fraction - 1).clamp(0.0, 1.0);
      canvas.drawArc(rect, -pi / 2, 2 * pi * extra, false, base..color = overColor.withValues(alpha: 0.55));
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.fraction != fraction || old.color != color || old.track != track;
}

/// Barra de macronutriente con etiqueta.
class MacroBar extends StatelessWidget {
  final String label;
  final double value;
  final double target;
  final Color color;
  const MacroBar({super.key, required this.label, required this.value, required this.target, required this.color});

  @override
  Widget build(BuildContext context) {
    final f = target <= 0 ? 0.0 : value / target;
    final ts = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: ts.labelMedium),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: f.clamp(0.0, 1.0),
            minHeight: 8,
            color: f > 1.1 ? overColor : color,
            backgroundColor: color.withValues(alpha: 0.15),
          ),
        ),
        const SizedBox(height: 3),
        Text('${fmtNum(value)} / ${fmtNum(target)} g', style: ts.bodySmall),
      ],
    );
  }
}

/// Gráfico de barras sencillo con línea de objetivo opcional por barra.
class BarChartSimple extends StatelessWidget {
  final List<double> values;
  final List<double?> targets;
  final List<String> labels;
  final List<Color> colors;
  final double height;
  final void Function(int)? onTap;
  const BarChartSimple({super.key, required this.values, required this.targets, required this.labels, required this.colors, this.height = 170, this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final maxV = [...values, ...targets.whereType<double>(), 1.0].reduce(max) * 1.12;
    return SizedBox(
      height: height,
      child: LayoutBuilder(builder: (context, c) {
        final n = values.length;
        final w = c.maxWidth / max(n, 1);
        return GestureDetector(
          onTapUp: onTap == null ? null : (d) => onTap!((d.localPosition.dx / w).floor().clamp(0, n - 1)),
          child: CustomPaint(
            size: Size(c.maxWidth, height),
            painter: _BarsPainter(values, targets, labels, colors, maxV, cs.onSurfaceVariant, cs.outline),
          ),
        );
      }),
    );
  }
}

class _BarsPainter extends CustomPainter {
  final List<double> values;
  final List<double?> targets;
  final List<String> labels;
  final List<Color> colors;
  final double maxV;
  final Color text, line;
  _BarsPainter(this.values, this.targets, this.labels, this.colors, this.maxV, this.text, this.line);

  @override
  void paint(Canvas canvas, Size size) {
    const labelH = 18.0;
    final h = size.height - labelH;
    final n = values.length;
    if (n == 0) return;
    final slot = size.width / n;
    final bw = min(slot * 0.62, 34.0);
    for (var i = 0; i < n; i++) {
      final x = slot * i + (slot - bw) / 2;
      final bh = values[i] / maxV * h;
      final r = RRect.fromRectAndCorners(Rect.fromLTWH(x, h - bh, bw, bh),
          topLeft: const Radius.circular(5), topRight: const Radius.circular(5));
      canvas.drawRRect(r, Paint()..color = colors[i]);
      final t = targets[i];
      if (t != null && t > 0) {
        final y = h - t / maxV * h;
        canvas.drawLine(Offset(x - 3, y), Offset(x + bw + 3, y), Paint()
          ..color = line
          ..strokeWidth = 2);
      }
      final tp = TextPainter(
        text: TextSpan(text: labels[i], style: TextStyle(fontSize: n > 16 ? 9 : 11, color: text)),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: slot + 6);
      if (n <= 16 || i % 3 == 0) tp.paint(canvas, Offset(slot * i + (slot - tp.width) / 2, h + 3));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// Gráfico de líneas: puntos (pesadas) + línea de tendencia.
class WeightChart extends StatelessWidget {
  final List<DateTime> dates;
  final List<double> weights;
  final List<double> trend;
  const WeightChart({super.key, required this.dates, required this.weights, required this.trend});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 200,
      child: CustomPaint(
        size: const Size(double.infinity, 200),
        painter: _WeightPainter(dates, weights, trend, cs.primary, cs.onSurfaceVariant, cs.outlineVariant),
      ),
    );
  }
}

class _WeightPainter extends CustomPainter {
  final List<DateTime> dates;
  final List<double> w, t;
  final Color color, text, grid;
  _WeightPainter(this.dates, this.w, this.t, this.color, this.text, this.grid);

  @override
  void paint(Canvas canvas, Size size) {
    if (w.isEmpty) return;
    const left = 40.0, bottom = 20.0;
    final all = [...w, ...t];
    var lo = all.reduce(min), hi = all.reduce(max);
    if (hi - lo < 1) {
      hi += 0.5;
      lo -= 0.5;
    }
    final pad = (hi - lo) * 0.1;
    lo -= pad;
    hi += pad;
    final first = dates.first, last = dates.last;
    final span = max(1, last.difference(first).inDays);
    final cw = size.width - left - 8, ch = size.height - bottom;
    Offset pt(int i, double v) =>
        Offset(left + (dates[i].difference(first).inDays / span) * cw, ch - (v - lo) / (hi - lo) * ch);

    final gp = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var k = 0; k <= 3; k++) {
      final v = lo + (hi - lo) * k / 3;
      final y = ch - (v - lo) / (hi - lo) * ch;
      canvas.drawLine(Offset(left, y), Offset(size.width, y), gp);
      final tp = TextPainter(
          text: TextSpan(text: fmtNum(v, 1), style: TextStyle(fontSize: 10, color: text)),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, Offset(0, y - 6));
    }
    for (final (i, d) in [(0, first), (dates.length - 1, last)]) {
      final tp = TextPainter(
          text: TextSpan(text: fmtShort(d), style: TextStyle(fontSize: 10, color: text)), textDirection: TextDirection.ltr)
        ..layout();
      final x = pt(i, w[i]).dx - (i == 0 ? 0 : tp.width);
      tp.paint(canvas, Offset(x, ch + 4));
    }
    final dot = Paint()..color = color.withValues(alpha: 0.35);
    for (var i = 0; i < w.length; i++) {
      canvas.drawCircle(pt(i, w[i]), 3.2, dot);
    }
    if (t.length > 1) {
      final path = Path()..moveTo(pt(0, t[0]).dx, pt(0, t[0]).dy);
      for (var i = 1; i < t.length; i++) {
        path.lineTo(pt(i, t[i]).dx, pt(i, t[i]).dy);
      }
      canvas.drawPath(
          path,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

Color statusColor(DayStatus status, ColorScheme cs) => switch (status) {
      DayStatus.ok => okColor,
      DayStatus.over => overColor,
      DayStatus.under => underColor,
      DayStatus.none => cs.surfaceContainerHighest,
    };

String statusLabel(DayStatus s) => switch (s) {
      DayStatus.ok => 'Objetivo cumplido',
      DayStatus.over => 'Te pasaste',
      DayStatus.under => 'Te quedaste corto',
      DayStatus.none => 'Sin registro',
    };
