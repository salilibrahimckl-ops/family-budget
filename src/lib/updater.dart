import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// In-app updates for the Android app. Every GitHub build publishes the APK
/// and a version.json on the builds-android branch; the app compares build
/// numbers and installs the new APK through Android's installer.
class Updater {
  static const _base =
      'https://raw.githubusercontent.com/salilibrahimckl-ops/family-budget/builds-android/';

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<int> currentBuild() async =>
      int.tryParse((await PackageInfo.fromPlatform()).buildNumber) ?? 0;

  /// Newer build number if one is available, else null.
  static Future<int?> checkForUpdate() async {
    if (!supported) return null;
    try {
      final r = await http
          .get(Uri.parse('${_base}version.json?t=${DateTime.now().millisecondsSinceEpoch}'))
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return null;
      final latest = (jsonDecode(r.body)['build'] as num).toInt();
      return latest > await currentBuild() ? latest : null;
    } catch (_) {
      return null;
    }
  }

  static Stream<OtaEvent> _install() =>
      OtaUpdate().execute('${_base}FamilyBudget.apk', destinationFilename: 'FamilyBudget.apk');
}

/// Downloads the update with a progress bar, then opens Android's
/// "Do you want to update this app?" screen.
Future<void> showUpdateDialog(BuildContext context) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _UpdateDialog(),
  );
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog();
  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  double? _progress;
  String _status = 'Starting download…';
  bool _done = false;

  @override
  void initState() {
    super.initState();
    try {
      Updater._install().listen((e) {
        if (!mounted) return;
        setState(() {
          switch (e.status) {
            case OtaStatus.DOWNLOADING:
              _progress = (double.tryParse(e.value ?? '') ?? 0) / 100;
              _status = 'Downloading… ${e.value ?? 0}%';
            case OtaStatus.INSTALLING:
            case OtaStatus.INSTALLATION_DONE:
              _progress = 1;
              _status = 'Tap "Update" on the Android screen to finish.';
              _done = true;
            case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
              _status = 'Android needs permission: allow "Install unknown apps" for Family Budget, then try again.';
              _done = true;
            default:
              _status = 'Update failed (${e.status.name}). Please try again.';
              _done = true;
          }
        });
      }, onError: (Object err) {
        if (mounted) {
          setState(() {
            _status = 'Update failed: $err';
            _done = true;
          });
        }
      });
    } catch (err) {
      _status = 'Update failed: $err';
      _done = true;
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Updating Family Budget'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          LinearProgressIndicator(value: _progress),
          const SizedBox(height: 12),
          Text(_status),
        ]),
        actions: [
          if (_done) TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      );
}
