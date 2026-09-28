import 'package:campus_mate/account/model/account_info.dart';
import 'package:campus_mate/account/model/account_repository.dart';
import 'package:campus_mate/account/view/account_screen.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../model/fake_account_repository.dart';

void main() {
  Future<FakeAccountRepository> pump(WidgetTester tester, {FakeAccountRepository? repository}) async {
    final fake = repository ?? FakeAccountRepository();
    await tester.pumpWidget(ProviderScope(
      overrides: [accountRepositoryProvider.overrideWithValue(fake)],
      child: const MaterialApp(home: AccountScreen()),
    ));
    await tester.pumpAndSettle();
    return fake;
  }

  AccountInfo info({String? realName, int? birthYear, String? kakaoId, DateTime? joinedAt}) => AccountInfo(
        email: 'hong@snu.ac.kr', realName: realName, birthYear: birthYear, university: '서울대학교',
        joinedAt: joinedAt ?? DateTime.utc(2026, 9, 1, 10), kakaoId: kakaoId,
      );

  testWidgets('로그인 · 본인 확인 · 연락처 · 가입 값이 보인다', (tester) async {
    await pump(tester);

    expect(find.text('hong@snu.ac.kr'), findsOneWidget);
    expect(find.text('인증 완료'), findsOneWidget);
    expect(find.text('홍길동'), findsOneWidget);
    expect(find.text('2003'), findsOneWidget); // pen EYBxA — 숫자만
    expect(find.text('서울대학교'), findsOneWidget);
    expect(find.text('2026.09.01'), findsOneWidget); // pen nntyt
    expect(find.text('fox_rain'), findsOneWidget);
    expect(find.text(AccountScreen.privacyNote), findsOneWidget);
    expect(find.byIcon(AppIcons.calendarCheck), findsOneWidget);
  });

  testWidgets('구역 순서는 pen n8lZI 대로 — 안내문은 본인 확인 정보 바로 아래', (tester) async {
    await pump(tester);

    double top(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(top('로그인 정보'), lessThan(top('본인 확인 정보')));
    expect(top('학교'), lessThan(top(AccountScreen.privacyNote)));
    expect(top(AccountScreen.privacyNote), lessThan(top('연락처 공개 정보')));
    expect(top('연락처 공개 정보'), lessThan(top('가입 정보')));
  });

  testWidgets('가입일은 기기 시간대가 아니라 한국 날짜다', (tester) async {
    // UTC 8/31 16:00 = 한국 9/1 01:00.
    await pump(tester, repository: (FakeAccountRepository()..accountResult = Success(info(joinedAt: DateTime.utc(2026, 8, 31, 16)))));

    expect(find.text('2026.09.01'), findsOneWidget);
  });

  testWidgets('빈 값은 "—" 로 그린다', (tester) async {
    await pump(tester, repository: (FakeAccountRepository()..accountResult = Success(info())));

    expect(tester.takeException(), isNull);
    // 상수가 아니라 글자로 찾는다 — 상수를 '' 로 바꿔도 통과하던 검토 R0 권고 1.
    expect(find.text('—'), findsNWidgets(3));
  });

  testWidgets('값은 카드 안쪽 오른쪽 끝에 붙는다 — pen 라벨 fill · 값 hug', (tester) async {
    usePenFrame(tester);
    await pump(tester);

    // 360 − 목록 좌우 16 − 줄 좌우 14. 글자 상자로 잰다(Text 상자는 정렬과 무관하게 칸을 채울 수 있다).
    const cardInnerRight = 330.0;
    double lastGlyphRight(String value) {
      final p = tester.renderObject<RenderParagraph>(find.text(value));
      final last = p.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: value.length)).last;
      return p.localToGlobal(Offset(last.right, 0)).dx;
    }

    for (final value in ['hong@snu.ac.kr', '인증 완료', '홍길동', '2003', '서울대학교', '2026.09.01']) {
      expect(lastGlyphRight(value), closeTo(cardInnerRight, 0.5), reason: value);
    }
    // 카톡 줄은 셰브런(18)이 끝에 붙고, 값은 줄 간격 12 앞에서 끝난다.
    expect(tester.getRect(find.byIcon(AppIcons.chevronRight)).right, cardInnerRight);
    expect(lastGlyphRight('fox_rain'), closeTo(cardInnerRight - 18 - 12, 0.5));
  });

  testWidgets('카카오톡 줄만 누를 수 있고 셰브런이 붙는다(pen ow0m3)', (tester) async {
    await pump(tester);

    final row = find.byType(InkWell);
    expect(row, findsOneWidget);
    expect(find.descendant(of: row, matching: find.text('카카오톡 아이디')), findsOneWidget);
    final chevron = find.descendant(of: row, matching: find.byIcon(AppIcons.chevronRight));
    expect(chevron, findsOneWidget);
    expect(tester.widget<Icon>(chevron).size, 18);
    expect(tester.widget<Icon>(chevron).color, AppColors.muted);
  });

  testWidgets('카카오톡 줄의 눌림 효과는 그 카드 안에서 그려진다', (tester) async {
    // 잉크는 가장 가까운 Material 에 그린다 — 카드 밖 Material(Scaffold)이면 모서리 밖까지 번진다(COMMON §4-2).
    await pump(tester);

    final row = find.byType(InkWell);
    final material = find.ancestor(of: row, matching: find.byType(Material)).first;
    expect(tester.getSize(material), tester.getSize(row));
  });

  group('카카오톡 줄 → 16e-1(T3)', () {
    late FakeAccountRepository fake;
    late GoRouter router;

    Future<void> openKakaoIdSettings(WidgetTester tester) async {
      fake = FakeAccountRepository();
      router = GoRouter(
        initialLocation: AppRoutes.account,
        routes: [
          GoRoute(path: AppRoutes.account, builder: (context, state) => const AccountScreen()),
          GoRoute(path: AppRoutes.kakaoIdSettings, builder: (context, state) => const Scaffold(body: Text('16e-1'))),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(ProviderScope(
        overrides: [accountRepositoryProvider.overrideWithValue(fake)],
        child: MaterialApp.router(routerConfig: router),
      ));
      await tester.pumpAndSettle();
      expect(fake.accountFetches, 1);

      await tester.ensureVisible(find.text('카카오톡 아이디'));
      await tester.tap(find.text('카카오톡 아이디'));
      await tester.pumpAndSettle();
      expect(find.text('16e-1'), findsOneWidget);
      // 16e-1 이 열려 있는 동안은 다시 읽지 않는다 — 닫힌 뒤에 읽어야 저장한 아이디가 보인다(검토 R2 권고 1).
      expect(fake.accountFetches, 1);
    }

    testWidgets('저장하고 돌아오면 다시 읽는다', (tester) async {
      await openKakaoIdSettings(tester);

      router.pop(true); // 16e-1 은 저장하면 true 를 들고 닫힌다.
      await tester.pumpAndSettle();

      expect(find.byType(AccountScreen), findsOneWidget);
      expect(fake.accountFetches, 2);
    });

    testWidgets('저장하지 않고 돌아오면 다시 읽지 않는다 — 실명이 든 GET 을 한 번 덜 부른다', (tester) async {
      await openKakaoIdSettings(tester);

      router.pop();
      await tester.pumpAndSettle();

      expect(find.byType(AccountScreen), findsOneWidget);
      expect(fake.accountFetches, 1);
    });
  });

  testWidgets('못 불러오면 다시 시도할 수 있다', (tester) async {
    final fake = await pump(tester, repository: (FakeAccountRepository()..accountResult = const FailureResult(NetworkFailure())));
    expect(find.text('잠시 뒤 다시 시도해 주세요'), findsOneWidget);

    fake.accountResult = Success(sampleAccount);
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(fake.accountFetches, 2);
    expect(find.text('홍길동'), findsOneWidget);
  });

  // DESIGN §11.2 — 넘침(Flex 오류)과 잘림(오류 없이 글자가 상자 밖)을 따로 본다. 기본 800 폭에선 안 보여 pen 폭 360 으로 본다.
  for (final scale in [1.0, 1.3, 1.5, 2.0]) {
    testWidgets('폭 360 · 글자 배율 $scale 에서 넘치거나 잘리는 글자가 없다', (tester) async {
      usePenFrame(tester);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pump(tester);

      expect(tester.takeException(), isNull);
      final clipped = [
        for (final element in find.byType(RichText).evaluate())
          if (element.renderObject case final RenderParagraph p when clips(p)) p.text.toPlainText(),
      ];
      expect(clipped, isEmpty);
    });
  }
}

void usePenFrame(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 780);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// 세로는 받은 폭에서 필요한 높이로, 가로는 글자 상자 하나하나로 잰다 — 긴 낱말은 글자 단위로 줄을 바꾸므로
/// 낱말 폭(minIntrinsicWidth)으로 재면 안 잘린 것도 잘렸다고 센다. 줄 끝 공백 상자는 원래 폭 밖이라 뺀다.
/// maxLines · 말줄임은 높이도 상자도 그 줄 수에 맞춰 돌려줘 위 두 검사로는 안 보인다(검토 R1 권고 1).
bool clips(RenderParagraph p) {
  if (p.didExceedMaxLines) return true;
  if (p.getMaxIntrinsicHeight(p.constraints.maxWidth) > p.size.height + 0.5) return true;
  final text = p.text.toPlainText();
  for (var i = 0; i < text.length; i++) {
    if (text[i].trim().isEmpty) continue;
    final boxes = p.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
    if (boxes.any((box) => box.left < -0.5 || box.right > p.size.width + 0.5)) return true;
  }
  return false;
}
