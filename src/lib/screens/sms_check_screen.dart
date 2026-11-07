import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../sms_parser.dart';
import '../sms_sync.dart';
import 'common.dart';

/// Shows recent bank SMS and what the app understood from each one, so a
/// missed payment can be spotted (and the SMS copied to report a new format).
class SmsCheckScreen extends StatefulWidget {
  const SmsCheckScreen({super.key, required this.sms});
  final SmsSync sms;
  @override
  State<SmsCheckScreen> createState() => _SmsCheckScreenState();
}

class _SmsCheckScreenState extends State<SmsCheckScreen> {
  List<(String, String, DateTime)>? _msgs;

  @override
  void initState() {
    super.initState();
    widget.sms.recentBankSms().then((m) => mounted ? setState(() => _msgs = m) : null);
  }

  /// Hide OTP codes and long account numbers before showing/copying.
  String _mask(String s) => s
      .replaceAll(RegExp(r'\b\d{6}\b(?=\s*(?:is|as)\b[^.]{0,30}otp)', caseSensitive: false), '******')
      .replaceAll(RegExp(r'(?<=otp[^\d]{0,20})\d{4,8}', caseSensitive: false), '******')
      .replaceAllMapped(RegExp(r'\b(\d{4,})(\d{4})\b'), (m) => 'XXXX${m.group(2)}');

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Check bank SMS')),
      body: _msgs == null
          ? const Center(child: CircularProgressIndicator())
          : _msgs!.isEmpty
              ? const Center(child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No bank SMS in the last 7 days. If you paid, your bank may not have sent an SMS '
                      '(e.g. UPI Lite, wallet) — add it with + Add spending.', textAlign: TextAlign.center)))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _msgs!.length + 1,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    if (i == 0) {
                      return Text(
                          'Last 7 days of SMS from banks. Green = read as a payment. '
                          'If a payment shows "Not read", tap Copy and send it to Claude so the format can be added.',
                          style: tt.bodySmall);
                    }
                    final (addr, body, at) = _msgs![i - 1];
                    final spend = SmsParser.parse(body);
                    final otp = spend == null ? SmsParser.parseCardOtp(body) : null;
                    final bal = SmsParser.parseBalance(body);
                    final String status;
                    final Color color;
                    if (spend != null) {
                      status = 'Payment ${money(spend.amount)} to ${spend.payee}';
                      color = cs.primary;
                    } else if (otp != null) {
                      status = 'Card OTP ${money(otp.amount)} at ${otp.merchant} → asks "did it go through?"';
                      color = cs.tertiary;
                    } else if (bal != null && bal.delta > 0) {
                      status = 'Money in ${money(bal.delta)}${bal.payer != null ? ' from ${bal.payer}' : ''}';
                      color = cs.primary;
                    } else if (bal != null && bal.balance != null) {
                      status = 'Balance only: ${money(bal.balance!)}';
                      color = cs.secondary;
                    } else {
                      status = 'Not read (not a payment, or a new format)';
                      color = cs.error;
                    }
                    final masked = _mask(body);
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 4, 6),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Icon(Icons.circle, size: 10, color: color),
                            const SizedBox(width: 6),
                            Expanded(child: Text(status, style: tt.labelLarge?.copyWith(color: color))),
                          ]),
                          const SizedBox(height: 4),
                          Text('$addr · ${DateFormat('d MMM, h:mm a').format(at)}', style: tt.labelSmall),
                          const SizedBox(height: 4),
                          Text(masked, style: tt.bodySmall),
                          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                            TextButton.icon(
                              icon: const Icon(Icons.copy, size: 16),
                              label: const Text('Copy'),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: masked));
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(const SnackBar(content: Text('Copied (OTP and account number hidden)')));
                              },
                            ),
                            if (spend != null || otp != null || (bal != null && bal.delta > 0))
                              TextButton.icon(
                                icon: const Icon(Icons.refresh, size: 16),
                                label: const Text('Add again'),
                                onPressed: () async {
                                  final added = await widget.sms.ingestOne(body, at);
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                      content: Text(added ? 'Added' : 'Already in the app (or handled)')));
                                },
                              ),
                          ]),
                        ]),
                      ),
                    );
                  },
                ),
    );
  }
}
