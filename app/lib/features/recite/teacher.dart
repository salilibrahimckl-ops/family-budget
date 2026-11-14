import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../core/l10n/l10n.dart';
import '../../core/settings/settings_controller.dart';
import '../updates/updates.dart';

/// The AI recitation teacher: the open-source Quran Muaalem model, run on our own free
/// Hugging Face Space (see /server). It hears the recitation as Quran phonetic script and
/// compares it with the verified Ayah: words, letters, harakat and Tajweed.
///
/// Its address is published next to the app builds (server.json), so it can move without
/// an app update. null = not set up yet; the app then uses the phone's speech recogniser.
final teacherUrlProvider = FutureProvider<String?>((ref) async {
  final prefs = ref.read(sharedPrefsProvider);
  try {
    final r = await http
        .get(Uri.parse('${Updater.base}server.json?t=${DateTime.now().millisecondsSinceEpoch ~/ 600000}'))
        .timeout(const Duration(seconds: 8));
    if (r.statusCode == 200) {
      final url = (jsonDecode(r.body) as Map<String, dynamic>)['teacher_url'] as String?;
      if (url != null && url.startsWith('https://')) {
        await prefs.setString('teacher_url', url);
        return url;
      }
    }
  } catch (_) {}
  return prefs.getString('teacher_url');
});

enum TeacherErrorType { word, harakah, tajweed }

class TeacherRule {
  const TeacherRule({required this.kind, this.tag, required this.ar, required this.en, this.goldenLen});
  final String kind; // e.g. LazemMaddRule, Qalqalah, Ghonnah
  final String? tag;
  final String ar;
  final String en;
  final int? goldenLen;

  static TeacherRule fromJson(Map<String, dynamic> j) => TeacherRule(
        kind: (j['kind'] as String?) ?? '',
        tag: j['tag'] as String?,
        ar: (j['ar'] as String?) ?? '',
        en: (j['en'] as String?) ?? '',
        goldenLen: (j['golden_len'] as num?)?.toInt(),
      );
}

class TeacherError {
  const TeacherError({
    required this.wordStart,
    required this.wordEnd,
    required this.type,
    required this.speech,
    required this.expected,
    required this.heard,
    this.mistake = true,
    this.expectedLen,
    this.heardLen,
    this.rules = const [],
    this.missingRules = const [],
    this.extraRules = const [],
  });
  final int wordStart; // 0-based, in the Ayah's Uthmani words
  final int wordEnd;
  final TeacherErrorType type;
  final String speech; // insert | delete | replace

  /// true = a real mistake; false = a tip (shown softly, never counted against you).
  final bool mistake;
  final String expected; // Quran phonetic script
  final String heard;
  final int? expectedLen;
  final int? heardLen;
  final List<TeacherRule> rules;
  final List<TeacherRule> missingRules;
  final List<TeacherRule> extraRules;

  static TeacherError fromJson(Map<String, dynamic> j) {
    List<TeacherRule> rules(String k) =>
        [for (final r in (j[k] as List? ?? const [])) TeacherRule.fromJson(r as Map<String, dynamic>)];
    return TeacherError(
      wordStart: (j['word_start'] as num).toInt(),
      wordEnd: (j['word_end'] as num).toInt(),
      type: switch (j['type']) {
        'tajweed' => TeacherErrorType.tajweed,
        'tashkeel' || 'harakah' => TeacherErrorType.harakah,
        _ => TeacherErrorType.word,
      },
      speech: (j['speech'] as String?) ?? 'replace',
      mistake: (j['severity'] as String? ?? 'mistake') == 'mistake',
      expected: (j['expected'] as String?) ?? '',
      heard: (j['heard'] as String?) ?? '',
      expectedLen: (j['expected_len'] as num?)?.toInt(),
      heardLen: (j['heard_len'] as num?)?.toInt(),
      rules: rules('rules'),
      missingRules: rules('missing_rules'),
      extraRules: rules('extra_rules'),
    );
  }
}

/// The teacher's findings for one Ayah.
class AyahReport {
  const AyahReport({required this.aya, required this.words, required this.recited, required this.errors});
  final int aya;
  final List<String> words;
  final bool recited; // false = the learner stopped before reaching this Ayah
  final List<TeacherError> errors;

