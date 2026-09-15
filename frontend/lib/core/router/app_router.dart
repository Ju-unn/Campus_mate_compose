import 'package:campus_mate/auth/view/sign_up_screen.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/router/auth_redirect.dart';
import 'package:campus_mate/core/router/placeholder_screens.dart';
import 'package:go_router/go_router.dart';

/// 앱의 라우터를 구성한다.
/// 이동 판단은 [AuthRedirect] 가 맡고 여기서는 경로와 화면만 연결한다.
abstract final class AppRouter {
  static GoRouter create({required bool isAuthenticated}) {
    final redirect = AuthRedirect(isAuthenticated);
    return GoRouter(
      initialLocation: AppRoutes.splash,
      redirect: (context, state) => redirect.resolve(state.matchedLocation),
      routes: _routes(),
    );
  }

  static List<RouteBase> _routes() {
    return <RouteBase>[
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const SignUpScreen(),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const HomeScreen(),
      ),
    ];
  }
}
