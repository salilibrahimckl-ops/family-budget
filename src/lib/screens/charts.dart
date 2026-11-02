import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'common.dart';

class Segment {
  final double value;
  final Color color;
  final String label;
  const Segment(this.value, this.color, this.label);
}

/// Ring chart: one slice per category spent, plus a grey "remaining" slice.
class DonutChart extends StatelessWidget {
  const DonutChart({super.key, required this.segments, this.size = 200, this.thickness = 26, this.center});
  final List<Segment> segments;
  final double size, thickness;
  final Widget? center;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _DonutPainter(segments, thickness, Theme.of(context).colorScheme.surfaceContainerHighest),
          child: Center(child: center),
        ),
      );
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.segments, this.thickness, this.track);
  final List<Segment> segments;
  final double thickness;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(thickness / 2, thickness / 2, size.width - thickness, size.height - thickness);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..color = track;
    canvas.drawArc(rect, 0, math.pi * 2, false, base);
    final total = segments.fold<double>(0, (s, e) => s + e.value);
    if (total <= 0) return;
    const gap = 0.025;
    var start = -math.pi / 2;
    for (final s in segments) {
      if (s.value <= 0) continue;
      final sweep = s.value / total * math.pi * 2;
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness
        ..strokeCap = StrokeCap.butt
        ..color = s.color;
      final g = segments.where((e) => e.value > 0).length > 1 ? gap : 0.0;
      canvas.drawArc(rect, start + g / 2, math.max(0.001, sweep - g), false, p);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => true;
}

/// Small legend chips under a chart.
class ChartLegend extends StatelessWidget {
  const ChartLegend(this.segments, {super.key, this.total, this.showMoney = true});
  final List<Segment> segments;
  /// When set, each item also shows its share of this total as a percentage.
  final double? total;
  final bool showMoney;
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    String pct(double v) => total != null && total! > 0 ? '${(v / total! * 100).round()}%' : '';
    return Wrap(spacing: 12, runSpacing: 6, alignment: WrapAlignment.center, children: [
      for (final s in segments.where((s) => s.value > 0))
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: s.color, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text([s.label, if (showMoney) money(s.value), if (total != null) pct(s.value)].join(' '),
              style: tt.bodySmall),
        ]),
    ]);
  }
}

/// Spent vs budget for each category, as paired vertical bars.
class BudgetBars extends StatelessWidget {
  const BudgetBars({super.key, required this.items});
  /// (label, spent, budget, color)
  final List<(String, double, double, Color)> items;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final maxV = items.fold<double>(1, (m, e) => math.max(m, math.max(e.$2, e.$3)));
    const h = 150.0;
    return SizedBox(
      height: h + 44,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (final e in items)
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
              Text(_short(e.$2), style: tt.labelSmall?.copyWith(
                  color: e.$2 > e.$3 && e.$3 > 0 ? cs.error : null, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                _bar(e.$3 / maxV * h, e.$4.withValues(alpha: 0.22)),
                const SizedBox(width: 3),
                _bar(e.$2 / maxV * h, e.$2 > e.$3 && e.$3 > 0 ? cs.error : e.$4),
              ]),
              const SizedBox(height: 6),
              Text(e.$1, style: tt.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
      ]),
    );
  }

  Widget _bar(double height, Color c) => Container(
        width: 11,
        height: math.max(2, height),
        decoration: BoxDecoration(color: c, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
      );

  static String _short(double v) {
    if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '₹${(v / 1000).toStringAsFixed(v >= 10000 ? 0 : 1)}k';
    return '₹${v.toStringAsFixed(0)}';
  }
}

/// Spending per day of the month, with a dashed line for the daily budget.
class DailyBars extends StatelessWidget {
  const DailyBars({super.key, required this.perDay, required this.dailyBudget, required this.today});
  final List<double> perDay; // index 0 = day 1
  final double dailyBudget;
  final int? today; // 1-based, null if not the current month

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 120,
      child: CustomPaint(
        size: Size.infinite,
        painter: _DailyPainter(perDay, dailyBudget, today, cs.primary, cs.error, cs.outline,
            cs.surfaceContainerHighest, Theme.of(context).textTheme.labelSmall!),
      ),
    );
  }
}

class _DailyPainter extends CustomPainter {
  _DailyPainter(this.v, this.daily, this.today, this.color, this.over, this.line, this.track, this.label);
  final List<double> v;
  final double daily;
  final int? today;
  final Color color, over, line, track;
  final TextStyle label;

  @override
  void paint(Canvas canvas, Size size) {
    const bottom = 16.0;
    final h = size.height - bottom;
    final maxV = math.max(daily * 1.2, v.fold<double>(1, math.max));
    final n = v.length;
    final slot = size.width / n;
    final bw = math.max(2.0, slot * 0.62);
    for (var i = 0; i < n; i++) {
      final x = i * slot + (slot - bw) / 2;
      final future = today != null && i + 1 > today!;
      final bh = v[i] / maxV * h;
      final p = Paint()
        ..color = future ? track : (daily > 0 && v[i] > daily ? over : color.withValues(alpha: i + 1 == today ? 1 : 0.7));
      canvas.drawRRect(
          RRect.fromRectAndCorners(Rect.fromLTWH(x, h - math.max(bh, future ? 2 : 1.5), bw, math.max(bh, future ? 2 : 1.5)),
              topLeft: const Radius.circular(2), topRight: const Radius.circular(2)),
          p);
      if ((i + 1) % 5 == 0 || i == 0) {
        final tp = TextPainter(text: TextSpan(text: '${i + 1}', style: label), textDirection: TextDirection.ltr)..layout();
        tp.paint(canvas, Offset(i * slot + slot / 2 - tp.width / 2, h + 3));
      }
    }
    if (daily > 0) {
      final y = h - daily / maxV * h;
      final dash = Paint()
        ..color = line
        ..strokeWidth = 1;
      for (double x = 0; x < size.width; x += 8) {
        canvas.drawLine(Offset(x, y), Offset(math.min(x + 4, size.width), y), dash);
      }
    }
  }

  @override
  bool shouldRepaint(_DailyPainter old) => true;
}
