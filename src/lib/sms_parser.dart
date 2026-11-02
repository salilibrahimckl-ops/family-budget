// Parses Indian bank / UPI debit SMS into a structured transaction.
// Pure Dart (no Flutter imports) so it can be unit-tested with `flutter test`.

class ParsedTxn {
  final double amount;
  final String payee; // best human-readable payee name or VPA
  final String? vpa; // e.g. swiggy@icici
  final String? ref; // UPI reference / RRN, used to avoid duplicates
  final DateTime? date; // date printed inside the SMS, if any
  final bool isUpi;

  const ParsedTxn({
    required this.amount,
    required this.payee,
    this.vpa,
    this.ref,
    this.date,
    this.isUpi = false,
  });

  @override
  String toString() =>
      'ParsedTxn(₹$amount, payee=$payee, vpa=$vpa, ref=$ref, date=$date, upi=$isUpi)';
}

class SmsParser {
  static final _debitWord = RegExp(
      r'\b(debited|debit|sent|paid|spent|withdrawn|transferred|purchase)\b',
      caseSensitive: false);

  // Messages that mention money but are not a completed spend.
  static final _notASpend = RegExp(
      r'(\botp\b|will be debited|to be debited|is due|due on|due date|'
      r'requested|request of|collect request|has requested|reminder|'
      r'\bfailed\b|declined|unsuccessful|reversed|refund|cashback|'
      r'credited to your (a/c|acc|account)|received from|'
      r'mandate (has been |is )?(created|registered|set)|e-?mandate|'
      r'emi (of|due)|min(imum)? amount due|statement)',
      caseSensitive: false);

  static final _amountCurrency = RegExp(
      r'(?:rs\.?|inr|₹)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)',
      caseSensitive: false);
  static final _amountDebitedBy = RegExp(
      r'debited\s+(?:by|for|with)\s+(?:rs\.?|inr|₹)?\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)',
      caseSensitive: false);

  static final _vpa = RegExp(r'([a-z0-9][a-z0-9._\-]{1,60}@[a-z][a-z0-9]{1,30})\b',
      caseSensitive: false);

  // Payee name patterns, most specific first. Group 1 = name.
  static final List<RegExp> _payeePatterns = [
    // Axis / Canara style: UPI/P2M/430512345678/SWIGGY LIMITED/...
    RegExp(r'upi/(?:p2[am]|dr|cr)/\d+/([^/|]+?)(?:\s*/|\s*\||\.\s|\.?$)', caseSensitive: false),
    // SBI style: trf to SWIGGY Refno 4305...
    RegExp(r'trf to\s+([^|]+?)\s+(?:ref\s?no|refno|ref|on\b|upi)', caseSensitive: false),
    // ICICI style: ...; SWIGGY credited. UPI:4305...
    RegExp(r';\s*([^;|]+?)\s+credited', caseSensitive: false),
    // Generic: paid/sent/transferred to NAME on/ref/...
    RegExp(
        r'(?:paid|sent|transferred|payment)\s+to\s+([^|]+?)(?:\s+on\b|\s+ref|\s+upi|\s+via|\s+from|\s+using|\s+a/c|\s*\||[.,;(]|$)',
        caseSensitive: false),
    // HDFC style multi-line: "To SWIGGY On 01/11/26"
    RegExp(
        r'\bto\s+([a-z][a-z0-9 .&\x27\-]{1,50}?)(?:\s+on\b|\s+ref|\s+upi|\s+via|\s+not you|\s*\||[.,;(]|$)',
        caseSensitive: false),
  ];

  static final List<RegExp> _refPatterns = [
    RegExp(r'upi/(?:p2[am]|dr|cr)/(\d{9,})', caseSensitive: false),
    RegExp(
        r'(?:upi\s*ref(?:erence)?(?:\s*no)?|ref(?:erence)?\s*no|refno|rrn|ref|upi)\.?\s*[:#\-]?\s*(\d{9,})',
        caseSensitive: false),
    RegExp(r'\b(\d{12})\b'),
  ];

