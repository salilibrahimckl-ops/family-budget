import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'categories.dart';
import 'categorizer.dart';
import 'config.dart';
import 'sms_parser.dart';

/// One spend record, shared by the family.
class Txn {
  final String id;
  final double amount;
  final String payee;
  final String payeeKey;
  final String category;
  final String member;
  final DateTime date;
  final String source; // sms | iphone | manual
  final bool chittiSuggest;
  final String? note;

  Txn.fromDoc(DocumentSnapshot<Map<String, dynamic>> d)
      : id = d.id,
        amount = (d.data()!['amount'] as num).toDouble(),
        payee = d.data()!['payee'] as String? ?? 'Unknown',
        payeeKey = d.data()!['payeeKey'] as String? ?? 'unknown',
        category = d.data()!['category'] as String? ?? kUncategorised,
        member = d.data()!['member'] as String? ?? '?',
        date = (d.data()!['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
        source = d.data()!['source'] as String? ?? 'manual',
        chittiSuggest = d.data()!['chittiSuggest'] as bool? ?? false,
        note = d.data()!['note'] as String?;
}

/// Money moved into Savings / Chitti through the app.
class SetAside {
  final Map<String, double> byMonth;
  final Map<String, double> byMember;
  const SetAside(this.byMonth, this.byMember);
  double get total => byMonth.values.fold(0.0, (s, v) => s + v);
}

/// A card payment seen only as an OTP SMS, waiting for "did it go through?".
class PendingCard {
  final String id;
  final double amount;
  final String merchant;
  final String? card;
  final String member;
  final DateTime at;
  PendingCard.fromDoc(DocumentSnapshot<Map<String, dynamic>> d)
      : id = d.id,
        amount = (d.data()!['amount'] as num).toDouble(),
        merchant = d.data()!['merchant'] as String? ?? 'Card payment',
        card = d.data()!['card'] as String?,
        member = d.data()!['member'] as String? ?? '?',
        at = (d.data()!['at'] as Timestamp?)?.toDate() ?? DateTime.now();
}

/// A bank account's balance, kept up to date from bank SMS.
class BankAccount {
  final String id;
  final String member;
  final String account; // last digits, or 'main'
  final String? label;
  final double? balance;
  final bool exact; // true = printed by the bank / set by you; false = estimated
  final DateTime? balanceAt;

  BankAccount.fromDoc(DocumentSnapshot<Map<String, dynamic>> d)
      : id = d.id,
        member = d.data()!['member'] as String? ?? '?',
        account = d.data()!['account'] as String? ?? 'main',
        label = d.data()!['label'] as String?,
        balance = (d.data()!['balance'] as num?)?.toDouble(),
        exact = d.data()!['exact'] as bool? ?? false,
        balanceAt = (d.data()!['balanceAt'] as Timestamp?)?.toDate();

  String get title => label ?? (account == 'main' ? 'Bank account' : 'A/c ••$account');
}

/// Money you expect to receive (debt payback, pending stipend…), savings you
/// hold outside the bank accounts (FD, mutual fund, chitti so far…) or gold.
class MoneyItem {
  final String id;
  final String kind; // 'receivable' | 'asset'
  final String title;
  final String member;
  final double amount;
  final DateTime? due;
  final bool received;
  final DateTime? receivedAt;
  final String? note;
  final double grams; // gold only
  final int purity; // gold only: 22 or 24 (carat)

  MoneyItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> d)
      : id = d.id,
        kind = d.data()!['kind'] as String? ?? 'asset',
        title = d.data()!['title'] as String? ?? '',
        member = d.data()!['member'] as String? ?? '?',
        amount = (d.data()!['amount'] as num?)?.toDouble() ?? 0,
        due = (d.data()!['due'] as Timestamp?)?.toDate(),
        received = d.data()!['received'] as bool? ?? false,
        receivedAt = (d.data()!['receivedAt'] as Timestamp?)?.toDate(),
        note = d.data()!['note'] as String?,
        grams = (d.data()!['grams'] as num?)?.toDouble() ?? 0,
        purity = (d.data()!['purity'] as num?)?.toInt() ?? 22;

  bool get isGold => kind == 'gold';
  double get pavan => grams / 8;

  /// Value in rupees; gold uses today's rate per gram for its purity.
  double value(Map<int, double> goldRates) => isGold ? grams * (goldRates[purity] ?? 0) : amount;
}

/// Monthly budget: amount per category + optional personal limit per member.
class Budget {
  final Map<String, double> categories;
  final Map<String, double> members; // personal spending limit
  final Map<String, double> income; // expected monthly income per person
  const Budget(this.categories, this.members, [this.income = const {}]);

