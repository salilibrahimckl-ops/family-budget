import 'dart:async';

import 'package:flutter/material.dart';

import 'config.dart';
import 'repo.dart';
import 'screens/budget_screen.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/setup_screen.dart';
import 'screens/transactions_screen.dart';
import 'sms_sync.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FamilyBudgetApp());
}

class FamilyBudgetApp extends StatelessWidget {
  const FamilyBudgetApp({super.key});

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) => ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF16808A), brightness: b),
          cardTheme: const CardThemeData(margin: EdgeInsets.zero),
        );
    return MaterialApp(
      title: 'Family Budget',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: const Bootstrap(),
    );
  }
}

/// Decides between first-time setup and the main app.
class Bootstrap extends StatefulWidget {
  const Bootstrap({super.key});
  @override
  State<Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<Bootstrap> {
  Repo? _repo;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await Session.load();
      if (s != null) {
        await ensureFirebase(s.cfg);
        await Repo.signIn();
        _repo = Repo(s.familyId, s.myName);
      }
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.cloud_off, size: 48),
              const SizedBox(height: 12),
              Text('Could not connect.\n$_error', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                  onPressed: () {
                    setState(() {
                      _loading = true;
                      _error = null;
                    });
                    _load();
                  },
                  child: const Text('Retry')),
            ]),
          ),
        ),
      );
    }
    if (_repo == null) {
      return SetupScreen(onDone: (repo) => setState(() => _repo = repo));
    }
    return HomeShell(
      repo: _repo!,
      onLeft: () async {
        await Session.clear();
        setState(() => _repo = null);
      },
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.repo, required this.onLeft});
  final Repo repo;
  final VoidCallback onLeft;
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _tab = 0;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  late final SmsSync _sms = SmsSync(widget.repo);
  Timer? _timer;
  String? _txnMemberFilter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sync(first: true);
    _timer = Timer.periodic(const Duration(minutes: 2), (_) => _sync());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _sync();
  }

  bool _syncing = false;
  Future<void> _sync({bool first = false}) async {
    if (_syncing) return;
    _syncing = true;
    var added = 0;
    try {
      added += await widget.repo.processInbox();
      added += first ? await _sms.start() : await _sms.scan();
    } catch (e) {
      debugPrint('sync error: $e');
    } finally {
      _syncing = false;
    }
    if (added > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added $added new payment${added == 1 ? '' : 's'}')));
    }
  }

  void _openTxns({String? member}) => setState(() {
        _txnMemberFilter = member;
        _tab = 1;
      });

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(
        repo: widget.repo,
        month: _month,
        onMonth: (m) => setState(() => _month = m),
        onRefresh: _sync,
        onOpenTxns: _openTxns,
      ),
      TransactionsScreen(
        key: ValueKey('tx_$_txnMemberFilter'),
        repo: widget.repo,
        month: _month,
        onMonth: (m) => setState(() => _month = m),
        initialMember: _txnMemberFilter,
      ),
      BudgetScreen(repo: widget.repo, month: _month),
      SettingsScreen(repo: widget.repo, sms: _sms, onLeft: widget.onLeft),
    ];
    return Scaffold(
      body: SafeArea(child: IndexedStack(index: _tab, children: pages)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() {
          if (i != 1) _txnMemberFilter = null;
          _tab = i;
        }),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.pie_chart_outline), selectedIcon: Icon(Icons.pie_chart), label: 'Overview'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Payments'),
          NavigationDestination(icon: Icon(Icons.tune), label: 'Budget'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
