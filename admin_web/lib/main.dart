import 'package:campus_mate_admin/app.dart';
import 'package:campus_mate_admin/config/admin_config.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  // 해시(#) 없는 주소. 처음 연 주소(/reports/123)는 vercel.json 이 모든 경로를 index.html 로 돌려 여기까지 온다.
  usePathUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();
  const config = AdminConfig.fromEnvironment();
  // 값이 빠졌으면 Supabase 를 켜지 않는다 — 관문이 "설정 누락" 화면을 보여 준다.
  // 웹 기본 흐름은 PKCE: 구글에서 돌아온 /?code= 를 initialize 가 기다려 세션으로 바꾸고 주소에서 지운 뒤(replaceState)
  // runApp 한다 — 라우터는 지워진 주소로 시작한다. 실패(?error=)하면 남는 매개변수는 GateRedirector 가 지운다.
  if (config.isComplete) {
    await Supabase.initialize(url: config.supabaseUrl, publishableKey: config.supabaseAnonKey);
  }
  runApp(const ProviderScope(child: AdminApp()));
}
