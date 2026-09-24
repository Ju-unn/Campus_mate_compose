import 'dart:async';

import 'package:campus_mate/auth/model/verification_gate.dart';
import 'package:campus_mate/chat/viewmodel/conversations_view_model.dart';
import 'package:campus_mate/core/push/push_provider.dart';
import 'package:campus_mate/core/push/push_route.dart';
import 'package:campus_mate/core/router/app_router.dart';
import 'package:campus_mate/core/router/onboarding_step_listenable.dart';
import 'package:campus_mate/core/router/onboarding_step_listenable_provider.dart';
import 'package:campus_mate/core/router/verification_gate_listenable.dart';
import 'package:campus_mate/core/router/verification_gate_listenable_provider.dart';
import 'package:campus_mate/core/router/splash_hold.dart';
import 'package:campus_mate/core/supabase/auth_session_listenable.dart';
import 'package:campus_mate/core/supabase/supabase_config.dart';
import 'package:campus_mate/core/supabase/supabase_initializer.dart';
import 'package:campus_mate/core/theme/app_theme.dart';
import 'package:campus_mate/matching/viewmodel/acceptances_view_model.dart';
import 'package:campus_mate/matching/viewmodel/today_cards_view_model.dart';
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
  runApp(const ProviderScope(child: CampusMateApp()));
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
  late final GoRouter _router;
  /// 스플래시를 잠깐 붙잡아 두는 임시 장치 (로고 작업 때 다시 본다).
  final SplashHold _splashHold = SplashHold();
  final List<StreamSubscription<Map<String, dynamic>>> _pushSubscriptions = [];

  @override
  void initState() {
    super.initState();
    _authSession = AuthSessionListenable(Supabase.instance.client);
    // 3b·3c·온보딩 ViewModel 이 각 단계 직후 부르는 것과 같은 인스턴스여야 라우터가 다시 평가된다.
    _verificationGate = ref.read(verificationGateListenableProvider);
    _onboardingStep = ref.read(onboardingStepListenableProvider);
    _authSession.addListener(_refreshVerificationGate);
    _verificationGate.addListener(_startPushWhenGateOpens);
    _router = _createRouter();
    _refreshVerificationGate();
  }

  /// 세션이 바뀔 때마다 게이트·온보딩 단계를 다시 조회한다.
  /// 로그아웃하면 조회에 쓸 토큰이 없고, 앞 사용자의 통과 상태를
  /// 다음 사용자가 물려받으면 안 되므로 캐시를 비운다.
  void _refreshVerificationGate() {
    if (!_authSession.isAuthenticated) {
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
  void _refreshForRoute(Map<String, dynamic> data) {
    switch (data['route']) {
      case 'daily_card':
        unawaited(ref.read(todayCardsViewModelProvider.notifier).refresh());
      case 'acceptances' || 'match':
        unawaited(ref.read(acceptancesViewModelProvider.notifier).refresh());
      // 방을 열어 두고 있으면 Realtime 이 이미 줄을 붙였다 — 여기서는 목록만 맞춘다.
      case 'chat':
        unawaited(ref.read(conversationsViewModelProvider.notifier).refresh());
    }
  }

  void _openRoute(Map<String, dynamic> data) {
    final path = PushRoute.resolve(data);
    if (path != null) {
      _router.go(path);
    }
  }

  GoRouter _createRouter() {
    return AppRouter.create(
      isAuthenticated: () => _authSession.isAuthenticated,
      verificationGate: () => _verificationGate.value,
      onboardingStep: () => _onboardingStep.value,
      isSplashHeld: _splashHold.isHolding,
      refreshListenable: Listenable.merge([_authSession, _verificationGate, _onboardingStep, _splashHold]),
    );
  }

  /// 게이트는 provider 가 소유해 [ProviderScope] 와 함께 정리된다 — 여기서 dispose 하지 않는다.
  @override
  void dispose() {
    for (final subscription in _pushSubscriptions) {
      unawaited(subscription.cancel());
    }
    _verificationGate.removeListener(_startPushWhenGateOpens);
    _authSession.removeListener(_refreshVerificationGate);
    _authSession.dispose();
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
