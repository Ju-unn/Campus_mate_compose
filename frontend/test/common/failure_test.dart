import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/core/l10n/error_text.dart';
import 'package:campus_mate/l10n/app_localizations_ko.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('네트워크 실패는 연결 확인 안내를 보여준다', () {
    const failure = NetworkFailure();

    expect(failureText(AppLocalizationsKo(), failure), '네트워크 연결을 확인해 주세요');
  });

  test('세션 만료 실패는 다시 로그인하라는 안내를 보여준다', () {
    const failure = SessionExpiredFailure();
    expect(failureText(AppLocalizationsKo(), failure), '세션이 만료됐어요, 다시 로그인해 주세요');
  });

  test('찾을 수 없음 실패는 대상이 없다는 안내를 보여준다', () {
    const failure = NotFoundFailure();

    expect(failureText(AppLocalizationsKo(), failure), '요청한 정보를 찾을 수 없습니다');
  });

  test('알 수 없는 실패는 일반 오류 안내를 보여준다', () {
    const failure = UnknownFailure();

    expect(failureText(AppLocalizationsKo(), failure), '알 수 없는 오류가 발생했습니다');
  });

  test('시간당 재전송 한도 실패는 잠시 후 다시 시도하라는 안내를 보여준다', () {
    const failure = RateLimitedFailure();
    expect(failureText(AppLocalizationsKo(), failure), '너무 많이 시도했어요. 잠시 후 다시 시도해 주세요');
  });

  test('가입 거부 실패는 서버가 준 이유를 그대로 보여준다', () {
    const failure = SignUpRejectedFailure('허용되지 않은 학교 이메일이에요');
    expect(failureText(AppLocalizationsKo(), failure), '허용되지 않은 학교 이메일이에요');
  });

  test('서버가 잠깐 못 받으면 잠시 후 다시 시도하라고 안내한다', () {
    const failure = ServerUnavailableFailure();
    expect(failureText(AppLocalizationsKo(), failure), '잠시 후 다시 시도해 주세요');
  });

  test('서버 거부 사유를 그대로 보여준다', () {
    const failure = ServerRejectedFailure('이미 검토 중이에요');
    expect(failureText(AppLocalizationsKo(), failure), '이미 검토 중이에요');
  });
  group('학교 메일 인증(02 · 03)', () {
    test('인증번호를 못 보냈으면 잠시 후 다시 하라는 임시 문구', () {
      expect(failureText(AppLocalizationsKo(), const CodeNotSentFailure()), '인증번호를 보내지 못했어요. 잠시 후 다시 시도해 주세요');
    });

    test('학교 메일 인증을 못 마쳤으면 잠시 후 다시 하라는 임시 문구', () {
      expect(
        failureText(AppLocalizationsKo(), const SchoolEmailIncompleteFailure()),
        '학교 메일 인증을 마치지 못했어요. 잠시 후 다시 시도해 주세요',
      );
    });

    // 설계 5-4 문구 1 · 2 · 3(10-17 학생증 제거 B안): 내 소셜과 다른 소셜이 쥔 메일 → 그 소셜로 다시 로그인.
    test('다른 소셜이 쥔 메일이면 "이미 {X}로 가입된 학교 메일이에요" / "{X}로 로그인해 주세요" 와 다시 로그인 길', () {
      const cases = {'kakao': '카카오', 'google': '구글', 'apple': '애플'};
      for (final MapEntry(key: provider, value: label) in cases.entries) {
        final mine = provider == 'kakao' ? 'google' : 'kakao';
        final failure = SchoolEmailTakenFailure('서버 문구', provider, myProvider: mine);

        expect(failureText(AppLocalizationsKo(), failure), '이미 $label로 가입된 학교 메일이에요', reason: provider);
        expect(takenHintText(AppLocalizationsKo(), failure), '$label로 로그인해 주세요', reason: provider);
        expect(AppLocalizationsKo().authSchoolEmailRelogin(provider: failure.otherSocialProvider()!), '$label로 다시 로그인', reason: provider);
        expect(takenReloginNoticeText(AppLocalizationsKo(), failure), '이 학교 메일은 $label로 가입돼 있어요. $label로 로그인해 주세요', reason: provider);
        expect(failure.isTakenBySocial(), isTrue, reason: provider);
      }
    });

    // 설계 5-4 문구 4: 이미 그 소셜로 로그인 중이다 — "그 소셜로 로그인하라" 는 잘못된 안내다(빌려 쓰기 의심).
    test('내 소셜과 같은 소셜이 쥔 다른 계정이면 "이미 가입된 학교 메일이에요" / "한 학교 메일로는 계정 하나만…", 다시 로그인 없음', () {
      for (final provider in ['kakao', 'google', 'apple']) {
        final failure = SchoolEmailTakenFailure('서버 문구', provider, myProvider: provider);

        expect(failureText(AppLocalizationsKo(), failure), '이미 가입된 학교 메일이에요', reason: provider);
        expect(takenHintText(AppLocalizationsKo(), failure), '한 학교 메일로는 계정 하나만 만들 수 있어요', reason: provider);
        expect(failure.otherSocialProvider(), isNull, reason: provider);
        expect(takenReloginNoticeText(AppLocalizationsKo(), failure), isNull, reason: provider);
        expect(failure.isTakenBySocial(), isTrue, reason: provider);
      }
    });

    test('provider 가 email 이면 앱 상수 "이 학교 메일로 이미 가입된 계정이 있어요. 문의해 주세요", 보조 문구 없음', () {
      const failure = SchoolEmailTakenFailure('서버 문구', 'email', myProvider: 'kakao');

      expect(failureText(AppLocalizationsKo(), failure), '이 학교 메일로 이미 가입된 계정이 있어요. 문의해 주세요');
      expect(takenHintText(AppLocalizationsKo(), failure), isNull);
      expect(failure.otherSocialProvider(), isNull);
      expect(failure.isTakenBySocial(), isFalse);
    });

    test('모르는 수단이면 서버 문구를 그대로 쓰고 보조 문구는 없다', () {
      const failure = SchoolEmailTakenFailure('이 메일은 다른 수단으로 가입돼 있어요', 'line');

      expect(failureText(AppLocalizationsKo(), failure), '이 메일은 다른 수단으로 가입돼 있어요');
      expect(takenHintText(AppLocalizationsKo(), failure), isNull);
      expect(failure.otherSocialProvider(), isNull);
      expect(failure.isTakenBySocial(), isFalse);
    });

    test('서버가 임시 토큰을 못 읽었으면(미확인) 다시 하라는 임시 문구', () {
      expect(
        failureText(AppLocalizationsKo(), const SchoolEmailNotConfirmedFailure()),
        '학교 메일 인증을 마치지 못했어요. 잠시 후 다시 시도해 주세요',
      );
    });

    test('등록되지 않은 학교 · 재가입 제한(422)은 서버 문구를 그대로', () {
      expect(failureText(AppLocalizationsKo(), const SchoolEmailRejectedFailure('등록되지 않은 학교 메일이에요')), '등록되지 않은 학교 메일이에요');
    });
  });

  // 글자로 바꾸는 곳(core/l10n/error_text.dart)이 꺼내 읽는 값 — 문구는 거기서, 값은 여기서.
  group('error_text 가 읽는 값', () {
    test('서버가 준 문구를 들고 있는 실패는 그 문구를 꺼낼 수 있다', () {
      expect(const RateLimitedFailure('내일 다시').serverMessage, '내일 다시');
      expect(const RateLimitedFailure().serverMessage, isNull);
      expect(const SignUpRejectedFailure('가입 거부').serverMessage, '가입 거부');
      expect(const ServerRejectedFailure('거부', code: 'X').serverMessage, '거부');
      expect(const SchoolEmailRejectedFailure('학교 거부').serverMessage, '학교 거부');
      expect(const SchoolEmailTakenFailure('중복', 'line').serverMessage, '중복');
    });

    test('다른 소셜이 쥔 메일이면 그 소셜의 서버 값을, 내 소셜 · 이메일 계정 · 모르는 수단이면 null 을 돌려준다', () {
      expect(const SchoolEmailTakenFailure('서버', 'kakao', myProvider: 'google').otherSocialProvider(), 'kakao');
      expect(const SchoolEmailTakenFailure('서버', 'kakao').otherSocialProvider(), 'kakao');
      expect(const SchoolEmailTakenFailure('서버', 'kakao', myProvider: 'kakao').otherSocialProvider(), isNull);
      expect(const SchoolEmailTakenFailure('서버', 'email').otherSocialProvider(), isNull);
      expect(const SchoolEmailTakenFailure('서버', 'line').otherSocialProvider(), isNull);
    });

    test('이메일 방식 계정이 쥔 메일인지 안다', () {
      expect(const SchoolEmailTakenFailure('서버', 'email').isTakenByEmailAccount(), isTrue);
      expect(const SchoolEmailTakenFailure('서버', 'kakao').isTakenByEmailAccount(), isFalse);
    });

    test('앱이 정하는 에러는 종류를 들고 다니고 글자는 error_text 가 정한다', () {
      const failure = AppErrorFailure(AppError.notificationsLoad);

      expect(failure.error, AppError.notificationsLoad);
      expect(failureText(AppLocalizationsKo(), failure), '알림을 불러오지 못했어요');
    });
  });

  // 시작 화면 소셜 로그인 토스트 문구(대장 지시문 07).
  test('소셜 로그인을 사용자가 취소하면 취소 안내를 보여준다', () {
    const failure = LoginCancelledFailure();
    expect(failureText(AppLocalizationsKo(), failure), '로그인이 취소됐어요');
  });

  test('소셜 로그인이 실패하면 잠시 후 다시 시도하라고 안내한다', () {
    const failure = SocialLoginFailure();
    expect(failureText(AppLocalizationsKo(), failure), '로그인하지 못했어요. 잠시 후 다시 시도해 주세요');
  });
}
