import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/input_rules.dart';
import 'package:flutter_test/flutter_test.dart';

import 'input_rules_cases.dart';

/// 서버와 같은 입력 표(`backend/tests/fixtures/input_rules_cases.json`)로 본다 — 앱이 통과시키고 서버가 거절하면 가입이 막힌다.
void main() {
  group('학과(서버 is_valid_department)', () {
    for (final department in inputRuleCases('department', 'reject')) {
      test('서버가 거절하는 ${Uri.encodeComponent(department)} 는 앱도 거절한다', () {
        expect(isValidDepartment(department), isFalse);
      });
    }
    for (final department in inputRuleCases('department', 'accept')) {
      test('서버가 받는 $department 는 앞뒤 공백이 있어도 앱도 받는다', () {
        expect(isValidDepartment(' $department '), isTrue);
      });
    }
  });

  group('닉네임(서버 NICKNAME_PATTERN + has_letter_run)', () {
    for (final nickname in inputRuleCases('nickname', 'pattern_invalid')) {
      test('패턴 밖 $nickname 은 형식 오류다', () {
        expect(NicknameFormat.of(nickname), NicknameFormat.invalid);
      });
    }
    for (final nickname in inputRuleCases('nickname', 'letter_run')) {
      test('연속 글자 $nickname 은 쓸 수 없다', () {
        expect(NicknameFormat.of(nickname), NicknameFormat.notAllowed);
      });
    }
    for (final nickname in inputRuleCases('nickname', 'accept')) {
      test('서버가 받는 $nickname 은 서버에 물어볼 수 있다', () {
        expect(NicknameFormat.of(nickname), NicknameFormat.valid);
      });
    }
  });

  group('카카오톡 아이디(서버 is_valid_kakao_id)', () {
    for (final kakaoId in inputRuleCases('kakao_id', 'reject')) {
      test('서버가 거절하는 ${Uri.encodeComponent(kakaoId)} 는 앱도 거절한다', () {
        expect(isValidKakaoId(kakaoId), isFalse);
      });
    }
    for (final kakaoId in inputRuleCases('kakao_id', 'accept')) {
      test('서버가 받는 $kakaoId 는 앞뒤 공백이 있어도 앱도 받는다', () {
        expect(isValidKakaoId(' $kakaoId '), isTrue);
      });
    }
  });

  // 대장 판정(11-24, 나안): 칸 아래 문구 — 안쪽 공백은 바로 "공백 없이", 다른 거절 이유는 손을 멈춘 뒤 "입력한 값을 다시", 빈 칸은 없음.
  group('카카오톡 아이디 칸 아래 오류(서버와 같은 표)', () {
    for (final kakaoId in inputRuleCases('kakao_id', 'reject')) {
      final expected = hasKakaoIdSpace(kakaoId)
          ? const AppErrorFailure(AppError.kakaoIdSpace)
          : kakaoId.trim().isEmpty
              ? null
              : const AppErrorFailure(AppError.invalidInput);
      test('${Uri.encodeComponent(kakaoId)} 는 손을 멈춘 뒤 $expected', () {
        expect(kakaoIdFieldError(kakaoId, settled: true), expected);
      });
    }
    for (final kakaoId in inputRuleCases('kakao_id', 'accept')) {
      test('서버가 받는 $kakaoId 는 오류가 없다', () {
        expect(kakaoIdFieldError(kakaoId, settled: true), isNull);
      });
    }
    test('공백 아닌 거절 이유는 손을 멈추기 전에는 띄우지 않는다', () {
      expect(kakaoIdFieldError('a', settled: false), isNull);
    });
    test('안쪽 공백은 손을 멈추기 전에도 띄운다', () {
      expect(kakaoIdFieldError('my id', settled: false), const AppErrorFailure(AppError.kakaoIdSpace));
    });
    test('빈 값 · 공백만은 손을 멈춰도 띄우지 않는다', () {
      expect(kakaoIdFieldError('', settled: true), isNull);
      expect(kakaoIdFieldError('   ', settled: true), isNull);
    });
  });

  // 칸 아래 "공백 없이 적어 주세요" 의 조건 — 안쪽 공백 · 줄바꿈 · 0폭 문자만. 앞뒤 공백 · 다른 거절 이유는 아니다.
  group('카카오톡 아이디 안쪽 공백', () {
    for (final kakaoId in ['my id', 'fox\nrain', 'fox\train', 'fox\u3000rain', 'fox\u200B', '\uFEFFfox_rain', 'fox\u200Drain']) {
      test('${Uri.encodeComponent(kakaoId)} 는 안쪽 공백이다', () {
        expect(hasKakaoIdSpace(kakaoId), isTrue);
      });
    }
    for (final kakaoId in [' fox_rain ', '', '  ', 'a', 'ㅋㅋfox', 'fox\u0000rain', 'fox\u202Erain']) {
      test('${Uri.encodeComponent(kakaoId)} 는 안쪽 공백이 아니다', () {
        expect(hasKakaoIdSpace(kakaoId), isFalse);
      });
    }
  });
}
