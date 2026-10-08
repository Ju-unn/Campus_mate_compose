import 'package:campus_mate/auth/model/verification_gate.dart';
import 'package:campus_mate/core/auth/account_status_listenable.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/profile/model/onboarding_step.dart';

/// 로그인 여부와 인증 게이트에 따라 이동해야 할 경로를 판단한다.
///
/// 라우터에서 떼어낸 이유는 이 판단이 화면과 무관한 규칙이고,
/// 위젯을 띄우지 않고 테스트해야 하기 때문이다.
class AuthRedirect {
  const AuthRedirect(
    this._isAuthenticated,
    this._gate,
    this._onboardingStep, {
    this._accountStatus = AccountStatus.active,
  });

  final bool _isAuthenticated;
  final VerificationGate _gate;
  final OnboardingStep _onboardingStep;
  final AccountStatus _accountStatus;

  /// 이동이 필요 없으면 null 을 돌려준다 (go_router 의 규약).
  String? resolve(String location) {
    if (_isAuthenticated) {
      return _resolveForMember(location);
    }
    return _resolveForGuest(location);
  }

  /// 게이트를 통과하지 못했으면 그 화면에 묶어두고, 게이트는 통과했지만 온보딩이 남았으면
  /// 그 다음 온보딩 화면에 묶어둔다. 둘 다 끝났으면 로그인·스플래시·게이트·온보딩 화면에
  /// 머무를 이유가 없다.
  String? _resolveForMember(String location) {
    // 탈퇴 · 로그인 만료면 곧 main.dart 가 로그아웃해 로그인 화면으로 간다 — 그 사이 관문 화면으로 튀지 않게 제자리.
    if (_accountStatus == AccountStatus.withdrawn || _accountStatus == AccountStatus.expired) {
      return null;
    }
    // 정지가 가장 먼저다 — 정지면 게이트·온보딩 조회가 403 이라 기본값(3b · 04-1)에 머물러 있다.
    if (_accountStatus == AccountStatus.suspended) {
      return location == AppRoutes.accountSuspended ? null : AppRoutes.accountSuspended;
    }
    final gateTarget = _gateTarget();
    if (gateTarget != null) {
      return _isOnGate(location, gateTarget) ? null : gateTarget;
    }
    final onboardingTarget = _onboardingTarget();
    if (onboardingTarget != null) {
      // 한 단계가 화면 둘로 나뉜 경우(04-2 → 04-3) 아래 경로도 같은 단계로 본다.
      final isSameStep = location == onboardingTarget || location.startsWith('$onboardingTarget/');
      return isSameStep ? null : onboardingTarget;
    }
    if (_isBeforeHome(location)) {
      return AppRoutes.home;
    }
    return null;
  }

  /// 아직 통과하지 못한 게이트 화면. 모두 통과했으면 null.
  String? _gateTarget() {
    return switch (_gate) {
      VerificationGate.unknown => AppRoutes.splash,
      VerificationGate.unreachable => AppRoutes.offline,
      VerificationGate.needsConsent || VerificationGate.needsConsentRenewal => AppRoutes.consent,
      // 02(학교 메일 입력). 03(인증번호)도 같은 관문이다 — [_isOnGate].
      VerificationGate.needsSchoolEmail => AppRoutes.login,
      VerificationGate.needsStudentVerification => AppRoutes.studentVerification,
      VerificationGate.needsSchoolInfo => AppRoutes.schoolInfo,
      VerificationGate.complete => null,
    };
  }

  /// 관문 하나가 화면 둘인 경우(학교 메일 02 → 03) 둘째 화면도 그 관문으로 본다.
  /// 인증을 마쳐 관문이 바뀌면 02 · 03 둘 다 다음 관문으로 밀려나 다시 돌아오지 못한다.
  bool _isOnGate(String location, String gateTarget) {
    if (location == gateTarget) {
      return true;
    }
    return _gate == VerificationGate.needsSchoolEmail && location == AppRoutes.verifyCode;
  }

  /// 아직 끝내지 못한 온보딩 화면. 모두 끝냈으면 null.
  String? _onboardingTarget() {
    return switch (_onboardingStep) {
      OnboardingStep.basicInfo => AppRoutes.onboardingBasicInfo,
      OnboardingStep.kakaoId => AppRoutes.onboardingKakaoId,
      OnboardingStep.photos => AppRoutes.onboardingPhotos,
      OnboardingStep.avatar => AppRoutes.onboardingAvatar,
      OnboardingStep.appearanceType => AppRoutes.onboardingAppearanceType,
      OnboardingStep.interests => AppRoutes.onboardingInterests,
      OnboardingStep.myTraits => AppRoutes.onboardingMyTraits,
      OnboardingStep.survey => AppRoutes.onboardingSurvey,
      OnboardingStep.idealConditions => AppRoutes.onboardingIdealConditions,
      OnboardingStep.idealTraits => AppRoutes.onboardingIdealTraits,
      OnboardingStep.idealNote => AppRoutes.onboardingIdealNote,
      OnboardingStep.bio => AppRoutes.onboardingBio,
      OnboardingStep.complete => null,
    };
  }

  /// 홈에 도착하기 전에만 지나는 화면들.
  /// 홈은 09b 메인 자리 화면이고, 오늘의 카드는 하단 내비의 `/today` 다(조각 4).
  bool _isBeforeHome(String location) {
    return location == AppRoutes.login ||
        location == AppRoutes.verifyCode ||
        location == AppRoutes.splash ||
        location == AppRoutes.offline ||
        location == AppRoutes.consent ||
        location == AppRoutes.studentVerification ||
        location == AppRoutes.schoolInfo ||
        _isOnboardingRoute(location);
  }

  /// 아래 경로도 그 온보딩 화면으로 본다 — `_resolveForMember` 와 **같은 규칙**이어야 한다.
  /// 규칙이 갈라지면 `/onboarding/photos/avatar-source` 같은 화면이 한쪽에서만 온보딩이 된다.
  bool _isOnboardingRoute(String location) {
    return _onboardingRoutes.any(
      (route) => location == route || location.startsWith('$route/'),
    );
  }

  static const _onboardingRoutes = <String>{
    AppRoutes.onboardingBasicInfo,
    AppRoutes.onboardingKakaoId,
    AppRoutes.onboardingPhotos,
    AppRoutes.onboardingAvatarSource,
    AppRoutes.onboardingAvatar,
    AppRoutes.onboardingAppearanceType,
    AppRoutes.onboardingInterests,
    AppRoutes.onboardingMyTraits,
    AppRoutes.onboardingSurvey,
    AppRoutes.onboardingIdealConditions,
    AppRoutes.onboardingIdealTraits,
    AppRoutes.onboardingIdealNote,
    AppRoutes.onboardingBio,
  };

  /// 로그인하지 않은 사용자는 로그인·인증코드 화면 외에는 갈 수 없다.
  String? _resolveForGuest(String location) {
    if (location == AppRoutes.login || location == AppRoutes.verifyCode) {
      return null;
    }
    return AppRoutes.login;
  }
}
