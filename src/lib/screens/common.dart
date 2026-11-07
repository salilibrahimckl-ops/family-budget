import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../categories.dart';
import '../repo.dart';

final _inr = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
String money(num v) => _inr.format(v);

class MonthSwitcher extends StatelessWidget {
  const MonthSwitcher({super.key, required this.month, required this.onChanged});
  final DateTime month;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isCurrent = month.year == now.year && month.month == now.month;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(
        icon: const Icon(Icons.chevron_left),
        onPressed: () => onChanged(DateTime(month.year, month.month - 1)),
      ),
      Text(DateFormat('MMMM yyyy').format(month), style: Theme.of(context).textTheme.titleMedium),
      IconButton(
        icon: const Icon(Icons.chevron_right),
        onPressed: isCurrent ? null : () => onChanged(DateTime(month.year, month.month + 1)),
      ),
    ]);
  }
}

class CatAvatar extends StatelessWidget {
  const CatAvatar(this.cat, {super.key, this.size = 40});
  final Cat cat;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: cat.color.withValues(alpha: 0.15), shape: BoxShape.circle),
        child: Icon(cat.icon, color: cat.color, size: size * 0.5),
      );
}

/// Bottom sheet to tag / edit one payment.
Future<void> showTxnSheet(BuildContext context, Repo repo, Txn t) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _TxnSheet(repo: repo, t: t),
  );
}

class _TxnSheet extends StatefulWidget {
  const _TxnSheet({required this.repo, required this.t});
  final Repo repo;
  final Txn t;
  @override
  State<_TxnSheet> createState() => _TxnSheetState();
}

class _TxnSheetState extends State<_TxnSheet> {
  bool _remember = true;
  late final _amount = TextEditingController(text: widget.t.amount.toStringAsFixed(0));
  late final _note = TextEditingController(text: widget.t.note ?? '');

  Future<void> _pick(String cat) async {
    await widget.repo.setCategory(widget.t, cat, remember: _remember);
    await _saveEdits();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _saveEdits() async {
    final a = double.tryParse(_amount.text.replaceAll(',', ''));
    await widget.repo.updateTxn(widget.t,
        amount: a != null && a != widget.t.amount ? a : null,
        note: _note.text != (widget.t.note ?? '') ? _note.text : null);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(t.payee, style: tt.titleLarge),
          Text('${DateFormat('d MMM, h:mm a').format(t.date)} · ${t.member} · ${t.source}',
              style: tt.bodySmall),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹ ', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: TextField(
                controller: _note,
                decoration: const InputDecoration(labelText: 'Note', border: OutlineInputBorder()),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          Text('Category', style: tt.titleSmall),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in kCats)
              ChoiceChip(
                avatar: Icon(c.icon, size: 18, color: c.color),
                label: Text(c.label),
                selected: t.category == c.id,
                onSelected: (_) => _pick(c.id),
              ),
          ]),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _remember,
            onChanged: (v) => setState(() => _remember = v ?? true),
            title: const Text('Always use this category for this payee'),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          const SizedBox(height: 8),
          Row(children: [
            TextButton.icon(
              icon: const Icon(Icons.visibility_off_outlined),
              label: const Text('Not a spend'),
              onPressed: () async {
                await widget.repo.ignore(t);
                if (context.mounted) Navigator.pop(context);
              },
            ),
            const Spacer(),
            FilledButton(
              onPressed: () async {
                await _saveEdits();
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ]),
          if (t.source == 'manual')
            TextButton.icon(
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete'),
              onPressed: () async {
                await widget.repo.delete(t);
                if (context.mounted) Navigator.pop(context);
              },
            ),
        ]),
      ),
    );
  }
}

/// Add a cash / missed payment by hand.
Future<void> showAddSheet(BuildContext context, Repo repo) async {
  final amount = TextEditingController();
  final payee = TextEditingController();
  final note = TextEditingController();
  var cat = 'food';
  var date = DateTime.now();
  // Where the money came from: one of my bank accounts, cash, or nothing.
  final myAccounts = (await repo.accountsStream().first).where((a) => a.member == repo.myName).toList();
  String? paidFrom = myAccounts.isNotEmpty ? myAccounts.first.id : 'cash';
  if (!context.mounted) return;
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
      Future<void> save() async {
        final a = double.tryParse(amount.text.replaceAll(',', ''));
        if (a == null || a <= 0) return;
        await repo.addManual(
          amount: a,
          payee: payee.text.trim().isEmpty ? 'Cash' : payee.text.trim(),
          category: cat,
          date: date,
          note: note.text.trim().isEmpty ? null : note.text.trim(),
          paidFrom: paidFrom,
        );
        if (ctx.mounted) Navigator.pop(ctx);
      }

      return Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('Add payment', style: Theme.of(ctx).textTheme.titleLarge)),
            // Save at the top too, so it is reachable even with many categories.
            FilledButton(onPressed: save, child: const Text('Save')),
          ]),
          const SizedBox(height: 16),
          TextField(
            controller: amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹ ', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: payee,
            decoration: const InputDecoration(labelText: 'Paid to', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: note,
            decoration: const InputDecoration(labelText: 'Note (optional)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in kCats)
              ChoiceChip(
                avatar: Icon(c.icon, size: 18, color: c.color),
                label: Text(c.label),
                selected: cat == c.id,
                onSelected: (_) => setS(() => cat = c.id),
              ),
          ]),
          const SizedBox(height: 12),
          Text('Paid from', style: Theme.of(ctx).textTheme.labelLarge),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 6, children: [
            for (final a in myAccounts)
              ChoiceChip(
                avatar: const Icon(Icons.account_balance, size: 16),
                label: Text(a.title),
                selected: paidFrom == a.id,
                onSelected: (_) => setS(() => paidFrom = a.id),
              ),
            ChoiceChip(
              avatar: const Icon(Icons.payments, size: 16),
              label: const Text('Cash in hand'),
              selected: paidFrom == 'cash',
              onSelected: (_) => setS(() => paidFrom = 'cash'),
            ),
            ChoiceChip(
              label: const Text("Don't change balances"),
              selected: paidFrom == null,
              onSelected: (_) => setS(() => paidFrom = null),
            ),
          ]),
          const SizedBox(height: 8),
          TextButton.icon(
            icon: const Icon(Icons.event),
            label: Text(DateFormat('d MMM yyyy').format(date)),
            onPressed: () async {
              final d = await showDatePicker(
                  context: ctx, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime.now());
              if (d != null) setS(() => date = DateTime(d.year, d.month, d.day, 12));
            },
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: save,
              child: const Text('Save'),
            ),
          ),
        ]),
        ),
      );
    }),
  );
}
