import 'package:campus_mate/auth/model/verification_gate.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/router/auth_redirect.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('로그인하지 않은 사용자', () {
    // 게이트가 미통과여도 로그인이 먼저다 — 게이트 화면이 로그인보다 앞설 수 없다.
    const redirect = AuthRedirect(false, VerificationGate.needsStudentVerification);

    test('로그인 화면에서는 이동시키지 않는다', () {
      expect(redirect.resolve(AppRoutes.login), isNull);
    });

    test('홈으로 가려 하면 로그인 화면으로 보낸다', () {
      expect(redirect.resolve(AppRoutes.home), AppRoutes.login);
    });

    test('스플래시에서도 로그인 화면으로 보낸다', () {
      expect(redirect.resolve(AppRoutes.splash), AppRoutes.login);
    });

    test('인증코드 화면에서는 이동시키지 않는다', () {
      expect(redirect.resolve(AppRoutes.verifyCode), isNull);
    });

    test('학생증 화면으로 가려 해도 로그인 화면으로 보낸다', () {
      expect(redirect.resolve(AppRoutes.studentVerification), AppRoutes.login);
    });
  });

  group('게이트를 모두 통과한 사용자', () {
    const redirect = AuthRedirect(true, VerificationGate.complete);

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
  });

  group('게이트를 통과하지 못한 사용자', () {
    test('학생증 미인증이면 3b 로 보낸다', () {
      const redirect = AuthRedirect(true, VerificationGate.needsStudentVerification);

      expect(redirect.resolve(AppRoutes.home), AppRoutes.studentVerification);
    });

    test('학생증은 통과했지만 학과 정보가 없으면 3c 로 보낸다', () {
      const redirect = AuthRedirect(true, VerificationGate.needsSchoolInfo);

      expect(redirect.resolve(AppRoutes.home), AppRoutes.schoolInfo);
    });

    test('이미 목적지에 있으면 리다이렉트하지 않는다', () {
      const redirect = AuthRedirect(true, VerificationGate.needsStudentVerification);

      expect(redirect.resolve(AppRoutes.studentVerification), isNull);
    });

    test('앞 단계를 건너뛰고 3c 에 들어와도 3b 로 되돌린다', () {
      const redirect = AuthRedirect(true, VerificationGate.needsStudentVerification);

      expect(redirect.resolve(AppRoutes.schoolInfo), AppRoutes.studentVerification);
    });
  });
}
