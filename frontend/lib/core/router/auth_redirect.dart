import 'package:campus_mate/auth/model/verification_gate.dart';
import 'package:campus_mate/core/router/app_routes.dart';

/// 로그인 여부와 인증 게이트에 따라 이동해야 할 경로를 판단한다.
///
/// 라우터에서 떼어낸 이유는 이 판단이 화면과 무관한 규칙이고,
/// 위젯을 띄우지 않고 테스트해야 하기 때문이다.
class AuthRedirect {
  const AuthRedirect(this._isAuthenticated, this._gate);

  final bool _isAuthenticated;
  final VerificationGate _gate;

  /// 이동이 필요 없으면 null 을 돌려준다 (go_router 의 규약).
  String? resolve(String location) {
    if (_isAuthenticated) {
      return _resolveForMember(location);
    }
    return _resolveForGuest(location);
  }

  /// 게이트를 통과하지 못했으면 그 화면에 묶어두고,
  /// 통과했으면 로그인·스플래시·게이트 화면에 머무를 이유가 없다.
  String? _resolveForMember(String location) {
    final gateTarget = _gateTarget();
    if (gateTarget != null) {
      return location == gateTarget ? null : gateTarget;
    }
    if (_isBeforeHome(location)) {
      return AppRoutes.home;
    }
    return null;
  }

  /// 아직 통과하지 못한 게이트 화면. 모두 통과했으면 null.
  String? _gateTarget() {
    return switch (_gate) {
      VerificationGate.needsStudentVerification => AppRoutes.studentVerification,
      VerificationGate.needsSchoolInfo => AppRoutes.schoolInfo,
      VerificationGate.complete => null,
    };
  }

  /// 홈에 도착하기 전에만 지나는 화면들.
  bool _isBeforeHome(String location) {
    return location == AppRoutes.login ||
        location == AppRoutes.splash ||
        location == AppRoutes.studentVerification ||
        location == AppRoutes.schoolInfo;
  }

  /// 로그인하지 않은 사용자는 로그인·인증코드 화면 외에는 갈 수 없다.
  String? _resolveForGuest(String location) {
    if (location == AppRoutes.login || location == AppRoutes.verifyCode) {
      return null;
    }
    return AppRoutes.login;
  }
}
