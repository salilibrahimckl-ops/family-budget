import 'package:flutter_test/flutter_test.dart';
import 'package:hifz_academy/features/prayer/prayer_times.dart';

void main() {
  // The device time zone in tests may not be India's, so compare the clock time in UTC.
  String utc(DateTime t) {
    final u = t.toUtc();
    return '${u.hour.toString().padLeft(2, '0')}:${u.minute.toString().padLeft(2, '0')}';
  }

  int mins(String hm) => int.parse(hm.split(':')[0]) * 60 + int.parse(hm.split(':')[1]);

  test('Kozhikode, 14 Nov 2026 (Karachi, Shafi Asr) is within a few minutes of expected', () {
    final t = PrayerTimes.calculate(date: DateTime(2026, 11, 14), lat: 11.2588, lng: 75.7804, method: CalcMethod.byId('karachi'));
    // Expected in India time: Fajr 5:09, Sunrise 6:23, Dhuhr 12:12, Asr 15:31, Maghrib 18:00, Isha 19:13 (UTC = IST - 5:30).
    final expectUtc = {
      Prayer.fajr: '23:39', Prayer.sunrise: '00:53', Prayer.dhuhr: '06:42',
      Prayer.asr: '10:01', Prayer.maghrib: '12:30', Prayer.isha: '13:43',
    };
    for (final e in expectUtc.entries) {
      final got = mins(utc(t[e.key]));
      final want = mins(e.value);
      final diff = ((got - want + 720) % 1440) - 720;
      expect(diff.abs() <= 3, isTrue, reason: '${e.key}: got ${utc(t[e.key])} UTC, want ${e.value}');
    }
  });

  test('times are in order and Hanafi Asr is later', () {
    final s = PrayerTimes.calculate(date: DateTime(2026, 6, 1), lat: 21.4225, lng: 39.8262, method: CalcMethod.byId('makkah'));
    final h = PrayerTimes.calculate(date: DateTime(2026, 6, 1), lat: 21.4225, lng: 39.8262, method: CalcMethod.byId('makkah'), hanafiAsr: true);
    final order = [Prayer.fajr, Prayer.sunrise, Prayer.dhuhr, Prayer.asr, Prayer.maghrib, Prayer.isha];
    for (var i = 1; i < order.length; i++) {
      expect(s[order[i]].isAfter(s[order[i - 1]]), isTrue);
    }
    expect(h[Prayer.asr].isAfter(s[Prayer.asr]), isTrue);
    expect(s[Prayer.isha].difference(s[Prayer.maghrib]).inMinutes, 90);
  });

  test('Qibla from Kozhikode points west-north-west (~291°)', () {
    expect(qiblaBearing(11.2588, 75.7804), closeTo(291.1, 0.5));
    expect(qiblaBearing(51.5074, -0.1278), closeTo(119, 1)); // London
  });
}
