import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// iPhone Safari needs DeviceOrientationEvent.requestPermission() from a tap.
Future<bool> requestCompassPermission() async {
  try {
    final ctor = web.window.getProperty<JSObject?>('DeviceOrientationEvent'.toJS);
    if (ctor != null && ctor.has('requestPermission')) {
      final res = await ctor.callMethod<JSPromise<JSString>>('requestPermission'.toJS).toDart;
      return res.toDart == 'granted';
    }
  } catch (_) {
    return false;
  }
  return true;
}

Stream<double?> compassHeadings() {
  late StreamController<double?> c;
  void onEvent(web.Event e) {
    final o = e as JSObject;
    // iPhone: webkitCompassHeading is already degrees from north.
    final wk = o.getProperty<JSNumber?>('webkitCompassHeading'.toJS);
    if (wk != null) {
      c.add(wk.toDartDouble);
      return;
    }
    // Others: 'deviceorientationabsolute' gives alpha counter-clockwise from north.
    final alpha = o.getProperty<JSNumber?>('alpha'.toJS);
    final absolute = o.getProperty<JSBoolean?>('absolute'.toJS)?.toDart ?? false;
    if (alpha != null && (absolute || e.type == 'deviceorientationabsolute')) {
      c.add((360 - alpha.toDartDouble) % 360);
    }
  }

  final listener = onEvent.toJS;
  c = StreamController<double?>(
    onListen: () {
      web.window.addEventListener('deviceorientationabsolute', listener);
      web.window.addEventListener('deviceorientation', listener);
    },
    onCancel: () {
      web.window.removeEventListener('deviceorientationabsolute', listener);
      web.window.removeEventListener('deviceorientation', listener);
    },
  );
  return c.stream;
}
