import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../categories.dart';
import '../config.dart';
import '../repo.dart';
import 'common.dart';

class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key, required this.repo, required this.month});
  final Repo repo;
  final DateTime month;
  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  final _cat = <String, TextEditingController>{};
  final _mem = <String, TextEditingController>{};
  String? _loadedFor;
  bool _saving = false;

  Future<void> _load() async {
    final mk = monthKey(widget.month);
    if (_loadedFor == mk) return;
    _loadedFor = mk;
    final b = await widget.repo.budgetStream(mk).first;
    final fam = await widget.repo.family.get();
    final names = Map<String, dynamic>.from(fam.data()?['members'] as Map? ?? {})
        .values
        .cast<String>()
        .toSet();
    names.addAll(b.members.keys);
    if (!mounted) return;
    setState(() {
      for (final c in kCats) {
        _cat[c.id] = TextEditingController(text: _fmt(b.categories[c.id]));
      }
      _mem.clear();
      for (final n in names) {
        _mem[n] = TextEditingController(text: _fmt(b.members[n]));
      }
    });
  }

  String _fmt(double? v) => v == null || v == 0 ? '' : v.toStringAsFixed(0);
  double _val(TextEditingController? c) => double.tryParse((c?.text ?? '').replaceAll(',', '')) ?? 0;

  Future<void> _save() async {
    setState(() => _saving = true);
    final b = Budget(
      {for (final c in kCats) c.id: _val(_cat[c.id])},
      {for (final e in _mem.entries) if (_val(e.value) > 0) e.key: _val(e.value)},
    );
    await widget.repo.saveBudget(monthKey(widget.month), b);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Budget saved. It carries over to next months automatically.')));
  }

  @override
  Widget build(BuildContext context) {
    _load();
    final tt = Theme.of(context).textTheme;
    if (_cat.isEmpty) return const Center(child: CircularProgressIndicator());
    for (final c in kCats) {
      _cat.putIfAbsent(c.id, () => TextEditingController());
    }
    final total = kCats.fold<double>(0, (s, c) => s + _val(_cat[c.id]));
    return RefreshIndicator(
      onRefresh: () {
        _loadedFor = null;
        return _load();
      },
      child: ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Text('Budget for ${DateFormat('MMMM yyyy').format(widget.month)}', style: tt.titleLarge),
        const SizedBox(height: 4),
        Text('Family pool, shared by everyone. Total ${money(total)}', style: tt.bodySmall),
        const SizedBox(height: 16),
        for (final c in kCats)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              CatAvatar(c, size: 36),
              const SizedBox(width: 12),
              Expanded(child: Text(c.goal ? '${c.label} (monthly target)' : c.label)),
              SizedBox(
                width: 130,
                child: TextField(
                  controller: _cat[c.id],
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.right,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(prefixText: '₹ ', isDense: true, border: OutlineInputBorder()),
                ),
              ),
            ]),
          ),
        const SizedBox(height: 16),
        Text('Personal limits (optional)', style: tt.titleMedium),
        const SizedBox(height: 4),
        Text('How much each person may spend from the pool this month. Shown as their balance.',
            style: tt.bodySmall),
        const SizedBox(height: 12),
        for (final e in _mem.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              CircleAvatar(radius: 18, child: Text(e.key.isEmpty ? '?' : e.key[0].toUpperCase())),
              const SizedBox(width: 12),
              Expanded(child: Text(e.key)),
              SizedBox(
                width: 130,
                child: TextField(
                  controller: e.value,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.right,
                  decoration: const InputDecoration(
                      prefixText: '₹ ', hintText: 'No limit', isDense: true, border: OutlineInputBorder()),
                ),
              ),
            ]),
          ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.check),
          label: const Text('Save budget'),
        ),
      ],
    ),
    );
  }
}
