import 'repo.dart';

class SmsSync {
  SmsSync(this.repo);
  final Repo repo;
  static bool get supported => false;
  Future<int> start() async => 0;
  Future<int> scan({DateTime? from}) async => 0;
}
