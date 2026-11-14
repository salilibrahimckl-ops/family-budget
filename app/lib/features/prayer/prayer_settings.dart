import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/settings/settings_controller.dart';
import 'prayer_times.dart';

class SavedPlace {
  const SavedPlace(this.name, this.lat, this.lng);
  final String name;
  final double lat;
  final double lng;

  Map<String, dynamic> toJson() => {'name': name, 'lat': lat, 'lng': lng};
  static SavedPlace fromJson(Map<String, dynamic> j) =>
      SavedPlace(j['name'] as String, (j['lat'] as num).toDouble(), (j['lng'] as num).toDouble());
}

/// How a mosque sets one prayer's Iqamah.
class IqamahRule {
  const IqamahRule({this.afterAzan = 15, this.fixed});
  final int afterAzan; // minutes after the Azan…
  final String? fixed; // …or a fixed time "HH:mm"

  Map<String, dynamic> toJson() => {'after': afterAzan, if (fixed != null) 'fixed': fixed};
  static IqamahRule fromJson(Map<String, dynamic> j) => IqamahRule(afterAzan: (j['after'] as num?)?.toInt() ?? 15, fixed: j['fixed'] as String?);

  DateTime at(DateTime azan) {
    if (fixed != null) {
      final p = fixed!.split(':');
      return DateTime(azan.year, azan.month, azan.day, int.parse(p[0]), int.parse(p[1]));
    }
    return azan.add(Duration(minutes: afterAzan));
  }
}

/// A local mosque and its timetable: the Azan as calculated plus the mosque's own
/// adjustment, and its Iqamah rule for each prayer.
class Mosque {
  const Mosque({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    this.azanAdjust = const {},
    this.iqamah = const {},
    this.jumuah,
  });
  final String id;
  final String name;
  final double lat;
  final double lng;
  final Map<Prayer, int> azanAdjust; // minutes
  final Map<Prayer, IqamahRule> iqamah;
  final String? jumuah; // Friday Iqamah "HH:mm"

  IqamahRule rule(Prayer p) =>
      iqamah[p] ?? IqamahRule(afterAzan: switch (p) { Prayer.fajr => 20, Prayer.maghrib => 5, _ => 15 });

  Mosque copyWith({String? name, Map<Prayer, int>? azanAdjust, Map<Prayer, IqamahRule>? iqamah, String? jumuah, bool clearJumuah = false}) =>
      Mosque(
        id: id,
        name: name ?? this.name,
        lat: lat,
        lng: lng,
        azanAdjust: azanAdjust ?? this.azanAdjust,
        iqamah: iqamah ?? this.iqamah,
        jumuah: clearJumuah ? null : (jumuah ?? this.jumuah),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'lat': lat,
        'lng': lng,
        'azan': {for (final e in azanAdjust.entries) e.key.name: e.value},
        'iqamah': {for (final e in iqamah.entries) e.key.name: e.value.toJson()},
        if (jumuah != null) 'jumuah': jumuah,
      };

  static Mosque fromJson(Map<String, dynamic> j) => Mosque(
        id: j['id'] as String,
        name: j['name'] as String,
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        azanAdjust: {
          for (final e in ((j['azan'] as Map?) ?? const {}).entries) Prayer.values.byName(e.key as String): (e.value as num).toInt(),
        },
        iqamah: {
          for (final e in ((j['iqamah'] as Map?) ?? const {}).entries)
            Prayer.values.byName(e.key as String): IqamahRule.fromJson(e.value as Map<String, dynamic>),
        },
        jumuah: j['jumuah'] as String?,
      );
}

class PrayerSettings {
  const PrayerSettings({
    this.place,
    this.method = 'karachi',
    this.hanafi = false,
    this.mosques = const [],
    this.selected,
  });
  final SavedPlace? place;
  final String method;
  final bool hanafi;
  final List<Mosque> mosques;
  final String? selected; // mosque id

  Mosque? get mosque => mosques.where((m) => m.id == selected).firstOrNull ?? mosques.firstOrNull;

  PrayerSettings copyWith({SavedPlace? place, String? method, bool? hanafi, List<Mosque>? mosques, String? selected}) =>
      PrayerSettings(
        place: place ?? this.place,
        method: method ?? this.method,
        hanafi: hanafi ?? this.hanafi,
        mosques: mosques ?? this.mosques,
        selected: selected ?? this.selected,
      );

  /// Today's (or [day]'s) times: at the chosen mosque if there is one, else at the place.
  PrayerTimes? times([DateTime? day]) {
    final m = mosque;
    final lat = m?.lat ?? place?.lat;
    final lng = m?.lng ?? place?.lng;
    if (lat == null || lng == null) return null;
    return PrayerTimes.calculate(
      date: day ?? DateTime.now(),
      lat: lat,
      lng: lng,
      method: CalcMethod.byId(method),
      hanafiAsr: hanafi,
      adjust: m?.azanAdjust ?? const {},
    );
  }

  DateTime? iqamah(Prayer p, PrayerTimes t) {
    final m = mosque;
    if (m == null || p == Prayer.sunrise) return null;
    if (p == Prayer.dhuhr && t.date.weekday == DateTime.friday && m.jumuah != null) {
      return IqamahRule(fixed: m.jumuah).at(t[p]);
    }
    return m.rule(p).at(t[p]);
  }
}

class PrayerSettingsController extends Notifier<PrayerSettings> {
  static const _key = 'prayer_settings_v1';
  SharedPreferences get _prefs => ref.read(sharedPrefsProvider);

