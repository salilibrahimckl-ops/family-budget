import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../config.dart';
import '../repo.dart';

/// Settings: is each iPhone actually forwarding bank SMS?
class ForwardingStatus extends StatelessWidget {
  const ForwardingStatus({super.key, required this.repo});
  final Repo repo;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final mk = 'm_${monthKey(DateTime.now())}';
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: repo.familyStream(),
      builder: (context, snap) {
        final stats = Map<String, dynamic>.from(snap.data?.data()?['inboxStats'] as Map? ?? {});
        final tokens = Map<String, dynamic>.from(snap.data?.data()?['inboxTokens'] as Map? ?? {});
        if (tokens.isEmpty) return const SizedBox.shrink();
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.sms_outlined),
                const SizedBox(width: 10),
                Expanded(child: Text('iPhone SMS forwarding', style: tt.titleMedium)),
              ]),
              const SizedBox(height: 4),
              Text('Bank SMS that reached the app from each iPhone automation.', style: tt.bodySmall),
              for (final t in tokens.entries) ...[
                const SizedBox(height: 10),
                Builder(builder: (context) {
                  final st = Map<String, dynamic>.from(stats[t.key] as Map? ?? {});
                  final last = (st['lastAt'] as Timestamp?)?.toDate();
                  final n = (st[mk] as num?)?.toInt() ?? 0;
                  final stale = last == null || DateTime.now().difference(last).inHours > 36;
                  return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(stale ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                        size: 20, color: stale ? cs.error : Colors.green.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${t.value}: ${last == null ? 'nothing received yet (counting started with this update)' : 'last SMS ${DateFormat('d MMM, h:mm a').format(last)}'}'
                        ' · $n this month',
                        style: tt.bodyMedium,
                      ),
                    ),
                  ]);
                }),
              ],
              StreamBuilder<List<({String text, String member, DateTime at, String id})>>(
                stream: repo.unreadStream(),
                builder: (context, u) {
                  final list = u.data ?? const [];
                  if (list.isEmpty) return const SizedBox.shrink();
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const SizedBox(height: 14),
                    Text('Forwarded but not understood (${list.length})', style: tt.titleSmall),
                    Text('Copy these to Claude so the app learns the format.', style: tt.bodySmall),
                    for (final x in list.take(10))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(x.text, maxLines: 3, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${x.member} · ${DateFormat('d MMM, h:mm a').format(x.at)}'),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                            icon: const Icon(Icons.copy, size: 20),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: x.text));
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(const SnackBar(content: Text('Copied')));
                            },
                          ),
                          IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => repo.clearUnread(x.id)),
                        ]),
                      ),
                  ]);
                },
              ),
            ]),
          ),
        );
      },
    );
  }
}
