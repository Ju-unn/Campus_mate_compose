import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/router/auth_redirect.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('로그인하지 않은 사용자', () {
    const redirect = AuthRedirect(false);

    test('로그인 화면에서는 이동시키지 않는다', () {
      expect(redirect.resolve(AppRoutes.login), isNull);
    });

    test('홈으로 가려 하면 로그인 화면으로 보낸다', () {
      expect(redirect.resolve(AppRoutes.home), AppRoutes.login);
    });

    test('스플래시에서도 로그인 화면으로 보낸다', () {
      expect(redirect.resolve(AppRoutes.splash), AppRoutes.login);
    });
  });

  group('로그인한 사용자', () {
    const redirect = AuthRedirect(true);

    test('로그인 화면으로 가려 하면 홈으로 보낸다', () {
      expect(redirect.resolve(AppRoutes.login), AppRoutes.home);
    });

    test('스플래시에서는 홈으로 보낸다', () {
      expect(redirect.resolve(AppRoutes.splash), AppRoutes.home);
    });

    test('홈에서는 이동시키지 않는다', () {
      expect(redirect.resolve(AppRoutes.home), isNull);
    });
  });
}
