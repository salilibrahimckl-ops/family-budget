/// The phone's compass heading (degrees clockwise from north), or null when the device
/// has no compass. Native apps use flutter_compass; the web app uses the browser's
/// device-orientation events (on iPhone Safari after a tap, which grants permission).
export 'compass_io.dart' if (dart.library.js_interop) 'compass_web.dart';
