import 'dart:async';

import 'package:campus_mate_admin/api/admin_api.dart';
import 'package:campus_mate_admin/app.dart';
import 'package:campus_mate_admin/auth/admin_auth.dart';
import 'package:campus_mate_admin/config/admin_config.dart';
import 'package:campus_mate_admin/router/admin_router.dart';
import 'package:campus_mate_admin/widgets/admin_loader.dart';
import 'package:campus_mate_admin/widgets/side_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fakes.dart';

const _aal2 = MfaState(aal2: true, factorId: 'factor-1');

void main() {
  testWidgets('설정 누락(pen 공통_설정_누락): 관리자용 안내 · 다시 불러오기(페이지 다시 열기), 로그아웃은 없다(세션 없음)', (tester) async {
    const empty = AdminConfig(supabaseUrl: '', supabaseAnonKey: 'k', apiBaseUrl: '');
    var reloads = 0;

    await pumpAdminApp(tester, auth: FakeAdminAuth(), config: empty, onReload: () => reloads++);
    expect(find.text('설정이 빠졌어요'), findsOneWidget);
    expect(find.text('관리자용 안내: 서버 주소 또는 Supabase 설정 값이 비어 있어요. 배포 환경 변수를 확인해 주세요.'), findsOneWidget);
    expect(find.text('로그아웃'), findsNothing);
    await tester.tap(find.text('다시 불러오기'));

    expect(reloads, 1);
  });

  testWidgets('구글 로그인 시작이 실패하면 단추 아래 오류 줄', (tester) async {
    final auth = FakeAdminAuth(session: false)..signInFails = true;

    await pumpAdminApp(tester, auth: auth);
    await tester.tap(find.text('구글로 로그인'));
    await tester.pumpAndSettle();

    expect(find.text('구글 로그인을 마치지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
  });

  testWidgets('구글에서 실패 · 취소로 돌아오면(?error=) 로그인 화면에 오류 줄', (tester) async {
    await pumpAdminApp(tester, auth: FakeAdminAuth(session: false), initialPath: '/?error=access_denied');

    expect(find.text('관리자 로그인'), findsOneWidget);
    expect(find.text('구글 로그인을 마치지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
  });

  testWidgets('실패 표시는 failed=1 하나만 — 비슷한 글자(failed=10 · xfailed=1)로는 오류 줄을 띄우지 않는다', (tester) async {
    await pumpAdminApp(tester, auth: FakeAdminAuth(session: false));
    final router = ProviderScope.containerOf(tester.element(find.byType(AdminApp))).read(adminRouterProvider);

    // 첫 진입은 판정 중(/loading)을 거쳐 쿼리가 지워진다 — 로그아웃 상태에서 주소만 바뀌는 경우(브라우저 앞뒤 이동)를 본다.
    for (final path in ['/login?failed=10', '/login?xfailed=1']) {
      router.go(path);
      await tester.pumpAndSettle();

      expect(locationOf(tester), path);
      expect(find.text('관리자 로그인'), findsOneWidget, reason: path);
      expect(find.text('구글 로그인을 마치지 못했어요. 다시 시도해 주세요.'), findsNothing, reason: path);
    }
    router.go('/login?failed=1');
    await tester.pumpAndSettle();
    expect(find.text('구글 로그인을 마치지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
  });

  testWidgets('세션 없음 → A0 로그인, 구글로 로그인을 누르면 OAuth 를 시작한다', (tester) async {
    final auth = FakeAdminAuth(session: false);

    await pumpAdminApp(tester, auth: auth);
    expect(find.text('관리자 로그인'), findsOneWidget);
    await tester.tap(find.text('구글로 로그인'));
    await tester.pumpAndSettle();

    expect(auth.calls, ['signIn']);
  });

  testWidgets('TOTP 없음 → A1 등록: 비밀 키를 4자씩 보여 주고 복사는 원문을 넣는다', (tester) async {
    final copied = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text']);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

    await pumpAdminApp(tester, auth: FakeAdminAuth());
    expect(find.text('2단계 인증 등록'), findsOneWidget);
    expect(find.text('JBSW Y3DP EHPK 3PXP'), findsOneWidget);
    await tester.tap(find.text('복사'));
    await tester.pump();

    expect(copied, ['JBSWY3DPEHPK3PXP']);
    expect(find.text('복사했어요'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle(); // 나가는 움직임(150ms)까지
    expect(find.text('복사했어요'), findsNothing);
  });

  testWidgets('A1 등록에서 6자리를 다 치면(붙여넣기 포함) 확인 단추 없이 바로 확인하고 셸로 들어간다', (tester) async {
    final auth = FakeAdminAuth();

    await pumpAdminApp(tester, auth: auth);
    await tester.enterText(find.byType(EditableText), '123456');
    await tester.pumpAndSettle();

    expect(auth.calls, containsAllInOrder(['enroll', 'verify:factor-new:123456']));
    expect(find.text('2단계 인증됨'), findsOneWidget);
  });

  testWidgets('TOTP 있고 aal1 → A1 입력, 틀린 코드면 오류 줄을 보여 준다', (tester) async {
    final auth = FakeAdminAuth(mfa: const MfaState(aal2: false, factorId: 'factor-1'))
      ..verifyOutcome = VerifyOutcome.wrongCode;

    await pumpAdminApp(tester, auth: auth);
    expect(find.text('2단계 인증 코드 입력'), findsOneWidget);
    await tester.enterText(find.byType(EditableText), '000000');
    await tester.pumpAndSettle();

    expect(auth.calls, ['verify:factor-1:000000']);
    expect(find.text('코드가 맞지 않아요. 다시 확인해 주세요.'), findsOneWidget);

    // 고쳐 치기 시작하면 오류 줄을 내린다
    await tester.enterText(find.byType(EditableText), '00000');
    await tester.pump();
    expect(find.text('코드가 맞지 않아요. 다시 확인해 주세요.'), findsNothing);
  });

  testWidgets('6자리를 다 채우지 않으면 확인하지 않고 알려 준다', (tester) async {
    final auth = FakeAdminAuth(mfa: const MfaState(aal2: false, factorId: 'factor-1'));

    await pumpAdminApp(tester, auth: auth);
    await tester.enterText(find.byType(EditableText), '123');
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();

    expect(auth.calls, isEmpty);
    expect(find.text('6자리 숫자를 모두 입력해 주세요.'), findsOneWidget);
  });

  testWidgets('403 not_admin → 권한 없음, 로그아웃하면 로그인으로', (tester) async {
    final auth = FakeAdminAuth(mfa: _aal2);

    await pumpAdminApp(tester, auth: auth, server: FakeServer(403, {'detail': AdminReason.notAdmin}));
    expect(find.text('관리자 계정이 아니에요'), findsOneWidget);
    await tester.tap(find.text('로그아웃'));
    await tester.pumpAndSettle();

    expect(find.text('관리자 로그인'), findsOneWidget);
  });

  testWidgets('권한 없음에서 다른 계정으로 로그인은 로그아웃 뒤 OAuth 를 다시 시작한다', (tester) async {
    final auth = FakeAdminAuth(mfa: _aal2);

    await pumpAdminApp(tester, auth: auth, server: FakeServer(403, {'detail': AdminReason.notAdmin}));
    await tester.tap(find.text('다른 계정으로 로그인'));
    await tester.pumpAndSettle();

    expect(auth.calls, ['signOut', 'signIn']);
  });

  testWidgets('403 mfa_required → 2단계 필요, 단추를 누르면 A1 입력', (tester) async {
    await pumpAdminApp(tester, auth: FakeAdminAuth(mfa: _aal2), server: FakeServer(403, {'detail': AdminReason.mfaRequired}));
    expect(find.text('2단계 인증이 필요해요'), findsOneWidget);

    await tester.tap(find.text('2단계 인증 코드 입력'));
    await tester.pumpAndSettle();

    expect(find.text('인증 앱에 나온 6자리 숫자를 입력해 주세요.'), findsOneWidget);
  });

  testWidgets('401 → 로그아웃하고 A0', (tester) async {
    final auth = FakeAdminAuth(mfa: _aal2);

    await pumpAdminApp(tester, auth: auth, server: FakeServer(401));

    expect(auth.calls, contains('signOut'));
    expect(find.text('관리자 로그인'), findsOneWidget);
  });

  testWidgets('서버 오류 → 연결 안 됨, 다시 시도로 셸에 들어간다', (tester) async {
    final server = FakeServer(500);

    await pumpAdminApp(tester, auth: FakeAdminAuth(mfa: _aal2), server: server);
    expect(find.text('서버에 연결하지 못했어요'), findsOneWidget);
    expect(find.text('인터넷 연결을 확인하고 잠시 뒤 다시 시도해 주세요.'), findsOneWidget);
    server.status = 200;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(find.text('2단계 인증됨'), findsOneWidget);
  });

  testWidgets('200 → 셸: 메뉴 8개 · 관리자 메일 · 배지, 메뉴를 누르면 그 화면 자리 표시', (tester) async {
    await pumpAdminApp(tester, auth: FakeAdminAuth(mfa: _aal2));

    for (final label in ['인증샷 검수', '신고', '매칭', '사용자', '결제', '미등록 학교 메일', '작업 기록']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('admin@example.com'), findsOneWidget);
    expect(find.text('다음 조각에서 채움'), findsOneWidget);

    await tester.tap(find.text('결제'));
    await tester.pumpAndSettle();

    // 메뉴 · TopBar 제목 · 자리 표시 제목
    expect(find.text('결제'), findsNWidgets(3));
  });

  testWidgets('셸에서 로그아웃하면 A0', (tester) async {
    final auth = FakeAdminAuth(mfa: _aal2);

    await pumpAdminApp(tester, auth: auth);
    await tester.tap(find.text('로그아웃'));
    await tester.pumpAndSettle();

    expect(auth.calls, ['signOut']);
    expect(find.text('관리자 로그인'), findsOneWidget);
  });

  testWidgets('세션이 있는 채로 /reports 를 열면 판정 뒤에도 /reports 에 남는다', (tester) async {
    await pumpAdminApp(tester, auth: FakeAdminAuth(mfa: _aal2), initialPath: '/reports');

    // 메뉴 · TopBar 제목(W2 부터 신고 화면 — 자리 표시 없음)
    expect(locationOf(tester), '/reports');
    expect(find.text('신고'), findsNWidgets(2));
  });

  testWidgets('/reports 를 열고 2단계 입력을 거쳐도 /reports 로 돌아간다', (tester) async {
    final auth = FakeAdminAuth(mfa: const MfaState(aal2: false, factorId: 'factor-1'));

    await pumpAdminApp(tester, auth: auth, initialPath: '/reports');
    expect(find.text('2단계 인증 코드 입력'), findsOneWidget);
    await tester.enterText(find.byType(EditableText), '123456');
    await tester.pumpAndSettle();

    expect(locationOf(tester), '/reports');
    expect(find.text('신고'), findsNWidgets(2));
  });

  testWidgets('판정이 끝나기 전에는 /reports 를 열어도 불러오는 중이고 셸은 안 보인다', (tester) async {
    final auth = FakeAdminAuth()..hold = Completer<MfaState>();

    await pumpAdminApp(tester, auth: auth, initialPath: '/reports', settle: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(AdminLoader), findsOneWidget);
    expect(find.text('로그인 상태를 확인하고 있어요'), findsOneWidget);
    expect(find.byType(SideNav), findsNothing);
    expect(find.text('admin@example.com'), findsNothing);

    auth.hold!.complete(_aal2);
    await tester.pumpAndSettle();

    expect(find.byType(SideNav), findsOneWidget);
    expect(find.text('신고'), findsNWidgets(2));
  });

  testWidgets('해시 없는 주소: /reports/123 을 바로 열어도 신고 상세에 남는다(메뉴는 신고, TopBar 는 "신고 상세")', (tester) async {
    await pumpAdminApp(tester, auth: FakeAdminAuth(mfa: _aal2), initialPath: '/reports/123');

    expect(locationOf(tester), '/reports/123');
    expect(find.text('신고'), findsOneWidget);
    expect(find.text('신고 상세'), findsOneWidget);
  });

  testWidgets('구글 로그인 복귀 주소(/?code=)는 판정 뒤 매개변수를 지운 홈이 된다', (tester) async {
    await pumpAdminApp(tester, auth: FakeAdminAuth(mfa: _aal2), initialPath: '/?code=abc');

    expect(locationOf(tester), '/');
  });

  testWidgets('브라우저 탭 제목은 메뉴 이름 · CampusMate 관리자', (tester) async {
    await pumpAdminApp(tester, auth: FakeAdminAuth(mfa: _aal2), initialPath: '/reports');

    final titles = tester.widgetList<Title>(find.byType(Title)).map((t) => t.title);
    expect(titles, contains('신고 · CampusMate 관리자'));
  });

  testWidgets('휴대폰 폭(360)에서도 관문 화면이 깨지지 않는다', (tester) async {
    await pumpAdminApp(tester, auth: FakeAdminAuth(), size: const Size(360, 740));
    expect(tester.takeException(), isNull);
    expect(find.text('2단계 인증 등록'), findsOneWidget);
  });

  testWidgets('1280 보다 좁은 창에서도 깨지지 않는다(가로 스크롤)', (tester) async {
    await pumpAdminApp(tester, auth: FakeAdminAuth(mfa: _aal2), size: const Size(800, 600));

    expect(tester.takeException(), isNull);
    expect(find.text('2단계 인증됨'), findsOneWidget);
  });
}
