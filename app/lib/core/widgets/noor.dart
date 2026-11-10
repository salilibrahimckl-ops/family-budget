import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Noor, the app's friendly star (original, drawn in code). Appears in kids mode.
class Noor extends StatefulWidget {
  const Noor({super.key, this.size = 72, this.happy = true, this.bob = true});
  final double size;
  final bool happy;
  final bool bob;

  @override
  State<Noor> createState() => _NoorState();
}

class _NoorState extends State<Noor> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void initState() {
    super.initState();
    if (widget.bob) _c.repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) => Transform.translate(
        offset: Offset(0, -4 * Curves.easeInOut.transform(_c.value)),
        child: Transform.rotate(angle: 0.06 * (_c.value - 0.5), child: child),
      ),
      child: SizedBox.square(
        dimension: widget.size,
        child: CustomPaint(painter: _NoorPainter(happy: widget.happy)),
      ),
    );
  }
}

class _NoorPainter extends CustomPainter {
  _NoorPainter({required this.happy});
  final bool happy;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final rad = i.isEven ? r : r * 0.52;
      final a = -math.pi / 2 + i * math.pi / 5;
      final p = c + Offset(math.cos(a), math.sin(a)) * rad;
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    canvas.drawShadow(path, Colors.black26, 3, false);
    canvas.drawPath(
      path,
      Paint()
        ..shader = const RadialGradient(colors: [Color(0xFFFFE680), Color(0xFFFFB627)])
            .createShader(Rect.fromCircle(center: c, radius: r)),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = r * 0.06
        ..color = const Color(0xFFE08E0B),
    );

    final ink = Paint()..color = const Color(0xFF3B2A12);
    final eyeY = c.dy + r * 0.02;
    final eyeDx = r * 0.18;
    canvas.drawOval(Rect.fromCenter(center: Offset(c.dx - eyeDx, eyeY), width: r * 0.11, height: r * 0.16), ink);
    canvas.drawOval(Rect.fromCenter(center: Offset(c.dx + eyeDx, eyeY), width: r * 0.11, height: r * 0.16), ink);
    final white = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(c.dx - eyeDx + r * 0.02, eyeY - r * 0.04), r * 0.025, white);
    canvas.drawCircle(Offset(c.dx + eyeDx + r * 0.02, eyeY - r * 0.04), r * 0.025, white);

    final cheek = Paint()..color = const Color(0x66FF6B6B);
    canvas.drawCircle(Offset(c.dx - r * 0.32, eyeY + r * 0.13), r * 0.07, cheek);
    canvas.drawCircle(Offset(c.dx + r * 0.32, eyeY + r * 0.13), r * 0.07, cheek);

    final mouth = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = r * 0.05
      ..color = const Color(0xFF3B2A12);
    final mr = Rect.fromCenter(center: Offset(c.dx, eyeY + r * 0.14), width: r * 0.26, height: r * 0.18);
    if (happy) {
      canvas.drawArc(mr, 0.2, math.pi - 0.4, false, mouth);
    } else {
      canvas.drawArc(mr.shift(Offset(0, r * 0.1)), math.pi + 0.5, math.pi - 1.0, false, mouth);
    }
  }

  @override
  bool shouldRepaint(_NoorPainter old) => old.happy != happy;
}

/// Noor with a speech bubble.
class NoorSays extends StatelessWidget {
  const NoorSays(this.message, {super.key, this.size = 64});
  final String message;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Noor(size: size),
      const SizedBox(width: 10),
      Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: scheme.secondaryContainer,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(18),
            ),
          ),
          child: Text(message, style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
        ),
      ),
    ]);
  }
}

/// Stickers earned for each memorised Ayah. Chosen by Ayah number, so the same Ayah
/// always gives the same sticker.
const stickerIcons = <(IconData, Color)>[
  (Icons.star_rounded, Color(0xFFFFB627)),
  (Icons.nightlight_round, Color(0xFF6A4CE0)),
  (Icons.local_florist, Color(0xFFFF6B9A)),
  (Icons.wb_sunny_rounded, Color(0xFFFF9F1C)),
  (Icons.park_rounded, Color(0xFF2E9E5B)),
  (Icons.water_drop_rounded, Color(0xFF2EC4F1)),
  (Icons.cloud_rounded, Color(0xFF7FA7E8)),
  (Icons.favorite_rounded, Color(0xFFE5484D)),
  (Icons.emoji_nature, Color(0xFF8BC34A)),
  (Icons.diamond_rounded, Color(0xFF00B3A4)),
  (Icons.auto_awesome, Color(0xFFFFC93C)),
  (Icons.mosque, Color(0xFF14866D)),
  (Icons.pets, Color(0xFFB07A4A)),
  (Icons.rocket_launch_rounded, Color(0xFFEF6C00)),
  (Icons.cruelty_free, Color(0xFFA77BFF)),
  (Icons.icecream_rounded, Color(0xFFFF8FB1)),
];

(IconData, Color) stickerFor(int ayahId) => stickerIcons[(ayahId * 7 + 3) % stickerIcons.length];
