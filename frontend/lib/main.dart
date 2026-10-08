import 'dart:async';

import 'package:campus_mate/account/model/login_notice.dart';
import 'package:campus_mate/auth/model/kakao_login_gateway.dart';
import 'package:campus_mate/auth/model/verification_gate.dart';
import 'package:campus_mate/core/auth/account_status_listenable.dart';
import 'package:campus_mate/core/auth/session_scope.dart';
import 'package:campus_mate/core/auth/sign_out.dart';
import 'package:campus_mate/core/env.dart';
import 'package:campus_mate/core/lifecycle/resume_refresh.dart';
import 'package:campus_mate/core/push/push_provider.dart';
import 'package:campus_mate/core/push/push_refresh.dart';
import 'package:campus_mate/core/push/push_route.dart';
import 'package:campus_mate/core/router/app_router.dart';
import 'package:campus_mate/core/router/auth_redirect.dart';
import 'package:campus_mate/core/router/onboarding_step_listenable.dart';
import 'package:campus_mate/core/router/onboarding_step_listenable_provider.dart';
import 'package:campus_mate/core/router/verification_gate_listenable.dart';
import 'package:campus_mate/core/router/verification_gate_listenable_provider.dart';
import 'package:campus_mate/core/router/splash_hold.dart';
import 'package:campus_mate/core/supabase/auth_session_listenable.dart';
import 'package:campus_mate/core/supabase/auth_session_listenable_provider.dart';
import 'package:campus_mate/core/supabase/supabase_config.dart';
import 'package:campus_mate/core/supabase/supabase_initializer.dart';
import 'package:campus_mate/core/theme/app_theme.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 안드로이드는 google-services 플러그인이 넣어 준 리소스를 읽으므로 options 를 코드에 적지 않는다
  // (firebase_options.dart 를 만들지 않는 이유 — flutterfire CLI 를 새로 들이지 않는다).
  await Firebase.initializeApp();
  await SupabaseInitializer.run(SupabaseConfig.fromEnvironment());
  // 키가 없는 빌드(시험 · CI)는 건너뛴다 — 앱은 켜지고 카카오 버튼만 실패 토스트를 띄운다.
  await initializeKakaoSdk(Env.kakaoNativeAppKey);
  runApp(SessionScope(
    authChanges: Supabase.instance.client.auth.onAuthStateChange,
    child: const CampusMateApp(),
  ));
}

/// 앱 루트 위젯. 로그인 상태는 [AuthSessionListenable] 이,
/// 인증 게이트는 [VerificationGateListenable] 이 실시간으로 알려준다.
class CampusMateApp extends ConsumerStatefulWidget {
  const CampusMateApp({super.key});

  @override
  ConsumerState<CampusMateApp> createState() => _CampusMateAppState();
}

class _CampusMateAppState extends ConsumerState<CampusMateApp> {
  late final AuthSessionListenable _authSession;
  late final VerificationGateListenable _verificationGate;
  late final OnboardingStepListenable _onboardingStep;
  late final AccountStatusListenable _accountStatus;
  late final GoRouter _router;
  /// 앱이 백그라운드에서 돌아올 때 하단 내비 "대화" 숫자를 갱신한다([_refreshChatsOnResume]).
  late final AppLifecycleListener _lifecycle;
  /// 스플래시를 잠깐 붙잡아 두는 임시 장치 (로고 작업 때 다시 본다).
  final SplashHold _splashHold = SplashHold();
  final List<StreamSubscription<Map<String, dynamic>>> _pushSubscriptions = [];
  /// 알림을 눌러 연 경로. 라우터가 그대로 받아 줄 때까지 붙잡아 둔다([_openPendingPushRoute]).
  String? _pendingPushPath;

