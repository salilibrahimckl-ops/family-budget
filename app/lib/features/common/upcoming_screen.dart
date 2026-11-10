import 'package:flutter/material.dart';

import '../../core/design/tokens.dart';
import '../../core/l10n/l10n.dart';

/// Honest stand-in for a screen that is not built yet. It has no buttons that pretend
/// to work; it states which phase delivers it. Each one is listed in docs/ROADMAP.md.
class UpcomingScreen extends StatelessWidget {
  const UpcomingScreen({super.key, required this.title, required this.phase, this.showAppBar = true});

  final String title;
  final int phase;
  final bool showAppBar;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: showAppBar ? AppBar(title: Text(title)) : null,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(HSpace.xl),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.construction_outlined, size: 48, color: scheme.onSurfaceVariant),
              const SizedBox(height: HSpace.m),
              Text(l.upcomingTitle(title), style: t.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: HSpace.s),
              Text(l.upcomingBody(phase),
                  style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant), textAlign: TextAlign.center),
            ]),
          ),
        ),
      ),
    );
  }
}
