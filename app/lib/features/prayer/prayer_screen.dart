import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/tokens.dart';
import '../../core/l10n/l10n.dart';
import 'compass_source.dart';
import 'prayer_settings.dart';
import 'prayer_times.dart';

String prayerName(AppLocalizations l, Prayer p) => switch (p) {
      Prayer.fajr => l.prFajr,
      Prayer.sunrise => l.prSunrise,
      Prayer.dhuhr => l.prDhuhr,
      Prayer.asr => l.prAsr,
      Prayer.maghrib => l.prMaghrib,
      Prayer.isha => l.prIsha,
    };

String hm(BuildContext context, DateTime t) => MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(t),
      alwaysUse24HourFormat: MediaQuery.of(context).alwaysUse24HourFormat,
    );

/// The next Azan from now (today's or tomorrow's Fajr), with its Iqamah if a mosque is set.
(Prayer, DateTime, DateTime?)? nextPrayer(PrayerSettings s, [DateTime? now]) {
  now ??= DateTime.now();
  final today = s.times(now);
  if (today == null) return null;
  for (final p in salah) {
    final iq = s.iqamah(p, today);
    if (today[p].isAfter(now) || (iq != null && iq.isAfter(now))) return (p, today[p], iq);
  }
  final tomorrow = s.times(now.add(const Duration(days: 1)))!;
  return (Prayer.fajr, tomorrow[Prayer.fajr], s.iqamah(Prayer.fajr, tomorrow));
}

String untilText(AppLocalizations l, Duration d) {
  if (d.isNegative) return l.prNow;
  final h = d.inHours, m = d.inMinutes % 60;
  return h > 0 ? l.prInHM(h, m) : l.prInM(m == 0 ? 1 : m);
}

/// Prayer times, local mosques' Iqamah and the Qibla compass.
class PrayerScreen extends ConsumerStatefulWidget {
  const PrayerScreen({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  ConsumerState<PrayerScreen> createState() => _PrayerScreenState();
}

class _PrayerScreenState extends ConsumerState<PrayerScreen> {
  Timer? _tick;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _locate() async {
    final l = context.l10n;
    setState(() => _locating = true);
    try {
      final p = await currentPlace();
      await ref.read(prayerSettingsProvider.notifier).setPlace(p);
    } on LocationProblem catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(switch (e.reason) { 'off' => l.locOff, 'denied' => l.locDenied, _ => l.locError }),
        ));
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _search() async {
    final place = await showDialog<SavedPlace>(context: context, builder: (_) => const _PlaceSearchDialog());
    if (place != null) await ref.read(prayerSettingsProvider.notifier).setPlace(place);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return DefaultTabController(
      length: 3,
      initialIndex: widget.initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.prTitle),
          bottom: TabBar(tabs: [
            Tab(icon: const Icon(Icons.schedule), text: l.prTimesTab),
            Tab(icon: const Icon(Icons.explore), text: l.prQiblaTab),
            Tab(icon: const Icon(Icons.mosque), text: l.prMosquesTab),
          ]),
        ),
        body: TabBarView(children: [
          _TimesTab(onLocate: _locate, onSearch: _search, locating: _locating),
          _QiblaTab(onLocate: _locate, locating: _locating),
          _MosquesTab(onLocate: _locate, locating: _locating),
        ]),
      ),
    );
  }
}

class _NeedPlace extends StatelessWidget {
  const _NeedPlace({required this.onLocate, required this.locating, this.onSearch});
  final VoidCallback onLocate;
  final VoidCallback? onSearch;
  final bool locating;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Padding(
      padding: const EdgeInsets.all(HSpace.l),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Icon(Icons.location_on_outlined, size: 56),
        const SizedBox(height: HSpace.m),
        Text(l.prNeedPlace, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: HSpace.l),
        FilledButton.icon(
          icon: locating ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.my_location),
          label: Text(l.prUseLocation),
          onPressed: locating ? null : onLocate,
        ),
        if (onSearch != null) ...[
          const SizedBox(height: HSpace.s),
          OutlinedButton.icon(icon: const Icon(Icons.search), label: Text(l.prSearchPlace), onPressed: onSearch),
        ],
      ]),
    );
  }
}

