import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/backend/backend.dart';
import '../../core/backend/sync_service.dart';
import '../../core/design/tokens.dart';
import '../../core/l10n/l10n.dart';
import '../../core/widgets/widgets.dart';

/// Email sign-in with a 6-digit code. No password to remember; works the same on Android and iPhone.
/// The app is fully usable without an account; signing in adds backup and sync between devices.
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() f) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await f();
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = context.l10n.authNetworkError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final client = ref.watch(supabaseProvider);
    final t = Theme.of(context).textTheme;

    if (client == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l.screenAuth)),
        body: Padding(padding: const EdgeInsets.all(HSpace.xl), child: Text(l.authNotConfigured, style: t.bodyLarge)),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l.screenAuth)),
      body: ListView(padding: const EdgeInsets.all(HSpace.l), children: [
        const Center(child: BrandMark(size: 56)),
        const SizedBox(height: HSpace.l),
        Text(l.authWhy, style: t.bodyLarge),
        const SizedBox(height: HSpace.l),
        TextField(
          controller: _email,
          enabled: !_codeSent,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: InputDecoration(labelText: l.authEmail, border: const OutlineInputBorder()),
        ),
        if (_codeSent) ...[
          const SizedBox(height: HSpace.m),
          Text(l.authCodeSent(_email.text.trim()), style: t.bodyMedium),
          const SizedBox(height: HSpace.s),
          TextField(
            controller: _code,
            keyboardType: TextInputType.number,
            maxLength: 6,
            autofillHints: const [AutofillHints.oneTimeCode],
            decoration: InputDecoration(labelText: l.authCode, border: const OutlineInputBorder()),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: HSpace.s),
          Text(_error!, style: t.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: HSpace.m),
        FilledButton(
          onPressed: _busy
              ? null
              : () => _run(() async {
                    final email = _email.text.trim();
                    if (!_codeSent) {
                      await client.auth.signInWithOtp(email: email, shouldCreateUser: true);
                      setState(() => _codeSent = true);
                    } else {
                      await client.auth.verifyOTP(type: OtpType.email, email: email, token: _code.text.trim());
                      await ref.read(syncServiceProvider).syncNow();
                      if (context.mounted) context.go('/me');
                    }
                  }),
          child: _busy
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_codeSent ? l.authVerify : l.authSendCode),
        ),
        if (_codeSent)
          TextButton(
            onPressed: _busy ? null : () => setState(() => _codeSent = false),
            child: Text(l.authChangeEmail),
          ),
        const SizedBox(height: HSpace.m),
        Text(l.authPrivacy, style: t.bodySmall),
      ]),
    );
  }
}
