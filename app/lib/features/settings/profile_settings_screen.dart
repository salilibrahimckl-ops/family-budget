import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/backend/backend.dart';
import '../../core/backend/sync_service.dart';
import '../../core/design/tokens.dart';
import '../../core/l10n/l10n.dart';
import '../../core/settings/settings_controller.dart';
import '../onboarding/onboarding_store.dart';

/// Me tab: account and sync, language, theme, assessment, data rights, sources.
class ProfileSettingsScreen extends ConsumerStatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  ConsumerState<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends ConsumerState<ProfileSettingsScreen> {
  bool _syncing = false;
  String? _syncMsg;

  Future<void> _sync() async {
    setState(() => _syncing = true);
    try {
      final r = await ref.read(syncServiceProvider).syncNow();
      if (mounted) setState(() => _syncMsg = context.l10n.syncDone(r.pushed, r.pulled));
    } catch (_) {
      if (mounted) setState(() => _syncMsg = context.l10n.authNetworkError);
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _confirmDelete() async {
    final l = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l.deleteTitle),
        content: Text(l.deleteBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(l.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error),
            onPressed: () => Navigator.pop(c, true),
            child: Text(l.deleteConfirm),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(syncServiceProvider).deleteAccount();
    if (mounted) context.go('/onboarding');
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final s = ref.watch(settingsProvider);
    final ctrl = ref.read(settingsProvider.notifier);
    final user = ref.watch(authUserProvider).valueOrNull;
    final backend = ref.watch(supabaseProvider);
    final t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: Text(l.settings)),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: HSpace.l, vertical: HSpace.s),
        children: [
          if (backend != null) ...[
            if (user == null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.cloud_outlined),
                title: Text(l.signInToSync),
                subtitle: Text(l.signInToSyncSub),
                onTap: () => context.push('/auth'),
              )
            else ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.cloud_done_outlined),
                title: Text(user.email ?? ''),
                subtitle: _syncMsg == null ? null : Text(_syncMsg!),
                trailing: _syncing
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : IconButton(icon: const Icon(Icons.sync), tooltip: l.syncNow, onPressed: _sync),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.logout),
                title: Text(l.signOut),
                onTap: () => backend.auth.signOut(),
              ),
            ],
            const Divider(),
          ],
          Text(l.settingsLanguage, style: t.titleSmall),
          const SizedBox(height: HSpace.s),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'en', label: Text('English')),
              ButtonSegment(value: 'ml', label: Text('മലയാളം')),
              ButtonSegment(value: 'ar', label: Text('العربية')),
            ],
            selected: {s.locale.languageCode},
            onSelectionChanged: (v) => ctrl.setLocale(Locale(v.first)),
          ),
          const SizedBox(height: HSpace.l),
          Text(l.settingsTheme, style: t.titleSmall),
          const SizedBox(height: HSpace.s),
          SegmentedButton<ThemeMode>(
            segments: [
              ButtonSegment(value: ThemeMode.system, label: Text(l.themeSystem)),
              ButtonSegment(value: ThemeMode.light, label: Text(l.themeLight)),
              ButtonSegment(value: ThemeMode.dark, label: Text(l.themeDark)),
            ],
            selected: {s.themeMode},
            onSelectionChanged: (v) => ctrl.setThemeMode(v.first),
          ),
          const SizedBox(height: HSpace.l),
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.restart_alt),
            title: Text(l.resetPlan),
            onTap: () async {
              await ref.read(onboardingProvider.notifier).clear();
              if (context.mounted) context.go('/onboarding');
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.info_outline),
            title: Text(l.about),
            subtitle: Text(l.quranSource),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.delete_forever_outlined, color: Theme.of(context).colorScheme.error),
            title: Text(user == null ? l.deleteLocalData : l.deleteAccount),
            onTap: _confirmDelete,
          ),
        ],
      ),
    );
  }
}