  static const _months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  /// Returns null when the SMS is not a completed debit/spend.
  static ParsedTxn? parse(String body) {
    // Keep line breaks as " | " so multi-line SMS (HDFC, Axis) still have
    // a boundary after the payee name.
    final text = body
        .replaceAll(RegExp(r'[\r\n]+'), ' | ')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .trim();
    if (text.isEmpty) return null;
    if (!_debitWord.hasMatch(text)) return null;
    if (_notASpend.hasMatch(text)) return null;

    final amount = _parseAmount(text);
    if (amount == null || amount <= 0) return null;

    final vpaMatch = _vpa.firstMatch(text);
    final vpa = vpaMatch?.group(1)?.toLowerCase();

    String? name;
    for (final p in _payeePatterns) {
      final m = p.firstMatch(text);
      if (m == null) continue;
      final cand = _cleanName(m.group(1)!);
      if (cand == null) continue;
      name = cand;
      break;
    }

    String? ref;
    for (final p in _refPatterns) {
      final m = p.firstMatch(text);
      if (m != null) {
        ref = m.group(1);
        break;
      }
    }

    final payee = name ?? (vpa != null ? vpa : 'Unknown');
    final isUpi = RegExp(r'\bupi\b', caseSensitive: false).hasMatch(text) || vpa != null;

    return ParsedTxn(
      amount: amount,
      payee: payee,
      vpa: vpa,
      ref: ref,
      date: parseDate(text),
      isUpi: isUpi,
    );
  }

  static double? _parseAmount(String text) {
    final m = _amountDebitedBy.firstMatch(text) ?? _amountCurrency.firstMatch(text);
    if (m == null) return null;
    return double.tryParse(m.group(1)!.replaceAll(',', ''));
  }

  static String? _cleanName(String raw) {
    var s = raw.trim();
    // Names that are really account references or VPAs are handled elsewhere.
    if (s.contains('@')) return null;
    final lower = s.toLowerCase();
    if (lower.startsWith('vpa') ||
        lower.startsWith('your') ||
        lower.startsWith('a/c') ||
        lower.startsWith('ac ') ||
        lower.startsWith('account') ||
        lower.startsWith('block') ||
        lower.startsWith('dispute') ||
        lower.startsWith('report')) {
      return null;
    }
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    if (s.length < 2) return null;
    if (RegExp(r'^[\d\s/x*-]+$', caseSensitive: false).hasMatch(s)) return null;
    return s.toUpperCase();
  }

  /// Finds a date written inside the SMS. Handles 01-11-26, 01/11/2026,
  /// 01Nov26, 01-Nov-26, 01 Nov 2026, 2026-11-01.
  static DateTime? parseDate(String text) {
    DateTime? build(int y, int m, int d) {
      if (y < 100) y += 2000;
      if (m < 1 || m > 12 || d < 1 || d > 31) return null;
      if (y < 2015 || y > 2100) return null;
      return DateTime(y, m, d, 12);
    }

    var m = RegExp(r'\b(20\d{2})-(\d{1,2})-(\d{1,2})\b').firstMatch(text);
    if (m != null) {
      final r = build(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
      if (r != null) return r;
    }
    m = RegExp(r'\b(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})\b').firstMatch(text);
    if (m != null) {
      final r = build(int.parse(m.group(3)!), int.parse(m.group(2)!), int.parse(m.group(1)!));
      if (r != null) return r;
    }
    m = RegExp(r'\b(\d{1,2})[\s-]?([a-z]{3})[a-z]*[\s-]?(\d{2,4})\b', caseSensitive: false)
        .firstMatch(text);
    if (m != null) {
      final mon = _months[m.group(2)!.toLowerCase()];
      if (mon != null) {
        final r = build(int.parse(m.group(3)!), mon, int.parse(m.group(1)!));
        if (r != null) return r;
      }
    }
    return null;
  }

  /// Bank SMS come from alphanumeric sender IDs like "AX-HDFCBK" or
  /// "VM-SBIUPI-S". Personal numbers are ignored so a friend's text such as
  /// "I sent Rs 500" is never counted.
  static bool looksLikeBankSender(String? address) {
    if (address == null) return false;
    final a = address.trim();
    if (a.isEmpty) return false;
    return !RegExp(r'^\+?[\d\s-]+$').hasMatch(a);
  }
}