  @override
  PrayerSettings build() {
    final raw = _prefs.getString(_key);
    if (raw == null) return const PrayerSettings();
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return PrayerSettings(
        place: j['place'] == null ? null : SavedPlace.fromJson(j['place'] as Map<String, dynamic>),
        method: j['method'] as String? ?? 'karachi',
        hanafi: j['hanafi'] as bool? ?? false,
        mosques: [for (final m in (j['mosques'] as List? ?? const [])) Mosque.fromJson(m as Map<String, dynamic>)],
        selected: j['selected'] as String?,
      );
    } catch (_) {
      return const PrayerSettings();
    }
  }

  Future<void> _save(PrayerSettings s) async {
    state = s;
    await _prefs.setString(
      _key,
      jsonEncode({
        if (s.place != null) 'place': s.place!.toJson(),
        'method': s.method,
        'hanafi': s.hanafi,
        'mosques': [for (final m in s.mosques) m.toJson()],
        if (s.selected != null) 'selected': s.selected,
      }),
    );
  }

  Future<void> setPlace(SavedPlace p) => _save(state.copyWith(place: p));
  Future<void> setMethod(String id) => _save(state.copyWith(method: id));
  Future<void> setHanafi(bool v) => _save(state.copyWith(hanafi: v));
  Future<void> select(String id) => _save(state.copyWith(selected: id));

  Future<void> saveMosque(Mosque m) {
    final list = [...state.mosques.where((x) => x.id != m.id), m];
    return _save(state.copyWith(mosques: list, selected: state.selected ?? m.id));
  }

  Future<void> removeMosque(String id) {
    final list = state.mosques.where((x) => x.id != id).toList();
    return _save(PrayerSettings(
      place: state.place,
      method: state.method,
      hanafi: state.hanafi,
      mosques: list,
      selected: state.selected == id ? list.firstOrNull?.id : state.selected,
    ));
  }
}

final prayerSettingsProvider = NotifierProvider<PrayerSettingsController, PrayerSettings>(PrayerSettingsController.new);

// ------------------------------------------------------------------ location --

class LocationProblem implements Exception {
  const LocationProblem(this.reason); // 'off' | 'denied' | 'error'
  final String reason;
}

/// The phone's position (GPS or network), asking for permission if needed.
Future<SavedPlace> currentPlace() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) throw const LocationProblem('off');
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      throw const LocationProblem('denied');
    }
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 20)),
    );
    final name = await placeName(pos.latitude, pos.longitude);
    return SavedPlace(name ?? '${pos.latitude.toStringAsFixed(3)}, ${pos.longitude.toStringAsFixed(3)}', pos.latitude, pos.longitude);
  } on LocationProblem {
    rethrow;
  } catch (_) {
    throw const LocationProblem('error');
  }
}

const _ua = {'User-Agent': 'HifzAcademy/1.0 (github.com/salilibrahimckl-ops/family-budget)'};

/// Town name for a position (OpenStreetMap Nominatim).
Future<String?> placeName(double lat, double lng) async {
  try {
    final r = await http
        .get(Uri.parse('https://nominatim.openstreetmap.org/reverse?format=jsonv2&zoom=14&lat=$lat&lon=$lng'), headers: _ua)
        .timeout(const Duration(seconds: 10));
    final a = (jsonDecode(r.body) as Map<String, dynamic>)['address'] as Map<String, dynamic>?;
    if (a == null) return null;
    return (a['suburb'] ?? a['village'] ?? a['town'] ?? a['city'] ?? a['county'] ?? a['state']) as String?;
  } catch (_) {
    return null;
  }
}

/// Places matching a name (OpenStreetMap Nominatim), for setting the location by hand.
Future<List<SavedPlace>> searchPlaces(String q) async {
  final r = await http
      .get(Uri.parse('https://nominatim.openstreetmap.org/search?format=jsonv2&limit=8&q=${Uri.encodeQueryComponent(q)}'), headers: _ua)
      .timeout(const Duration(seconds: 15));
  return [
    for (final p in jsonDecode(r.body) as List)
      SavedPlace(
        (p['display_name'] as String).split(',').take(3).join(','),
        double.parse(p['lat'] as String),
        double.parse(p['lon'] as String),
      ),
  ];
}

/// Mosques near a place, from OpenStreetMap (Overpass API). Returns
/// (id, name, lat, lng) sorted by distance.
Future<List<Mosque>> nearbyMosques(double lat, double lng, {int radius = 3000}) async {
  final query = '[out:json][timeout:25];('
      'node(around:$radius,$lat,$lng)[amenity=place_of_worship][religion=muslim];'
      'way(around:$radius,$lat,$lng)[amenity=place_of_worship][religion=muslim];'
      'relation(around:$radius,$lat,$lng)[amenity=place_of_worship][religion=muslim];'
      ');out center 60;';
  final r = await http
      .post(Uri.parse('https://overpass-api.de/api/interpreter'), headers: _ua, body: {'data': query})
      .timeout(const Duration(seconds: 40));
  final out = <Mosque>[];
  for (final e in (jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>)['elements'] as List) {
    final tags = (e['tags'] as Map?) ?? const {};
    final c = (e['center'] as Map?) ?? e as Map;
    final la = (c['lat'] as num?)?.toDouble();
    final lo = (c['lon'] as num?)?.toDouble();
    if (la == null || lo == null) continue;
    final name = (tags['name:en'] ?? tags['name'] ?? tags['name:ml'] ?? 'Masjid') as String;
    out.add(Mosque(id: 'osm-${e['type']}-${e['id']}', name: name, lat: la, lng: lo));
  }
  out.sort((a, b) => distanceKm(lat, lng, a.lat, a.lng).compareTo(distanceKm(lat, lng, b.lat, b.lng)));
  return out;
}
