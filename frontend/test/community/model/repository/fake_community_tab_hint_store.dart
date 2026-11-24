import 'package:campus_mate/community/model/repository/community_tab_hint_store.dart';

/// 메모리에만 두는 가짜. [played] 에 계정별 횟수를 미리 넣어 둔다. [failing] 이면 읽기가 실패한다.
class FakeCommunityTabHintStore implements CommunityTabHintStore {
  FakeCommunityTabHintStore({Map<String, int>? played, this.failing = false}) : played = played ?? {};

  final Map<String, int> played;
  final bool failing;

  @override
  Future<int> playedCount(String profileId) async {
    if (failing) throw StateError('저장소를 못 엶');
    return played[profileId] ?? 0;
  }

  @override
  Future<void> markPlayed(String profileId) async {
    played[profileId] = (played[profileId] ?? 0) + 1;
  }
}
