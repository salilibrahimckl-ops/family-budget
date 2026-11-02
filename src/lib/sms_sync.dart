// Android reads bank SMS; the web version (iPhone home-screen app) cannot,
// so it gets a stub with the same API.
export 'sms_sync_stub.dart' if (dart.library.io) 'sms_sync_native.dart';