// --------------------------------------------------------------------- times --
class _TimesTab extends ConsumerWidget {
  const _TimesTab({required this.onLocate, required this.onSearch, required this.locating});
  final VoidCallback onLocate;
  final VoidCallback onSearch;
  final bool locating;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final s = ref.watch(prayerSettingsProvider);
    final ctrl = ref.read(prayerSettingsProvider.notifier);
    final times = s.times();
    if (times == null) return _NeedPlace(onLocate: onLocate, onSearch: onSearch, locating: locating);
    final now = DateTime.now();
    final next = nextPrayer(s, now)!;
    final mosque = s.mosque;

    return ListView(padding: const EdgeInsets.all(HSpace.m), children: [
      Row(children: [
        Icon(mosque != null ? Icons.mosque : Icons.location_on, size: 18),
        const SizedBox(width: 6),
        Expanded(child: Text(mosque?.name ?? s.place?.name ?? '', style: t.titleMedium, overflow: TextOverflow.ellipsis)),
        IconButton(tooltip: l.prUseLocation, icon: const Icon(Icons.my_location), onPressed: locating ? null : onLocate),
        IconButton(tooltip: l.prSearchPlace, icon: const Icon(Icons.search), onPressed: onSearch),
      ]),
      Card(
        color: scheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(HSpace.m),
          child: Column(children: [
            Text(l.prNext, style: t.labelLarge),
            Text(prayerName(l, next.$1), style: t.headlineMedium),
            Text(
              next.$3 == null ? l.prAzanAt(hm(context, next.$2)) : l.prAzanIqamah(hm(context, next.$2), hm(context, next.$3!)),
              style: t.titleMedium,
            ),
            Text(untilText(l, next.$2.difference(now)), style: t.bodyMedium),
          ]),
        ),
      ),
      const SizedBox(height: HSpace.s),
      Card(
        child: Column(children: [
          ListTile(
            dense: true,
            title: Text(MaterialLocalizations.of(context).formatFullDate(now), style: t.labelLarge),
            trailing: SizedBox(
              width: 150,
              child: Row(children: [
                Expanded(child: Text(l.prAzan, style: t.labelMedium, textAlign: TextAlign.center)),
                Expanded(child: Text(mosque == null ? '' : l.prIqamah, style: t.labelMedium, textAlign: TextAlign.center)),
              ]),
            ),
          ),
          for (final p in Prayer.values)
            Builder(builder: (context) {
              final isNext = p == next.$1 && next.$2.day == now.day;
              final iq = s.iqamah(p, times);
              final style = isNext ? t.titleMedium?.copyWith(color: scheme.primary, fontWeight: FontWeight.w700) : t.bodyLarge;
              return Container(
                color: isNext ? scheme.primaryContainer.withValues(alpha: 0.35) : null,
                child: ListTile(
                  title: Text(prayerName(l, p), style: style),
                  trailing: SizedBox(
                    width: 150,
                    child: Row(children: [
                      Expanded(child: Text(hm(context, times[p]), style: style, textAlign: TextAlign.center)),
                      Expanded(child: Text(iq == null ? '' : hm(context, iq), style: style, textAlign: TextAlign.center)),
                    ]),
                  ),
                ),
              );
            }),
        ]),
      ),
      if (mosque != null && mosque.jumuah != null)
        Padding(
          padding: const EdgeInsets.only(top: HSpace.s),
          child: Text(l.prJumuahAt(mosque.jumuah!), style: t.bodyMedium, textAlign: TextAlign.center),
        ),
      const SizedBox(height: HSpace.m),
      ExpansionTile(
        leading: const Icon(Icons.tune),
        title: Text(l.prCalcSettings),
        childrenPadding: const EdgeInsets.symmetric(horizontal: HSpace.s),
        children: [
          DropdownButtonFormField<String>(
            initialValue: s.method,
            isExpanded: true,
            decoration: InputDecoration(labelText: l.prMethod, border: const OutlineInputBorder()),
            items: [for (final m in CalcMethod.all) DropdownMenuItem(value: m.id, child: Text(m.name, overflow: TextOverflow.ellipsis))],
            onChanged: (v) => ctrl.setMethod(v!),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l.prHanafi),
            subtitle: Text(s.hanafi ? l.prHanafiOn : l.prHanafiOff),
            value: s.hanafi,
            onChanged: ctrl.setHanafi,
          ),
          Text(l.prCalcNote, style: t.bodySmall),
          const SizedBox(height: HSpace.s),
        ],
      ),
    ]);
  }
}

