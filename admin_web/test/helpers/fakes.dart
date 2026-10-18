import 'dart:async';
import 'dart:convert';

import 'package:campus_mate_admin/api/admin_api.dart';
import 'package:campus_mate_admin/app.dart';
import 'package:campus_mate_admin/auth/admin_auth.dart';
import 'package:campus_mate_admin/config/admin_config.dart';
import 'package:campus_mate_admin/providers.dart';
import 'package:campus_mate_admin/router/admin_router.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 시험용 설정. 값은 가짜 주소다(실제 주소 · 키를 시험에 쓰지 않는다).
const completeConfig = AdminConfig(
  supabaseUrl: 'https://supabase.test',
  supabaseAnonKey: 'anon-test',
  apiBaseUrl: 'https://api.test',
);

/// Supabase 대신 끼우는 가짜. 실제 gotrue 처럼 확인 성공 · 로그아웃 때 변경 알림을 낸다.
class FakeAdminAuth implements AdminAuth {
  FakeAdminAuth({this.session = true, this.mfa = const MfaState(aal2: false, factorId: null)});

  bool session;
  MfaState mfa;
  TotpEnrollment enrollment = const TotpEnrollment(factorId: 'factor-new', secret: 'JBSWY3DPEHPK3PXP');
  VerifyOutcome verifyOutcome = VerifyOutcome.ok;

  /// 참이면 구글 로그인 시작이 실패한다(팝업 막힘 · 공급자 꺼짐 등)
  bool signInFails = false;

  /// 채우면 mfaState 가 이 Completer 가 끝날 때까지 기다린다 — 판정 중 화면을 붙잡아 볼 때 쓴다.
  Completer<MfaState>? hold;
  final List<String> calls = <String>[];
  final StreamController<void> _changes = StreamController<void>.broadcast();

  void emitChange() => _changes.add(null);

  @override
  bool get hasSession => session;

  @override
  String? get accessToken => session ? 'token-test' : null;

  @override
  String? get email => 'admin@example.com';

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<void> signInWithGoogle() async {
    calls.add('signIn');
    if (signInFails) throw Exception('oauth start failed');
  }

  @override
  Future<MfaState> mfaState() => hold?.future ?? Future.value(mfa);

  @override
  Future<TotpEnrollment> enrollTotp() async {
    calls.add('enroll');
    return enrollment;
  }

  @override
  Future<VerifyOutcome> verifyTotp({required String factorId, required String code}) async {
    calls.add('verify:$factorId:$code');
    if (verifyOutcome == VerifyOutcome.ok) {
      mfa = MfaState(aal2: true, factorId: factorId);
      emitChange();
    }
    return verifyOutcome;
  }

  @override
  Future<void> signOut() async {
    calls.add('signOut');
    session = false;
    emitChange();
  }
}

/// 서버 대신 정해진 상태코드 · 본문을 돌려준다. [status] 를 바꾸면 다음 요청부터 바뀐다.
class FakeServer {
  FakeServer(this.status, [this.body = const <String, Object?>{}]);

  int status;
  Map<String, Object?> body;
  final List<http.Request> requests = <http.Request>[];

  AdminApi api() => AdminApi(completeConfig.apiBaseUrl, MockClient(_handle), () => 'token-test');

  Future<http.Response> _handle(http.Request request) async {
    requests.add(request);
    return http.Response.bytes(utf8.encode(jsonEncode(body)), status);
  }
}

/// pen 기준 화면(1440×900)으로 앱 전체를 띄운다. 필요하면 [size] 로 좁히고,
/// [initialPath] 로 브라우저 주소창에 친 주소처럼 시작한다. [settle] 이 거짓이면 첫 장면만 그린다(불러오는 중 확인용).
Future<void> pumpAdminApp(
  WidgetTester tester, {
  required FakeAdminAuth auth,
  FakeServer? server,
  AdminConfig config = completeConfig,
  Size size = const Size(1440, 900),
  String? initialPath,
  bool settle = true,
  VoidCallback? onReload,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  if (initialPath != null) {
    tester.binding.platformDispatcher.defaultRouteNameTestValue = initialPath;
    addTearDown(tester.binding.platformDispatcher.clearDefaultRouteNameTestValue);
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        adminConfigProvider.overrideWithValue(config),
        adminAuthProvider.overrideWithValue(auth),
        adminApiProvider.overrideWithValue((server ?? FakeServer(200)).api()),
        pageReloaderProvider.overrideWithValue(onReload ?? () {}),
      ],
      child: const AdminApp(),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

/// 지금 라우터 주소(쿼리 포함)
String locationOf(WidgetTester tester) {
  final container = ProviderScope.containerOf(tester.element(find.byType(AdminApp)));
  return container.read(adminRouterProvider).routerDelegate.currentConfiguration.uri.toString();
}
