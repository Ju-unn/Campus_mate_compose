import 'package:campus_mate/core/router/app_router.dart';
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

/// 앱 루트 위젯. 로그인 상태는 [AuthSessionListenable] 이 실시간으로 알려준다.
class CampusMateApp extends StatefulWidget {
  const CampusMateApp({super.key});

  @override
  State<CampusMateApp> createState() => _CampusMateAppState();
}

class _CampusMateAppState extends State<CampusMateApp> {
  late final AuthSessionListenable _authSession;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _authSession = AuthSessionListenable(Supabase.instance.client);
    _router = AppRouter.create(
      isAuthenticated: () => _authSession.isAuthenticated,
      refreshListenable: _authSession,
    );
  }

  @override
  void dispose() {
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
