import 'package:flutter_compass/flutter_compass.dart';

Future<bool> requestCompassPermission() async => true;

Stream<double?> compassHeadings() =>
    (FlutterCompass.events ?? const Stream<CompassEvent>.empty()).map((e) => e.heading);
