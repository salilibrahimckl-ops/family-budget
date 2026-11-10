import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../core/l10n/l10n.dart';
import '../../core/settings/settings_controller.dart';

/// Thin wrapper around the phone's own speech recogniser (Google on Android, Apple on
/// iPhone, the browser's on the web), set to Arabic. Audio is not saved by Hifz Academy.
class ReciteService {
  final SpeechToText _stt = SpeechToText();
  bool _ready = false;
  String? _localeId;

  Future<bool> init() async {
    if (_ready) return true;
    try {
      _ready = await _stt.initialize(onError: (_) {}, onStatus: (_) {});
      if (_ready) {
        final locales = await _stt.locales();
        String? pick(bool Function(String) f) => locales.map((l) => l.localeId).where(f).firstOrNull;
        _localeId = pick((id) => id.replaceAll('-', '_') == 'ar_SA') ?? pick((id) => id.startsWith('ar')) ?? 'ar-SA';
      }
    } catch (_) {
      _ready = false;
    }
    return _ready;
  }

  bool get isListening => _stt.isListening;

  /// Streams what is heard. [onDone] gets the final words and the recogniser's confidence
  /// (-1 when the platform doesn't report one).
  Future<void> listen({
    required void Function(String words) onPartial,
    required void Function(String words, double confidence) onDone,
  }) async {
    var finished = false;
    await _stt.listen(
      localeId: _localeId,
      listenFor: const Duration(seconds: 90),
      pauseFor: const Duration(seconds: 5),
      listenOptions: SpeechListenOptions(partialResults: true, cancelOnError: true, listenMode: ListenMode.dictation),
      onResult: (SpeechRecognitionResult r) {
        onPartial(r.recognizedWords);
        if (r.finalResult && !finished) {
          finished = true;
          onDone(r.recognizedWords, r.hasConfidenceRating ? r.confidence : -1);
        }
      },
    );
  }

  Future<void> stop() => _stt.stop();
}

final reciteServiceProvider = Provider<ReciteService>((ref) => ReciteService());

const _consentKey = 'speech_consent_v1';

/// Asks once before the first use of the microphone and explains where the audio goes.
Future<bool> ensureSpeechConsent(BuildContext context, WidgetRef ref) async {
  final prefs = ref.read(sharedPrefsProvider);
  if (prefs.getBool(_consentKey) == true) return true;
  final l = context.l10n;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      icon: const Icon(Icons.mic),
      title: Text(l.micConsentTitle),
      content: Text(l.micConsentBody),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(l.cancel)),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(l.micConsentAgree)),
      ],
    ),
  );
  if (ok == true) await prefs.setBool(_consentKey, true);
  return ok == true;
}
