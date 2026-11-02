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

/// Monthly budget: amount per category + optional personal limit per member.
class Budget {
  final Map<String, double> categories;
  final Map<String, double> members;
  const Budget(this.categories, this.members);

  static Budget fromMap(Map<String, dynamic>? m) {
    Map<String, double> conv(dynamic x) => x is Map
        ? x.map((k, v) => MapEntry(k as String, (v as num).toDouble()))
        : <String, double>{};
    return Budget(conv(m?['categories']), conv(m?['members']));
  }

  Map<String, dynamic> toMap() => {'categories': categories, 'members': members};
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
    final p = SmsParser.parse(body);
    if (p == null) return false;
    final when = p.date != null && source == 'iphone' ? _withTime(p.date!, receivedAt) : receivedAt;
    final id = p.ref != null
        ? 'ref_${p.ref}'
        : 'sms_${receivedAt.millisecondsSinceEpoch ~/ 60000}_${(p.amount * 100).round()}';

    final ref = txns.doc(id);
    if ((await ref.get()).exists) return false;

    final key = Categorizer.payeeKey(p.payee, vpa: p.vpa);
    final rule = (await rules.doc(key).get()).data();
    String category;
    var chittiAsk = false;
    if (rule?['category'] != null) {
      category = rule!['category'] as String;
    } else {
      final g = Categorizer.guess(p.payee, vpa: p.vpa);
      category = g.category;
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