  @override
  void initState() {
    super.initState();
    // 시작 화면이 로그아웃 확인에 쓰는 것과 같은 인스턴스다. 로그아웃하면 SessionScope 가 새로 만든다.
    _authSession = ref.read(authSessionListenableProvider);
    // 3b·3c·온보딩 ViewModel 이 각 단계 직후 부르는 것과 같은 인스턴스여야 라우터가 다시 평가된다.
    _verificationGate = ref.read(verificationGateListenableProvider);
    _onboardingStep = ref.read(onboardingStepListenableProvider);
    // apiClientProvider 가 실패를 올리는 것과 같은 인스턴스다. 로그아웃하면 SessionScope 가 새로 만든다.
    _accountStatus = ref.read(accountStatusListenableProvider);
    _authSession.addListener(_refreshVerificationGate);
    _verificationGate.addListener(_startPushWhenGateOpens);
    _verificationGate.addListener(_openPendingPushRoute);
    _onboardingStep.addListener(_openPendingPushRoute);
    _accountStatus.addListener(_signOutWhenWithdrawn);
    _router = _createRouter();
    _lifecycle = AppLifecycleListener(onResume: _refreshChatsOnResume);
    _refreshVerificationGate();
  }

  /// 어느 탭에 있든 돌아오면 대화 목록·수락 대기를 다시 읽는다. 로그아웃·관문 미완료 가드는 함수 안에 있다.
  void _refreshChatsOnResume() =>
      refreshOnResume(ref.read, isAuthenticated: _authSession.isAuthenticated, gate: _verificationGate.value);

  /// 탈퇴(직접 16c 든 다른 기기에서든)면 시작 화면용 알림을 남기고 로그아웃한다 — 로그아웃은 여기 한 곳뿐이다.
  void _signOutWhenWithdrawn() => signOutWhenWithdrawn(_accountStatus.value, ref.read(signOutProvider));

  /// 세션이 바뀔 때마다 게이트·온보딩 단계를 다시 조회한다.
  /// 로그아웃하면 조회에 쓸 토큰이 없고, 앞 사용자의 통과 상태를
  /// 다음 사용자가 물려받으면 안 되므로 캐시를 비운다.
  void _refreshVerificationGate() {
    if (!_authSession.isAuthenticated) {
      // 앞 사용자가 눌러 둔 알림 경로를 다음 사용자가 물려받지 않게 한다.
      _pendingPushPath = null;
      _verificationGate.reset();
      _onboardingStep.reset();
      _stopPush();
      return;
    }
    unawaited(_verificationGate.refresh());
    unawaited(_onboardingStep.refresh());
    _startPush();
  }

  /// 로그인한 뒤에만 FCM 을 건드린다 — 로그인 전에는 등록할 주인이 없고,
  /// Firebase 를 켜지 않은 테스트도 이 경로로는 들어오지 않는다.
  /// 구독은 한 번만 걸고, 토큰 등록은 부를 때마다 다시 시도한다(registrar 가 중복을 걸러 준다).
  void _startPush() {
    if (_pushSubscriptions.isEmpty) {
      final messaging = ref.read(pushMessagingProvider);
      _pushSubscriptions.addAll([
        // 앱이 켜져 있을 때는 알림 배너 대신 화면을 갱신한다(새 의존성 표의 결정).
        messaging.onMessage.listen(_refreshForRoute),
        // 알림을 눌러서 열었을 때만 화면을 옮긴다.
        messaging.onMessageOpenedApp.listen(_openRoute),
      ]);
      unawaited(messaging.initialMessage().then((data) {
        if (data != null) {
          _openRoute(data);
        }
      }));
    }
    unawaited(ref.read(pushRegistrarProvider).start());
  }

  /// 새로 가입한 사용자는 학생 인증·학과 입력 전이라 토큰 등록이 403 으로 막힌다 —
  /// 로그인 때 한 번만 시도하면 앱을 다시 켜기 전까지 알림을 못 받는다.
  /// 게이트가 열리는 순간 다시 등록한다.
  void _startPushWhenGateOpens() {
    if (_verificationGate.value == VerificationGate.complete) {
      _startPush();
    }
  }

