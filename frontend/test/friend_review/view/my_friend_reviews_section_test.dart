import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/friend_review/model/friend_review_repository_provider.dart';
import 'package:campus_mate/friend_review/view/my_friend_reviews_section.dart';
import 'package:campus_mate/friend_review/view/written_reviews_screen.dart';
import 'package:campus_mate/me/view/profile_entry_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../model/fake_friend_review_repository.dart';

final _received = find.widgetWithText(ProfileEntryRow, '친구들이 본 나');
final _written = find.widgetWithText(ProfileEntryRow, '내가 쓴 리뷰');

/// 15 지인 리뷰 칸(pen `Cux1p`, 값표 20e §1 · 값표 B §8): 헤더 → 12 → 분홍 줄 `o9BA0` → 12 → 흰 줄 `tStBN`.
void main() {
  late FakeFriendReviewRepository reviews;

  setUp(() {
    reviews = FakeFriendReviewRepository()
      ..received = Success([
        friendReviewFixture(id: 'a1'),
        friendReviewFixture(id: 'a2'),
        friendReviewFixture(id: 'a3'),
      ])
      ..written = Success([
        friendReviewFixture(id: 'r1', nickname: '달빛'),
        friendReviewFixture(id: 'r2', nickname: '봄바람'),
      ]);
  });

  /// 15 본문 자리(좌우 16, 폭 328)에 칸만 놓는다. 20e 는 진짜 화면, 20c 는 자리 화면.
  Future<void> pump(WidgetTester tester, {double scale = 1, bool settle = true}) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final container = ProviderContainer(overrides: [friendReviewRepositoryProvider.overrideWithValue(reviews)]);
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: AppRoutes.myProfile,
      routes: [
        GoRoute(
          path: AppRoutes.myProfile,
          builder: (context, state) => Scaffold(
            body: ListView(padding: const EdgeInsets.all(16), children: const [MyFriendReviewsSection()]),
          ),
        ),
        GoRoute(path: AppRoutes.friendReviews, builder: (context, state) => const Scaffold(body: Text('20c 화면'))),
        GoRoute(path: AppRoutes.friendReviewsWritten, builder: (context, state) => const WrittenReviewsScreen()),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: MaterialApp.router(routerConfig: router)),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  String noteOf(WidgetTester tester, Finder row) => tester.widget<ProfileEntryRow>(row).note;

  testWidgets('헤더 "지인 리뷰"(p7FSo/mHDrn) 17/700 ink 렌더 25 → 12 → 분홍 줄 84 → 12 → 흰 줄 84, 폭 328', (tester) async {
    await pump(tester);

    final header = find.text('지인 리뷰');
    final headerRect = tester.getRect(header);
    final style = tester.widget<Text>(header).style!;
    expect((style.fontSize, style.fontWeight, style.color), (17, FontWeight.w700, AppColors.ink));
    expect(headerRect.height, 25);
    final received = tester.getRect(_received);
    final written = tester.getRect(_written);
    expect(received.top - headerRect.bottom, 12);
    expect(written.top - received.bottom, 12);
    expect((received.left, received.width, received.height), (16, 328, 84));
    expect((written.left, written.width, written.height), (16, 328, 84));
    expect(tester.getSize(find.byType(MyFriendReviewsSection)).height, 25 + 12 + 84 + 12 + 84);
  });

  testWidgets('분홍 줄(o9BA0)은 강조 · 3D heart-handshake "친구들이 본 나", 흰 줄(tStBN)은 3D 대화 "내가 쓴 리뷰"', (tester) async {
    await pump(tester);

    final received = tester.widget<ProfileEntryRow>(_received);
    expect((received.emphasis, received.icon), (true, AppIcon3d.heartHandshake));
    final written = tester.widget<ProfileEntryRow>(_written);
    expect((written.emphasis, written.icon), (false, AppIcon3d.chat));
    // pen 의 3D 아이콘(`M4cgT` heart-handshake · `s2EdJh` 대화 feature-icon-chat-3d-tight)이다.
    expect((AppIcon3d.heartHandshake.asset, AppIcon3d.chat.asset), ('assets/icons/ui-3d-heart-handshake.webp', 'assets/icons/feature-icon-chat-3d-tight.webp'));
  });

  testWidgets('노트는 개수 — "받은 리뷰 3개"(B4ppA) · "쓴 리뷰 2개"(tStBN/B4ppA)', (tester) async {
    await pump(tester);

    expect((noteOf(tester, _received), noteOf(tester, _written)), ('받은 리뷰 3개', '쓴 리뷰 2개'));
  });

  testWidgets('0개면 "받은 리뷰 0개" · "쓴 리뷰 0개"', (tester) async {
    reviews
      ..received = const Success([])
      ..written = const Success([]);
    await pump(tester);

    expect((noteOf(tester, _received), noteOf(tester, _written)), ('받은 리뷰 0개', '쓴 리뷰 0개'));
  });

  testWidgets('읽는 중이거나 실패하면 노트는 비워 제목만 — 줄 높이 84 는 그대로(대장 결정 가)', (tester) async {
    reviews
      ..holdReceived = Completer<void>()
      ..written = const FailureResult(NetworkFailure());
    await pump(tester, settle: false);
    await tester.pump();

    expect((noteOf(tester, _received), noteOf(tester, _written)), ('', ''));
    expect((tester.getSize(_received).height, tester.getSize(_written).height), (84, 84));
    reviews.holdReceived!.complete();
    await tester.pumpAndSettle();
    expect(noteOf(tester, _received), '받은 리뷰 3개');
  });

  testWidgets('분홍 줄을 누르면 20c, 흰 줄을 누르면 20e 로 간다(push — 뒤로 오면 15)', (tester) async {
    await pump(tester);

    await tester.tap(_received);
    await tester.pumpAndSettle();
    expect(find.text('20c 화면'), findsOneWidget);
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();

    await tester.tap(_written);
    await tester.pumpAndSettle();
    expect(find.byType(WrittenReviewsScreen), findsOneWidget);
  });

  testWidgets('15 가 떠 있어도 20e 에 들어가면 새로 읽는다 — 그새 늘어난 리뷰가 보이고 15 개수도 맞는다(검토 필수 1)', (tester) async {
    await pump(tester);
    reviews.written = Success([
      friendReviewFixture(id: 'r0', nickname: '새벽'),
      friendReviewFixture(id: 'r1', nickname: '달빛'),
      friendReviewFixture(id: 'r2', nickname: '봄바람'),
    ]);

    await tester.tap(_written);
    await tester.pumpAndSettle();

    expect(find.text('새벽'), findsOneWidget);
    expect(reviews.writtenCount, 2);
    await tester.tap(find.byTooltip(const DefaultMaterialLocalizations().backButtonTooltip));
    await tester.pumpAndSettle();
    expect(noteOf(tester, _written), '쓴 리뷰 3개');
  });

  testWidgets('20e 에서 지우고 돌아오면 "쓴 리뷰 1개" — 15 는 다시 읽지 않는다(20e 에 들어갈 때 한 번만)', (tester) async {
    await pump(tester);
    await tester.tap(_written);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(AppIcons.trash2).first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(AppButton, '지우기'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(const DefaultMaterialLocalizations().backButtonTooltip));
    await tester.pumpAndSettle();

    expect(noteOf(tester, _written), '쓴 리뷰 1개');
    expect(reviews.deletes, ['r1']);
    expect(reviews.writtenCount, 2);
  });

  // DESIGN §11.2 — 넘침(Flex 오류)과 잘림(고정 상자, 오류 없음)을 따로 본다.
  for (final scale in [1.3, 2.0]) {
    testWidgets('글자 배율 $scale 에서 넘치거나 잘리는 글자가 없다', (tester) async {
      await pump(tester, scale: scale);

      expect(tester.takeException(), isNull);
      final clipped = [
        for (final element in find.byType(RichText).evaluate())
          if (element.renderObject case final RenderParagraph p
              when p.getMaxIntrinsicHeight(p.size.width) > p.size.height + 0.5 ||
                  p.getMinIntrinsicWidth(double.infinity) > p.size.width + 0.5)
            p.text.toPlainText(),
      ];
      expect(clipped, isEmpty);
    });
  }
}
