import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:campus_mate_admin/auth/admin_auth.dart';
import 'package:campus_mate_admin/notices/notice_item.dart';
import 'package:campus_mate_admin/providers.dart';
import 'package:campus_mate_admin/widgets/admin_button.dart';
import 'package:campus_mate_admin/widgets/admin_toast.dart';
import 'package:campus_mate_admin/widgets/status_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fakes.dart';
import '../helpers/notice_fakes.dart';

/// 공지사항(`/notices`) — pen 에 화면이 없어 문의 목록(신고 목록 틀)을 따른다: 머리 줄 [공지 쓰기] → 표 → [더 보기] → 안내.
void main() {
  const aal2 = MfaState(aal2: true, factorId: 'f');

  Future<FakeNoticeServer> open(
    WidgetTester tester, {
    FakeNoticeServer? server,
    String path = '/notices',
    Future<NoticeImage?> Function()? picker,
    Size size = const Size(1440, 900),
  }) async {
    final fake = server ?? FakeNoticeServer(rows: [noticeRow('n1', title: '점검 안내'), noticeRow('n2', status: 'blinded', createdAt: '2026-11-23T01:00:00+00:00')]);
    await pumpAdminApp(
      tester,
      auth: FakeAdminAuth(mfa: aal2),
      api: fake.api(),
      initialPath: path,
      size: size,
      overrides: [if (picker != null) imagePickerProvider.overrideWithValue(picker)],
    );
    return fake;
  }

  Finder key(String name) => find.byKey(ValueKey(name));
  Finder button(String label) => find.widgetWithText(AdminButton, label);
  Finder inDialog(Finder f) => find.descendant(of: key('notice-dialog'), matching: f);

  Future<void> letToastGo(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  }

  Future<void> fillForm(WidgetTester tester) async {
    await tester.tap(button('공지 쓰기'));
    await tester.pumpAndSettle();
    await tester.enterText(find.descendant(of: key('notice-title'), matching: find.byType(TextField)), '점검 안내');
    await tester.enterText(find.descendant(of: key('notice-body'), matching: find.byType(TextField)), '오늘 밤 점검해요');
    await tester.pump();
  }

  testWidgets('사이드 메뉴 "공지사항"을 누르면 /notices, TopBar 도 "공지사항"', (tester) async {
    await open(tester, path: '/');

    await tester.tap(key('nav-notices'));
    await tester.pumpAndSettle();

    expect(locationOf(tester), '/notices');
    expect(find.text('공지사항'), findsNWidgets(2)); // 메뉴 + TopBar
  });

  testWidgets('목록: 가린 공지도 보이고 상태 배지로 가른다(보임 · 가려짐)', (tester) async {
    await open(tester);

    expect(find.descendant(of: key('notice-row-n1'), matching: find.text('점검 안내')), findsOneWidget);
    final badges = {
      for (final id in ['n1', 'n2']) id: tester.widget<StatusBadge>(find.descendant(of: key('notice-row-$id'), matching: find.byType(StatusBadge))),
    };
    expect((badges['n1']!.label, badges['n1']!.tone), ('보임', StatusTone.success));
    expect((badges['n2']!.label, badges['n2']!.tone), ('가려짐', StatusTone.danger));
  });

  testWidgets('가장 좁은 창(1280)에서도 표 줄이 넘치지 않는다(가려짐 배지 · [지우기])', (tester) async {
    await open(tester, size: const Size(1280, 720));

    expect(tester.takeException(), isNull);
    expect(find.descendant(of: key('notice-row-n2'), matching: button('지우기')), findsOneWidget);
  });

  testWidgets('공지가 없으면 빈 안내', (tester) async {
    await open(tester, server: FakeNoticeServer());

    expect(find.text('올린 공지가 없어요'), findsOneWidget);
  });

  testWidgets('[더 보기]: 마지막 줄 커서로 다음 쪽을 이어 붙이고, 끝이면 단추가 사라진다', (tester) async {
    final server = FakeNoticeServer(rows: [
      for (var i = 0; i < 25; i++) noticeRow('n${i.toString().padLeft(2, '0')}', createdAt: '2026-11-24T01:00:${i.toString().padLeft(2, '0')}+00:00'),
    ]);
    await open(tester, server: server);
    expect(key('notice-row-n04'), findsNothing);

    await tester.ensureVisible(button('더 보기'));
    await tester.tap(button('더 보기'));
    await tester.pumpAndSettle();

    expect(server.lists.last.url.queryParameters, {'before': '2026-11-24T01:00:05+00:00', 'before_id': 'n05'});
    expect(key('notice-row-n24'), findsOneWidget);
    expect(key('notice-row-n00'), findsOneWidget);
    expect(button('더 보기'), findsNothing);
  });

  testWidgets('목록을 못 받으면 오류 + [다시 시도]', (tester) async {
    final server = FakeNoticeServer(rows: [noticeRow('n1')])..listFailure = 500;
    await open(tester, server: server);
    expect(find.text('공지를 불러오지 못했어요'), findsOneWidget);

    server.listFailure = null;
    await tester.tap(button('다시 시도'));
    await tester.pumpAndSettle();

    expect(key('notice-row-n1'), findsOneWidget);
  });

  testWidgets('쓰기: 제목 · 본문이 차야 [올리기]가 열리고, 그림 없이 보내면 image 칸이 없다 → 토스트 + 목록 새로', (tester) async {
    final server = await open(tester);
    await tester.tap(button('공지 쓰기'));
    await tester.pumpAndSettle();
    expect(tester.widget<AdminButton>(inDialog(button('올리기'))).onPressed, isNull);
    await tester.tap(inDialog(button('취소')));
    await tester.pumpAndSettle();

    await fillForm(tester);
    await tester.tap(inDialog(button('올리기')));
    await tester.pumpAndSettle();

    final form = FakeNoticeServer.formText(server.creates.single);
    expect(form, contains('점검 안내'));
    expect(form, isNot(contains('name="image"')));
    expect(key('notice-dialog'), findsNothing);
    expect(find.widgetWithText(AdminToast, '공지를 올렸어요'), findsOneWidget);
    expect(server.lists.length, 2);
    expect(key('notice-row-n-new-1'), findsOneWidget);
    await letToastGo(tester);
  });

  testWidgets('쓰기: 그림을 고르면 미리보기, 보내면 image 칸에 실린다 · [그림 빼기]로 뺄 수 있다', (tester) async {
    final server = await open(tester, picker: () async => (bytes: tinyPng, name: 'notice.png'));
    await fillForm(tester);

    await tester.tap(inDialog(button('그림 고르기')));
    await tester.pumpAndSettle();
    expect(key('notice-image-preview'), findsOneWidget);
    await tester.tap(inDialog(button('그림 빼기')));
    await tester.pumpAndSettle();
    expect(key('notice-image-preview'), findsNothing);

    await tester.tap(inDialog(button('그림 고르기')));
    await tester.pumpAndSettle();
    await tester.tap(inDialog(button('올리기')));
    await tester.pumpAndSettle();

    expect(FakeNoticeServer.formText(server.creates.single), contains('name="image"; filename="notice.png"'));
    await letToastGo(tester);
  });

  testWidgets('쓰기: 10MB 를 넘는 그림은 고르는 자리에서 막는다(보내지 않음)', (tester) async {
    final big = Uint8List(maxNoticeImageBytes + 1);
    await open(tester, picker: () async => (bytes: big, name: 'big.png'));
    await fillForm(tester);

    await tester.tap(inDialog(button('그림 고르기')));
    await tester.pumpAndSettle();

    expect(key('notice-image-preview'), findsNothing);
    expect(inDialog(find.text('그림이 10MB 를 넘어요. 더 작은 그림을 골라 주세요.')), findsOneWidget);
  });

  testWidgets('쓰기: 서버가 그림을 거절하면(422 image_type) 대화상자에 남아 오류 줄', (tester) async {
    final server = FakeNoticeServer()
      ..createFailure = 422
      ..createReason = 'image_type';
    await open(tester, server: server, picker: () async => (bytes: tinyPng, name: 'x.png'));
    await fillForm(tester);
    await tester.tap(inDialog(button('그림 고르기')));
    await tester.pumpAndSettle();

    await tester.tap(inDialog(button('올리기')));
    await tester.pumpAndSettle();

    expect(key('notice-dialog'), findsOneWidget);
    expect(inDialog(find.text('올릴 수 없는 그림이에요. JPG · PNG · WEBP 그림을 골라 주세요.')), findsOneWidget);
  });

  testWidgets('지우기: 사유를 받아 DELETE 로 보내고 → 토스트 + 줄이 빠진다', (tester) async {
    final server = await open(tester);

    await tester.tap(find.descendant(of: key('notice-row-n1'), matching: button('지우기')));
    await tester.pumpAndSettle();
    expect(find.text('공지를 지울까요?'), findsOneWidget);
    await tester.enterText(find.descendant(of: key('reason-dialog'), matching: find.byType(TextField)), '잘못 올렸어요');
    await tester.pump();
    await tester.tap(find.descendant(of: key('reason-dialog'), matching: button('지우기')));
    await tester.pumpAndSettle();

    final request = server.deletes.single;
    expect(request.url.path, '/admin/notices/n1');
    expect(jsonDecode(request.body), {'reason': '잘못 올렸어요'});
    expect(find.widgetWithText(AdminToast, '공지를 지웠어요'), findsOneWidget);
    expect(key('notice-row-n1'), findsNothing);
    await letToastGo(tester);
  });

  /// [held] 면 pumpAndSettle 대신 1초씩만 흘린다 — 붙잡은 [더 보기] 의 도는 아이콘 때문에 settle 이 시계를 계속 돌려
  /// 조회 시간 제한(15초)이 먼저 끊으면, 늦게 온 응답이 아니라 그냥 실패가 된다.
  Future<void> deleteRow(WidgetTester tester, String id, {bool held = false}) async {
    Future<void> settle() async => held ? tester.pump(const Duration(seconds: 1)) : tester.pumpAndSettle();
    await tester.ensureVisible(find.descendant(of: key('notice-row-$id'), matching: button('지우기')));
    await tester.tap(find.descendant(of: key('notice-row-$id'), matching: button('지우기')));
    await settle();
    await tester.enterText(find.descendant(of: key('reason-dialog'), matching: find.byType(TextField)), '잘못 올렸어요');
    await tester.pump();
    await tester.tap(find.descendant(of: key('reason-dialog'), matching: button('지우기')));
    await settle();
    await settle();
  }

  testWidgets('지우기: 다른 관리자가 먼저 지웠으면(404) 일반 실패 줄 + 목록을 다시 받아 그 줄을 없앤다', (tester) async {
    final server = await open(tester);
    server.rows.removeWhere((row) => row['id'] == 'n1');
    server.deleteFailure = 404;

    await deleteRow(tester, 'n1');

    expect(find.descendant(of: key('reason-dialog'), matching: find.text('처리하지 못했어요. 다시 시도해 주세요.')), findsOneWidget);
    expect(server.lists.length, 2);
    await tester.tap(find.descendant(of: key('reason-dialog'), matching: button('취소')));
    await tester.pumpAndSettle();
    expect(key('notice-row-n1'), findsNothing);
    expect(key('notice-row-n2'), findsOneWidget);
  });

  group('늦게 온 [더 보기] 응답', () {
    List<Map<String, Object?>> rows25() => [
      for (var i = 0; i < 25; i++) noticeRow('n${i.toString().padLeft(2, '0')}', createdAt: '2026-11-24T01:00:${i.toString().padLeft(2, '0')}+00:00'),
    ];

    testWidgets('[더 보기]를 받는 사이 목록을 다시 받았으면, 뒤늦게 온 다음 쪽은 붙이지 않는다', (tester) async {
      final server = FakeNoticeServer(rows: rows25())..holdMore = Completer<void>();
      await open(tester, server: server);
      await tester.ensureVisible(button('더 보기'));
      await tester.tap(button('더 보기'));
      await tester.pump();

      await deleteRow(tester, 'n24', held: true); // 지우기 성공 → 첫 쪽부터 다시 받기
      server.holdMore!.complete();
      await tester.pumpAndSettle();

      expect(find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('notice-row-')), findsNWidgets(20));
      expect(key('notice-row-n00'), findsNothing);
      await letToastGo(tester);
    });

    testWidgets('[더 보기]를 받는 사이 목록을 다시 받았으면, 뒤늦게 온 실패도 오류 줄로 남기지 않는다', (tester) async {
      final server = FakeNoticeServer(rows: rows25())
        ..holdMore = Completer<void>()
        ..moreFailure = 500;
      await open(tester, server: server);
      await tester.ensureVisible(button('더 보기'));
      await tester.tap(button('더 보기'));
      await tester.pump();

      await deleteRow(tester, 'n24', held: true);
      server.holdMore!.complete();
      await tester.pumpAndSettle();

      expect(find.text('더 불러오지 못했어요. 다시 시도해 주세요.'), findsNothing);
      expect(key('notice-row-n23'), findsOneWidget);
      await letToastGo(tester);
    });
  });

  testWidgets('쓰기: 고르는 자리에서 10MB 를 넘는다고 알려 오면(읽기 전 거절) 같은 오류 줄, 미리보기 없음', (tester) async {
    await open(tester, picker: () async => throw const NoticeImageTooLarge());
    await fillForm(tester);

    await tester.tap(inDialog(button('그림 고르기')));
    await tester.pumpAndSettle();

    expect(key('notice-image-preview'), findsNothing);
    expect(inDialog(find.text('그림이 10MB 를 넘어요. 더 작은 그림을 골라 주세요.')), findsOneWidget);
  });
}
