import 'package:flutter/material.dart';

import '../../features/memorisation/engine/srs.dart';
import '../design/tokens.dart';
import '../l10n/l10n.dart';

/// Card with a title row and free content. The base surface for dashboard and lesson cards.
class LearningCard extends StatelessWidget {
  const LearningCard({super.key, this.title, this.trailing, required this.child, this.onTap});

  final String? title;
  final Widget? trailing;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(HSpace.m),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null) ...[
                Row(children: [
                  Expanded(child: Text(title!, style: t.titleMedium)),
                  if (trailing != null) trailing!,
                ]),
                const SizedBox(height: HSpace.s),
              ],
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// One number with a label. Shows an em dash, never a fake number, when value is null.
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.icon});

  final String label;
  final String? value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(HSpace.m),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: const BorderRadius.all(HRadius.m),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) Icon(icon, size: 20, color: scheme.primary),
          if (icon != null) const SizedBox(height: HSpace.s),
          Text(value ?? '—', style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: HSpace.xs),
          Text(label, style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// Selectable answer row used throughout the assessment.
class OptionTile extends StatelessWidget {
  const OptionTile({super.key, required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: HSpace.s),
      child: Semantics(
        selected: selected,
        button: true,
        child: AnimatedContainer(
          duration: HMotion.fast,
          curve: HMotion.curve,
          decoration: BoxDecoration(
            color: selected ? scheme.primaryContainer : scheme.surfaceContainerLow,
            borderRadius: const BorderRadius.all(HRadius.m),
            border: Border.all(color: selected ? scheme.primary : scheme.outlineVariant, width: selected ? 2 : 1),
          ),
          child: InkWell(
            borderRadius: const BorderRadius.all(HRadius.m),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: HSpace.m, vertical: 14),
              child: Row(children: [
                Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyLarge)),
                AnimatedOpacity(
                  duration: HMotion.fast,
                  opacity: selected ? 1 : 0,
                  child: Icon(Icons.check_circle, color: scheme.primary),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Memorisation status colours, shared by chips, the journey map and charts.
Color memoStatusColor(MemoStatus s) => switch (s) {
      MemoStatus.newAyah => HColors.statusNew,
      MemoStatus.learning => HColors.statusLearning,
      MemoStatus.recentlyMemorised => HColors.statusRecent,
      MemoStatus.stable => HColors.statusStable,
      MemoStatus.strong => HColors.statusStrong,
      MemoStatus.needsRevision => HColors.statusNeedsRevision,
    };

String memoStatusLabel(BuildContext context, MemoStatus s) {
  final l = context.l10n;
  return switch (s) {
    MemoStatus.newAyah => l.statusNew,
    MemoStatus.learning => l.statusLearning,
    MemoStatus.recentlyMemorised => l.statusRecent,
    MemoStatus.stable => l.statusStable,
    MemoStatus.strong => l.statusStrong,
    MemoStatus.needsRevision => l.statusNeedsRevision,
  };
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});
  final MemoStatus status;

  @override
  Widget build(BuildContext context) {
    final c = memoStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: const BorderRadius.all(HRadius.pill),
      ),
      child: Text(memoStatusLabel(context, status),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: c, fontWeight: FontWeight.w600)),
    );
  }
}

/// Brand mark: an eight-point star drawn in code (original artwork, no external asset).
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 72, this.color});
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.square(size),
        painter: _StarPainter(color ?? Theme.of(context).colorScheme.primary),
      );
}

class _StarPainter extends CustomPainter {
  _StarPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final square = Rect.fromCenter(center: c, width: r * 1.42, height: r * 1.42);
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.06
      ..strokeJoin = StrokeJoin.round;
    canvas.drawRect(square, p);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(0.785398); // 45°
    canvas.translate(-c.dx, -c.dy);
    canvas.drawRect(square, p);
    canvas.restore();
    canvas.drawCircle(c, r * 0.22, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_StarPainter old) => old.color != color;
}