// --------------------------------------------------------------------- qibla --
class _QiblaTab extends ConsumerStatefulWidget {
  const _QiblaTab({required this.onLocate, required this.locating});
  final VoidCallback onLocate;
  final bool locating;

  @override
  ConsumerState<_QiblaTab> createState() => _QiblaTabState();
}

class _QiblaTabState extends ConsumerState<_QiblaTab> {
  StreamSubscription<double?>? _sub;
  double? _heading;
  bool _started = false;
  bool _noSensor = false;
  bool _wasAligned = false;
  Timer? _watch;

  @override
  void dispose() {
    _sub?.cancel();
    _watch?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    final ok = await requestCompassPermission();
    if (!mounted) return;
    setState(() {
      _started = true;
      _noSensor = !ok;
    });
    if (!ok) return;
    _sub = compassHeadings().listen((h) {
      if (h == null || !mounted) return;
      setState(() => _heading = h);
    });
    _watch = Timer(const Duration(seconds: 4), () {
      if (mounted && _heading == null) setState(() => _noSensor = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final s = ref.watch(prayerSettingsProvider);
    final lat = s.place?.lat ?? s.mosque?.lat;
    final lng = s.place?.lng ?? s.mosque?.lng;
    if (lat == null || lng == null) return _NeedPlace(onLocate: widget.onLocate, locating: widget.locating);
    final qibla = qiblaBearing(lat, lng);
    final h = _heading;
    final diff = h == null ? null : ((qibla - h + 540) % 360) - 180; // −180..180, + = turn right
    final aligned = diff != null && diff.abs() <= 5;
    if (aligned && !_wasAligned) HapticFeedback.mediumImpact();
    _wasAligned = aligned;

    return ListView(padding: const EdgeInsets.all(HSpace.l), children: [
      Text(l.qiblaBearing(qibla.round()), style: t.titleMedium, textAlign: TextAlign.center),
      Text(l.qiblaDistance(distanceKm(lat, lng, 21.422487, 39.826206).round()), style: t.bodySmall, textAlign: TextAlign.center),
      const SizedBox(height: HSpace.l),
      Center(
        child: SizedBox.square(
          dimension: 280,
          child: AnimatedRotation(
            turns: -(h ?? 0) / 360,
            duration: const Duration(milliseconds: 250),
            child: CustomPaint(painter: _DialPainter(qibla: qibla, scheme: scheme, aligned: aligned, labels: l.compassLabels.split(','))),
          ),
        ),
      ),
      const SizedBox(height: HSpace.m),
      if (!_started)
        FilledButton.icon(icon: const Icon(Icons.explore), label: Text(l.qiblaStart), onPressed: _start)
      else if (_noSensor)
        Text(l.qiblaNoCompass(qibla.round()), style: t.bodyMedium, textAlign: TextAlign.center)
      else if (diff != null)
        Text(
          aligned ? l.qiblaAligned : (diff > 0 ? l.qiblaTurnRight(diff.abs().round()) : l.qiblaTurnLeft(diff.abs().round())),
          style: t.titleLarge?.copyWith(color: aligned ? Colors.green : null),
          textAlign: TextAlign.center,
        ),
      const SizedBox(height: HSpace.m),
      Text(l.qiblaTips, style: t.bodySmall, textAlign: TextAlign.center),
    ]);
  }
}

class _DialPainter extends CustomPainter {
  _DialPainter({required this.qibla, required this.scheme, required this.aligned, required this.labels});
  final double qibla;
  final ColorScheme scheme;
  final bool aligned;
  final List<String> labels; // N,E,S,W

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    canvas.drawCircle(c, r, Paint()..color = scheme.surfaceContainerHighest);
    canvas.drawCircle(c, r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = aligned ? Colors.green : scheme.outline);
    for (var d = 0; d < 360; d += 10) {
      final a = (d - 90) * math.pi / 180;
      final len = d % 90 == 0 ? 16.0 : (d % 30 == 0 ? 10.0 : 5.0);
      final p1 = c + Offset(math.cos(a), math.sin(a)) * (r - 4);
      final p2 = c + Offset(math.cos(a), math.sin(a)) * (r - 4 - len);
      canvas.drawLine(p1, p2, Paint()
        ..strokeWidth = d % 90 == 0 ? 3 : 1.5
        ..color = scheme.onSurfaceVariant);
    }
    for (var i = 0; i < 4; i++) {
      final a = (i * 90 - 90) * math.pi / 180;
      final tp = TextPainter(
        text: TextSpan(
          text: labels.length == 4 ? labels[i] : 'NESW'[i],
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: i == 0 ? Colors.red : scheme.onSurface),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final p = c + Offset(math.cos(a), math.sin(a)) * (r - 36);
      tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
    }
    // Qibla needle with the Kaaba at its tip.
    final qa = (qibla - 90) * math.pi / 180;
    final tip = c + Offset(math.cos(qa), math.sin(qa)) * (r - 52);
    canvas.drawLine(c, tip, Paint()
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..color = aligned ? Colors.green : scheme.primary);
    final kaaba = Rect.fromCenter(center: tip, width: 26, height: 26);
    canvas.drawRRect(RRect.fromRectAndRadius(kaaba, const Radius.circular(3)), Paint()..color = const Color(0xFF1B1B1B));
    canvas.drawRect(Rect.fromLTWH(kaaba.left, kaaba.top + 7, kaaba.width, 4), Paint()..color = const Color(0xFFD4AF37));
    canvas.drawCircle(c, 8, Paint()..color = scheme.primary);
  }

  @override
  bool shouldRepaint(_DialPainter o) => o.qibla != qibla || o.aligned != aligned || o.scheme != scheme;
}

// ------------------------------------------------------------------- mosques --
class _MosquesTab extends ConsumerStatefulWidget {
  const _MosquesTab({required this.onLocate, required this.locating});
  final VoidCallback onLocate;
  final bool locating;

  @override
  ConsumerState<_MosquesTab> createState() => _MosquesTabState();
}

class _MosquesTabState extends ConsumerState<_MosquesTab> {
  List<Mosque>? _found;
  bool _searching = false;
  String? _error;

  Future<void> _find(SavedPlace p) async {
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final list = await nearbyMosques(p.lat, p.lng);
      if (mounted) setState(() => _found = list);
    } catch (_) {
      if (mounted) setState(() => _error = context.l10n.mosqueSearchFailed);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _edit(Mosque m) async {
    final saved = await Navigator.of(context).push<Mosque>(MaterialPageRoute(builder: (_) => MosqueEditor(mosque: m)));
    if (saved != null) await ref.read(prayerSettingsProvider.notifier).saveMosque(saved);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final s = ref.watch(prayerSettingsProvider);
    final ctrl = ref.read(prayerSettingsProvider.notifier);
    final place = s.place;
    if (place == null) return _NeedPlace(onLocate: widget.onLocate, locating: widget.locating);

    return ListView(padding: const EdgeInsets.all(HSpace.m), children: [
      Text(l.mosquesIntro, style: t.bodyMedium),
      const SizedBox(height: HSpace.m),
      if (s.mosques.isNotEmpty) ...[
        Text(l.myMosques, style: t.titleMedium),
        RadioGroup<String>(
          groupValue: s.mosque?.id,
          onChanged: (v) => v == null ? null : ctrl.select(v),
          child: Column(children: [
            for (final m in s.mosques)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Radio<String>(value: m.id),
                title: Text(m.name),
                subtitle: Text(l.kmAway(distanceKm(place.lat, place.lng, m.lat, m.lng).toStringAsFixed(1))),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(icon: const Icon(Icons.edit), tooltip: l.mosqueEdit, onPressed: () => _edit(m)),
                  IconButton(icon: const Icon(Icons.delete_outline), tooltip: l.mosqueRemove, onPressed: () => ctrl.removeMosque(m.id)),
                ]),
                onTap: () => ctrl.select(m.id),
              ),
          ]),
        ),
        const Divider(),
      ],
      FilledButton.icon(
        icon: _searching ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.travel_explore),
        label: Text(l.findMosques(place.name)),
        onPressed: _searching ? null : () => _find(place),
      ),
      const SizedBox(height: HSpace.s),
      OutlinedButton.icon(
        icon: const Icon(Icons.add),
        label: Text(l.addMosqueByHand),
        onPressed: () => _edit(Mosque(id: 'own-${DateTime.now().millisecondsSinceEpoch}', name: '', lat: place.lat, lng: place.lng)),
      ),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: HSpace.s), child: Text(_error!, style: t.bodySmall)),
      if (_found != null) ...[
        const SizedBox(height: HSpace.m),
        Text(_found!.isEmpty ? l.noMosquesFound : l.mosquesFound(_found!.length), style: t.titleSmall),
        for (final m in _found!)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.mosque),
            title: Text(m.name),
            subtitle: Text(l.kmAway(distanceKm(place.lat, place.lng, m.lat, m.lng).toStringAsFixed(1))),
            trailing: s.mosques.any((x) => x.id == m.id) ? const Icon(Icons.check) : const Icon(Icons.add_circle_outline),
            onTap: () => _edit(s.mosques.where((x) => x.id == m.id).firstOrNull ?? m),
          ),
        Text(l.osmCredit, style: t.bodySmall),
      ],
    ]);
  }
}

