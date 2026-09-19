import 'package:campus_mate/auth/model/university_email.dart';
import 'package:campus_mate/auth/model/verification_gate.dart';
import 'package:campus_mate/auth/view/school_info_screen.dart';
import 'package:campus_mate/auth/view/sign_up_screen.dart';
import 'package:campus_mate/auth/view/student_verification_screen.dart';
import 'package:campus_mate/auth/view/verify_code_screen.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/router/auth_redirect.dart';
import 'package:campus_mate/core/router/placeholder_screens.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// 앱의 라우터를 구성한다.
/// 이동 판단은 [AuthRedirect] 가 맡고 여기서는 경로와 화면만 연결한다.
abstract final class AppRouter {
  static GoRouter create({
    required bool Function() isAuthenticated,
    required VerificationGate Function() verificationGate,
    Listenable? refreshListenable,
  }) {
    return GoRouter(
      initialLocation: AppRoutes.splash,
      refreshListenable: refreshListenable,
      redirect: (context, state) {
        return AuthRedirect(isAuthenticated(), verificationGate()).resolve(state.matchedLocation);
      },
      routes: _routes(),
    );
  }

  /// 3b·3c 는 [AuthRedirect] 가 미인증·게이트 미충족을 이미 막아 화면 가드를 두지 않는다.
  static List<RouteBase> _routes() {
    return <RouteBase>[
      GoRoute(path: AppRoutes.splash, builder: (context, state) => const SplashScreen()),
      GoRoute(path: AppRoutes.login, builder: (context, state) => const SignUpScreen()),
      GoRoute(path: AppRoutes.verifyCode, redirect: _verifyCodeGuard, builder: _buildVerifyCode),
      GoRoute(path: AppRoutes.studentVerification, builder: (context, state) => const StudentVerificationScreen()),
      GoRoute(path: AppRoutes.schoolInfo, builder: (context, state) => const SchoolInfoScreen()),
      GoRoute(path: AppRoutes.home, builder: (context, state) => const HomeScreen()),
    ];
  }

  /// 이메일 없이 이 경로에 들어오면 로그인부터 다시 시작한다.
  static String? _verifyCodeGuard(BuildContext context, GoRouterState state) {
    return state.extra is UniversityEmail ? null : AppRoutes.login;
  }

  static Widget _buildVerifyCode(BuildContext context, GoRouterState state) {
    return VerifyCodeScreen(email: state.extra as UniversityEmail);
  }
}
