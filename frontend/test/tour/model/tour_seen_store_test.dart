import 'package:campus_mate/tour/model/tour_seen_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('처음 보는 계정은 본 적이 없고, 본 것으로 저장하면 다시 켜도 본 것이다', () async {
    const store = SharedPreferencesTourSeenStore();

    expect(await store.hasSeen('profile-a'), isFalse);
    await store.markSeen('profile-a');

    expect(await store.hasSeen('profile-a'), isTrue);
    // 디스크에 남는다 — 앱을 다시 켠 것과 같다(새 인스턴스).
    expect(await const SharedPreferencesTourSeenStore().hasSeen('profile-a'), isTrue);
  });

  test('같은 기기의 다른 계정은 따로 센다 — 한 계정이 봤다고 다른 계정이 본 것이 아니다', () async {
    const store = SharedPreferencesTourSeenStore();

    await store.markSeen('profile-a');

    expect(await store.hasSeen('profile-b'), isFalse);
  });
}
