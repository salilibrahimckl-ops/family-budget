/// Azan and Iqamah reminders as phone notifications (Android app). The web app can't
/// show reminders while it's closed, so there it does nothing.
export 'alerts_io.dart' if (dart.library.js_interop) 'alerts_web.dart';
