import 'package:campus_mate/core/draft/draft_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('화면 키는 서로 겹치지 않고 키에 쓰는 / 가 없다', () {
    final keys = DraftScreen.values.map((screen) => screen.key).toList();
    expect(keys.toSet(), hasLength(keys.length));
    expect(keys.where((key) => key.contains('/')), isEmpty);
  });

  test('카카오톡 아이디와 아바타 만들기는 저장 대상이 아니다', () {
    // 카카오톡 아이디는 평문으로 폰에 남기지 않는다. 아바타는 서버가 작업 상태를 들고 있다.
    final keys = DraftScreen.values.map((screen) => screen.key);
    expect(keys.where((key) => key.contains('kakao')), isEmpty);
    expect(keys.where((key) => key.contains('avatar')), isEmpty);
  });

  test('저장하는 화면은 10개다(온보딩 12단계 중 카카오톡 아이디 · 아바타 제외)', () {
    expect(DraftScreen.values, hasLength(10));
  });
}
