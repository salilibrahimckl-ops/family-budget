import 'dart:math' as math;

/// Prayer-time calculation (the standard astronomical method used by PrayTimes.org and
/// most Islamic apps): the sun's position for the date, then the times when it reaches
/// the angles each method defines.
enum Prayer { fajr, sunrise, dhuhr, asr, maghrib, isha }

/// The five prayers (sunrise is shown but has no Azan or Iqamah).
const salah = [Prayer.fajr, Prayer.dhuhr, Prayer.asr, Prayer.maghrib, Prayer.isha];

class CalcMethod {
  const CalcMethod(this.id, this.name, this.fajr, {this.isha, this.ishaMinutes, this.maghribMinutes = 0});
  final String id;
  final String name;
  final double fajr; // sun angle below the horizon
  final double? isha; // angle, or…
  final int? ishaMinutes; // …minutes after Maghrib
  final int maghribMinutes; // added after sunset

  static const all = [
    CalcMethod('karachi', 'University of Islamic Sciences, Karachi (18°/18°) — common in India', 18, isha: 18),
    CalcMethod('mwl', 'Muslim World League (18°/17°)', 18, isha: 17),
    CalcMethod('isna', 'ISNA, North America (15°/15°)', 15, isha: 15),
    CalcMethod('egypt', 'Egyptian General Authority (19.5°/17.5°)', 19.5, isha: 17.5),
    CalcMethod('makkah', 'Umm al-Qura, Makkah (18.5° / 90 min)', 18.5, ishaMinutes: 90),
    CalcMethod('dubai', 'Dubai (18.2°/18.2°)', 18.2, isha: 18.2),
    CalcMethod('kuwait', 'Kuwait (18°/17.5°)', 18, isha: 17.5),
    CalcMethod('qatar', 'Qatar (18° / 90 min)', 18, ishaMinutes: 90),
    CalcMethod('singapore', 'Singapore (20°/18°)', 20, isha: 18),
  ];

  static CalcMethod byId(String? id) => all.firstWhere((m) => m.id == id, orElse: () => all.first);
}

double _d2r(double d) => d * math.pi / 180;
double _r2d(double r) => r * 180 / math.pi;
double _sin(double d) => math.sin(_d2r(d));
double _cos(double d) => math.cos(_d2r(d));
double _tan(double d) => math.tan(_d2r(d));
double _asin(double x) => _r2d(math.asin(x));
double _acos(double x) => _r2d(math.acos(x.clamp(-1.0, 1.0)));
double _atan2(double y, double x) => _r2d(math.atan2(y, x));
double _acot(double x) => _r2d(math.atan(1 / x));
double _fix(double a, double b) {
  final r = a - b * (a / b).floor();
  return r < 0 ? r + b : r;
}

double _julian(int y, int m, int d) {
  if (m <= 2) {
    y -= 1;
    m += 12;
  }
  final a = (y / 100).floor();
  final b = 2 - a + (a / 4).floor();
  return (365.25 * (y + 4716)).floor() + (30.6001 * (m + 1)).floor() + d + b - 1524.5;
}

/// (declination, equation of time) for a Julian date.
(double, double) _sun(double jd) {
  final d = jd - 2451545.0;
  final g = _fix(357.529 + 0.98560028 * d, 360);
  final q = _fix(280.459 + 0.98564736 * d, 360);
  final l = _fix(q + 1.915 * _sin(g) + 0.020 * _sin(2 * g), 360);
  final e = 23.439 - 0.00000036 * d;
  final ra = _atan2(_cos(e) * _sin(l), _cos(l)) / 15;
  final eqt = q / 15 - _fix(ra, 24);
  final decl = _asin(_sin(e) * _sin(l));
  return (decl, eqt);
}

class PrayerTimes {
  PrayerTimes._(this.date, this.times);
  final DateTime date;
  final Map<Prayer, DateTime> times;

