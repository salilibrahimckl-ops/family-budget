// Guesses a category from the payee name / VPA. Pure Dart.
// Learned rules (stored in Firestore when you tag a payee) always win over these.

class Guess {
  final String category; // a category id, or 'uncategorised'
  final bool chittiHint; // payee name looks like a chit fund
  const Guess(this.category, {this.chittiHint = false});
}

class Categorizer {
  static const Map<String, List<String>> keywords = {
    'food': [
      'swiggy', 'zomato', 'eatsure', 'domino', 'pizza', 'kfc', 'mcdonald',
      'burger', 'restaurant', 'cafe', 'bakery', 'bakers', 'biryani', 'chai',
      'starbucks', 'haldiram', 'juice', 'tea stall', 'food', 'kitchen',
      'dhaba', 'mess', 'canteen', 'barbeque', 'icecream', 'ice cream',
    ],
    'grocery': [
      'bigbasket', 'blinkit', 'grofers', 'zepto', 'instamart', 'dmart',
      'avenue supermarts', 'jiomart', 'reliance fresh', 'reliance retail',
      'more retail', 'supermarket', 'hypermarket', 'lulu', 'margin free',
      'nilgiris', 'triveni', 'supplyco', 'milma', 'vegetable', 'fruits',
      'provision', 'grocery', 'kirana', 'fish', 'meat', 'chicken',
    ],
    'travel': [
      'uber', 'ola', 'olacabs', 'rapido', 'namma yatri', 'irctc', 'redbus',
      'makemytrip', 'goibibo', 'indigo', 'interglobe', 'air india',
      'airindia', 'akasa', 'spicejet', 'cleartrip', 'ixigo', 'yatra',
      'fastag', 'petrol', 'fuel', 'hpcl', 'bpcl', 'indian oil', 'indianoil',
      'iocl', 'nayara', 'shell', 'ksrtc', 'metro', 'kmrl', 'parking', 'toll',
      'railway', 'airport', 'cab',
    ],
    'shopping': [
      'amazon', 'flipkart', 'myntra', 'ajio', 'meesho', 'nykaa', 'tatacliq',
      'tata cliq', 'croma', 'reliance digital', 'decathlon', 'lifestyle',
      'westside', 'trends', 'max fashion', 'ikea', 'pantaloons', 'zudio',
      'textiles', 'silks', 'jewel', 'footwear', 'electronics', 'mobiles',
    ],
    'fun': [
      'bookmyshow', 'pvr', 'inox', 'cinepolis', 'netflix', 'spotify',
      'hotstar', 'jiocinema', 'primevideo', 'prime video', 'youtube',
      'steam', 'playstation', 'cinema', 'theatre', 'gaming', 'wonderla',
      'district',
    ],
    'savings': [
      'groww', 'zerodha', 'upstox', 'kuvera', 'paytm money', 'smallcase',
      'indmoney', 'mutual fund', 'mf ', 'sip', 'nps', 'ppf',
      'recurring deposit', 'bse limited', 'nse clearing', 'icclzerodha',
    ],
  };

  static const chittiWords = ['ksfe', 'chit', 'chitty', 'chitti', 'kuri', 'kuries', 'kurees'];

  static Guess guess(String payee, {String? vpa}) {
    final hay = ' ${payee.toLowerCase()} ${vpa?.toLowerCase() ?? ''} ';
    final chittiHint = chittiWords.any((w) => hay.contains(w));
    for (final entry in keywords.entries) {
      for (final w in entry.value) {
        if (_containsWord(hay, w)) return Guess(entry.key, chittiHint: chittiHint);
      }
    }
    return Guess('uncategorised', chittiHint: chittiHint);
  }

  // Short keywords (ola, sip, nps, cab...) must match a whole word so that
  // e.g. "COLA" or "GOSSIP" are not misread. Long ones may match anywhere.
  static bool _containsWord(String hay, String w) {
    if (w.length > 4) return hay.contains(w);
    return RegExp('(^|[^a-z])${RegExp.escape(w.trim())}([^a-z]|\$)').hasMatch(hay);
  }

  /// Stable key used to remember a payee: lower-case letters and digits only.
  static String payeeKey(String payee, {String? vpa}) {
    var base = payee;
    if (base == 'Unknown' || base.isEmpty) base = vpa ?? 'unknown';
    // For a VPA keep only the handle before '@'.
    if (base.contains('@')) base = base.split('@').first;
    final k = base.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return k.isEmpty ? 'unknown' : (k.length > 60 ? k.substring(0, 60) : k);
  }
}