/// Set a mosque's own timetable: its Azan compared with the calculation, and when it
/// holds each Iqamah (minutes after the Azan, or a fixed time), plus Jumu'ah.
class MosqueEditor extends ConsumerStatefulWidget {
  const MosqueEditor({super.key, required this.mosque});
  final Mosque mosque;

  @override
  ConsumerState<MosqueEditor> createState() => _MosqueEditorState();
}

class _MosqueEditorState extends ConsumerState<MosqueEditor> {
  late final _name = TextEditingController(text: widget.mosque.name);
  late final Map<Prayer, int> _azan = {...widget.mosque.azanAdjust};
  late final Map<Prayer, IqamahRule> _iq = {for (final p in salah) p: widget.mosque.rule(p)};
  late String? _jumuah = widget.mosque.jumuah;

  String _fmt(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  TimeOfDay _parse(String s) => TimeOfDay(hour: int.parse(s.split(':')[0]), minute: int.parse(s.split(':')[1]));

  Future<String?> _pick(String? current, DateTime fallback) async {
    final t = await showTimePicker(context: context, initialTime: current != null ? _parse(current) : TimeOfDay.fromDateTime(fallback));
    return t == null ? null : _fmt(t);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final s = ref.watch(prayerSettingsProvider);
    final m = widget.mosque;
    final today = PrayerTimes.calculate(
      date: DateTime.now(),
      lat: m.lat,
      lng: m.lng,
      method: CalcMethod.byId(s.method),
      hanafiAsr: s.hanafi,
      adjust: _azan,
    );

    Widget stepper(int value, ValueChanged<int> onChanged, {int min = -60, int max = 60}) => Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: value > min ? () => onChanged(value - 1) : null),
          SizedBox(width: 36, child: Text('$value', textAlign: TextAlign.center, style: t.titleMedium)),
          IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: value < max ? () => onChanged(value + 1) : null),
        ]);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.mosqueTimetable),
        actions: [
          TextButton(
            onPressed: () {
              final name = _name.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(context, m.copyWith(name: name, azanAdjust: _azan, iqamah: _iq, jumuah: _jumuah, clearJumuah: _jumuah == null));
            },
            child: Text(l.save),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(HSpace.m), children: [
        TextField(controller: _name, decoration: InputDecoration(labelText: l.mosqueName, border: const OutlineInputBorder())),
        const SizedBox(height: HSpace.s),
        Text(l.mosqueEditorHelp, style: t.bodySmall),
        for (final p in salah)
          Card(
            margin: const EdgeInsets.only(top: HSpace.s),
            child: Padding(
              padding: const EdgeInsets.all(HSpace.s),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Text(prayerName(l, p), style: t.titleMedium),
                  const Spacer(),
                  Text('${l.prAzan} ${hm(context, today[p])}', style: t.bodyMedium),
                  const SizedBox(width: HSpace.s),
                  Text('${l.prIqamah} ${hm(context, _iq[p]!.at(today[p]))}', style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                ]),
                Row(children: [
                  Expanded(child: Text(l.azanAdjust, style: t.bodySmall)),
                  stepper(_azan[p] ?? 0, (v) => setState(() => _azan[p] = v)),
                ]),
                Row(children: [
                  Expanded(
                    child: SegmentedButton<bool>(
                      segments: [
                        ButtonSegment(value: false, label: Text(l.iqAfter)),
                        ButtonSegment(value: true, label: Text(l.iqFixed)),
                      ],
                      selected: {_iq[p]!.fixed != null},
                      onSelectionChanged: (v) async {
                        if (v.first) {
                          final f = await _pick(null, _iq[p]!.at(today[p]));
                          if (f != null) setState(() => _iq[p] = IqamahRule(afterAzan: _iq[p]!.afterAzan, fixed: f));
                        } else {
                          setState(() => _iq[p] = IqamahRule(afterAzan: _iq[p]!.afterAzan));
                        }
                      },
                    ),
                  ),
                ]),
                if (_iq[p]!.fixed == null)
                  Row(children: [
                    Expanded(child: Text(l.iqMinutesAfter, style: t.bodySmall)),
                    stepper(_iq[p]!.afterAzan, (v) => setState(() => _iq[p] = IqamahRule(afterAzan: v)), min: 0, max: 90),
                  ])
                else
                  TextButton.icon(
                    icon: const Icon(Icons.schedule),
                    label: Text(_iq[p]!.fixed!),
                    onPressed: () async {
                      final f = await _pick(_iq[p]!.fixed, today[p]);
                      if (f != null) setState(() => _iq[p] = IqamahRule(afterAzan: _iq[p]!.afterAzan, fixed: f));
                    },
                  ),
              ]),
            ),
          ),
        Card(
          margin: const EdgeInsets.only(top: HSpace.s),
          child: ListTile(
            leading: const Icon(Icons.groups),
            title: Text(l.jumuah),
            subtitle: Text(_jumuah ?? l.jumuahNotSet),
            trailing: _jumuah == null ? null : IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _jumuah = null)),
            onTap: () async {
              final f = await _pick(_jumuah, DateTime(2000, 1, 1, 13, 0));
              if (f != null) setState(() => _jumuah = f);
            },
          ),
        ),
      ]),
    );
  }
}