  static Budget fromMap(Map<String, dynamic>? m) {
    Map<String, double> conv(dynamic x) => x is Map
        ? x.map((k, v) => MapEntry(k as String, (v as num).toDouble()))
        : <String, double>{};
    return Budget(conv(m?['categories']), conv(m?['members']), conv(m?['income']));
  }

  Map<String, dynamic> toMap() => {'categories': categories, 'members': members, 'income': income};
}

/// Money that came in (salary, stipend, payback…). `counted` = false for
/// transfers between the two of you, refunds, etc.
class IncomeEntry {
  final String id;
  final double amount;
  final String from;
  final String member;
  final DateTime date;
  final String source; // sms | iphone | manual
  final bool counted;
  final String? note;
  IncomeEntry.fromDoc(DocumentSnapshot<Map<String, dynamic>> d)
      : id = d.id,
        amount = (d.data()!['amount'] as num?)?.toDouble() ?? 0,
        from = d.data()!['from'] as String? ?? 'Money in',
        member = d.data()!['member'] as String? ?? '?',
        date = (d.data()!['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
        source = d.data()!['source'] as String? ?? 'manual',
        counted = d.data()!['counted'] as bool? ?? true,
        note = d.data()!['note'] as String?;
}

/// What was left at the end of a month, before the next month's income.
class Closing {
  final String month; // YYYY-MM
  final DateTime at;
  final bool auto;
  final Map<String, Map<String, double>> members; // name -> {bank, cash, other, gold, goldGrams}
  Closing.fromDoc(DocumentSnapshot<Map<String, dynamic>> d)
      : month = d.id,
        at = (d.data()!['at'] as Timestamp?)?.toDate() ?? DateTime.now(),
        auto = d.data()!['auto'] as bool? ?? false,
        members = {
          for (final e in Map<String, dynamic>.from(d.data()!['members'] as Map? ?? {}).entries)
            e.key: {
              for (final f in Map<String, dynamic>.from(e.value as Map).entries)
                f.key: (f.value as num?)?.toDouble() ?? 0
            }
        };
  double total(String key) => members.values.fold(0.0, (s, m) => s + (m[key] ?? 0));
  double get grand => total('bank') + total('cash') + total('other') + total('gold');
}

class Repo {
  Repo(this.familyId, this.myName);
  final String familyId;
  final String myName;

  static FirebaseFirestore get db => FirebaseFirestore.instance;
  DocumentReference<Map<String, dynamic>> get family => db.collection('families').doc(familyId);
  CollectionReference<Map<String, dynamic>> get txns => family.collection('transactions');
  CollectionReference<Map<String, dynamic>> get rules => family.collection('rules');
  CollectionReference<Map<String, dynamic>> get budgets => family.collection('budgets');
  String get myUid => FirebaseAuth.instance.currentUser!.uid;

  // ---------- auth & family ----------

  static Future<User> signIn() async {
    final auth = FirebaseAuth.instance;
    final existing = auth.currentUser ?? await auth.authStateChanges().first;
    if (existing != null) return existing;
    return (await auth.signInAnonymously()).user!;
  }

  static Future<String> createFamily(String familyName, String myName) async {
    final user = await signIn();
    final ref = db.collection('families').doc();
    await ref.set({
      'name': familyName,
      'createdAt': FieldValue.serverTimestamp(),
      'members': {user.uid: myName},
      'adminName': myName, // only this person can use Developer options
      'inboxTokens': {randomToken(): myName},
      'defaultBudget': {
        'categories': {for (final c in kCats) c.id: 0},
        'members': <String, double>{},
      },
    });
    return ref.id;
  }

  static Future<void> joinFamily(String familyId, String myName) async {
    final user = await signIn();
    final ref = db.collection('families').doc(familyId);
    final snap = await ref.get();
    if (!snap.exists) throw Exception('Family not found. Check the invite code.');
    final tokens = Map<String, dynamic>.from(snap.data()!['inboxTokens'] as Map? ?? {});
    final update = <String, dynamic>{'members.${user.uid}': myName};
    if (!tokens.values.contains(myName)) update['inboxTokens.${randomToken()}'] = myName;
    await ref.update(update);
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> familyStream() => family.snapshots();

  /// Inbox token for this member (used by the iPhone Shortcut).
  Future<String?> myInboxToken() async {
    final snap = await family.get();
    final tokens = Map<String, dynamic>.from(snap.data()?['inboxTokens'] as Map? ?? {});
    for (final e in tokens.entries) {
      if (e.value == myName) return e.key;
    }
    final t = randomToken();
    await family.update({'inboxTokens.$t': myName});
    return t;
  }

  // ---------- budgets ----------

  Stream<Budget> budgetStream(String month) {
    return budgets.doc(month).snapshots().asyncMap((s) async {
      if (s.exists) return Budget.fromMap(s.data());
      final f = await family.get();
      return Budget.fromMap(f.data()?['defaultBudget'] as Map<String, dynamic>?);
    });
  }

  Future<void> saveBudget(String month, Budget b, {bool asDefault = true}) async {
    await budgets.doc(month).set(b.toMap());
    if (asDefault) await family.update({'defaultBudget': b.toMap()});
  }

  // ---------- transactions ----------

  Stream<List<Txn>> monthTxns(String month) => txns
      .where('month', isEqualTo: month)
      .snapshots()
      .map((q) => q.docs.map(Txn.fromDoc).toList()..sort((a, b) => b.date.compareTo(a.date)));

  /// Turns a bank SMS into a transaction. Safe to call twice for the same SMS:
  /// the id is derived from the UPI reference (or time + amount) and existing
  /// records are never overwritten, so your edits are kept.
  Future<bool> ingestSms(String body,
      {required DateTime receivedAt, required String member, required String source}) async {
    try {
      final info = SmsParser.parseBalance(body);
      if (info != null && info.delta > 0 && DateTime.now().difference(receivedAt).inHours < 48) {
        // First money in of a new month: remember last month's leftovers first.
        // (Only for fresh SMS — an old SMS found by a re-scan would snapshot today's balances.)
        await ensureClosing(monthKey(DateTime(receivedAt.year, receivedAt.month - 1)), before: receivedAt);
      }
      await updateBalance(body, when: receivedAt, member: member);
      if (info != null && info.delta > 0) await _addIncomeFromSms(info, receivedAt, member, source);
    } catch (_) {}
    final p = SmsParser.parse(body);
    if (p == null) {
      final otp = SmsParser.parseCardOtp(body);
      if (otp != null) await _addPendingCard(otp, receivedAt, member);
      return false;
    }
    final when = p.date != null && source == 'iphone' ? _withTime(p.date!, receivedAt) : receivedAt;
    final id = p.ref != null
        ? 'ref_${p.ref}'
        : 'sms_${receivedAt.millisecondsSinceEpoch ~/ 60000}_${(p.amount * 100).round()}';

    final ref = txns.doc(id);
    if ((await ref.get()).exists) return false;
    if (await _matchesCardPayment(p.amount, when, member)) return false;

    final key = Categorizer.payeeKey(p.payee, vpa: p.vpa);
    final rule = (await rules.doc(key).get()).data();
    String category;
    var chittiAsk = false;
    if (rule?['category'] != null) {
      category = rule!['category'] as String;
    } else {
      await _loadCats();
      final g = Categorizer.guess(p.payee, vpa: p.vpa);
      category = CatStore.matchKeywords(p.payee, p.vpa) ?? g.category;
      chittiAsk = g.chittiHint;
    }

    final declined = rule?['chittiDeclined'] == true;
    if (category != 'chitti' && !declined) {
      chittiAsk = chittiAsk || await _looksRecurring(key, p.amount, monthKey(when));
    } else {
      chittiAsk = false;
    }

    await db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (snap.exists) return;
      tx.set(ref, {
        'amount': p.amount,
        'payee': p.payee,
        'payeeKey': key,
        'vpa': p.vpa,
        'ref': p.ref,
        'category': category,
        'member': member,
        'date': Timestamp.fromDate(when),
        'month': monthKey(when),
        'source': source,
        'raw': body.length > 500 ? body.substring(0, 500) : body,
        'chittiSuggest': chittiAsk,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
    return true;
  }

  bool _catsLoaded = false;
  Future<void> _loadCats() async {
    if (_catsLoaded) return;
    CatStore.apply((await family.get()).data());
    _catsLoaded = true;
  }

  /// The family admin (creator) is the only one who can use Developer options.
  /// Older families without an admin: the first person to turn on developer
  /// mode becomes admin.
  Future<bool> isAdmin({bool claimIfUnset = false}) async {
    final d = (await family.get()).data();
    final admin = d?['adminName'] as String?;
    if (admin == null) {
      if (!claimIfUnset) return false;
      await family.update({'adminName': myName});
      return true;
    }
    return admin == myName;
  }

  // ---------- categories (Developer options) ----------

  /// Create or update a category. Built-ins only store overrides.
  Future<void> saveCat(Cat c, {int? order}) async {
    await family.update({
      'cats.${c.id}': {
        'label': c.label,
        'icon': c.iconKey,
        'color': c.color.toARGB32(),
        'goal': c.goal,
        'hidden': c.hidden,
        'custom': c.custom,
        'keywords': c.keywords,
        if (order != null) 'order': order,
      }
    });
  }

  /// Removes a custom category; its payments move to "To tag".
  Future<void> deleteCat(Cat c) async {
    if (!c.custom) return;
    await family.update({'cats.${c.id}': FieldValue.delete()});
    final used = await txns.where('category', isEqualTo: c.id).get();
    for (final d in used.docs) {
      await d.reference.update({'category': kUncategorised});
    }
    final r = await rules.where('category', isEqualTo: c.id).get();
    for (final d in r.docs) {
      await d.reference.update({'category': FieldValue.delete()});
    }
  }

  /// Restores a built-in category's original name, icon and colour.
  Future<void> resetCat(Cat c) => family.update({'cats.${c.id}': FieldValue.delete()});

  DateTime _withTime(DateTime day, DateTime t) =>
      DateTime(day.year, day.month, day.day, t.hour, t.minute);

  /// Same payee, (almost) the same amount, paid in an earlier month → probably chitti.
  Future<bool> _looksRecurring(String key, double amount, String month) async {
    if (amount < 500 || key == 'unknown') return false;
    final prev = await txns.where('payeeKey', isEqualTo: key).limit(60).get();
    return prev.docs.any((d) {
      final m = d.data();
      return m['month'] != month &&
          m['category'] != kIgnored &&
          ((m['amount'] as num).toDouble() - amount).abs() <= 1;
    });
  }

  Future<void> addManual({
    required double amount,
    required String payee,
    required String category,
    required DateTime date,
    String? note,
  }) async {
    await txns.add({
      'amount': amount,
      'payee': payee.toUpperCase(),
      'payeeKey': Categorizer.payeeKey(payee),
      'category': category,
      'member': myName,
      'date': Timestamp.fromDate(date),
      'month': monthKey(date),
      'source': 'manual',
      'note': note,
      'chittiSuggest': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Change a transaction's category; optionally remember it for this payee
  /// and re-tag that payee's other untagged transactions.
  Future<void> setCategory(Txn t, String category, {bool remember = true}) async {
    await txns.doc(t.id).update({'category': category, 'chittiSuggest': false});
    if (!remember || category == kIgnored || t.payeeKey == 'unknown') return;
    await rules.doc(t.payeeKey).set({'category': category}, SetOptions(merge: true));
    final others = await txns
        .where('payeeKey', isEqualTo: t.payeeKey)
        .where('category', isEqualTo: kUncategorised)
        .get();
    for (final d in others.docs) {
      await d.reference.update({'category': category});
    }
  }

  Future<void> answerChitti(Txn t, bool isChitti) async {
    if (isChitti) {
      await setCategory(t, 'chitti');
      // Earlier payments of the same amount to this payee are chitti too.
      final prev = await txns.where('payeeKey', isEqualTo: t.payeeKey).get();
      for (final d in prev.docs) {
        final a = (d.data()['amount'] as num).toDouble();
        if ((a - t.amount).abs() <= 1 && d.data()['category'] != kIgnored) {
          await d.reference.update({'category': 'chitti', 'chittiSuggest': false});
        }
      }
    } else {
      await txns.doc(t.id).update({'chittiSuggest': false});
      await rules.doc(t.payeeKey).set({'chittiDeclined': true}, SetOptions(merge: true));
    }
  }

  Future<void> updateTxn(Txn t, {double? amount, String? note, String? payee}) async {
    await txns.doc(t.id).update({
      if (amount != null) 'amount': amount,
      if (note != null) 'note': note,
      if (payee != null) 'payee': payee.toUpperCase(),
    });
  }

  /// Ignored (not deleted) so a later SMS scan doesn't bring it back.
  Future<void> ignore(Txn t) => txns.doc(t.id).update({'category': kIgnored, 'chittiSuggest': false});

  Future<void> delete(Txn t) => txns.doc(t.id).delete();

  // ---------- income ----------

  CollectionReference<Map<String, dynamic>> get income => family.collection('income');

  Stream<List<IncomeEntry>> incomeStream(String month) => income
      .where('month', isEqualTo: month)
      .snapshots()
      .map((q) => q.docs.map(IncomeEntry.fromDoc).toList()..sort((a, b) => b.date.compareTo(a.date)));

  Future<void> _addIncomeFromSms(BalanceInfo info, DateTime when, String member, String source) async {
    final id = 'in_${member.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')}'
        '_${when.millisecondsSinceEpoch ~/ 60000}_${(info.delta * 100).round()}';
    final ref = income.doc(id);
    if ((await ref.get()).exists) return;
    final from = info.payer ?? 'Money in';
    // Money from the other person in the family is a transfer, not income.
    final fam = (await family.get()).data();
    final names = Map<String, dynamic>.from(fam?['members'] as Map? ?? {}).values.cast<String>().toSet();
    final fromLower = from.toLowerCase();
    final internal = names.where((n) => n != member).any((n) {
      final first = n.toLowerCase().split(' ').first;
      return first.length >= 3 && fromLower.contains(first);
    });
    final refund = RegExp(r'refund|reversal|reversed|cashback', caseSensitive: false).hasMatch(from);
    await ref.set({
      'amount': info.delta,
      'from': from,
      'member': member,
      'date': Timestamp.fromDate(when),
      'month': monthKey(when),
      'source': source,
      'counted': !(internal || refund),
      if (internal) 'note': 'Transfer between you two',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> addIncome({required double amount, required String from, required String member, required DateTime date, String? note}) =>
      income.add({
        'amount': amount,
        'from': from,
        'member': member,
        'date': Timestamp.fromDate(date),
        'month': monthKey(date),
        'source': 'manual',
        'counted': true,
        'note': note,
        'createdAt': FieldValue.serverTimestamp(),
      });

  Future<void> setIncomeCounted(IncomeEntry e, bool counted) => income.doc(e.id).update({'counted': counted});
  Future<void> deleteIncome(IncomeEntry e) => income.doc(e.id).delete();

  // ---------- month-end leftovers ----------

  CollectionReference<Map<String, dynamic>> get closings => family.collection('closings');

  Stream<List<Closing>> closingsStream() => closings
      .snapshots()
      .map((q) => q.docs.map(Closing.fromDoc).toList()..sort((a, b) => b.month.compareTo(a.month)));

  /// Save what's left now as [month]'s closing, unless one exists already
  /// (or [overwrite]). Uses the current bank balances, cash, other savings and gold.
  Future<void> ensureClosing(String month, {DateTime? before, bool overwrite = false, bool auto = true}) async {
    final ref = closings.doc(month);
    if (!overwrite && (await ref.get()).exists) return;
    final fam = (await family.get()).data();
    final members = <String, Map<String, double>>{};
    Map<String, double> m(String n) => members.putIfAbsent(n, () => {'bank': 0, 'cash': 0, 'other': 0, 'gold': 0, 'goldGrams': 0});
    for (final n in Map<String, dynamic>.from(fam?['members'] as Map? ?? {}).values.cast<String>()) {
      m(n);
    }
    for (final d in (await accounts.get()).docs) {
      final a = BankAccount.fromDoc(d);
      if (a.balance != null) m(a.member)['bank'] = m(a.member)['bank']! + a.balance!;
    }
    final rates = goldRatesFrom(fam);
    final auto22 = (fam?['autoGold22'] as num?)?.toDouble();
    for (final d in (await money.get()).docs) {
      final it = MoneyItem.fromDoc(d);
      final x = m(it.member);
      if (it.kind == 'cash') x['cash'] = x['cash']! + it.amount;
      if (it.kind == 'asset') x['other'] = x['other']! + it.amount;
      if (it.isGold) {
        final rate = it.purity == 22 ? (auto22 ?? rates[22] ?? 0) : (rates[24] ?? (auto22 ?? 0) / 0.916);
        x['goldGrams'] = x['goldGrams']! + it.grams;
        x['gold'] = x['gold']! + it.grams * rate;
      }
    }
    await ref.set({
      'members': members,
      'at': Timestamp.fromDate(before ?? DateTime.now()),
      'auto': auto,
    });
  }

  /// Remember the automatic 22K rate so month-end snapshots can value gold.
  Future<void> rememberGoldRate(double rate22) => family.update({'autoGold22': rate22});

  // ---------- card payments seen only as an OTP ----------

  CollectionReference<Map<String, dynamic>> get pending => family.collection('pending');

  Stream<List<PendingCard>> pendingStream() => pending.snapshots().map(
      (q) => q.docs.map(PendingCard.fromDoc).toList()..sort((a, b) => b.at.compareTo(a.at)));

  Future<void> _addPendingCard(CardOtp o, DateTime at, String member) async {
    // One OTP SMS = one pending item, even when re-scanned.
    final id = 'otp_${member.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')}_${at.millisecondsSinceEpoch ~/ 1000}';
    final ref = pending.doc(id);
    if ((await ref.get()).exists) return;
    // Ignore OTPs we already turned into a payment or dismissed.
    final done = await family.collection('pendingDone').doc(id).get();
    if (done.exists) return;
    await ref.set({
      'amount': o.amount,
      'merchant': o.merchant,
      'card': o.card,
      'member': member,
      'at': Timestamp.fromDate(at),
    });
  }

  /// Bank debit SMS that matches an OTP card payment (same person, same amount,
  /// within 3 hours): drop the pending item, and don't double-count one the
  /// user already confirmed.
  Future<bool> _matchesCardPayment(double amount, DateTime when, String member) async {
    bool near(DateTime t) => t.difference(when).inMinutes.abs() <= 180;
    final p = await pending.where('member', isEqualTo: member).get();
    for (final d in p.docs) {
      final pc = PendingCard.fromDoc(d);
      if ((pc.amount - amount).abs() < 0.01 && near(pc.at)) {
        await family.collection('pendingDone').doc(d.id).set({'by': 'sms'});
        await d.reference.delete();
        return false; // let the real SMS create the payment
      }
    }
    final card = await txns.where('source', isEqualTo: 'card').where('member', isEqualTo: member).get();
    return card.docs.any((d) {
      final t = Txn.fromDoc(d);
      return (t.amount - amount).abs() < 0.01 && near(t.date);
    });
  }

  Future<void> confirmCard(PendingCard pc, bool wentThrough) async {
    if (wentThrough) {
      await _loadCats();
      final key = Categorizer.payeeKey(pc.merchant);
      final rule = (await rules.doc(key).get()).data();
      final category = rule?['category'] as String? ??
          CatStore.matchKeywords(pc.merchant, null) ??
          Categorizer.guess(pc.merchant).category;
      await txns.doc('card_${pc.id}').set({
        'amount': pc.amount,
        'payee': pc.merchant,
        'payeeKey': key,
        'category': category,
        'member': pc.member,
        'date': Timestamp.fromDate(pc.at),
        'month': monthKey(pc.at),
        'source': 'card',
        'note': pc.card != null ? 'Card ••${pc.card}' : 'Card payment',
        'chittiSuggest': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    await family.collection('pendingDone').doc(pc.id).set({'by': wentThrough ? 'yes' : 'no'});
    await pending.doc(pc.id).delete();
  }

  // ---------- bank balances ----------

  CollectionReference<Map<String, dynamic>> get accounts => family.collection('accounts');

  Stream<List<BankAccount>> accountsStream() => accounts.snapshots().map(
      (q) => q.docs.map(BankAccount.fromDoc).toList()..sort((a, b) => a.member.compareTo(b.member)));

  static String _acctId(String member, String account) =>
      '${member.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')}_$account';

  /// Uses the balance printed in a bank SMS when there is one (exact);
  /// otherwise adjusts the last known balance by the amount debited/credited
  /// (estimated). SMS older than the last one applied are ignored, so
  /// re-scans never double-count.
  Future<void> updateBalance(String body, {required DateTime when, required String member}) async {
    final info = SmsParser.parseBalance(body);
    if (info == null) return;
    final ref = accounts.doc(_acctId(member, info.account));
    await db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final d = snap.data();
      final last = (d?['lastAppliedMs'] as num?)?.toInt() ?? 0;
      if (when.millisecondsSinceEpoch <= last) return;
      double? balance;
      bool exact;
      if (info.balance != null) {
        balance = info.balance;
        exact = true;
      } else if (d?['balance'] != null) {
        balance = (d!['balance'] as num).toDouble() + info.delta;
        exact = false;
      } else {
        balance = null; // no starting point yet: shown as "set balance"
        exact = false;
      }
      tx.set(
          ref,
          {
            'member': member,
            'account': info.account,
            'balance': balance,
            'exact': exact,
            'balanceAt': Timestamp.fromDate(when),
            'lastAppliedMs': when.millisecondsSinceEpoch,
          },
          SetOptions(merge: true));
    });
  }

  /// Set the balance by hand (e.g. from the bank app) and/or rename the account.
  Future<void> setAccount(BankAccount a, {double? balance, String? label}) async {
    final now = DateTime.now();
    await accounts.doc(a.id).set({
      if (balance != null) ...{
        'balance': balance,
        'exact': true,
        'balanceAt': Timestamp.fromDate(now),
        'lastAppliedMs': now.millisecondsSinceEpoch,
      },
      if (label != null) 'label': label.isEmpty ? FieldValue.delete() : label,
    }, SetOptions(merge: true));
  }

  Future<void> addAccount(String label, double balance) async {
    final now = DateTime.now();
    final acct = 'm${now.millisecondsSinceEpoch % 100000}';
    await accounts.doc(_acctId(myName, acct)).set({
      'member': myName,
      'account': acct,
      'label': label,
      'balance': balance,
      'exact': true,
      'balanceAt': Timestamp.fromDate(now),
      'lastAppliedMs': now.millisecondsSinceEpoch,
    });
  }

  Future<void> deleteAccount(BankAccount a) => accounts.doc(a.id).delete();

  // ---------- money to receive & other savings ----------

  CollectionReference<Map<String, dynamic>> get money => family.collection('money');

  Stream<List<MoneyItem>> moneyStream() => money.snapshots().map((q) => q.docs.map(MoneyItem.fromDoc).toList()
    ..sort((a, b) => (a.due ?? DateTime(2100)).compareTo(b.due ?? DateTime(2100))));

  Future<void> saveMoney({
    String? id,
    required String kind,
    required String title,
    required String member,
    required double amount,
    DateTime? due,
    String? note,
    double? grams,
    int? purity,
  }) async {
    final data = <String, dynamic>{
      'kind': kind,
      'title': title,
      'member': member,
      'amount': amount,
      if (grams != null) 'grams': grams,
      if (purity != null) 'purity': purity,
      'due': due == null ? null : Timestamp.fromDate(due),
      'note': note,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (id == null) {
      await money.add({...data, 'received': false});
    } else {
      await money.doc(id).set(data, SetOptions(merge: true));
    }
  }

  Future<void> setReceived(MoneyItem m, bool received) => money.doc(m.id).update({
        'received': received,
        'receivedAt': received ? Timestamp.now() : null,
      });

  Future<void> deleteMoney(MoneyItem m) => money.doc(m.id).delete();

  /// Today's gold rate per gram, by purity (22K / 24K), shared by the family.
  Map<int, double> goldRatesFrom(Map<String, dynamic>? familyData) {
    final r = familyData?['goldRates'];
    if (r is! Map) return {};
    return {
      for (final e in r.entries)
        if (int.tryParse('${e.key}') != null && e.value is num) int.parse('${e.key}'): (e.value as num).toDouble()
    };
  }

  Future<void> setGoldRates(double? r22, double? r24) => family.update({
        if (r22 != null) 'goldRates.22': r22,
        if (r24 != null) 'goldRates.24': r24,
        'goldRatesAt': FieldValue.serverTimestamp(),
      });

  /// Savings + chitti paid (all months), by month and by person.
  Stream<SetAside> setAsideStream() => txns
      .where('category', whereIn: [
        for (final c in CatStore.all)
          if (c.goal) c.id
      ].take(30).toList())
      .snapshots()
      .map((q) {
        final byMonth = <String, double>{};
        final byMember = <String, double>{};
        for (final d in q.docs) {
          final a = (d.data()['amount'] as num?)?.toDouble() ?? 0;
          final mk = d.data()['month'] as String? ?? '';
          final who = d.data()['member'] as String? ?? '?';
          byMonth[mk] = (byMonth[mk] ?? 0) + a;
          byMember[who] = (byMember[who] ?? 0) + a;
        }
        return SetAside(byMonth, byMember);
      });

  // ---------- iPhone inbox ----------

  /// Messages posted by the iPhone Shortcut land in
  /// families/{id}/inbox/{token}/items. Any family phone that is open
  /// turns them into transactions and removes them.
  Future<int> processInbox() async {
    final snap = await family.get();
    final tokens = Map<String, dynamic>.from(snap.data()?['inboxTokens'] as Map? ?? {});
    var added = 0;
    for (final e in tokens.entries) {
      final items = await family.collection('inbox').doc(e.key).collection('items').get();
      for (final d in items.docs) {
        final text = d.data()['text'];
        if (text is String) {
          final ok = await ingestSms(text,
              receivedAt: DateTime.now(), member: e.value as String, source: 'iphone');
          if (ok) added++;
        }
        await d.reference.delete();
      }
    }
    return added;
  }
}
