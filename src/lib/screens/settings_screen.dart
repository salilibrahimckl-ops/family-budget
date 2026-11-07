import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../repo.dart';
import '../sms_sync.dart';
import 'dev_options_screen.dart';
import 'sms_check_screen.dart';
import '../updater.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.repo, required this.sms, required this.onLeft});
  final Repo repo;
  final SmsSync sms;
  final VoidCallback onLeft;
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Session? _s;
  String? _token;
  bool _scanning = false;
  bool _devMode = false;
  int _taps = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final s = await Session.load();
    final t = await widget.repo.myInboxToken();
    final dev = (await SharedPreferences.getInstance()).getBool('devMode') ?? false;
    final admin = await widget.repo.isAdmin();
    if (mounted) setState(() {
      _s = s;
      _token = t;
      _devMode = dev && admin;
    });
  }

  /// Tap the version 7 times to turn developer mode on (family admin only).
  Future<void> _versionTap() async {
    _taps++;
    if (_devMode || _taps < 7) {
      if (!_devMode && _taps >= 4) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
              duration: const Duration(milliseconds: 700), content: Text('${7 - _taps} more taps…')));
      }
      return;
    }
    _taps = 0;
    final admin = await widget.repo.isAdmin(claimIfUnset: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    if (!admin) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Developer mode is only for the family admin (the person who created the family).')));
      return;
    }
    (await SharedPreferences.getInstance()).setBool('devMode', true);
    setState(() => _devMode = true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Developer mode is on')));
    }
  }

  void _copy(String text, String what) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$what copied')));
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final tt = Theme.of(context).textTheme;
    if (s == null || _token == null) return const Center(child: CircularProgressIndicator());
    final invite = Invite(s.cfg, s.familyId).encode();
    final shortcutUrl = 'https://firestore.googleapis.com/v1/projects/${s.cfg.projectId}'
        '/databases/(default)/documents/families/${s.familyId}/inbox/$_token/items?key=${s.cfg.apiKey}';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Signed in as ${s.myName}', style: tt.titleLarge),
        const SizedBox(height: 20),
        _Section(
          icon: Icons.group_add,
          title: 'Invite your family',
          body: 'On the other phone, install the app, choose "Join family" and paste this code.',
          child: Row(children: [
            Expanded(
              child: Text(invite, maxLines: 2, overflow: TextOverflow.ellipsis, style: tt.bodySmall),
            ),
            IconButton(icon: const Icon(Icons.copy), onPressed: () => _copy(invite, 'Invite code')),
          ]),
        ),
        if (SmsSync.supported)
          _Section(
            icon: Icons.sms_outlined,
            title: 'Bank SMS (Android)',
            body: 'New bank SMS are read automatically. Re-scan if something was missed '
                '(already-added payments are skipped).',
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Check bank SMS'),
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => SmsCheckScreen(sms: widget.sms))),
              ),
              OutlinedButton.icon(
                icon: _scanning
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh),
                label: const Text('Re-scan this month'),
                onPressed: _scanning
                    ? null
                    : () async {
                        setState(() => _scanning = true);
                        final now = DateTime.now();
                        final n = await widget.sms.scan(from: DateTime(now.year, now.month, 1));
                        if (!mounted) return;
                        setState(() => _scanning = false);
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text('Added $n payment(s)')));
                      },
              ),
            ]),
          )
        else
          _Section(
            icon: Icons.bolt,
            title: 'iPhone automation',
            body: 'iPhone apps cannot read SMS, so a Shortcuts automation forwards bank SMS here. '
                'See the setup guide. Use this URL in the "Get Contents of URL" action:',
            child: Row(children: [
              Expanded(
                child: Text(shortcutUrl, maxLines: 3, overflow: TextOverflow.ellipsis, style: tt.bodySmall),
              ),
              IconButton(icon: const Icon(Icons.copy), onPressed: () => _copy(shortcutUrl, 'Shortcut URL')),
            ]),
          ),
        if (Updater.supported) _UpdateSection(),
        if (_devMode)
        Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: const Icon(Icons.developer_mode),
            title: const Text('Developer options'),
            subtitle: const Text('Add and name your own spending categories'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => DevOptionsScreen(repo: widget.repo))),
          ),
        ),
        _Section(
          icon: Icons.logout,
          title: 'Leave on this phone',
          body: 'Removes the family from this phone only. Your data stays in the family. '
              'Rejoin any time with the invite code and the same name.',
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('Leave on this phone?'),
                    content: const Text('Copy the invite code first so you can rejoin.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                      FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Leave')),
                    ],
                  ),
                );
                if (ok == true) widget.onLeft();
              },
              child: const Text('Leave'),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: InkWell(
            onTap: _versionTap,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_devMode ? 'Family Budget 1.1 · developer mode on' : 'Family Budget 1.1',
                  style: tt.bodySmall),
            ),
          ),
        ),
        if (_devMode)
          Center(
            child: TextButton(
              onPressed: () async {
                (await SharedPreferences.getInstance()).setBool('devMode', false);
                setState(() => _devMode = false);
              },
              child: const Text('Turn off developer mode'),
            ),
          ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.icon, required this.title, required this.body, required this.child});
  final IconData icon;
  final String title, body;
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon),
              const SizedBox(width: 8),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
            ]),
            const SizedBox(height: 6),
            Text(body),
            const SizedBox(height: 8),
            child,
          ]),
        ),
      );
}


class _UpdateSection extends StatefulWidget {
  @override
  State<_UpdateSection> createState() => _UpdateSectionState();
}

class _UpdateSectionState extends State<_UpdateSection> {
  int? _current;
  int? _latest;
  bool _checking = false;
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    Updater.currentBuild().then((v) => mounted ? setState(() => _current = v) : null);
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    final l = await Updater.checkForUpdate();
    if (!mounted) return;
    setState(() {
      _latest = l;
      _checking = false;
      _checked = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final has = _latest != null;
    return _Section(
      icon: Icons.system_update,
      title: 'App updates',
      body: 'Installed version: build ${_current ?? '…'}'
          '${_checked ? (has ? '\nNew version available: build $_latest' : '\nYou have the latest version.') : ''}',
      child: Align(
        alignment: Alignment.centerLeft,
        child: has
            ? FilledButton.icon(
                icon: const Icon(Icons.download),
                label: const Text('Update now'),
                onPressed: () => showUpdateDialog(context),
              )
            : OutlinedButton.icon(
                icon: _checking
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh),
                label: const Text('Check for update'),
                onPressed: _checking ? null : _check,
              ),
      ),
    );
  }
}
