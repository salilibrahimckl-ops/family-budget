import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../repo.dart';
import 'common.dart';

/// "Bank balances" card on the Overview: each person's accounts, kept in step
/// with the balance printed in bank SMS.
class BalancesCard extends StatefulWidget {
  const BalancesCard({super.key, required this.repo});
  final Repo repo;
  @override
  State<BalancesCard> createState() => _BalancesCardState();
}

class _BalancesCardState extends State<BalancesCard> {
  late final Stream<List<BankAccount>> _stream = widget.repo.accountsStream();

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return StreamBuilder<List<BankAccount>>(
      stream: _stream,
      builder: (context, snap) {
        final accts = snap.data ?? const <BankAccount>[];
        final byMember = <String, List<BankAccount>>{};
        for (final a in accts) {
          byMember.putIfAbsent(a.member, () => []).add(a);
        }
        final known = accts.where((a) => a.balance != null);
        final total = known.fold<double>(0, (s, a) => s + a.balance!);
        return Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.account_balance, color: cs.primary),
                const SizedBox(width: 8),
                Text('Bank balances', style: tt.titleMedium),
                const Spacer(),
                if (known.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(money(total), style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                IconButton(
                  tooltip: 'Add an account by hand',
                  icon: const Icon(Icons.add),
                  onPressed: () => _addAccount(context),
                ),
              ]),
              if (accts.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 4, 8, 8),
                  child: Text(
                    'Balances appear here from your next bank SMS that shows "Avl Bal". '
                    'You can also tap + to enter one from your bank app.',
                    style: tt.bodySmall,
                  ),
                ),
              for (final e in byMember.entries) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 2),
                  child: Text(e.key, style: tt.labelLarge?.copyWith(color: cs.primary)),
                ),
                for (final a in e.value)
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _edit(context, a, e.value),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(a.title, style: tt.bodyLarge),
                            Text(_status(a), style: tt.bodySmall?.copyWith(
                                color: a.exact ? null : cs.tertiary)),
                          ]),
                        ),
                        Text(a.balance == null ? 'Set balance' : money(a.balance!),
                            style: tt.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: a.balance == null ? cs.primary : (a.balance! < 0 ? cs.error : null))),
                        const SizedBox(width: 4),
                        const Icon(Icons.chevron_right, size: 18),
                      ]),
                    ),
                  ),
              ],
            ]),
          ),
        );
      },
    );
  }

  String _status(BankAccount a) {
    if (a.balance == null) return 'Tap to enter the balance from your bank app';
    final when = a.balanceAt == null ? '' : DateFormat('d MMM, h:mm a').format(a.balanceAt!);
    return a.exact ? 'As per bank · $when' : 'Estimated · last SMS had no balance · $when';
  }

  Future<void> _edit(BuildContext context, BankAccount a, [List<BankAccount> same = const []]) async {
    final others = same.where((o) => o.id != a.id).toList();
    final bal = TextEditingController(text: a.balance?.toStringAsFixed(2) ?? '');
    final name = TextEditingController(text: a.label ?? '');
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SingleChildScrollView(child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${a.member} · ${a.title}', style: Theme.of(ctx).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('Correct the balance from your bank app if it ever drifts. '
              'The next bank SMS with a balance updates it automatically.',
              style: Theme.of(ctx).textTheme.bodySmall),
          const SizedBox(height: 16),
          TextField(
            controller: bal,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: const InputDecoration(labelText: 'Current balance', prefixText: '₹ ', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: name,
            decoration: const InputDecoration(
                labelText: 'Name (optional)', hintText: 'e.g. SBI salary', border: OutlineInputBorder()),
          ),
          if (others.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Is this the same bank account as another one below? Merge it so it is counted only once.',
                style: Theme.of(ctx).textTheme.bodySmall),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final o in others)
                ActionChip(
                  avatar: const Icon(Icons.merge_type, size: 18),
                  label: Text('Same as ${o.title}'),
                  onPressed: () async {
                    await widget.repo.mergeAccounts(a, o);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                ),
            ]),
          ],
          const SizedBox(height: 8),
          TextButton.icon(
            icon: const Icon(Icons.visibility_off_outlined, size: 18),
            label: const Text('Not a real account — stop tracking it'),
            onPressed: () async {
              await widget.repo.ignoreAccount(a);
              if (ctx.mounted) Navigator.pop(ctx);
            },
          ),
          const SizedBox(height: 4),
          Row(children: [
            TextButton(
              onPressed: () async {
                await widget.repo.deleteAccount(a);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Remove'),
            ),
            const Spacer(),
            FilledButton(
              onPressed: () async {
                final v = double.tryParse(bal.text.replaceAll(',', '').trim());
                await widget.repo.setAccount(a,
                    balance: v != null && v != a.balance ? v : null, label: name.text.trim());
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ]),
        ]),
      )),
    );
  }

  Future<void> _addAccount(BuildContext context) async {
    final bal = TextEditingController();
    final name = TextEditingController();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Add an account', style: Theme.of(ctx).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('Usually not needed: accounts appear by themselves from bank SMS.',
              style: Theme.of(ctx).textTheme.bodySmall),
          const SizedBox(height: 16),
          TextField(
            controller: name,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Federal Bank', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: bal,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: const InputDecoration(labelText: 'Current balance', prefixText: '₹ ', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () async {
                final v = double.tryParse(bal.text.replaceAll(',', '').trim());
                if (v == null || name.text.trim().isEmpty) return;
                await widget.repo.addAccount(name.text.trim(), v);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Add'),
            ),
          ),
        ]),
      ),
    );
  }
}
