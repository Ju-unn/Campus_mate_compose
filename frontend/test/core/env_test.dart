import 'package:campus_mate/core/env.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('주입값이 없는 테스트 환경에서는 apiBaseUrl 이 비어 있다', () {
    expect(Env.apiBaseUrl, '');
  });

  test('소셜 로그인 키도 주입하지 않으면 비어 있다(키 없는 빌드에서 버튼은 실패 토스트)', () {
    expect(Env.kakaoNativeAppKey, '');
    expect(Env.googleWebClientId, '');
  });
}