class _PlaceSearchDialog extends StatefulWidget {
  const _PlaceSearchDialog();

  @override
  State<_PlaceSearchDialog> createState() => _PlaceSearchDialogState();
}

class _PlaceSearchDialogState extends State<_PlaceSearchDialog> {
  final _q = TextEditingController();
  List<SavedPlace>? _results;
  bool _busy = false;

  Future<void> _go() async {
    if (_q.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final r = await searchPlaces(_q.text.trim());
      if (mounted) setState(() => _results = r);
    } catch (_) {
      if (mounted) setState(() => _results = const []);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.prSearchPlace),
      content: SizedBox(
        width: 400,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _q,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _go(),
            decoration: InputDecoration(
              hintText: l.placeHint,
              suffixIcon: _busy
                  ? const Padding(padding: EdgeInsets.all(12), child: SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                  : IconButton(icon: const Icon(Icons.search), onPressed: _go),
            ),
          ),
          if (_results != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ListView(shrinkWrap: true, children: [
                if (_results!.isEmpty) Padding(padding: const EdgeInsets.all(8), child: Text(l.noPlaces)),
                for (final p in _results!) ListTile(title: Text(p.name), onTap: () => Navigator.pop(context, p)),
              ]),
            ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(l.cancel))],
    );
  }
}
