import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../repo.dart';
import 'common.dart';

/// "Card payment ₹456 at SWIGGY FOOD — did it go through?" cards, made from
/// card-purchase OTP SMS (the OTP itself is never stored).
class PendingCards extends StatefulWidget {
  const PendingCards({super.key, required this.repo});
  final Repo repo;
  @override
  State<PendingCards> createState() => _PendingCardsState();
}

class _PendingCardsState extends State<PendingCards> {
  late final Stream<List<PendingCard>> _stream = widget.repo.pendingStream();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return StreamBuilder<List<PendingCard>>(
      stream: _stream,
      builder: (context, snap) {
        final items = snap.data ?? const <PendingCard>[];
        if (items.isEmpty) return const SizedBox.shrink();
        return Column(children: [
          for (final p in items)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Card(
                color: cs.secondaryContainer,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 12, 6),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(Icons.credit_card, color: cs.onSecondaryContainer),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text('Card payment ${money(p.amount)} at ${p.merchant}',
                            style: tt.titleSmall?.copyWith(color: cs.onSecondaryContainer)),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    Text(
                      '${p.member} · ${DateFormat('d MMM, h:mm a').format(p.at)}'
                      '${p.card != null ? ' · card ••${p.card}' : ''}\n'
                      'An OTP was sent for this. Did the payment go through?',
                      style: tt.bodySmall?.copyWith(color: cs.onSecondaryContainer),
                    ),
                    Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      TextButton(
                        onPressed: () => widget.repo.confirmCard(p, false),
                        child: const Text('No'),
                      ),
                      FilledButton.tonal(
                        onPressed: () => widget.repo.confirmCard(p, true),
                        child: const Text('Yes, add it'),
                      ),
                    ]),
                  ]),
                ),
              ),
            ),
        ]);
      },
    );
  }
}