  Iterable<TeacherError> get mistakes => errors.where((e) => e.mistake);
  Iterable<TeacherError> get tips => errors.where((e) => !e.mistake);

  /// Word mistakes only: what counts for memorisation. Tajweed and pronunciation are
  /// shown and practised, but never cost you a revision.
  Iterable<TeacherError> get wordMistakes => mistakes.where((e) => e.type == TeacherErrorType.word);

  static AyahReport fromJson(Map<String, dynamic> j) => AyahReport(
        aya: (j['aya'] as num).toInt(),
        words: [for (final w in j['words'] as List) w as String],
        recited: j['status'] != 'not_recited',
        errors: [for (final e in j['errors'] as List) TeacherError.fromJson(e as Map<String, dynamic>)],
      );
}

class TeacherResult {
  const TeacherResult({required this.status, required this.ayahs, required this.confidence});

  /// ok | unclear | too_little | different_ayah | silent
  final String status;
  final List<AyahReport> ayahs;
  final double confidence;

  bool get assessed => status == 'ok' || status == 'unclear';
  AyahReport get first => ayahs.first;

  // One-Ayah views (lessons and revision).
  List<String> get words => first.words;
  List<TeacherError> get errors => first.errors;

  static TeacherResult fromJson(Map<String, dynamic> j) {
    final ayahs = j['ayahs'] is List
        ? [for (final a in j['ayahs'] as List) AyahReport.fromJson(a as Map<String, dynamic>)]
        : [
            AyahReport(
              aya: (j['aya'] as num?)?.toInt() ?? 0,
              words: [for (final w in j['words'] as List) w as String],
              recited: true,
              errors: [for (final e in j['errors'] as List) TeacherError.fromJson(e as Map<String, dynamic>)],
            ),
          ];
    return TeacherResult(status: j['status'] as String, ayahs: ayahs, confidence: (j['confidence'] as num?)?.toDouble() ?? 0);
  }
}

/// Sent with every check so the teacher can share its free credit fairly (see /server).
const _appHeader = 'hifz-academy-app-v1';

String deviceId(SharedPreferences prefs) {
  var id = prefs.getString('device_id');
  if (id == null) {
    id = const Uuid().v4();
    prefs.setString('device_id', id);
  }
  return id;
}

const familyCodeKey = 'family_code';

Map<String, String> teacherHeaders(SharedPreferences prefs) => {
      'X-Hifz-App': _appHeader,
      'X-Hifz-Device': deviceId(prefs),
      if (prefs.getString(familyCodeKey) != null) 'X-Hifz-Family': prefs.getString(familyCodeKey)!,
    };

/// Asks the teacher whether a family code is right (doesn't use a check).
Future<bool> verifyFamilyCode(String baseUrl, String code) async {
  final r = await http
      .get(Uri.parse('$baseUrl/family'), headers: {'X-Hifz-Family': code.trim().toUpperCase()})
      .timeout(const Duration(seconds: 90));
  return r.statusCode == 200 && (jsonDecode(r.body) as Map<String, dynamic>)['family'] == true;
}

class TeacherUnavailable implements Exception {
  const TeacherUnavailable(this.reason);
  final String reason;
}

/// Records the learner and streams the recitation to the teacher while they recite, so
/// the teacher has heard and checked almost everything by the time they tap "I'm done".
/// The phone's own noise suppression is switched on, and the teacher's voice detector
/// skips background sounds and silences. If streaming fails, the whole recording is
/// sent in one go instead.
class TeacherClient {
  TeacherClient(this._prefs);
  final SharedPreferences _prefs;
  final _rec = AudioRecorder();

  String? _base;
  String? _session;
  int _seq = 0;
  bool _streamOk = true;
  final _pending = BytesBuilder(copy: false);
  final _all = BytesBuilder(copy: false);
  StreamSubscription<Uint8List>? _sub;
  Timer? _flush;
  Future<void> _sending = Future.value();
  late int _sura, _from, _to;
  late bool _strict;

