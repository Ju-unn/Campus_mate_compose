import 'package:campus_mate/auth/model/verification_gate.dart';
import 'package:campus_mate/core/auth/account_status_listenable.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/router/auth_redirect.dart';
import 'package:campus_mate/profile/model/onboarding_step.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 시작 화면(스플래시를 고친 것)에 소셜 로그인 버튼이 있다 — 로그아웃 상태는 어디로 가든 시작 화면에 머문다(대장 지시문 07).
  // 예전에는 로그인(학교 메일 입력) 화면으로 보냈다. 그 화면은 지시문 08 에서 로그인 뒤 단계가 된다.
  group('로그인하지 않은 사용자', () {
    // 게이트가 미통과여도 로그인이 먼저다 — 게이트 화면이 로그인보다 앞설 수 없다.
    const redirect = AuthRedirect(false, VerificationGate.needsStudentVerification, OnboardingStep.basicInfo);

    test('시작 화면(스플래시)에 머문다', () {
      expect(redirect.resolve(AppRoutes.splash), isNull);
    });

    test('홈으로 가려 하면 시작 화면으로 보낸다', () {
      expect(redirect.resolve(AppRoutes.home), AppRoutes.splash);
    });

    test('옛 학교 메일 로그인 · 인증코드 화면으로 가도 시작 화면으로 보낸다', () {
      expect(redirect.resolve(AppRoutes.login), AppRoutes.splash);
      expect(redirect.resolve(AppRoutes.verifyCode), AppRoutes.splash);
    });

    test('학생증 화면으로 가려 해도 시작 화면으로 보낸다', () {
      expect(redirect.resolve(AppRoutes.studentVerification), AppRoutes.splash);
    });

    test('관문을 아직 모를 때(로그아웃하면 게이트가 unknown 으로 돌아간다)에도 시작 화면에 머문다', () {
      const unknown = AuthRedirect(false, VerificationGate.unknown, OnboardingStep.basicInfo);

      expect(unknown.resolve(AppRoutes.splash), isNull);
      expect(unknown.resolve(AppRoutes.home), AppRoutes.splash);
    });
  });

  group('게이트·온보딩을 모두 통과한 사용자', () {
    const redirect = AuthRedirect(true, VerificationGate.complete, OnboardingStep.complete);

    test('로그인 화면으로 가려 하면 홈으로 보낸다', () {
      expect(redirect.resolve(AppRoutes.login), AppRoutes.home);
    });

    test('스플래시에서는 홈으로 보낸다', () {
      expect(redirect.resolve(AppRoutes.splash), AppRoutes.home);
    });

    test('홈에서는 이동시키지 않는다', () {
      expect(redirect.resolve(AppRoutes.home), isNull);
    });

    test('3b·3c 에 머물지 않는다', () {
      expect(redirect.resolve(AppRoutes.studentVerification), AppRoutes.home);
      expect(redirect.resolve(AppRoutes.schoolInfo), AppRoutes.home);
    });

    test('온보딩 화면에도 머물지 않는다', () {
      expect(redirect.resolve(AppRoutes.onboardingBasicInfo), AppRoutes.home);
    });

    test('온보딩 화면의 아래 경로에도 머물지 않는다', () {
      // 04-2 아래에 04-3 이 붙는 것처럼 한 단계가 화면 둘로 나뉜 경우다.
      // "다음 단계로 묶는 규칙"과 "홈 앞 화면 판정"이 갈라지면 여기서 걸린다.
      expect(redirect.resolve(AppRoutes.onboardingAvatarSource), AppRoutes.home);
      expect(redirect.resolve('${AppRoutes.onboardingPhotos}/무엇이든'), AppRoutes.home);
    });

    // 20 · 20d 는 서버 단계가 아니라 06-3 뒤 앱에서만 잇는다(2026-09-28 대장 D2) — auth_redirect 는 그대로 둔다.
    test('온보딩을 끝낸 사람은 20 · 20d 에 머문다(홈으로 튕기지 않는다)', () {
      expect(redirect.resolve(AppRoutes.onboardingReferral), isNull);
      expect(redirect.resolve(AppRoutes.onboardingAcquisition), isNull);
    });

    // 06-4 도 20d 뒤 앱에서만 잇는다(결정 8 ①). 거기서 여는 8d 도 같다 — 설정의 8d 로 가면 뒤로가 16 쪽으로 샌다.
    test('온보딩을 끝낸 사람은 06-4 와 거기서 연 8d 에 머문다', () {
      expect(redirect.resolve(AppRoutes.onboardingContactBlock), isNull);
      expect(redirect.resolve(AppRoutes.onboardingContactPicker), isNull);
    });

    // 나 탭 편집은 온보딩 화면을 `/me/...` 에 다시 띄운다 — `/onboarding/...` 이 아니라 돌려보내지지 않는다(계획서 A2).
    test('나 탭 편집 경로에는 머문다', () {
      for (final path in [
        AppRoutes.myProfileEdit,
        AppRoutes.myIdealConditions,
        '${AppRoutes.myTags}/interests',
      ]) {
        expect(redirect.resolve(path), isNull, reason: path);
      }
    });
  });

  group('약관 동의 전(02-c, 첫 관문)', () {
    test('동의 전이면 3b 보다 먼저 02-c 로 보낸다', () {
      const redirect = AuthRedirect(true, VerificationGate.needsConsent, OnboardingStep.basicInfo);

      expect(redirect.resolve(AppRoutes.splash), AppRoutes.consent);
      expect(redirect.resolve(AppRoutes.studentVerification), AppRoutes.consent);
      expect(redirect.resolve(AppRoutes.home), AppRoutes.consent);
    });

    test('재동의도 같은 02-c 로 보낸다 — 온보딩을 마친 계정도', () {
      const redirect = AuthRedirect(true, VerificationGate.needsConsentRenewal, OnboardingStep.complete);

      expect(redirect.resolve(AppRoutes.home), AppRoutes.consent);
      expect(redirect.resolve(AppRoutes.settings), AppRoutes.consent);
    });

    test('02-c 에 있으면 이동시키지 않는다', () {
      for (final gate in [VerificationGate.needsConsent, VerificationGate.needsConsentRenewal]) {
        expect(AuthRedirect(true, gate, OnboardingStep.basicInfo).resolve(AppRoutes.consent), isNull, reason: '$gate');
      }
    });

    test('동의를 마치면 02-c 에서 다음 관문으로 보낸다', () {
      expect(
        const AuthRedirect(true, VerificationGate.needsStudentVerification, OnboardingStep.basicInfo)
            .resolve(AppRoutes.consent),
        AppRoutes.studentVerification,
      );
      expect(
        const AuthRedirect(true, VerificationGate.complete, OnboardingStep.complete).resolve(AppRoutes.consent),
        AppRoutes.home,
      );
    });

    test('정지가 동의보다 먼저다', () {
      const redirect = AuthRedirect(true, VerificationGate.needsConsent, OnboardingStep.basicInfo,
          accountStatus: AccountStatus.suspended);

      expect(redirect.resolve(AppRoutes.consent), AppRoutes.accountSuspended);
    });

    test('로그인 전에는 02-c 로 가도 시작 화면으로 보낸다', () {
      const redirect = AuthRedirect(false, VerificationGate.needsConsent, OnboardingStep.basicInfo);

      expect(redirect.resolve(AppRoutes.consent), AppRoutes.splash);
    });
  });

  group('학교 메일 관문(02 · 03, 동의 다음)', () {
    const redirect = AuthRedirect(true, VerificationGate.needsSchoolEmail, OnboardingStep.basicInfo);

    test('학교 메일 인증 전이면 02(학교 메일 입력)로 보낸다', () {
      for (final path in [
        AppRoutes.splash,
        AppRoutes.consent,
        AppRoutes.studentVerification,
        AppRoutes.schoolInfo,
        AppRoutes.onboardingBasicInfo,
        AppRoutes.home,
      ]) {
        expect(redirect.resolve(path), AppRoutes.login, reason: path);
      }
    });

    test('02 와 03(인증번호)에는 머문다', () {
      expect(redirect.resolve(AppRoutes.login), isNull);
      expect(redirect.resolve(AppRoutes.verifyCode), isNull);
    });

    test('인증을 마치면 02 · 03 에서 학생증(3b)으로 보내고 다시 돌아오지 못한다', () {
      const verified = AuthRedirect(true, VerificationGate.needsStudentVerification, OnboardingStep.basicInfo);

      expect(verified.resolve(AppRoutes.login), AppRoutes.studentVerification);
      expect(verified.resolve(AppRoutes.verifyCode), AppRoutes.studentVerification);
    });

    test('모두 끝난 계정은 03 에 머물지 않고 홈으로 간다', () {
      const done = AuthRedirect(true, VerificationGate.complete, OnboardingStep.complete);

      expect(done.resolve(AppRoutes.verifyCode), AppRoutes.home);
    });

    test('다른 관문에서는 03 으로 가지 못한다', () {
      expect(
        const AuthRedirect(true, VerificationGate.needsConsent, OnboardingStep.basicInfo).resolve(AppRoutes.verifyCode),
        AppRoutes.consent,
      );
      expect(
        const AuthRedirect(true, VerificationGate.needsSchoolInfo, OnboardingStep.basicInfo)
            .resolve(AppRoutes.verifyCode),
        AppRoutes.schoolInfo,
      );
    });
  });

  // 순서 고정: 정지 > 동의 > 학교 메일 > 학생증 > 학과와 학번 > 온보딩. 한 줄이 (계정 상태, 관문) 하나다.
  group('관문 순서 표', () {
    const rows = <(AccountStatus, VerificationGate, String)>[
      (AccountStatus.suspended, VerificationGate.needsConsent, AppRoutes.accountSuspended),
      (AccountStatus.suspended, VerificationGate.needsSchoolEmail, AppRoutes.accountSuspended),
      (AccountStatus.active, VerificationGate.needsConsent, AppRoutes.consent),
      (AccountStatus.active, VerificationGate.needsConsentRenewal, AppRoutes.consent),
      (AccountStatus.active, VerificationGate.needsSchoolEmail, AppRoutes.login),
      (AccountStatus.active, VerificationGate.needsStudentVerification, AppRoutes.studentVerification),
      (AccountStatus.active, VerificationGate.needsSchoolInfo, AppRoutes.schoolInfo),
      (AccountStatus.active, VerificationGate.complete, AppRoutes.onboardingBasicInfo),
    ];
    for (final (status, gate, target) in rows) {
      test('$status · $gate → $target', () {
        final redirect = AuthRedirect(true, gate, OnboardingStep.basicInfo, accountStatus: status);

        expect(redirect.resolve(AppRoutes.home), target);
      });
    }
  });

  group('관문을 아직 모를 때(결정 13, B10)', () {
    test('묻는 중이면 동의 화면 대신 스플래시에 둔다', () {
      const redirect = AuthRedirect(true, VerificationGate.unknown, OnboardingStep.basicInfo);

      expect(redirect.resolve(AppRoutes.splash), isNull);
      expect(redirect.resolve(AppRoutes.home), AppRoutes.splash);
      expect(redirect.resolve(AppRoutes.consent), AppRoutes.splash);
    });

    test('조회가 실패했으면 인터넷 없음 화면으로 보낸다', () {
      const redirect = AuthRedirect(true, VerificationGate.unreachable, OnboardingStep.basicInfo);

      expect(redirect.resolve(AppRoutes.splash), AppRoutes.offline);
      expect(redirect.resolve(AppRoutes.home), AppRoutes.offline);
      expect(redirect.resolve(AppRoutes.offline), isNull);
    });

    test('연결이 돌아와 관문을 알면 인터넷 없음 화면에서 원래 화면으로 보낸다', () {
      expect(
        const AuthRedirect(true, VerificationGate.needsConsent, OnboardingStep.basicInfo).resolve(AppRoutes.offline),
        AppRoutes.consent,
      );
      expect(
        const AuthRedirect(true, VerificationGate.complete, OnboardingStep.complete).resolve(AppRoutes.offline),
        AppRoutes.home,
      );
    });

    test('정지가 인터넷 없음보다 먼저다', () {
      const redirect = AuthRedirect(true, VerificationGate.unreachable, OnboardingStep.basicInfo,
          accountStatus: AccountStatus.suspended);

      expect(redirect.resolve(AppRoutes.offline), AppRoutes.accountSuspended);
    });

    test('로그인 전에는 인터넷 없음 화면도 시작 화면으로 보낸다', () {
      const redirect = AuthRedirect(false, VerificationGate.unreachable, OnboardingStep.basicInfo);

      expect(redirect.resolve(AppRoutes.offline), AppRoutes.splash);
    });
  });

  group('게이트를 통과하지 못한 사용자', () {
    test('학생증 미인증이면 3b 로 보낸다', () {
      const redirect = AuthRedirect(true, VerificationGate.needsStudentVerification, OnboardingStep.basicInfo);

      expect(redirect.resolve(AppRoutes.home), AppRoutes.studentVerification);
    });

    test('학생증은 통과했지만 학과 정보가 없으면 3c 로 보낸다', () {
      const redirect = AuthRedirect(true, VerificationGate.needsSchoolInfo, OnboardingStep.basicInfo);

      expect(redirect.resolve(AppRoutes.home), AppRoutes.schoolInfo);
    });

    test('이미 목적지에 있으면 리다이렉트하지 않는다', () {
      const redirect = AuthRedirect(true, VerificationGate.needsStudentVerification, OnboardingStep.basicInfo);

      expect(redirect.resolve(AppRoutes.studentVerification), isNull);
    });

    test('앞 단계를 건너뛰고 3c 에 들어와도 3b 로 되돌린다', () {
      const redirect = AuthRedirect(true, VerificationGate.needsStudentVerification, OnboardingStep.basicInfo);

      expect(redirect.resolve(AppRoutes.schoolInfo), AppRoutes.studentVerification);
    });
  });

  group('검증은 끝났지만 온보딩이 남은 사용자', () {
    test('온보딩 화면으로 보낸다', () {
      const redirect = AuthRedirect(true, VerificationGate.complete, OnboardingStep.interests);

      expect(redirect.resolve(AppRoutes.home), AppRoutes.onboardingInterests);
    });

    test('이미 그 온보딩 화면에 있으면 이동시키지 않는다', () {
      const redirect = AuthRedirect(true, VerificationGate.complete, OnboardingStep.interests);

      expect(redirect.resolve(AppRoutes.onboardingInterests), isNull);
    });

    test('다른 온보딩 화면에 있으면 올바른 단계로 되돌린다', () {
      const redirect = AuthRedirect(true, VerificationGate.complete, OnboardingStep.basicInfo);

      expect(redirect.resolve(AppRoutes.onboardingBio), AppRoutes.onboardingBasicInfo);
    });

    test('나 탭 편집 경로로 가도 남은 온보딩 화면으로 보낸다', () {
      const redirect = AuthRedirect(true, VerificationGate.complete, OnboardingStep.interests);

      for (final path in [AppRoutes.myProfileEdit, AppRoutes.myIdealConditions, '${AppRoutes.myTags}/interests']) {
        expect(redirect.resolve(path), AppRoutes.onboardingInterests, reason: path);
      }
    });

    test('photos 단계에서는 04-3 아바타 사진 고르기에 머물 수 있다', () {
      const redirect = AuthRedirect(true, VerificationGate.complete, OnboardingStep.photos);

      expect(redirect.resolve(AppRoutes.onboardingAvatarSource), isNull);
    });

    test('photos 가 끝났으면 04-3 에서 다음 단계로 보낸다', () {
      const redirect = AuthRedirect(true, VerificationGate.complete, OnboardingStep.avatar);

      expect(redirect.resolve(AppRoutes.onboardingAvatarSource), AppRoutes.onboardingAvatar);
    });

    test('온보딩을 마쳤으면 04-3 에서 홈으로 보낸다', () {
      const redirect = AuthRedirect(true, VerificationGate.complete, OnboardingStep.complete);

      expect(redirect.resolve(AppRoutes.onboardingAvatarSource), AppRoutes.home);
    });

    test('06-3 을 끝내기 전에는 20 으로 가도 06-3 으로 돌려보낸다', () {
      const redirect = AuthRedirect(true, VerificationGate.complete, OnboardingStep.bio);

      expect(redirect.resolve(AppRoutes.onboardingReferral), AppRoutes.onboardingBio);
    });
  });

  group('정지된 계정(조각 6 A4)', () {
    test('suspended wins over onboarding default', () {
      // 정지면 온보딩 단계 조회가 403 이라 기본값 basicInfo 에 머문다 — 그래도 04-1 로 튀지 않는다.
      expect(
        const AuthRedirect(true, VerificationGate.complete, OnboardingStep.basicInfo,
                accountStatus: AccountStatus.suspended)
            .resolve(AppRoutes.onboardingBasicInfo),
        AppRoutes.accountSuspended,
      );
    });

    test('게이트 기본값(학생증 미통과)보다도 앞선다', () {
      const redirect = AuthRedirect(true, VerificationGate.needsStudentVerification, OnboardingStep.basicInfo,
          accountStatus: AccountStatus.suspended);

      expect(redirect.resolve(AppRoutes.splash), AppRoutes.accountSuspended);
      expect(redirect.resolve(AppRoutes.home), AppRoutes.accountSuspended);
    });

    test('suspended stays on the notice screen', () {
      const redirect = AuthRedirect(true, VerificationGate.complete, OnboardingStep.complete,
          accountStatus: AccountStatus.suspended);

      expect(redirect.resolve(AppRoutes.accountSuspended), isNull);
    });

    test('guest is never sent to the notice screen', () {
      const redirect = AuthRedirect(false, VerificationGate.complete, OnboardingStep.complete,
          accountStatus: AccountStatus.suspended);

      expect(redirect.resolve(AppRoutes.splash), isNull);
      expect(redirect.resolve(AppRoutes.accountSuspended), AppRoutes.splash);
    });
  });

  test('탈퇴 · 로그인 만료면 제자리 — 로그아웃이 로그인 화면으로 보내기 전에 관문 화면(02-c)으로 튀지 않는다', () {
    // 정지 화면에서 탈퇴하면 상태가 바뀌어 라우터가 다시 돈다. 게이트 기본값(약관 미동의)으로 떨어지면 안 된다.
    for (final status in [AccountStatus.withdrawn, AccountStatus.expired]) {
      final redirect = AuthRedirect(true, VerificationGate.needsConsent, OnboardingStep.basicInfo, accountStatus: status);

      expect(redirect.resolve(AppRoutes.accountSuspended), isNull, reason: '$status');
      expect(redirect.resolve(AppRoutes.home), isNull, reason: '$status');
    }
  });
}
