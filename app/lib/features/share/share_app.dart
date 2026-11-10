import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/l10n/l10n.dart';
import '../updates/updates.dart';

const webAppUrl = 'https://salilibrahimckl-ops.github.io/family-budget/hifz/';
const apkUrl = '${Updater.base}HifzAcademy.apk';

/// Opens the phone's share sheet (WhatsApp, Telegram, SMS…) with links to the app:
/// the Android download and the web app, which works on iPhone and any browser.
Future<void> shareApp(BuildContext context) async {
  final l = context.l10n;
  final box = context.findRenderObject() as RenderBox?;
  await Share.share(
    l.shareText(apkUrl, webAppUrl),
    subject: l.appTitle,
    sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
  );
}

class ShareAppButton extends StatelessWidget {
  const ShareAppButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: context.l10n.shareApp,
        icon: const Icon(Icons.share),
        onPressed: () => shareApp(context),
      );
}
