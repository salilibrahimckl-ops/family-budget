import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../categories.dart';
import '../config.dart';
import '../repo.dart';
import 'common.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({
    super.key,
    required this.repo,
    required this.month,
    required this.onMonth,
    this.initialMember,
  });
  final Repo repo;
  final DateTime month;
  final ValueChanged<DateTime> onMonth;
  final String? initialMember;

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  late String? _member = widget.initialMember;
  String? _cat;
  bool _showIgnored = false;
  String? _mk;
  late Stream<List<Txn>> _stream;

  @override
  Widget build(BuildContext context) {
    final mk = monthKey(widget.month);
    if (mk != _mk) {
      _mk = mk;
      _stream = widget.repo.monthTxns(mk);
    }
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showAddSheet(context, widget.repo),
        icon: const Icon(Icons.add),
        label: const Text('Cash / other'),
      ),
      body: StreamBuilder<List<Txn>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final all = snap.data!;
          final members = all.map((t) => t.member).toSet().toList()..sort();
          final list = all.where((t) {
            if (!_showIgnored && t.category == kIgnored) return false;
            if (_member != null && t.member != _member) return false;
            if (_cat != null && t.category != _cat) return false;
            return true;
          }).toList();
          final total = list.where((t) => t.category != kIgnored).fold<double>(0, (s, t) => s + t.amount);

          return CustomScrollView(slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Column(children: [
                  MonthSwitcher(month: widget.month, onChanged: widget.onMonth),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      _chip('Everyone', _member == null, () => setState(() => _member = null)),
                      for (final m in members) _chip(m, _member == m, () => setState(() => _member = m)),
                      const SizedBox(width: 12),
                      DropdownButton<String?>(
                        value: _cat,
                        hint: const Text('All categories'),
                        underline: const SizedBox(),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('All categories')),
                          for (final c in kCats) DropdownMenuItem(value: c.id, child: Text(c.label)),
                          const DropdownMenuItem(value: kUncategorised, child: Text('To tag')),
                        ],
                        onChanged: (v) => setState(() => _cat = v),
                      ),
                    ]),
                  ),
                  Row(children: [
                    Text('${list.length} payments · ${money(total)}',
                        style: Theme.of(context).textTheme.bodySmall),
                    const Spacer(),
                    TextButton(
                      onPressed: () => setState(() => _showIgnored = !_showIgnored),
                      child: Text(_showIgnored ? 'Hide not-spends' : 'Show not-spends'),
                    ),
                  ]),
                ]),
              ),
            ),
            if (list.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('No payments')),
              )
            else
              SliverList.builder(
                itemCount: list.length,
                itemBuilder: (context, i) => _TxnTile(repo: widget.repo, t: list[i]),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 88)),
          ]);
        },
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: FilterChip(label: Text(label), selected: selected, onSelected: (_) => onTap()),
      );
}

class _TxnTile extends StatelessWidget {
  const _TxnTile({required this.repo, required this.t});
  final Repo repo;
  final Txn t;

  @override
  Widget build(BuildContext context) {
    final cat = catById(t.category);
    final ignored = t.category == kIgnored;
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      onTap: () => showTxnSheet(context, repo, t),
      leading: ignored ? const CircleAvatar(child: Icon(Icons.visibility_off_outlined)) : CatAvatar(cat),
      title: Text(t.payee, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${DateFormat('d MMM').format(t.date)} · ${t.member}'
        '${t.category == kUncategorised ? ' · tap to tag' : ignored ? ' · not a spend' : ' · ${cat.label}'}'
        '${t.note != null && t.note!.isNotEmpty ? '\n${t.note}' : ''}',
      ),
      isThreeLine: t.note != null && t.note!.isNotEmpty,
      trailing: Text(
        money(t.amount),
        style: TextStyle(
          fontWeight: FontWeight.w600,
          decoration: ignored ? TextDecoration.lineThrough : null,
          color: t.category == kUncategorised ? cs.error : null,
        ),
      ),
    );
  }
}
