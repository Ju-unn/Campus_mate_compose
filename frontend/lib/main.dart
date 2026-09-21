import 'dart:async';

import 'package:campus_mate/core/router/app_router.dart';
import 'package:campus_mate/core/router/onboarding_step_listenable.dart';
import 'package:campus_mate/core/router/onboarding_step_listenable_provider.dart';
import 'package:campus_mate/core/router/verification_gate_listenable.dart';
import 'package:campus_mate/core/router/verification_gate_listenable_provider.dart';
import 'package:campus_mate/core/supabase/auth_session_listenable.dart';
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

  @override
  void initState() {
    super.initState();
    _authSession = AuthSessionListenable(Supabase.instance.client);
    // 3b·3c·온보딩 ViewModel 이 각 단계 직후 부르는 것과 같은 인스턴스여야 라우터가 다시 평가된다.
    _verificationGate = ref.read(verificationGateListenableProvider);
    _onboardingStep = ref.read(onboardingStepListenableProvider);
    _authSession.addListener(_refreshVerificationGate);
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
      return;
    }
    unawaited(_verificationGate.refresh());
    unawaited(_onboardingStep.refresh());
  }

  GoRouter _createRouter() {
    return AppRouter.create(
      isAuthenticated: () => _authSession.isAuthenticated,
      verificationGate: () => _verificationGate.value,
      onboardingStep: () => _onboardingStep.value,
      refreshListenable: Listenable.merge([_authSession, _verificationGate, _onboardingStep]),
    );
  }

  /// 게이트는 provider 가 소유해 [ProviderScope] 와 함께 정리된다 — 여기서 dispose 하지 않는다.
  @override
  void dispose() {
    _authSession.removeListener(_refreshVerificationGate);
    _authSession.dispose();
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
