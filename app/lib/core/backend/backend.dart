import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase settings come from build flags, never from source code:
///   flutter run --dart-define-from-file=env.json
/// with env.json = {"SUPABASE_URL": "...", "SUPABASE_ANON_KEY": "..."} (git-ignored).
/// The anon key is public by design; row-level security protects the data.
abstract final class BackendConfig {
  static const url = String.fromEnvironment('SUPABASE_URL');
  static const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;
}

Future<void> initBackend() async {
  if (!BackendConfig.isConfigured) return;
  await Supabase.initialize(url: BackendConfig.url, publishableKey: BackendConfig.anonKey);
}

/// Null when the build has no backend configured (app then runs fully offline).
final supabaseProvider = Provider<SupabaseClient?>((ref) =>
    BackendConfig.isConfigured ? Supabase.instance.client : null);

final authUserProvider = StreamProvider<User?>((ref) async* {
  final c = ref.watch(supabaseProvider);
  if (c == null) {
    yield null;
    return;
  }
  yield c.auth.currentUser;
  await for (final s in c.auth.onAuthStateChange) {
    yield s.session?.user;
  }
});
