import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../repo.dart';
import '../sms_parser.dart';

/// iPhone: add bank SMS that the Shortcut missed (or older ones) by pasting.
class PasteSmsScreen extends StatefulWidget {
  const PasteSmsScreen({super.key, required this.repo});
  final Repo repo;
  @override
  State<PasteSmsScreen> createState() => _PasteSmsScreenState();
}

class _PasteSmsScreenState extends State<PasteSmsScreen> {
  final _c = TextEditingController();
  bool _busy = false;
  String? _result;

  List<String> get _parts => _c.text
      .split(RegExp(r'\n\s*\n'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  Future<void> _add() async {
    setState(() => _busy = true);
    var pay = 0, other = 0, skipped = 0;
    for (final t in _parts) {
      final r = await widget.repo.ingestPasted(t);
      if (r == 1) {
        pay++;
      } else if (r == 0) {
        other++;
      } else {
        skipped++;
      }
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = '$pay payment(s) added'
          '${other > 0 ? ' · $other balance/income update(s)' : ''}'
          '${skipped > 0 ? ' · $skipped already added or not a bank SMS' : ''}';
      if (pay + other > 0) _c.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final parts = _parts;
    return Scaffold(
      appBar: AppBar(title: const Text('Paste bank SMS')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('In Messages, press and hold a bank SMS → Copy, then paste it here. '
            'To add several, leave an empty line between them. '
            'Payments already in the app are skipped, so pasting twice is safe.',
            style: tt.bodySmall),
        const SizedBox(height: 12),
        Row(children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.content_paste),
            label: const Text('Paste'),
            onPressed: () async {
              final d = await Clipboard.getData(Clipboard.kTextPlain);
              final t = d?.text?.trim();
              if (t == null || t.isEmpty) return;
              setState(() => _c.text = _c.text.trim().isEmpty ? t : '${_c.text.trim()}\n\n$t');
            },
          ),
          const Spacer(),
          FilledButton(
            onPressed: _busy || parts.isEmpty ? null : _add,
            child: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(parts.length > 1 ? 'Add ${parts.length} SMS' : 'Add'),
          ),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _c,
          minLines: 6,
          maxLines: 14,
          onChanged: (_) => setState(() => _result = null),
          decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Dear UPI user A/C X1234 debited by …'),
        ),
        if (_result != null) ...[
          const SizedBox(height: 12),
          Text(_result!, style: tt.titleSmall),
        ],
        for (final t in parts) ...[
          const SizedBox(height: 8),
          _Preview(t),
        ],
      ]),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    final p = SmsParser.parse(text);
    final b = SmsParser.parseBalance(text);
    final cs = Theme.of(context).colorScheme;
    String msg;
    Color c;
    if (p != null) {
      msg = 'Payment ₹${p.amount.toStringAsFixed(p.amount % 1 == 0 ? 0 : 2)}${p.payee != null ? ' → ${p.payee}' : ''}';
      c = Colors.green;
    } else if (b != null && b.delta > 0) {
      msg = 'Money in ₹${b.delta.toStringAsFixed(b.delta % 1 == 0 ? 0 : 2)}${b.payer != null ? ' from ${b.payer}' : ''}';
      c = Colors.blue;
    } else if (b != null) {
      msg = 'Balance update';
      c = Colors.blue;
    } else {
      msg = 'Not read as a bank payment';
      c = cs.error;
    }
    return Row(children: [
      Icon(Icons.circle, size: 10, color: c),
      const SizedBox(width: 8),
      Expanded(child: Text(msg, style: Theme.of(context).textTheme.bodyMedium)),
    ]);
  }
}
