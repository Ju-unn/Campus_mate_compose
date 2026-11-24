import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 커뮤니티 탭 줄 안내 움직임(19-3)을 이 기기에서 이 계정이 몇 번 봤는지. 앱 투어 "본 적 있음"
/// (`tour/model/repository/tour_seen_store.dart`)과 같은 방식 — 계정(프로필 id)마다 따로 센다.
abstract interface class CommunityTabHintStore {
  Future<int> playedCount(String profileId);

  Future<void> markPlayed(String profileId);
}

/// 기기 저장소(shared_preferences)에 계정 id 별 키로 남긴다. 앱을 지우면 같이 지워진다.
class SharedPreferencesCommunityTabHintStore implements CommunityTabHintStore {
  const SharedPreferencesCommunityTabHintStore([this._open = SharedPreferences.getInstance]);

  final Future<SharedPreferences> Function() _open;

  static String _key(String profileId) => 'community_tab_hint_played.$profileId';

  @override
  Future<int> playedCount(String profileId) async => (await _open()).getInt(_key(profileId)) ?? 0;

  @override
  Future<void> markPlayed(String profileId) async {
    final preferences = await _open();
    await preferences.setInt(_key(profileId), (preferences.getInt(_key(profileId)) ?? 0) + 1);
  }
}

final communityTabHintStoreProvider =
    Provider<CommunityTabHintStore>((ref) => const SharedPreferencesCommunityTabHintStore());