  /// 세션이 이미 끝난 뒤에 불리는 뒷정리다 — 토큰 삭제는 세션이 살아 있어야 되므로
  /// 로그아웃은 `signOut(registrar, auth)` 로 먼저 지우고 나간다(`core/auth/sign_out.dart`).
  /// 여기 `stop()` 은 그때 이미 비워진 토큰을 다시 지우려 하지 않고,
  /// 세션 만료처럼 우리가 부르지 않은 종료에서만 실제로 할 일이 남는다.
  void _stopPush() {
    if (_pushSubscriptions.isEmpty) {
      return;
    }
    for (final subscription in _pushSubscriptions) {
      unawaited(subscription.cancel());
    }
    _pushSubscriptions.clear();
    unawaited(ref.read(pushRegistrarProvider).stop());
  }

  /// 앱이 켜져 있는 동안에는 **어떤 알림도 배너로 띄우지 않고** 해당 화면만 갱신한다.
  /// 서버는 "상대가 방을 보고 있으면 새 메시지 푸시를 보내지 않는다" 를 `last_read_at` 30초로
  /// 눈대중하는데, 그 눈대중이 빗나가도 여기서 배너가 되지 않는다는 것이 앱 쪽 계약이다.
  void _refreshForRoute(Map<String, dynamic> data) => refreshForPush(ref.read, data);

  /// 알림을 눌러 연 경우에도 목록을 다시 읽는다 — 백그라운드에 있던 앱은 [_refreshForRoute] 를 못 받았고,
  /// 대화 탭 같은 목록은 들어갈 때 다시 읽지 않아 옮기기만 하면 낡은 목록(빈 상태)이 그대로 보인다.
  void _openRoute(Map<String, dynamic> data) {
    _refreshForRoute(data);
    _pendingPushPath = PushRoute.resolve(data);
    _openPendingPushRoute();
  }

  /// 꺼진 앱을 알림으로 켜면 경로가 관문 · 온보딩 조회보다 먼저 온다(A10). 그때 열면 조회 전
  /// 기본값(약관 동의)으로 끌려갔다가, 조회가 오면 홈으로 가서 목표 화면을 놓친다.
  /// 그래서 라우터와 같은 규칙이 그 경로를 그대로 받아 줄 때만 열고, 아니면 다음 변화 때 다시 본다.
  void _openPendingPushRoute() {
    final path = _pendingPushPath;
    if (path == null) {
      return;
    }
    final redirect = AuthRedirect(
      _authSession.isAuthenticated,
      _verificationGate.value,
      _onboardingStep.value,
      accountStatus: _accountStatus.value,
    );
    if (redirect.resolve(path) != null) {
      return;
    }
    _pendingPushPath = null;
    _router.go(path);
  }

  GoRouter _createRouter() {
    return AppRouter.create(
      isAuthenticated: () => _authSession.isAuthenticated,
      verificationGate: () => _verificationGate.value,
      onboardingStep: () => _onboardingStep.value,
      isSplashHeld: _splashHold.isHolding,
      accountStatus: () => _accountStatus.value,
      refreshListenable: Listenable.merge([_authSession, _verificationGate, _onboardingStep, _accountStatus, _splashHold]),
    );
  }

  /// 세션 리스너 · 게이트는 provider 가 소유해 [ProviderScope] 와 함께 정리된다 — 여기서 dispose 하지 않는다.
  @override
  void dispose() {
    _lifecycle.dispose();
    for (final subscription in _pushSubscriptions) {
      unawaited(subscription.cancel());
    }
    _verificationGate.removeListener(_startPushWhenGateOpens);
    _verificationGate.removeListener(_openPendingPushRoute);
    _onboardingStep.removeListener(_openPendingPushRoute);
    _accountStatus.removeListener(_signOutWhenWithdrawn);
    _authSession.removeListener(_refreshVerificationGate);
    _splashHold.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'CampusMate',
      theme: AppTheme.light(),
      // 시스템 다크에 끌려가지 않게 고정한다 (DESIGN.md §2.7 — 다크 모드는 MVP 범위 밖)
      themeMode: ThemeMode.light,
      routerConfig: _router,
    );
  }
}
