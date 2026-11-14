import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../core/l10n/l10n.dart';
import 'prayer_settings.dart';
import 'prayer_times.dart';

const alertsSupported = true;

final _plugin = FlutterLocalNotificationsPlugin();
bool _ready = false;

Future<void> _init() async {
  if (_ready) return;
  tzdata.initializeTimeZones();
  await _plugin.initialize(const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
  _ready = true;
}

AndroidFlutterLocalNotificationsPlugin? get _android =>
    _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

/// Asks for permission to show notifications and to ring at the exact minute.
Future<bool> requestAlertPermission() async {
  try {
    await _init();
    final ok = await _android?.requestNotificationsPermission() ?? true;
    await _android?.requestExactAlarmsPermission();
    return ok;
  } catch (_) {
    return false;
  }
}

const _days = 14; // reminders are set two weeks ahead; opening the app tops them up

/// Clears and sets the reminders for the next two weeks. Returns how many were set.
Future<int> rescheduleAlerts(PrayerSettings s, AppLocalizations l) async {
  try {
    await _init();
    await _plugin.cancelAll();
    final a = s.alerts;
    if (!a.any) return 0;
    final exact = await _android?.canScheduleExactNotifications() ?? false;
    final mode = exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle;
    const azanDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        'prayer_azan',
        'Azan',
        channelDescription: 'Prayer time reminders',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
      ),
    );
    const iqamahDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        'prayer_iqamah',
        'Iqamah',
        channelDescription: 'Reminders before the Iqamah at your mosque',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
      ),
    );
    final now = DateTime.now();
    final place = s.mosque?.name ?? s.place?.name ?? '';
    var n = 0;
    for (var d = 0; d < _days; d++) {
      final times = s.times(now.add(Duration(days: d)));
      if (times == null) break;
      for (final (i, p) in salah.indexed) {
        final name = _name(l, p);
        if (a.azan.contains(p) && times[p].isAfter(now)) {
          await _plugin.zonedSchedule(
            d * 20 + i * 2,
            l.alertAzanTitle(name),
            place.isEmpty ? null : place,
            tz.TZDateTime.from(times[p].toUtc(), tz.UTC),
            azanDetails,
            androidScheduleMode: mode,
          );
          n++;
        }
        final iq = s.iqamah(p, times);
        if (a.iqamahBefore > 0 && iq != null) {
          final at = iq.subtract(Duration(minutes: a.iqamahBefore));
          if (at.isAfter(now)) {
            await _plugin.zonedSchedule(
              d * 20 + i * 2 + 1,
              l.alertIqamahTitle(name, a.iqamahBefore),
              place,
              tz.TZDateTime.from(at.toUtc(), tz.UTC),
              iqamahDetails,
              androidScheduleMode: mode,
            );
            n++;
          }
        }
      }
    }
    return n;
  } catch (_) {
    return 0;
  }
}

String _name(AppLocalizations l, Prayer p) => switch (p) {
      Prayer.fajr => l.prFajr,
      Prayer.sunrise => l.prSunrise,
      Prayer.dhuhr => l.prDhuhr,
      Prayer.asr => l.prAsr,
      Prayer.maghrib => l.prMaghrib,
      Prayer.isha => l.prIsha,
    };
