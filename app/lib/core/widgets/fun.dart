import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/tokens.dart';
import '../l10n/l10n.dart';

/// Falling confetti, drawn in code (no assets). Plays once.
class Confetti extends StatefulWidget {
  const Confetti({super.key, this.duration = const Duration(milliseconds: 2200)});
  final Duration duration;

  @override
  State<Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<Confetti> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration)..forward();
  final _rng = math.Random();
  late final List<_Piece> _pieces = List.generate(90, (_) => _Piece(_rng));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => CustomPaint(painter: _ConfettiPainter(_pieces, _c.value), size: Size.infinite),
        ),
      );
}

class _Piece {
  _Piece(math.Random r)
      : x = r.nextDouble(),
        delay = r.nextDouble() * 0.3,
        speed = 0.7 + r.nextDouble() * 0.6,
        drift = (r.nextDouble() - 0.5) * 0.25,
        spin = r.nextDouble() * 12,
        size = 6 + r.nextDouble() * 6,
        color = const [HColors.emerald500, HColors.gold500, HColors.emerald100, Color(0xFFE8B4B8), Color(0xFF7FB3D5)][r.nextInt(5)];
  final double x, delay, speed, drift, spin, size;
  final Color color;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.pieces, this.t);
  final List<_Piece> pieces;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in pieces) {
      final local = ((t - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (local <= 0) continue;
      final y = -20 + local * p.speed * (size.height + 40);
      final x = (p.x + p.drift * local) * size.width;
      final paint = Paint()..color = p.color.withValues(alpha: (1 - local * 0.6));
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.spin * local);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.5), const Radius.circular(2)), paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}

/// A celebration card with confetti and a haptic tap: used for mastery, Surah
/// completion and new badges. Celebrates real learning, never just opening the app.
Future<void> showCelebration(BuildContext context, {required String title, String? body, int xp = 0, IconData icon = Icons.verified}) {
  HapticFeedback.mediumImpact();
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: title,
    barrierColor: Colors.black45,
    transitionDuration: HMotion.slow,
    pageBuilder: (ctx, _, __) {
      final t = Theme.of(ctx).textTheme;
      final scheme = Theme.of(ctx).colorScheme;
      return Stack(children: [
        const Positioned.fill(child: Confetti()),
        Center(
          child: Material(
            color: scheme.surfaceContainerLow,
            borderRadius: const BorderRadius.all(HRadius.l),
            child: Padding(
              padding: const EdgeInsets.all(HSpace.l),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    padding: const EdgeInsets.all(HSpace.m),
                    decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
                    child: Icon(icon, size: 44, color: scheme.primary),
                  ),
                  const SizedBox(height: HSpace.m),
                  Text(title, style: t.headlineSmall, textAlign: TextAlign.center),
                  if (body != null) ...[
                    const SizedBox(height: HSpace.s),
                    Text(body, style: t.bodyMedium, textAlign: TextAlign.center),
                  ],
                  if (xp > 0) ...[
                    const SizedBox(height: HSpace.m),
                    XpChip(xp),
                  ],
                  const SizedBox(height: HSpace.l),
                  FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.l10n.continueLabel)),
                ]),
              ),
            ),
          ),
        ),
      ]);
    },
    transitionBuilder: (_, a, __, child) => ScaleTransition(
      scale: CurvedAnimation(parent: a, curve: Curves.easeOutBack),
      child: FadeTransition(opacity: a, child: child),
    ),
  );
}

class XpChip extends StatelessWidget {
  const XpChip(this.xp, {super.key});
  final int xp;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: const BoxDecoration(color: HColors.gold100, borderRadius: BorderRadius.all(HRadius.pill)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.star_rounded, color: HColors.gold500, size: 20),
          const SizedBox(width: 4),
          Text('+$xp XP', style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF6B4E16))),
        ]),
      );
}

/// Circular progress with a label in the middle (the daily goal ring).
class ProgressRing extends StatelessWidget {
  const ProgressRing({super.key, required this.value, required this.child, this.size = 120, this.stroke = 12});
  final double value;
  final Widget child;
  final double size;
  final double stroke;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: value.clamp(0.0, 1.0).toDouble()),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (_, v, __) => CustomPaint(
          painter: _RingPainter(v, scheme.surfaceContainerHigh, v >= 1 ? HColors.gold500 : scheme.primary, stroke),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.v, this.track, this.fill, this.stroke);
  final double v;
  final Color track, fill;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromCircle(center: size.center(Offset.zero), radius: size.width / 2 - stroke / 2);
    final base = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(r, 0, math.pi * 2, false, base);
    canvas.drawArc(r, -math.pi / 2, math.pi * 2 * v, false, base
      ..color = fill
      ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.v != v || old.fill != fill;
}

/// Seven dots for this week: filled where the learner studied.
class WeekDots extends StatelessWidget {
  const WeekDots({super.key, required this.learnedDays, required this.freezeDays});
  final Set<DateTime> learnedDays;
  final Set<DateTime> freezeDays;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final learned = learnedDays.map((d) => DateTime(d.year, d.month, d.day)).toSet();
    final frozen = freezeDays.map((d) => DateTime(d.year, d.month, d.day)).toSet();
    final locale = Localizations.localeOf(context).toLanguageTag();
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      for (var i = 6; i >= 0; i--)
        Builder(builder: (_) {
          final d = DateTime(today.year, today.month, today.day - i);
          final done = learned.contains(d);
          final ice = frozen.contains(d);
          return Column(children: [
            AnimatedContainer(
              duration: HMotion.normal,
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? HColors.gold500 : ice ? const Color(0xFF7FB3D5) : scheme.surfaceContainerHigh,
                border: i == 0 ? Border.all(color: scheme.primary, width: 2) : null,
              ),
              child: Icon(done ? Icons.local_fire_department : ice ? Icons.ac_unit : null, size: 16, color: Colors.white),
            ),
            const SizedBox(height: 4),
            Text(_weekday(d, locale), style: Theme.of(context).textTheme.labelSmall),
          ]);
        }),
    ]);
  }

  static String _weekday(DateTime d, String locale) {
    const en = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return en[d.weekday - 1];
  }
}