  DateTime operator [](Prayer p) => times[p]!;

  /// Times for [date] at [lat], [lng], in the device's time zone.
  /// [hanafiAsr]: Asr when a shadow is twice an object's length (Hanafi) instead of once.
  /// [adjust]: minutes to add to each time (to match a local timetable).
  static PrayerTimes calculate({
    required DateTime date,
    required double lat,
    required double lng,
    required CalcMethod method,
    bool hanafiAsr = false,
    Map<Prayer, int> adjust = const {},
  }) {
    final day = DateTime(date.year, date.month, date.day);
    final tz = day.add(const Duration(hours: 12)).timeZoneOffset.inMinutes / 60.0;
    final jDate = _julian(day.year, day.month, day.day) - lng / (15 * 24);

    double midDay(double t) => _fix(12 - _sun(jDate + t).$2, 24);
    double angleTime(double angle, double t, {bool before = false}) {
      final decl = _sun(jDate + t).$1;
      final noon = midDay(t);
      final h = _acos((-_sin(angle) - _sin(decl) * _sin(lat)) / (_cos(decl) * _cos(lat))) / 15;
      return noon + (before ? -h : h);
    }

    double asrTime(double factor, double t) {
      final decl = _sun(jDate + t).$1;
      final angle = -_acot(factor + _tan((lat - decl).abs()));
      return angleTime(angle, t);
    }

    // Two passes: first from rough guesses, then refined from the first results.
    var t = {
      Prayer.fajr: 5.0, Prayer.sunrise: 6.0, Prayer.dhuhr: 12.0,
      Prayer.asr: 13.0, Prayer.maghrib: 18.0, Prayer.isha: 18.0,
    };
    for (var pass = 0; pass < 2; pass++) {
      final f = t.map((k, v) => MapEntry(k, v / 24));
      t = {
        Prayer.fajr: angleTime(method.fajr, f[Prayer.fajr]!, before: true),
        Prayer.sunrise: angleTime(0.833, f[Prayer.sunrise]!, before: true),
        Prayer.dhuhr: midDay(f[Prayer.dhuhr]!),
        Prayer.asr: asrTime(hanafiAsr ? 2 : 1, f[Prayer.asr]!),
        Prayer.maghrib: angleTime(0.833, f[Prayer.maghrib]!),
        Prayer.isha: method.isha != null ? angleTime(method.isha!, f[Prayer.isha]!) : 18,
      };
    }
    final shift = tz - lng / 15;
    t = t.map((k, v) => MapEntry(k, v + shift));
    t[Prayer.dhuhr] = t[Prayer.dhuhr]! + 1 / 60; // just after the sun passes its height
    t[Prayer.maghrib] = t[Prayer.maghrib]! + method.maghribMinutes / 60;
    if (method.ishaMinutes != null) t[Prayer.isha] = t[Prayer.maghrib]! + method.ishaMinutes! / 60;

    DateTime at(double hours, int extra) {
      final mins = (hours * 60).round() + extra;
      return day.add(Duration(minutes: mins));
    }

    return PrayerTimes._(day, {for (final p in Prayer.values) p: at(t[p]!, adjust[p] ?? 0)});
  }
}

/// Direction of the Kaaba from a place, in degrees clockwise from true north.
double qiblaBearing(double lat, double lng) {
  const kLat = 21.422487, kLng = 39.826206;
  final dl = kLng - lng;
  final y = _sin(dl);
  final x = _cos(lat) * _tan(kLat) - _sin(lat) * _cos(dl);
  return _fix(_atan2(y, x), 360);
}

/// Great-circle distance in km.
double distanceKm(double lat1, double lng1, double lat2, double lng2) {
  final a = math.pow(_sin((lat2 - lat1) / 2), 2) + _cos(lat1) * _cos(lat2) * math.pow(_sin((lng2 - lng1) / 2), 2);
  return 6371 * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}
