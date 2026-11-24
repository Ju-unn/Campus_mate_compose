import 'package:campus_mate/community/model/repository/community_tab_hint_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('처음 계정은 0번이고, 움직일 때마다 1씩 올라 다시 켜도 남는다', () async {
    const store = SharedPreferencesCommunityTabHintStore();

    expect(await store.playedCount('profile-a'), 0);
    await store.markPlayed('profile-a');
    await store.markPlayed('profile-a');

    // 디스크에 남는다 — 앱을 다시 켠 것과 같다(새 인스턴스).
    expect(await const SharedPreferencesCommunityTabHintStore().playedCount('profile-a'), 2);
  });

  test('같은 기기의 다른 계정은 따로 센다', () async {
    const store = SharedPreferencesCommunityTabHintStore();

    await store.markPlayed('profile-a');

    expect(await store.playedCount('profile-b'), 0);
  });
}
