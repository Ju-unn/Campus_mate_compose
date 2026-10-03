import 'package:campus_mate/account/model/account_repository.dart';
import 'package:campus_mate/account/view/kakao_id_settings_screen.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/notice_card.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/profile/model/kakao_id_repository_provider.dart';
import 'package:campus_mate/profile/view/kakao_id_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../profile/model/fake_kakao_id_repository.dart';
import '../model/fake_account_repository.dart';

void main() {
  late FakeAccountRepository account;
  late FakeKakaoIdRepository kakao;

  /// 앞 화면(16e · 14f 자리)에서 push 로 연다. 돌아온 값을 [popped] 에 담는다.
  Future<List<Object?>> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    account = FakeAccountRepository();
    kakao = FakeKakaoIdRepository();
    final popped = <Object?>[];
    final router = GoRouter(
      initialLocation: '/before',
      routes: [
        GoRoute(
          path: '/before',
          builder: (context, state) => Scaffold(
            body: TextButton(
              onPressed: () async => popped.add(await context.push<bool>(AppRoutes.kakaoIdSettings)),
              child: const Text('열기'),
            ),
          ),
        ),
        GoRoute(path: AppRoutes.kakaoIdSettings, builder: (context, state) => const KakaoIdSettingsScreen()),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountRepositoryProvider.overrideWithValue(account),
          kakaoIdRepositoryProvider.overrideWithValue(kakao),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    return popped;
  }

  testWidgets('pen bWrnD 글자 — 앱바 · 부제 · 입력칸 라벨 · 저장, helper 없음', (tester) async {
    await pump(tester);

    expect(find.descendant(of: find.byType(AppBar), matching: find.text('카카오톡 아이디')), findsOneWidget);
    expect(find.text('신뢰 확인을 마친 상대에게만 공개돼요.'), findsOneWidget);
    // 앱바 제목과 입력칸 라벨(HGpMk)이 같은 글자다.
    expect(find.text('카카오톡 아이디'), findsNWidgets(2));
    expect(find.text('저장'), findsOneWidget);
    // 04-1b 의 helper("설정 > 계정에서…")는 여기 없다.
    expect(find.text('설정 > 계정에서 언제든 바꿀 수 있어요'), findsNothing);
  });

  testWidgets('16e-1 shows NoticeCard with KakaoSettingExample (not a copy)', (tester) async {
    await pump(tester);

    final notice = find.byType(NoticeCard);
    expect(tester.widget<NoticeCard>(notice).isEmphasis, isTrue);
    expect(find.descendant(of: notice, matching: find.text('꼭 확인해 주세요')), findsOneWidget);
    expect(find.descendant(of: notice, matching: find.byType(KakaoSettingExample)), findsOneWidget);
    expect(
      find.text("카카오톡에서 'ID 검색 허용'을 켜주셔야 상대가 내 아이디를 검색할 수 있어요. 꺼져 있으면 신뢰 확인을 마쳐도 연락이 닿지 않아요."),
      findsOneWidget,
    );
    expect(find.text('카카오톡 > 설정 > 프로필 관리 > 카카오톡 ID 에서 켤 수 있어요'), findsOneWidget);
  });

  testWidgets('저장된 아이디가 입력칸에 채워진다', (tester) async {
    await pump(tester);

    expect(find.widgetWithText(TextField, 'hong_gildong'), findsOneWidget);
    expect(account.kakaoIdFetches, greaterThanOrEqualTo(1));
  });

  testWidgets('저장 버튼은 하단 고정 312×52(pen u6wJjx · Button HE8FZ 2026-10-01 개편), 아래 여백 28', (tester) async {
    await pump(tester);

    final save = find.byType(AppButton);
    expect(tester.getSize(save), const Size(312, 52));
    expect(tester.getRect(save).bottom, 780 - 28);
  });

  testWidgets('저장하면 다듬은 아이디를 보내고 true 로 닫힌다', (tester) async {
    final popped = await pump(tester);

    await tester.enterText(find.byType(TextField), '  fox_rain  ');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(kakao.submitted, ['fox_rain']);
    expect(find.byType(KakaoIdSettingsScreen), findsNothing);
    expect(popped, [true]);
  });

  testWidgets('비우면 저장할 수 없다', (tester) async {
    await pump(tester);

    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();

    expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).enabled, isFalse);
  });

  // DESIGN §11.2 — 시스템 글꼴 확대. 넘침(Flex 오류)과 잘림(고정 상자, 오류 없음)을 따로 본다.
  // 2.0 은 KakaoSettingExample 의 "ID 검색 허용" 이 Flexible 이 아니라 18px 넘쳤다(04-1b 도 같은 위젯).
  for (final scale in [1.3, 1.5, 2.0]) {
    testWidgets('글자 배율 $scale 에서 넘치거나 잘리는 글자가 없다', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pump(tester);

      final clipped = [
        for (final element in find.byType(RichText).evaluate())
          if (element.renderObject case final RenderParagraph p
              when p.getMaxIntrinsicHeight(p.size.width) > p.size.height + 0.5)
            p.text.toPlainText(),
      ];
      expect(tester.takeException(), isNull);
      expect(clipped, isEmpty);
    });
  }
}
