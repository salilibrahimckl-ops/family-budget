import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../quran/quran_repository.dart';
import '../settings/settings_controller.dart';

/// A reciter whose verse-by-verse recordings are streamed from EveryAyah.com.
/// Files are named by Surah and Ayah (001001.mp3 = 1:1), so each file is matched to
/// exactly one verified Ayah by its number. All folder names were checked to exist.
class Reciter {
  const Reciter(this.id, this.nameEn, this.nameAr, this.style);
  final String id;
  final String nameEn;
  final String nameAr;
  final String style; // 'muallim' (teaching), 'murattal', 'mujawwad'

  String urlFor(int surah, int ayah) =>
      'https://everyayah.com/data/$id/${surah.toString().padLeft(3, '0')}${ayah.toString().padLeft(3, '0')}.mp3';
}

const reciters = <Reciter>[
  Reciter('Husary_Muallim_128kbps', 'Mahmoud Khalil Al-Husary (teaching)', 'محمود خليل الحصري (المعلم)', 'muallim'),
  Reciter('Minshawy_Teacher_128kbps', 'Mohamed Siddiq Al-Minshawy (teaching)', 'محمد صديق المنشاوي (المعلم)', 'muallim'),
  Reciter('Alafasy_128kbps', 'Mishary Rashid Alafasy', 'مشاري راشد العفاسي', 'murattal'),
  Reciter('Husary_128kbps', 'Mahmoud Khalil Al-Husary', 'محمود خليل الحصري', 'murattal'),
  Reciter('Minshawy_Murattal_128kbps', 'Mohamed Siddiq Al-Minshawy', 'محمد صديق المنشاوي', 'murattal'),
  Reciter('Abdul_Basit_Murattal_192kbps', 'Abdul Basit Abdus Samad', 'عبد الباسط عبد الصمد', 'murattal'),
  Reciter('Abdurrahmaan_As-Sudais_192kbps', 'Abdur-Rahman As-Sudais', 'عبد الرحمن السديس', 'murattal'),
  Reciter('Saood_ash-Shuraym_128kbps', 'Saud Ash-Shuraym', 'سعود الشريم', 'murattal'),
  Reciter('MaherAlMuaiqly128kbps', 'Maher Al-Muaiqly', 'ماهر المعيقلي', 'murattal'),
  Reciter('Abu_Bakr_Ash-Shaatree_128kbps', 'Abu Bakr Ash-Shatri', 'أبو بكر الشاطري', 'murattal'),
  Reciter('Hudhaify_128kbps', 'Ali Al-Hudhaify', 'علي الحذيفي', 'murattal'),
  Reciter('Muhammad_Ayyoub_128kbps', 'Muhammad Ayyub', 'محمد أيوب', 'murattal'),
];

Reciter reciterById(String id) => reciters.firstWhere((r) => r.id == id, orElse: () => reciters.first);

@immutable
class PlaybackState {
  const PlaybackState({this.ayahId, this.playing = false, this.loading = false, this.error = false, this.round = 0, this.rounds = 1});
  final int? ayahId; // Ayah currently loaded
  final bool playing;
  final bool loading;
  final bool error;
  final int round; // 1-based repetition of the current Ayah
  final int rounds;
}

/// Plays one Ayah or a run of Ayahs, each repeated [repeatEach] times, with the
/// chosen reciter and speed. One player for the whole app.
class AudioController extends Notifier<PlaybackState> {
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<PlayerState>? _sub;
  List<VerifiedAyah> _queue = const [];
  int _index = 0;
  int _repeat = 1;
  int _round = 1;
  Reciter _reciter = reciters.first;

  @override
  PlaybackState build() {
    _sub = _player.playerStateStream.listen(_onPlayerState, onError: (_) => state = const PlaybackState(error: true));
    ref.onDispose(() {
      _sub?.cancel();
      _player.dispose();
    });
    return const PlaybackState();
  }

  void _onPlayerState(PlayerState ps) {
    if (_queue.isEmpty) return;
    if (ps.processingState == ProcessingState.completed) {
      _advance();
      return;
    }
    final loading = ps.processingState == ProcessingState.loading || ps.processingState == ProcessingState.buffering;
    state = PlaybackState(
      ayahId: _queue[_index].id,
      playing: ps.playing,
      loading: loading,
      round: _round,
      rounds: _repeat,
    );
  }

  /// Plays [ayahs] in order, each [repeatEach] times. [reciterId] overrides the setting
  /// (used for the preview buttons in setup).
  Future<void> play(List<VerifiedAyah> ayahs, {int repeatEach = 1, String? reciterId}) async {
    if (ayahs.isEmpty) return;
    final s = ref.read(settingsProvider);
    _reciter = reciterById(reciterId ?? s.reciterId);
    _queue = ayahs;
    _index = 0;
    _repeat = repeatEach.clamp(1, 20);
    _round = 1;
    await _player.setSpeed(s.speed);
    await _load();
  }

  Future<void> _load() async {
    final a = _queue[_index];
    state = PlaybackState(ayahId: a.id, loading: true, round: _round, rounds: _repeat);
    try {
      await _player.setUrl(_reciter.urlFor(a.surah, a.ayah));
      unawaited(_player.play());
    } catch (_) {
      state = PlaybackState(ayahId: a.id, error: true);
    }
  }

  Future<void> _advance() async {
    if (_round < _repeat) {
      _round++;
      await _player.seek(Duration.zero);
      unawaited(_player.play());
      return;
    }
    _round = 1;
    _index++;
    if (_index < _queue.length) {
      await _load();
    } else {
      await stop();
    }
  }

  Future<void> pause() => _player.pause();

  Future<void> resume() async => unawaited(_player.play());

  Future<void> stop() async {
    final wasActive = _queue.isNotEmpty;
    _queue = const [];
    if (wasActive) {
      try {
        await _player.stop();
      } catch (_) {}
    }
    state = const PlaybackState();
  }

  Future<void> setSpeed(double s) => _player.setSpeed(s);
}

final audioProvider = NotifierProvider<AudioController, PlaybackState>(AudioController.new);
