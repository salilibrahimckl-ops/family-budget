import 'dart:async';
import 'dart:convert';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
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
    this.expectedLen,
    this.heardLen,
    this.rules = const [],
    this.missingRules = const [],
    this.extraRules = const [],
  });
  final int wordStart; // 0-based, in the server's Uthmani words
  final int wordEnd;
  final TeacherErrorType type;
  final String speech; // insert | delete | replace
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
      type: switch (j['type']) { 'tajweed' => TeacherErrorType.tajweed, 'tashkeel' => TeacherErrorType.harakah, _ => TeacherErrorType.word },
      speech: (j['speech'] as String?) ?? 'replace',
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

class TeacherResult {
  const TeacherResult({required this.status, required this.words, required this.errors, required this.confidence});

  /// ok | unclear | too_little | different_ayah | silent
  final String status;
  final List<String> words;
  final List<TeacherError> errors;
  final double confidence;

  bool get assessed => status == 'ok' || status == 'unclear';

  static TeacherResult fromJson(Map<String, dynamic> j) => TeacherResult(
        status: j['status'] as String,
        words: [for (final w in j['words'] as List) w as String],
        errors: [for (final e in j['errors'] as List) TeacherError.fromJson(e as Map<String, dynamic>)],
        confidence: (j['confidence'] as num?)?.toDouble() ?? 0,
      );
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

/// Records the learner and sends the recording to the teacher.
class TeacherClient {
  TeacherClient(this._prefs);
  final SharedPreferences _prefs;
  final _rec = AudioRecorder();
  String _ext = 'wav';

  Future<bool> start() async {
    if (!await _rec.hasPermission()) return false;
    var encoder = AudioEncoder.wav;
    if (!await _rec.isEncoderSupported(encoder)) {
      encoder = await _rec.isEncoderSupported(AudioEncoder.opus) ? AudioEncoder.opus : AudioEncoder.aacLc;
    }
    _ext = switch (encoder) { AudioEncoder.wav => 'wav', AudioEncoder.opus => kIsWeb ? 'webm' : 'ogg', _ => 'm4a' };
    final path = kIsWeb ? '' : '${(await getTemporaryDirectory()).path}/recitation.$_ext';
    await _rec.start(RecordConfig(encoder: encoder, sampleRate: 16000, numChannels: 1), path: path);
    return true;
  }

  Future<Uint8List?> stop() async {
    final path = await _rec.stop();
    if (path == null) return null;
    return XFile(path).readAsBytes();
  }

  Future<void> cancel() async {
    try {
      await _rec.cancel();
    } catch (_) {}
  }

  void dispose() => _rec.dispose();

  /// Sends the recording. While the free server is waking up (it sleeps when unused)
  /// it answers 503; we keep trying for up to ~3 minutes and report progress.
  Future<TeacherResult> check({
    required String baseUrl,
    required Uint8List audio,
    required int sura,
    required int aya,
    void Function(bool wakingUp)? onStatus,
  }) async {
    final deadline = DateTime.now().add(const Duration(minutes: 3));
    while (true) {
      final req = http.MultipartRequest('POST', Uri.parse('$baseUrl/check'))
        ..headers.addAll(teacherHeaders(_prefs))
        ..fields['sura'] = '$sura'
        ..fields['aya'] = '$aya'
        ..files.add(http.MultipartFile.fromBytes('file', audio, filename: 'recitation.$_ext'));
      http.Response r;
      try {
        r = await http.Response.fromStream(await req.send().timeout(const Duration(seconds: 150)));
      } on TimeoutException {
        throw const TeacherUnavailable('timeout');
      } catch (_) {
        if (DateTime.now().isAfter(deadline)) throw const TeacherUnavailable('offline');
        onStatus?.call(true);
        await Future<void>.delayed(const Duration(seconds: 8));
        continue;
      }
      if (r.statusCode == 200) return TeacherResult.fromJson(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
      if ((r.statusCode == 503 || r.statusCode == 502 || r.statusCode == 504) && DateTime.now().isBefore(deadline)) {
        onStatus?.call(true);
        await Future<void>.delayed(const Duration(seconds: 8));
        continue;
      }
      if (r.statusCode == 429) {
        String reason = 'daily_limit';
        try {
          reason = ((jsonDecode(r.body) as Map<String, dynamic>)['detail'] as Map<String, dynamic>)['reason'] as String;
        } catch (_) {}
        throw TeacherUnavailable(reason);
      }
      throw TeacherUnavailable('http ${r.statusCode}');
    }
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
