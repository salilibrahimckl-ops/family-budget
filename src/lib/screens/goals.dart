import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../insights.dart';
import '../repo.dart';
import 'common.dart';

const kGoalIcons = <String, (IconData, String)>{
  'hajj': (Icons.mosque, 'Hajj / Umrah'),
  'home': (Icons.home_outlined, 'House'),
  'car': (Icons.directions_car_outlined, 'Car'),
  'edu': (Icons.school_outlined, 'Education'),
  'gold': (Icons.workspace_premium_outlined, 'Gold'),
  'travel': (Icons.flight_takeoff, 'Travel'),
  'emergency': (Icons.health_and_safety_outlined, 'Emergency fund'),
  'flag': (Icons.flag_outlined, 'Other'),
};

const _goalColors = [
  Color(0xFF2E7D6B),
  Color(0xFF5B5BD6),
  Color(0xFFB7791F),
  Color(0xFFC2185B),
  Color(0xFF0277BD),
  Color(0xFF6D4C41),
];

/// Money tab: savings goals with progress rings.
class GoalsSection extends StatefulWidget {
  const GoalsSection({super.key, required this.repo, required this.members});
  final Repo repo;
  final List<String> members;
  @override
  State<GoalsSection> createState() => _GoalsSectionState();
}

class _GoalsSectionState extends State<GoalsSection> {
  late final Stream<List<Goal>> _goals = widget.repo.goalsStream();

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return StreamBuilder<List<Goal>>(
      stream: _goals,
      builder: (context, snap) {
        final goals = snap.data ?? const <Goal>[];
        final saved = goals.fold<double>(0, (s, g) => s + g.saved);
        final target = goals.fold<double>(0, (s, g) => s + g.target);
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.flag_circle_outlined, size: 22),
            const SizedBox(width: 8),
            Expanded(child: Text('Goals', style: tt.titleMedium)),
            if (goals.isNotEmpty)
              Text('${money(saved)} of ${money(target)}', style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            IconButton(
              tooltip: 'New goal',
              icon: const Icon(Icons.add),
              onPressed: () => showGoalSheet(context, widget.repo, widget.members),
            ),
          ]),
          if (goals.isEmpty)
            Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.mosque)),
                title: const Text('Set your first goal'),
                subtitle: const Text('Hajj or Umrah, a house, a car, education… '
                    'See how much to put aside each month to get there on time.'),
                onTap: () => showGoalSheet(context, widget.repo, widget.members),
              ),
            )
          else
            LayoutBuilder(builder: (context, box) {
              final w = (box.maxWidth - 12) / 2;
              return Wrap(spacing: 12, runSpacing: 12, children: [
                for (var i = 0; i < goals.length; i++)
                  SizedBox(
                    width: w,
                    child: _GoalTile(
                      goal: goals[i],
                      color: _goalColors[i % _goalColors.length],
                      onTap: () => _open(context, goals[i], _goalColors[i % _goalColors.length]),
                    ),
                  ),
              ]);
            }),
          if (goals.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Goal money is part of your savings above; goals just mark what it is for.',
                  style: tt.bodySmall),
            ),
        ]);
      },
    );
  }

  Future<void> _open(BuildContext context, Goal g, Color color) async {
    final amount = TextEditingController();
    final tt = Theme.of(context).textTheme;
    final need = monthlyNeeded(g.target, g.saved, g.due);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(kGoalIcons[g.iconKey]?.$1 ?? Icons.flag_outlined, color: color),
              const SizedBox(width: 8),
              Expanded(child: Text(g.title, style: tt.titleLarge)),
              IconButton(
                tooltip: 'Edit goal',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () {
                  Navigator.pop(ctx);
                  showGoalSheet(context, widget.repo, widget.members, goal: g);
                },
              ),
            ]),
            const SizedBox(height: 4),
            Text('${money(g.saved)} of ${money(g.target)} · ${(g.progress * 100).floor()}%', style: tt.bodyLarge),
            if (need != null && !g.done)
              Text('Put aside ${money(need)} a month to reach it by ${DateFormat('MMM yyyy').format(g.due!)}.',
                  style: tt.bodyMedium),
            const SizedBox(height: 16),
            TextField(
              controller: amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹ ', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            Row(children: [
              OutlinedButton(
                onPressed: () async {
                  final v = double.tryParse(amount.text.replaceAll(',', '').trim());
                  if (v == null || v <= 0) return;
                  await widget.repo.addToGoal(g, -v);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('Take out'),
              ),
              const Spacer(),
              FilledButton.icon(
                icon: const Icon(Icons.add),
                onPressed: () async {
                  final v = double.tryParse(amount.text.replaceAll(',', '').trim());
                  if (v == null || v <= 0) return;
                  final wasDone = g.done;
                  await widget.repo.addToGoal(g, v);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (!wasDone && g.saved + v >= g.target && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('🎉 Masha Allah! "${g.title}" goal reached.')));
                  }
                },
                label: const Text('Add money'),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _GoalTile extends StatelessWidget {
  const _GoalTile({required this.goal, required this.color, required this.onTap});
  final Goal goal;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final need = monthlyNeeded(goal.target, goal.saved, goal.due);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            SizedBox(
              width: 96,
              height: 96,
              child: CustomPaint(
                painter: _Ring(goal.progress, color, cs.surfaceContainerHighest),
                child: Center(
                  child: goal.done
                      ? Icon(Icons.check_circle, color: color, size: 36)
                      : Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(kGoalIcons[goal.iconKey]?.$1 ?? Icons.flag_outlined, color: color, size: 22),
                          Text('${(goal.progress * 100).floor()}%',
                              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        ]),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(goal.title,
                style: tt.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
            Text('${money(goal.saved)} / ${money(goal.target)}', style: tt.bodySmall, textAlign: TextAlign.center),
            Text(
              goal.done
                  ? 'Reached'
                  : need != null
                      ? '${money(need)}/month · ${DateFormat('MMM yy').format(goal.due!)}'
                      : goal.member,
              style: tt.bodySmall?.copyWith(color: color, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ]),
        ),
      ),
    );
  }
}

