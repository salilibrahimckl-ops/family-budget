import 'dart:convert';
import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Firebase project details. Entered once by pasting the web config from the
/// Firebase console, then shared with the other phone inside the invite code.
class FbConfig {
  final String apiKey;
  final String appId;
  final String projectId;
  final String senderId;

  const FbConfig(this.apiKey, this.appId, this.projectId, this.senderId);

  FirebaseOptions toOptions() => FirebaseOptions(
        apiKey: apiKey,
        appId: appId,
        projectId: projectId,
        messagingSenderId: senderId,
      );

  Map<String, String> toJson() =>
      {'k': apiKey, 'a': appId, 'p': projectId, 's': senderId};

  static FbConfig fromJson(Map<String, dynamic> j) =>
      FbConfig(j['k'] as String, j['a'] as String, j['p'] as String, j['s'] as String);

  /// Accepts the `const firebaseConfig = { apiKey: "...", ... }` snippet.
  static FbConfig? fromSnippet(String text) {
    String? f(String key) {
      final m = RegExp('$key["\']?\\s*:\\s*["\']([^"\']+)["\']').firstMatch(text);
      return m?.group(1);
    }

    final k = f('apiKey'), a = f('appId'), p = f('projectId'), s = f('messagingSenderId');
    if (k == null || a == null || p == null || s == null) return null;
    return FbConfig(k, a, p, s);
  }
}

/// Built-in cloud project, so anyone who installs the app can start their own
/// family without any setup. Each family's data is private to its members
/// (enforced by the database rules); families never see each other.
const kDefaultConfig = FbConfig(
  'AIzaSyDWChy-rvv4-2LSzWk-yc5UCux5lYc_sFo',
  '1:744181321583:web:7995a9fb5d232f8d41a29a',
  'family-budget-6700e',
  '744181321583',
);

/// Links sent when sharing the app (no personal data in them).
const kApkUrl = 'https://github.com/salilibrahimckl-ops/family-budget/raw/builds-android/FamilyBudget.apk';
const kWebUrl = 'https://salilibrahimckl-ops.github.io/family-budget/';

/// Everything another phone needs to join: Firebase config + family id.
class Invite {
  final FbConfig cfg;
  final String familyId;
  const Invite(this.cfg, this.familyId);

  String encode() {
    final j = {...cfg.toJson(), 'f': familyId};
    return 'FAMBUDGET-${base64Url.encode(utf8.encode(jsonEncode(j)))}';
  }

  static Invite? decode(String code) {
    try {
      var c = code.trim();
      if (c.startsWith('FAMBUDGET-')) c = c.substring(10);
      final j = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(c))))
          as Map<String, dynamic>;
      return Invite(FbConfig.fromJson(j), j['f'] as String);
    } catch (_) {
      return null;
    }
  }
}

/// Locally stored session for this phone.
class Session {
  static const _kCfg = 'fbConfig', _kFid = 'familyId', _kName = 'myName';
  static const _kLastScan = 'lastSmsScanMs';

  final FbConfig cfg;
  final String familyId;
  final String myName;
  const Session(this.cfg, this.familyId, this.myName);

  static Future<Session?> load() async {
    final p = await SharedPreferences.getInstance();
    final c = p.getString(_kCfg), f = p.getString(_kFid), n = p.getString(_kName);
    if (c == null || f == null || n == null) return null;
    return Session(FbConfig.fromJson(jsonDecode(c) as Map<String, dynamic>), f, n);
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kCfg, jsonEncode(cfg.toJson()));
    await p.setString(_kFid, familyId);
    await p.setString(_kName, myName);
  }

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kFid);
    await p.remove(_kName);
    await p.remove(_kLastScan);
  }

  static Future<int?> lastScanMs() async =>
      (await SharedPreferences.getInstance()).getInt(_kLastScan);

  static Future<void> setLastScanMs(int ms) async =>
      (await SharedPreferences.getInstance()).setInt(_kLastScan, ms);
}

Future<void> ensureFirebase(FbConfig cfg) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: cfg.toOptions());
  }
}

String randomToken([int len = 20]) {
  const chars = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final r = Random.secure();
  return List.generate(len, (_) => chars[r.nextInt(chars.length)]).join();
}

String monthKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';
