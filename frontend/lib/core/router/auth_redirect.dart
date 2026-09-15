import 'package:campus_mate/core/router/app_routes.dart';

/// 로그인 여부에 따라 이동해야 할 경로를 판단한다.
///
/// 라우터에서 떼어낸 이유는 이 판단이 화면과 무관한 규칙이고,
/// 위젯을 띄우지 않고 테스트해야 하기 때문이다.
class AuthRedirect {
  const AuthRedirect(this._isAuthenticated);

  final bool _isAuthenticated;

  /// 이동이 필요 없으면 null 을 돌려준다 (go_router 의 규약).
  String? resolve(String location) {
    if (_isAuthenticated) {
      return _resolveForMember(location);
    }
    return _resolveForGuest(location);
  }

  /// 로그인한 사용자는 로그인·스플래시에 머무를 이유가 없다.
  String? _resolveForMember(String location) {
    if (location == AppRoutes.login || location == AppRoutes.splash) {
      return AppRoutes.home;
    }
    return null;
  }

  /// 로그인하지 않은 사용자는 로그인 화면 외에는 갈 수 없다.
  String? _resolveForGuest(String location) {
    if (location == AppRoutes.login) {
      return null;
    }
    return AppRoutes.login;
  }
}