class _Ring extends CustomPainter {
  _Ring(this.value, this.color, this.track);
  final double value;
  final Color color, track;
  @override
  void paint(Canvas canvas, Size size) {
    final r = math.min(size.width, size.height) / 2 - 6;
    final c = size.center(Offset.zero);
    final base = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10;
    canvas.drawCircle(c, r, base);
    if (value <= 0) return;
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 10;
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2, 2 * math.pi * value, false, p);
  }

  @override
  bool shouldRepaint(_Ring old) => old.value != value || old.color != color;
}

Future<void> showGoalSheet(BuildContext context, Repo repo, List<String> members, {Goal? goal}) async {
  final title = TextEditingController(text: goal?.title ?? '');
  final target = TextEditingController(text: goal == null ? '' : goal.target.toStringAsFixed(0));
  final saved = TextEditingController(text: goal == null ? '' : goal.saved.toStringAsFixed(0));
  var icon = goal?.iconKey ?? 'hajj';
  var who = goal?.member ?? 'Family';
  DateTime? due = goal?.due;
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        final tt = Theme.of(ctx).textTheme;
        final t = double.tryParse(target.text.replaceAll(',', '').trim()) ?? 0;
        final s = double.tryParse(saved.text.replaceAll(',', '').trim()) ?? 0;
        final need = monthlyNeeded(t, s, due);
        return SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(goal == null ? 'New goal' : 'Edit goal', style: tt.titleLarge)),
                FilledButton(
                  onPressed: t <= 0
                      ? null
                      : () async {
                          final name = title.text.trim().isEmpty ? kGoalIcons[icon]!.$2 : title.text.trim();
                          await repo.saveGoal(
                              id: goal?.id, title: name, target: t, saved: s, due: due, member: who, iconKey: icon);
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                  child: const Text('Save'),
                ),
              ]),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 6, children: [
                for (final e in kGoalIcons.entries)
                  ChoiceChip(
                    avatar: Icon(e.value.$1, size: 18),
                    label: Text(e.value.$2),
                    selected: icon == e.key,
                    onSelected: (_) => set(() {
                      if (title.text.trim().isEmpty || kGoalIcons.values.any((v) => v.$2 == title.text.trim())) {
                        title.text = e.value.$2;
                      }
                      icon = e.key;
                    }),
                  ),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: title,
                decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Umrah 2027', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: target,
                    onChanged: (_) => set(() {}),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Target', prefixText: '₹ ', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: saved,
                    onChanged: (_) => set(() {}),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration:
                        const InputDecoration(labelText: 'Saved so far', prefixText: '₹ ', border: OutlineInputBorder()),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              Wrap(spacing: 8, children: [
                for (final m in ['Family', ...members])
                  ChoiceChip(label: Text(m), selected: who == m, onSelected: (_) => set(() => who = m)),
              ]),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: Text(due == null ? 'Target date (optional)' : 'By ${DateFormat('MMMM yyyy').format(due!)}'),
                subtitle: need != null && t > 0 ? Text('${money(need)} a month needed') : null,
                trailing: due == null
                    ? null
                    : IconButton(icon: const Icon(Icons.close), onPressed: () => set(() => due = null)),
                onTap: () async {
                  final now = DateTime.now();
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: due ?? DateTime(now.year + 1, now.month, 1),
                    firstDate: now,
                    lastDate: DateTime(now.year + 30),
                    initialDatePickerMode: DatePickerMode.year,
                  );
                  if (d != null) set(() => due = d);
                },
              ),
              if (goal != null)
                TextButton.icon(
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete goal'),
                  onPressed: () async {
                    await repo.deleteGoal(goal);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                ),
            ]),
          ),
        );
      },
    ),
  );
}
