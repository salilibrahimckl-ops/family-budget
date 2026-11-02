import 'package:flutter/material.dart';

import '../config.dart';
import '../repo.dart';

/// First launch: create a new family (needs the Firebase config) or join one.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, required this.onDone});
  final ValueChanged<Repo> onDone;
  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  bool _join = true;
  final _name = TextEditingController();
  final _family = TextEditingController(text: 'Our family');
  final _config = TextEditingController();
  final _invite = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final name = _name.text.trim();
      if (name.isEmpty) throw Exception('Enter your name');
      late Session s;
      if (_join) {
        final inv = Invite.decode(_invite.text);
        if (inv == null) throw Exception('That invite code is not valid');
        await ensureFirebase(inv.cfg);
        await Repo.joinFamily(inv.familyId, name);
        s = Session(inv.cfg, inv.familyId, name);
      } else {
        final cfg = FbConfig.fromSnippet(_config.text);
        if (cfg == null) throw Exception('Could not read apiKey / appId / projectId / messagingSenderId');
        await ensureFirebase(cfg);
        final fid = await Repo.createFamily(_family.text.trim(), name);
        s = Session(cfg, fid, name);
      }
      await s.save();
      widget.onDone(Repo(s.familyId, s.myName));
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 24),
            Icon(Icons.account_balance_wallet, size: 56, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text('Family Budget', style: tt.headlineMedium, textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text('UPI payments sorted into your budgets, automatically.',
                style: tt.bodyMedium, textAlign: TextAlign.center),
            const SizedBox(height: 28),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Join family'), icon: Icon(Icons.login)),
                ButtonSegment(value: false, label: Text('Create family'), icon: Icon(Icons.add_home)),
              ],
              selected: {_join},
              onSelectionChanged: (v) => setState(() => _join = v.first),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Your name', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            if (_join)
              TextField(
                controller: _invite,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Invite code',
                  hintText: 'FAMBUDGET-…  (Settings → Invite on the other phone)',
                  border: OutlineInputBorder(),
                ),
              )
            else ...[
              TextField(
                controller: _family,
                decoration: const InputDecoration(labelText: 'Family name', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _config,
                maxLines: 8,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                decoration: const InputDecoration(
                  labelText: 'Firebase config',
                  hintText: 'Paste the  const firebaseConfig = { apiKey: … }  block from the Firebase console',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _go,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: _busy
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_join ? 'Join' : 'Create'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
