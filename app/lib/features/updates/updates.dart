import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/design/tokens.dart';
import '../../core/l10n/l10n.dart';
import '../../core/platform/reload.dart';
import '../../core/settings/settings_controller.dart';

/// Every GitHub build publishes HifzAcademy.apk and version.json on the hifz-builds
/// branch. The Android app compares build numbers and installs the new APK through
/// Android's own "Update this app?" screen. The web app updates itself on reload.
class UpdateInfo {
  const UpdateInfo({required this.build, required this.version, required this.notes});
  final int build;
  final String version;
  final List<String> notes;
}

abstract final class Updater {
  static const base = 'https://raw.githubusercontent.com/salilibrahimckl-ops/family-budget/hifz-builds/';

  static bool get isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<PackageInfo> current() => PackageInfo.fromPlatform();

  /// The published build, or null if it can't be reached.
  static Future<UpdateInfo?> latest() async {
    try {
      final r = await http
          .get(Uri.parse('${base}version.json?t=${DateTime.now().millisecondsSinceEpoch}'))
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return null;
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      return UpdateInfo(
        build: (j['build'] as num).toInt(),
        version: j['version'] as String? ?? '',
        notes: (j['notes'] as List? ?? const []).cast<String>(),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<UpdateInfo?> availableUpdate() async {
    final l = await latest();
    if (l == null) return null;
    final cur = int.tryParse((await current()).buildNumber) ?? 0;
    return l.build > cur ? l : null;
  }

  static Stream<OtaEvent> installApk() =>
      OtaUpdate().execute('${base}HifzAcademy.apk', destinationFilename: 'HifzAcademy.apk');
}

/// Android only: checks quietly at startup; the dashboard shows a banner when this is non-null.
final availableUpdateProvider = FutureProvider<UpdateInfo?>((ref) async =>
    Updater.isAndroid || kIsWeb ? Updater.availableUpdate() : null);

/// Bundled "What's new" list (assets/changelog.json), newest first.
final changelogProvider = FutureProvider<List<({String version, List<String> notes})>>((ref) async {
  try {
    final raw = jsonDecode(await rootBundle.loadString('assets/changelog.json')) as List;
    return [
      for (final e in raw.cast<Map<String, dynamic>>())
        (version: e['version'] as String, notes: (e['notes'] as List).cast<String>()),
    ];
  } catch (_) {
    return const [];
  }
});

/// Shows "What's new" once after the app is updated to a new version.
Future<void> maybeShowWhatsNew(BuildContext context, WidgetRef ref) async {
  final prefs = ref.read(sharedPrefsProvider);
  final version = (await Updater.current()).version;
  final seen = prefs.getString('whats_new_seen');
  if (seen == version) return;
  await prefs.setString('whats_new_seen', version);
  if (seen == null) return; // first install: the onboarding introduces the app instead
  final log = await ref.read(changelogProvider.future);
  if (log.isEmpty || !context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (c) => _WhatsNew(entries: log.take(1).toList()),
  );
}

class _WhatsNew extends StatelessWidget {
  const _WhatsNew({required this.entries});
  final List<({String version, List<String> notes})> entries;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(HSpace.l, 0, HSpace.l, HSpace.l),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(context.l10n.whatsNew, style: t.headlineSmall),
          const SizedBox(height: HSpace.m),
          for (final e in entries)
            for (final n in e.notes)
              Padding(
                padding: const EdgeInsets.only(bottom: HSpace.s),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('✨  '),
                  Expanded(child: Text(n, style: t.bodyLarge)),
                ]),
              ),
          const SizedBox(height: HSpace.m),
          FilledButton(onPressed: () => Navigator.pop(context), child: Text(context.l10n.continueLabel)),
        ]),
      ),
    );
  }
}

/// Me → App updates: current version, check for updates, install, and the full changelog.
class UpdatesScreen extends ConsumerStatefulWidget {
  const UpdatesScreen({super.key});

  @override
  ConsumerState<UpdatesScreen> createState() => _UpdatesScreenState();
}

class _UpdatesScreenState extends ConsumerState<UpdatesScreen> {
  bool _checking = false;
  UpdateInfo? _latest;
  bool _checked = false;
  double? _progress;
  String? _status;

  Future<void> _check() async {
    setState(() => _checking = true);
    final l = await Updater.latest();
    if (!mounted) return;
    setState(() {
      _latest = l;
      _checked = true;
      _checking = false;
    });
  }

  void _install() {
    final l = context.l10n;
    setState(() => _status = l.updateDownloading(0));
    Updater.installApk().listen((e) {
      if (!mounted) return;
      setState(() {
        switch (e.status) {
          case OtaStatus.DOWNLOADING:
            final pct = int.tryParse(e.value ?? '') ?? 0;
            _progress = pct / 100;
            _status = l.updateDownloading(pct);
          case OtaStatus.INSTALLING:
          case OtaStatus.INSTALLATION_DONE:
            _progress = 1;
            _status = l.updateTapInstall;
          case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
            _status = l.updatePermission;
          default:
            _status = l.updateFailed;
        }
      });
    }, onError: (Object _) {
      if (mounted) setState(() => _status = l.updateFailed);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final log = ref.watch(changelogProvider).valueOrNull ?? const [];
    return Scaffold(
      appBar: AppBar(title: Text(l.appUpdates)),
      body: FutureBuilder<PackageInfo>(
        future: Updater.current(),
        builder: (context, snap) {
          final info = snap.data;
          final curBuild = int.tryParse(info?.buildNumber ?? '') ?? 0;
          final newer = _latest != null && _latest!.build > curBuild;
          return ListView(padding: const EdgeInsets.all(HSpace.l), children: [
            Text(l.currentVersion(info?.version ?? '…', info?.buildNumber ?? '…'), style: t.titleMedium),
            const SizedBox(height: HSpace.m),
            if (_status != null) ...[
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: HSpace.s),
              Text(_status!, style: t.bodyMedium),
              const SizedBox(height: HSpace.m),
            ],
            if (newer) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(HSpace.m),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(l.updateAvailable(_latest!.version), style: t.titleMedium),
                    const SizedBox(height: HSpace.s),
                    for (final n in _latest!.notes) Text('✨  $n'),
                  ]),
                ),
              ),
              const SizedBox(height: HSpace.m),
              if (Updater.isAndroid)
                FilledButton.icon(icon: const Icon(Icons.system_update), label: Text(l.updateNow), onPressed: _status == null ? _install : null)
              else if (kIsWeb)
                FilledButton.icon(icon: const Icon(Icons.refresh), label: Text(l.updateNow), onPressed: reloadPage),
            ] else ...[
              FilledButton.icon(
                icon: _checking
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.sync),
                label: Text(l.checkForUpdates),
                onPressed: _checking ? null : _check,
              ),
              if (_checked) ...[
                const SizedBox(height: HSpace.s),
                Text(_latest == null ? l.updateOffline : l.upToDate, style: t.bodyMedium, textAlign: TextAlign.center),
              ],
            ],
            const SizedBox(height: HSpace.xl),
            Text(l.whatsNew, style: t.titleLarge),
            for (final e in log) ...[
              const SizedBox(height: HSpace.m),
              Text(e.version, style: t.titleSmall),
              for (final n in e.notes) Padding(padding: const EdgeInsets.only(top: 4), child: Text('•  $n')),
            ],
          ]);
        },
      ),
    );
  }
}
