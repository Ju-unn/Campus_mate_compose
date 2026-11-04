import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 앱 투어를 이 기기에서 이 계정이 본 적이 있는지. 계정(프로필 id)마다 따로 센다 — 같은 기기의 다른 계정은 처음이다.
abstract interface class TourSeenStore {
  Future<bool> hasSeen(String profileId);

  Future<void> markSeen(String profileId);
}

/// 기기 저장소(shared_preferences)에 계정 id 별 키로 남긴다. 앱을 지우면 같이 지워진다 — 다시 깔면 한 번 더 본다.
class SharedPreferencesTourSeenStore implements TourSeenStore {
  const SharedPreferencesTourSeenStore([this._open = SharedPreferences.getInstance]);

  final Future<SharedPreferences> Function() _open;

  static String _key(String profileId) => 'app_tour_seen.$profileId';

  @override
  Future<bool> hasSeen(String profileId) async => (await _open()).getBool(_key(profileId)) ?? false;

  @override
  Future<void> markSeen(String profileId) async {
    await (await _open()).setBool(_key(profileId), true);
  }
}

final tourSeenStoreProvider = Provider<TourSeenStore>((ref) => const SharedPreferencesTourSeenStore());
