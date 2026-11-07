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

  // ---------- account balance ----------

  static final _balance = RegExp(
      r'(?:avl\.?\s*bal(?:ance)?|avail(?:able)?\.?\s*bal(?:ance)?|a/c\s*bal(?:ance)?|clear\s*bal(?:ance)?|'
      r'total\s*bal(?:ance)?|\bbal(?:ance)?)\s*(?:is|:|-|of|in your a/c)?\s*(?:rs\.?|inr|₹)?\s*:?\s*'
      r'(-?[0-9][0-9,]*(?:\.[0-9]{1,2})?)',
      caseSensitive: false);

  static final _account = RegExp(
      r'(?:a/c|a/c\s*no\.?|ac|acct|account|card)\s*(?:no\.?|number)?\s*[:.]?\s*[x*.\s]*(\d{3,6})\b',
      caseSensitive: false);

  // Who sent money in a credit SMS. Group 1 = payer.
  static final List<RegExp> _payerPatterns = [
    RegExp(r'upi/cr/\d+/([^/|]+?)(?:\s*/|\s*\||\.\s|\.?$)', caseSensitive: false),
    RegExp(r'(?:from|by|vpa)\s+(?:vpa\s+)?([a-z0-9][a-z0-9._\-]{1,60}@[a-z][a-z0-9]{1,30})', caseSensitive: false),
    RegExp(r'(?:from|by)\s+([a-z][a-z .&\x27\-]{1,40}?)(?:\s+on\b|\s+ref|\s+upi|\s+via|\s*\(|\s*\||[.,;]|$)',
        caseSensitive: false),
    RegExp(r'\b(salary|stipend|neft|imps|rtgs)\b', caseSensitive: false),
  ];

  static final _interest = RegExp(
      r'\binterest\b|\bint\.?\s*(?:pd|paid|cr|credit(?:ed)?|amt)\b|\bsb\s*int\b|\bint\s*on\s*(?:sb|fd|rd)\b|'
      r'\btd\s*int\b|\bfd\s*int\b|\bint\.?\s*:|\binttr?\b|\bcredit\s*interest\b',
      caseSensitive: false);

  static final _creditWord = RegExp(r'\b(credited|received|deposited|refunded)\b', caseSensitive: false);

  /// Reads balance information from any bank SMS (debit or credit).
  /// Returns null if the SMS says nothing useful about an account balance.
  static BalanceInfo? parseBalance(String body) {
    final text = body
        .replaceAll(RegExp(r'[\r\n]+'), ' | ')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .trim();
    if (RegExp(r'\botp\b|will be debited|to be debited|requested|failed|declined', caseSensitive: false)
        .hasMatch(text)) {
      return null;
    }
    final accM = _account.firstMatch(text);
    var acct = accM?.group(1);
    if (acct != null && acct.length > 4) acct = acct.substring(acct.length - 4);

    double? bal;
    final bm = _balance.firstMatch(text);
    if (bm != null) bal = double.tryParse(bm.group(1)!.replaceAll(',', ''));

    // Movement: debit (from the spend parser) or credit.
    double delta = 0;
    final spend = parse(body);
    if (spend != null) {
      delta = -spend.amount;
    } else if (_creditWord.hasMatch(text) && !_debitWord.hasMatch(text)) {
      final m = _amountCurrency.firstMatch(text);
      final a = m == null ? null : double.tryParse(m.group(1)!.replaceAll(',', ''));
      // Don't mistake the balance figure for the credited amount.
      if (a != null && (bm == null || m!.start < bm.start)) delta = a;
    }
    if (bal == null && delta == 0) return null;
    String? payer;
    if (delta > 0) {
      outer:
      for (final p in _payerPatterns) {
        for (final m in p.allMatches(text)) {
          final c = m.group(1)!.trim();
          if (c.length < 2 || RegExp(r'^[\d\s/x*-]+$', caseSensitive: false).hasMatch(c)) continue;
          final l = c.toLowerCase();
          if (RegExp(r'^(your|a/c|ac |account|rs\b|inr\b|the |a |an |you)').hasMatch(l)) continue;
          payer = c.toUpperCase();
          break outer;
        }
      }
    }
    // Bank interest (SB / FD interest) — kept apart so it can be given away.
    final interest = delta > 0 && _interest.hasMatch(text);
    if (interest) payer = 'BANK INTEREST';
    return BalanceInfo(account: acct ?? 'main', balance: bal, delta: delta, payer: payer, isInterest: interest);
  }

  // ---------- card purchase OTP ----------

  static final _cardOtp = RegExp(
      r'(?:otp|one time password|one-time password).{0,80}?(?:purchase|transaction|txn|payment)\s+(?:of|for)\s+'
      r'(?:rs\.?|inr|₹)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)\s*(?:at|on|to|with)\s+(.+?)'
      r'(?:\s+(?:thru|through|using|via|with|on|from)\b|[.;,]|$)',
      caseSensitive: false);
  static final _cardDigits =
      RegExp(r'card\s*(?:no\.?|number|ending(?:\s*with)?)?\s*[x*.\s]*(\d{4})\b', caseSensitive: false);

  /// "123456 is OTP for online purchase of Rs. 456.00 at SWIGGY FOOD thru
  /// State Bank Debit Card 9645" → amount, merchant, card. The OTP code
  /// itself is never returned or stored.
  static CardOtp? parseCardOtp(String body) {
    final text = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    final m = _cardOtp.firstMatch(text);
    if (m == null) return null;
    final amount = double.tryParse(m.group(1)!.replaceAll(',', ''));
    if (amount == null || amount <= 0) return null;
    var merchant = m.group(2)!.trim();
    if (merchant.length > 60) merchant = merchant.substring(0, 60);
    if (merchant.isEmpty) return null;
    final card = _cardDigits.firstMatch(text)?.group(1);
    return CardOtp(amount: amount, merchant: merchant.toUpperCase(), card: card);
  }
}

class CardOtp {
  final double amount;
  final String merchant;
  final String? card;
  const CardOtp({required this.amount, required this.merchant, this.card});
  @override
  String toString() => 'CardOtp(₹$amount at $merchant, card $card)';
}

class BalanceInfo {
  final String account; // last digits of the account, or 'main'
  final double? balance; // exact balance printed by the bank, if any
  final double delta; // money out (negative) or in (positive)
  final String? payer; // who sent the money (credits only), if the SMS says
  final bool isInterest; // bank interest credited (riba) — to be given away
  const BalanceInfo({required this.account, this.balance, this.delta = 0, this.payer, this.isInterest = false});
  @override
  String toString() => 'BalanceInfo($account, bal=$balance, delta=$delta)';
}