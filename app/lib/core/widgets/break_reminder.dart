import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/onboarding/onboarding_store.dart';
import '../l10n/l10n.dart';
import '../settings/settings_controller.dart';
import 'noor.dart';

/// Kids mode: after the planned daily minutes of lessons (at most 20), Noor suggests
/// a short break. Shown once per app session.
mixin BreakReminder<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  static DateTime? _sessionStart;
  static bool _shown = false;
  Timer? _breakTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _arm());
  }

  void _arm() {
    if (!mounted || _shown || !ref.read(settingsProvider).kidsMode) return;
    final start = _sessionStart ??= DateTime.now();
    final planned = ref.read(learningPlanProvider)?.dailyMinutes ?? 20;
    final limit = Duration(minutes: planned.clamp(5, 20));
    final left = limit - DateTime.now().difference(start);
    _breakTimer = Timer(left.isNegative ? Duration.zero : left, _show);
  }

  void _show() {
    if (!mounted || _shown) return;
    _shown = true;
    final l = context.l10n;
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Noor(size: 80),
        title: Text(l.breakTitle),
        content: Text(l.breakBody),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: Text(l.breakOk))],
      ),
    );
  }

  @override
  void dispose() {
    _breakTimer?.cancel();
    super.dispose();
  }
}
