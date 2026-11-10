import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../settings/settings_controller.dart';

/// Short, gentle sound effects (synthesised for the app). Off with one switch in Settings.
class Sfx {
  Sfx(this._ref);
  final Ref _ref;
  AudioPlayer? _player;

  Future<void> _play(String name) async {
    if (!_ref.read(settingsProvider).soundEffects) return;
    try {
      final p = _player ??= AudioPlayer();
      await p.setAsset('assets/sounds/$name.wav');
      await p.seek(Duration.zero);
      await p.play();
    } catch (_) {
      // Sound effects are a nicety; never let them break a lesson.
    }
  }

  void success() => _play('success');
  void oops() => _play('oops');
  void star() => _play('star');
  void levelUp() => _play('levelup');
}

final sfxProvider = Provider<Sfx>((ref) {
  final s = Sfx(ref);
  ref.onDispose(() => s._player?.dispose());
  return s;
});
