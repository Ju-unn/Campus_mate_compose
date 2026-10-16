import 'package:campus_mate/profile/model/signup_phone_number.dart';
import 'package:flutter_test/flutter_test.dart';

/// 가입용 휴대폰 번호 규칙(출시준비 `전화번호_인증_방법_가격.md` §3-1 · §3-2 A·B·C · §3-3). 서버도 같은 예시로 시험한다.
void main() {
  group('받는 번호', () {
    for (final digits in [
      '01001352468', // 패턴 없는 시험용 번호
      '01012342841', // 가운데만 1234
      '01048210000', // 끝만 0000
      '01048211234', // 끝만 1234
      '01048211111', // 끝만 1111
      '01034563456', // 가운데 · 끝이 같은 번호(목록에 없으면 막지 않는다)
      '01000005678', // 가운데 0000(D)은 처음엔 막지 않는다
    ]) {
      test('$digits 는 받는다', () => expect(SignupPhoneNumber.accepts(digits), isTrue));
    }
  });

  group('010 + 8자리가 아니면 막는다', () {
    for (final digits in ['0114821291', '01100000000', '01600000000', '01900000000', '0104821291', '010000000001', '']) {
      test('"$digits" 는 막는다', () => expect(SignupPhoneNumber.accepts(digits), isFalse));
    }
  });

  group('A — 뒤 8자리가 전부 같은 숫자', () {
    for (final digits in ['01000000000', '01011111111', '01099999999']) {
      test('$digits 는 막는다', () => expect(SignupPhoneNumber.accepts(digits), isFalse));
    }
  });

  group('B — 뒤 8자리가 한 줄로 이어지는 순서(오름 · 내림, 9 다음 0 으로 돌지 않는다)', () {
    for (final digits in ['01012345678', '01087654321', '01001234567', '01098765432', '01023456789', '01076543210']) {
      test('$digits 는 막는다', () => expect(SignupPhoneNumber.accepts(digits), isFalse));
    }

    test('9 → 0 으로 넘어가는 순서(78901234)는 한 줄 순서가 아니라 받는다', () {
      expect(SignupPhoneNumber.accepts('01078901234'), isTrue);
    });
  });

  group('C — 알려진 가짜 번호 목록', () {
    for (final digits in ['01012341234', '01012341111', '01011112222', '01012121212', '01000001234', '01012340000']) {
      test('$digits 는 막는다', () => expect(SignupPhoneNumber.accepts(digits), isFalse));
    }
  });
}