  /// How long the learner has been reciting.
  Duration get elapsed => Duration(milliseconds: _all.length ~/ 32);

  /// Starts listening for Ayahs [from]..[to] of [sura]. Returns false without microphone
  /// permission.
  Future<bool> start({
    required String baseUrl,
    required int sura,
    required int from,
    required int to,
    required bool strict,
  }) async {
    if (!await _rec.hasPermission()) return false;
    _base = baseUrl;
    _sura = sura;
    _from = from;
    _to = to;
    _strict = strict;
    _seq = 0;
    _streamOk = true;
    _session = null;
    _all.clear();
    _pending.clear();
    const config = RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: 16000,
      numChannels: 1,
      noiseSuppress: true,
      autoGain: true,
      echoCancel: true,
    );
    final stream = await _rec.startStream(config);
    _sub = stream.listen((b) {
      _all.add(b);
      _pending.add(b);
    });
    // Open the session while the learner starts reciting.
    _openSession().ignore();
    _flush = Timer.periodic(const Duration(seconds: 2), (_) => _send());
    return true;
  }

  Future<void> _openSession() async {
    try {
      final r = await http.post(
        Uri.parse('$_base/session'),
        headers: teacherHeaders(_prefs),
        body: {'sura': '$_sura', 'aya_from': '$_from', 'aya_to': '$_to', 'strict': '$_strict'},
      ).timeout(const Duration(seconds: 60));
      if (r.statusCode == 200) {
        _session = (jsonDecode(r.body) as Map<String, dynamic>)['id'] as String;
      } else {
        _streamOk = false;
        _startError = r;
      }
    } catch (_) {
      _streamOk = false;
    }
  }

  http.Response? _startError;

  void _send() {
    if (!_streamOk || _session == null || _pending.isEmpty) return;
    final chunk = _pending.takeBytes();
    final seq = _seq++;
    _sending = _sending.then((_) async {
      if (!_streamOk) return;
      try {
        final r = await http
            .post(Uri.parse('$_base/session/$_session/audio?seq=$seq'),
                headers: {'Content-Type': 'application/octet-stream'}, body: chunk)
            .timeout(const Duration(seconds: 30));
        if (r.statusCode != 200) _streamOk = false;
      } catch (_) {
        _streamOk = false;
      }
    });
  }

  /// Stops listening and returns the teacher's report.
  Future<TeacherResult> finish({void Function(bool wakingUp)? onStatus}) async {
    _flush?.cancel();
    await _rec.stop();
    await _sub?.cancel();
    final err = _startError;
    if (err != null && err.statusCode == 429) throw TeacherUnavailable(_reason(err));
    // Give the session a moment to open if the learner was very quick.
    for (var i = 0; i < 50 && _session == null && _streamOk; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    _send();
    await _sending;
    if (_streamOk && _session != null && _seq > 0) {
      try {
        final r = await http
            .post(Uri.parse('$_base/session/$_session/finish?last_seq=${_seq - 1}'))
            .timeout(const Duration(seconds: 150));
        if (r.statusCode == 200) return _parse(r);
      } catch (_) {}
    }
    // Fall back: send everything at once.
    return _checkWhole(onStatus: onStatus);
  }

  Future<void> cancel() async {
    _flush?.cancel();
    try {
      await _rec.cancel();
    } catch (_) {}
    await _sub?.cancel();
  }

  void dispose() {
    _flush?.cancel();
    _rec.dispose();
  }

  TeacherResult _parse(http.Response r) =>
      TeacherResult.fromJson(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);

  String _reason(http.Response r) {
    try {
      return ((jsonDecode(r.body) as Map<String, dynamic>)['detail'] as Map<String, dynamic>)['reason'] as String;
    } catch (_) {
      return 'daily_limit';
    }
  }

  Future<TeacherResult> _checkWhole({void Function(bool wakingUp)? onStatus}) async {
    final audio = _wav(_all.toBytes());
    final deadline = DateTime.now().add(const Duration(minutes: 3));
    while (true) {
      final req = http.MultipartRequest('POST', Uri.parse('$_base/check'))
        ..headers.addAll(teacherHeaders(_prefs))
        ..fields['sura'] = '$_sura'
        ..fields['aya_from'] = '$_from'
        ..fields['aya_to'] = '$_to'
        ..fields['strict'] = '$_strict'
        ..files.add(http.MultipartFile.fromBytes('file', audio, filename: 'recitation.wav'));
      http.Response r;
      try {
        r = await http.Response.fromStream(await req.send().timeout(const Duration(seconds: 150)));
      } on TimeoutException {
        throw const TeacherUnavailable('timeout');
      } catch (_) {
        if (DateTime.now().isAfter(deadline)) throw const TeacherUnavailable('offline');
        onStatus?.call(true);
        await Future<void>.delayed(const Duration(seconds: 5));
        continue;
      }
      if (r.statusCode == 200) return _parse(r);
      if ((r.statusCode == 503 || r.statusCode == 502 || r.statusCode == 504) && DateTime.now().isBefore(deadline)) {
        onStatus?.call(true);
        await Future<void>.delayed(const Duration(seconds: 5));
        continue;
      }
      if (r.statusCode == 429) throw TeacherUnavailable(_reason(r));
      throw TeacherUnavailable('http ${r.statusCode}');
    }
  }

  /// 16 kHz 16-bit mono PCM wrapped as a WAV file.
  static Uint8List _wav(Uint8List pcm) {
    final b = ByteData(44);
    void str(int o, String v) {
      for (var i = 0; i < v.length; i++) {
        b.setUint8(o + i, v.codeUnitAt(i));
      }
    }

    str(0, 'RIFF');
    b.setUint32(4, 36 + pcm.length, Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    b.setUint32(16, 16, Endian.little);
    b.setUint16(20, 1, Endian.little);
    b.setUint16(22, 1, Endian.little);
    b.setUint32(24, 16000, Endian.little);
    b.setUint32(28, 32000, Endian.little);
    b.setUint16(32, 2, Endian.little);
    b.setUint16(34, 16, Endian.little);
    str(36, 'data');
    b.setUint32(40, pcm.length, Endian.little);
    return (BytesBuilder()
          ..add(b.buffer.asUint8List())
          ..add(pcm))
        .toBytes();
  }
}

/// Wakes the free server as soon as a lesson opens, so it's ready by the time the
/// learner recites.
void warmUpTeacher(String url) {
  http.get(Uri.parse('$url/health')).timeout(const Duration(seconds: 20)).ignore();
}

const _noticeKey = 'teacher_notice_v1';

/// The AI advisory notice (required by the Quran Muaalem License): shown before first use,
/// in the app language and always also in Arabic. Also reachable from Me → About.
Future<bool> ensureTeacherNotice(BuildContext context, WidgetRef ref) async {
  final prefs = ref.read(sharedPrefsProvider);
  if (prefs.getBool(_noticeKey) == true) return true;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      icon: const Icon(Icons.school),
      title: Text(c.l10n.teacherTitle),
      content: SingleChildScrollView(child: TeacherNotice(intro: c.l10n.teacherConsent)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(c.l10n.cancel)),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(c.l10n.micConsentAgree)),
      ],
    ),
  );
  if (ok == true) await prefs.setBool(_noticeKey, true);
  return ok == true;
}

class TeacherNotice extends StatelessWidget {
  const TeacherNotice({super.key, this.intro});
  final String? intro;

  static const arabic = 'هذا المعلّم القرآني نموذج ذكاء اصطناعي قد يخطئ؛ فهو للإعانة فقط ولا يُعتمد عليه، '
      'وليس بديلاً عن معلّمٍ مُتقِنٍ مُجاز؛ لأنّ القرآن لا يُؤخذ إلا بالمشافهة.';

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (intro != null) ...[Text(intro!, style: t.bodyMedium), const SizedBox(height: 12)],
      if (!isAr) ...[Text(l.teacherNotice, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)), const SizedBox(height: 8)],
      Text(arabic, textDirection: TextDirection.rtl, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
      const SizedBox(height: 12),
      Text(l.teacherCredit, style: t.bodySmall),
    ]);
  }
}
