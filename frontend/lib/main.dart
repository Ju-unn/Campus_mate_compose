import 'dart:async';

import 'package:campus_mate/auth/model/verification_gate_repository_provider.dart';
import 'package:campus_mate/core/router/app_router.dart';
import 'package:campus_mate/core/router/verification_gate_listenable.dart';
import 'package:campus_mate/core/supabase/auth_session_listenable.dart';
import 'package:campus_mate/core/supabase/supabase_config.dart';
import 'package:campus_mate/core/supabase/supabase_initializer.dart';
import 'package:campus_mate/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _authSession = AuthSessionListenable(Supabase.instance.client);
    _verificationGate = VerificationGateListenable(ref.read(verificationGateRepositoryProvider));
    _authSession.addListener(_refreshVerificationGate);
    _router = _createRouter();
    _refreshVerificationGate();
  }

  /// 세션이 바뀔 때마다 게이트를 다시 조회한다.
  /// 로그아웃 상태에서는 조회에 쓸 토큰이 없어 건너뛴다.
  void _refreshVerificationGate() {
    if (!_authSession.isAuthenticated) {
      return;
    }
    unawaited(_verificationGate.refresh());
  }

  GoRouter _createRouter() {
    return AppRouter.create(
      isAuthenticated: () => _authSession.isAuthenticated,
      verificationGate: () => _verificationGate.value,
      refreshListenable: Listenable.merge([_authSession, _verificationGate]),
    );
  }

  @override
  void dispose() {
    _authSession.removeListener(_refreshVerificationGate);
    _authSession.dispose();
    _verificationGate.dispose();
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
