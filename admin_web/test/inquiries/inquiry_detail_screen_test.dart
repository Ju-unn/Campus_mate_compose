import 'dart:async';

import 'package:campus_mate_admin/auth/admin_auth.dart';
import 'package:campus_mate_admin/widgets/admin_button.dart';
import 'package:campus_mate_admin/widgets/admin_chip.dart';
import 'package:campus_mate_admin/widgets/status_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fakes.dart';
import '../helpers/inquiry_fakes.dart';

/// 문의 상세(`/inquiries/{id}`) — 신고 상세(A4)와 같은 틀: 머리줄 → 두 열 카드(왼쪽 내용, 오른쪽 처리). 서버에 한 건 조회가 없어
/// 목록에서 고른 줄을 들고 온다(주소로 바로 열면 목록으로 안내).
void main() {
  const aal2 = MfaState(aal2: true, factorId: 'f');
  const longBody = '로그인하고 카드를 보려는데 앱이 계속 멈춰요.\n두 번째 줄입니다.\n세 번째 줄입니다. 아주 긴 글이어도 잘리지 않고 끝까지 보여야 해요.';

  setUpAll(() async {
    final loader = FontLoader('Pretendard');
    for (final weight in ['Regular', 'SemiBold', 'Bold']) {
      loader.addFont(rootBundle.load('assets/fonts/Pretendard-$weight.otf'));
    }
    await loader.load();
  });

  FakeInquiryServer server0() => FakeInquiryServer(rows: [
    inquiryRow(inquiryA, body: longBody, replyEmail: 'me@example.com'),
    inquiryRow(inquiryB, createdAt: '2026-11-10T02:00:00+00:00', status: 'answered', answeredAt: '2026-11-10T05:30:00+00:00', adminMemo: '전화 예정'),
    inquiryRow(inquiryC, createdAt: '2026-11-10T03:00:00+00:00', profile: null),
  ]);

  Finder key(String name) => find.byKey(ValueKey(name));
  Finder chip(String label) => find.widgetWithText(AdminChip, label);

  /// 목록에서 줄을 눌러 상세로 간다(주소로 바로 열면 줄이 없다)
  Future<FakeInquiryServer> openDetail(WidgetTester tester, String id, {FakeInquiryServer? server}) async {
    final fake = server ?? server0();
    await pumpAdminApp(tester, auth: FakeAdminAuth(mfa: aal2), api: fake.api(), initialPath: '/inquiries');
    await tester.tap(chip('전체'));
    await tester.pumpAndSettle();
    await tester.tap(key('inquiry-row-$id'));
    await tester.pumpAndSettle();
    return fake;
  }

  Future<void> drainToast(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  }

  TextField memoField(WidgetTester tester) => tester.widget<TextField>(find.descendant(of: key('inquiry-memo'), matching: find.byType(TextField)));

  testWidgets('머리줄 "{사유} 문의" + 상태 배지, 왼쪽 카드에 본문 전체 · 보낸 사람 · 학교 · 시각 · 답장 메일', (tester) async {
    await openDetail(tester, inquiryA);

    expect(find.descendant(of: key('inquiry-head'), matching: find.text('앱 오류 문의')), findsOneWidget);
    expect(find.descendant(of: key('inquiry-head'), matching: find.byType(StatusBadge)), findsOneWidget);
    expect(find.descendant(of: key('inquiry-head'), matching: find.text('새 문의')), findsOneWidget);
    final card = key('inquiry-content-card');
    for (final text in ['앱 오류', '하늘 · 테스트대학교', '2026-11-10 10:00', 'me@example.com']) {
      expect(find.descendant(of: card, matching: find.text(text)), findsOneWidget, reason: text);
    }
    // 줄바꿈 포함 본문이 말줄임 없이 그대로
    final body = tester.widget<Text>(find.descendant(of: key('inquiry-body'), matching: find.byType(Text)));
    expect(body.data, longBody);
    expect(body.maxLines, isNull);
    expect(body.overflow, isNot(TextOverflow.ellipsis));
  });

  testWidgets('가장 낮은 창(1280×560)에서도 넘치지 않고, 저장 단추까지 스크롤로 닿는다', (tester) async {
    final server = server0();
    await pumpAdminApp(tester, auth: FakeAdminAuth(mfa: aal2), api: server.api(), initialPath: '/inquiries', size: const Size(1280, 560));
    await tester.tap(chip('전체'));
    await tester.pumpAndSettle();
    await tester.tap(key('inquiry-row-$inquiryA'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.widgetWithText(AdminButton, '메모 저장'));
    await tester.pump();
    expect(tester.getRect(find.widgetWithText(AdminButton, '메모 저장')).bottom, lessThanOrEqualTo(560));
  });

  testWidgets('탈퇴한 사람의 문의는 "탈퇴한 사용자"', (tester) async {
    await openDetail(tester, inquiryC);

    expect(find.descendant(of: key('inquiry-content-card'), matching: find.text('탈퇴한 사용자')), findsOneWidget);
  });

  testWidgets('답변 완료 건은 "답변 시각"도 보이고, 칩 "답변 완료"가 켜져 있으며 메모가 칸에 들어 있다', (tester) async {
    await openDetail(tester, inquiryB);

    expect(find.descendant(of: key('inquiry-content-card'), matching: find.text('2026-11-10 14:30')), findsOneWidget);
    expect(tester.widget<AdminChip>(chip('답변 완료')).selected, isTrue);
    expect(tester.widget<AdminChip>(chip('새 문의')).selected, isFalse);
    expect(memoField(tester).controller!.text, '전화 예정');
  });

  testWidgets('답장 메일 복사: 누르면 클립보드에 메일 한 줄, 토스트 "답장 메일을 복사했어요"', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await openDetail(tester, inquiryA);

    await tester.tap(key('inquiry-copy-email'));
    await tester.pump();

    expect(copied, 'me@example.com');
    expect(find.text('답장 메일을 복사했어요'), findsOneWidget);
    await drainToast(tester);
  });

  testWidgets('상태 바꾸기: 칩 "처리 중"을 누르면 status 만 PATCH, 칩 · 배지가 바뀌고 토스트 "저장했어요"', (tester) async {
    final server = await openDetail(tester, inquiryA);

    await tester.tap(chip('처리 중'));
    await tester.pump();

    expect(server.patches.single.url.path, '/admin/inquiries/$inquiryA');
    expect(server.patches.single.body, '{"status":"in_progress"}');
    expect(tester.widget<AdminChip>(chip('처리 중')).selected, isTrue);
    expect(tester.widget<AdminChip>(chip('새 문의')).selected, isFalse);
    expect(find.descendant(of: key('inquiry-head'), matching: find.text('처리 중')), findsOneWidget);
    expect(find.text('저장했어요'), findsOneWidget);
    await drainToast(tester);
  });

  testWidgets('"답변 완료"로 바꾸면 서버가 돌려준 답변 시각이 카드에 뜬다', (tester) async {
    await openDetail(tester, inquiryA);

    await tester.tap(chip('답변 완료'));
    await tester.pumpAndSettle();

    expect(find.descendant(of: key('inquiry-content-card'), matching: find.text('2026-11-10 18:00')), findsOneWidget);
    await drainToast(tester);
  });

  testWidgets('이미 켜진 상태 칩을 다시 눌러도 요청하지 않는다', (tester) async {
    final server = await openDetail(tester, inquiryA);

    await tester.tap(chip('새 문의'));
    await tester.pump();

    expect(server.patches, isEmpty);
  });

  testWidgets('요청 중에는 칩 · 저장 단추가 눌리지 않아 같은 요청이 둘 가지 않는다', (tester) async {
    final server = server0()..holdPatch = Completer<void>();
    await openDetail(tester, inquiryA, server: server);

    await tester.tap(chip('처리 중'));
    await tester.pump();
    await tester.tap(chip('답변 완료'));
    await tester.pump();

    expect(server.patches, hasLength(1));
    server.holdPatch!.complete();
    await tester.pumpAndSettle();
    await drainToast(tester);
  });

  testWidgets('메모 저장: 처음엔 단추가 꺼져 있고, 글을 바꾸면 켜져, 누르면 admin_memo 만 PATCH · 다시 꺼진다', (tester) async {
    final server = await openDetail(tester, inquiryA);
    AdminButton save() => tester.widget<AdminButton>(find.widgetWithText(AdminButton, '메모 저장'));
    expect(save().onPressed, isNull);

    await tester.enterText(find.descendant(of: key('inquiry-memo'), matching: find.byType(TextField)), '내일 메일 보내기');
    await tester.pump();
    expect(save().onPressed, isNotNull);
    await tester.tap(find.widgetWithText(AdminButton, '메모 저장'));
    await tester.pump();

    expect(server.patches.single.body, '{"admin_memo":"내일 메일 보내기"}');
    expect(find.text('저장했어요'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(save().onPressed, isNull);
    expect(memoField(tester).controller!.text, '내일 메일 보내기');
    await drainToast(tester);
  });

  testWidgets('메모를 모두 지우고 저장하면 빈 글을 보낸다(서버가 메모를 지운다)', (tester) async {
    final server = await openDetail(tester, inquiryB);

    await tester.enterText(find.descendant(of: key('inquiry-memo'), matching: find.byType(TextField)), '');
    await tester.pump();
    await tester.tap(find.widgetWithText(AdminButton, '메모 저장'));
    await tester.pumpAndSettle();

    expect(server.patches.single.body, '{"admin_memo":""}');
    await drainToast(tester);
  });

  testWidgets('메모는 1000자까지만 들어간다(서버 MEMO_MAX)', (tester) async {
    await openDetail(tester, inquiryA);

    await tester.enterText(find.descendant(of: key('inquiry-memo'), matching: find.byType(TextField)), '가' * 1100);
    await tester.pump();

    expect(memoField(tester).controller!.text.length, 1000);
  });

  testWidgets('저장 실패(500): 오류 줄, 상태는 그대로, 단추는 다시 누를 수 있다', (tester) async {
    final server = await openDetail(tester, inquiryA);
    server.patchFailure = 500;

    await tester.tap(chip('처리 중'));
    await tester.pumpAndSettle();

    expect(find.text('저장하지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
    expect(tester.widget<AdminChip>(chip('새 문의')).selected, isTrue);
    expect(find.text('저장했어요'), findsNothing);
    server.patchFailure = null;
    await tester.tap(chip('처리 중'));
    await tester.pumpAndSettle();
    expect(find.text('저장하지 못했어요. 다시 시도해 주세요.'), findsNothing);
    expect(tester.widget<AdminChip>(chip('처리 중')).selected, isTrue);
    await drainToast(tester);
  });

  for (final (status, what) in [(401, '토큰 거절'), (403, '권한 없음')]) {
    testWidgets('저장 중 $status($what)이 나면 관문이 다시 판정한다 — /admin/me 를 한 번 더 부른다', (tester) async {
      final server = await openDetail(tester, inquiryA);
      final before = server.gateChecks.length;
      server.patchFailure = status;

      await tester.tap(chip('처리 중'));
      await tester.pumpAndSettle();

      expect(server.gateChecks.length, before + 1);
    });
  }

  testWidgets('저장이 500 으로 실패하면 관문은 다시 판정하지 않는다', (tester) async {
    final server = await openDetail(tester, inquiryA);
    final before = server.gateChecks.length;
    server.patchFailure = 500;

    await tester.tap(chip('처리 중'));
    await tester.pumpAndSettle();

    expect(server.gateChecks.length, before);
  });

  testWidgets('메모 저장 실패(연결 끊김): 쓴 글은 칸에 남는다', (tester) async {
    final server = await openDetail(tester, inquiryA);
    server.patchFailure = 0;

    await tester.enterText(find.descendant(of: key('inquiry-memo'), matching: find.byType(TextField)), '지우면 안 되는 글');
    await tester.pump();
    await tester.tap(find.widgetWithText(AdminButton, '메모 저장'));
    await tester.pumpAndSettle();

    expect(find.text('저장하지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
    expect(memoField(tester).controller!.text, '지우면 안 되는 글');
  });

  testWidgets('이미 지워진 문의(404)는 따로 알려 준다', (tester) async {
    final server = await openDetail(tester, inquiryA);
    server.patchFailure = 404;

    await tester.tap(chip('처리 중'));
    await tester.pumpAndSettle();

    expect(find.text('이미 지워진 문의예요. 목록에서 다시 확인해 주세요.'), findsOneWidget);
  });

  testWidgets('처리하고 목록으로 돌아오면 목록을 새로 받아 줄이 새 상태로 보인다', (tester) async {
    final server = await openDetail(tester, inquiryA);
    await tester.tap(chip('답변 완료'));
    await tester.pumpAndSettle();
    await drainToast(tester);

    await tester.tap(key('inquiry-back'));
    await tester.pumpAndSettle();

    expect(locationOf(tester), '/inquiries');
    expect(server.lists.last.url.queryParameters, isEmpty); // 상세로 가기 전에 고른 "전체"
    expect(find.descendant(of: key('inquiry-row-$inquiryA'), matching: find.text('답변 완료')), findsOneWidget);
  });

  testWidgets('주소로 바로 열면(줄 없음) "문의를 찾을 수 없어요" + 목록 단추', (tester) async {
    final server = server0();
    await pumpAdminApp(tester, auth: FakeAdminAuth(mfa: aal2), api: server.api(), initialPath: '/inquiries/$inquiryA');

    expect(find.text('문의를 찾을 수 없어요'), findsOneWidget);
    expect(server.patches, isEmpty);
    await tester.tap(find.widgetWithText(AdminButton, '문의 목록'));
    await tester.pumpAndSettle();
    expect(locationOf(tester), '/inquiries');
  });

  testWidgets('본문에 HTML · 긴 서버 글자가 와도 일반 글자로만 그린다', (tester) async {
    final server = FakeInquiryServer(rows: [inquiryRow(inquiryA, body: '<script>alert(1)</script> **굵게**')]);
    await openDetail(tester, inquiryA, server: server);

    expect(find.text('<script>alert(1)</script> **굵게**'), findsOneWidget);
  });
}
