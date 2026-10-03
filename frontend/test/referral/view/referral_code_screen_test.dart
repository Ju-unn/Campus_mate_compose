import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_theme.dart';
import 'package:campus_mate/friend_review/model/friend_review_repository_provider.dart';
import 'package:campus_mate/friend_review/model/friend_review_tags.dart';
import 'package:campus_mate/friend_review/view/friend_review_compose_sheet.dart';
import 'package:campus_mate/referral/model/referral_repository_provider.dart';
import 'package:campus_mate/referral/view/referral_code_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../friend_review/model/fake_friend_review_repository.dart';
import '../model/fake_referral_repository.dart';

const _referrerId = '22222222-2222-2222-2222-222222222222';

/// 20 → 20d 두 경로만 둔 라우터. 20d 자리는 글자 하나로 둬 A3 화면에 기대지 않는다.
Widget _app(FakeReferralRepository repository, {FakeFriendReviewRepository? reviews}) {
  final router = GoRouter(
    initialLocation: AppRoutes.onboardingReferral,
    routes: [
      GoRoute(path: AppRoutes.onboardingReferral, builder: (context, state) => const ReferralCodeScreen()),
      GoRoute(path: AppRoutes.onboardingAcquisition, builder: (context, state) => const Text('20d')),
    ],
  );
  return ProviderScope(
    overrides: [
      referralRepositoryProvider.overrideWithValue(repository),
      friendReviewRepositoryProvider.overrideWithValue(reviews ?? FakeFriendReviewRepository()),
    ],
    child: MaterialApp.router(routerConfig: router, theme: AppTheme.light()),
  );
}

Finder _confirm() => find.byKey(const Key('referral-confirm'));

VoidCallback? _onConfirm(WidgetTester tester) => tester.widget<ElevatedButton>(_confirm()).onPressed;

void main() {
  testWidgets('소문자 · 공백을 쳐도 대문자 6자로 들어간다', (tester) async {
    await tester.pumpWidget(_app(FakeReferralRepository()));

    await tester.enterText(find.byType(TextField), ' k7qmx2 ');
    await tester.pump();

    expect(find.text('K7QMX2'), findsOneWidget);
    expect(_onConfirm(tester), isNotNull);
  });

  testWidgets('6자보다 길게 붙여 넣어도 6자까지만 들어간다', (tester) async {
    await tester.pumpWidget(_app(FakeReferralRepository()));

    await tester.enterText(find.byType(TextField), 'k7qmx2abc');
    await tester.pump();

    expect(find.text('K7QMX2'), findsOneWidget);
  });

  testWidgets('6자 전에는 확인 버튼이 꺼져 있다', (tester) async {
    await tester.pumpWidget(_app(FakeReferralRepository()));

    await tester.enterText(find.byType(TextField), 'k7qm');
    await tester.pump();

    expect(_onConfirm(tester), isNull);
  });

  testWidgets('확인되면 코드를 준 친구의 리뷰 시트(20b)가 뜨고, 닫으면 20d 로 간다', (tester) async {
    final repository = FakeReferralRepository();
    final reviews = FakeFriendReviewRepository();
    await tester.pumpWidget(_app(repository, reviews: reviews));

    await tester.enterText(find.byType(TextField), 'k7qmx2');
    await tester.pump();
    await tester.tap(_confirm());
    await tester.pumpAndSettle();

    expect(repository.redeemedCodes, ['K7QMX2']);
    expect(tester.widget<FriendReviewComposeSheet>(find.byType(FriendReviewComposeSheet)).revieweeId, _referrerId);
    expect(reviews.targetRequests, [_referrerId]);
    expect(find.text('20d'), findsNothing);

    // 안 쓰고 닫아도(뒤로 · 밖 누르기) 가입은 이어진다.
    Navigator.of(tester.element(find.byType(FriendReviewComposeSheet))).pop();
    await tester.pumpAndSettle();

    expect(find.byType(FriendReviewComposeSheet), findsNothing);
    expect(find.text('20d'), findsOneWidget);
  });

  testWidgets('20b 에서 리뷰를 남겨도 20d 로 간다', (tester) async {
    final reviews = FakeFriendReviewRepository();
    await tester.pumpWidget(_app(FakeReferralRepository(), reviews: reviews));
    await tester.enterText(find.byType(TextField), 'k7qmx2');
    await tester.pump();
    await tester.tap(_confirm());
    await tester.pumpAndSettle();

    final chip = find.text(friendReviewTags.first);
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await tester.pump();
    await tester.tap(find.byKey(friendReviewSubmitKey));
    await tester.pumpAndSettle();

    expect(reviews.creates.single.revieweeId, _referrerId);
    expect(find.byType(FriendReviewComposeSheet), findsNothing);
    expect(find.text('20d'), findsOneWidget);
  });

  testWidgets('서버가 거절하면 그 문구를 보여 주고 20d 로 가지 않는다', (tester) async {
    final repository = FakeReferralRepository()
      ..nextRedeem = const FailureResult(ServerRejectedFailure('추천 코드는 한 번만 입력할 수 있어요'));
    await tester.pumpWidget(_app(repository));

    await tester.enterText(find.byType(TextField), 'k7qmx2');
    await tester.pump();
    await tester.tap(_confirm());
    await tester.pumpAndSettle();

    expect(find.text('추천 코드는 한 번만 입력할 수 있어요'), findsOneWidget);
    expect(find.text('20d'), findsNothing);
    expect(find.byType(ReferralCodeScreen), findsOneWidget);
  });

  testWidgets('건너뛰기는 입력 없이 20d 로 간다', (tester) async {
    final repository = FakeReferralRepository();
    await tester.pumpWidget(_app(repository));

    await tester.tap(find.byKey(const Key('referral-skip')));
    await tester.pumpAndSettle();

    expect(find.text('20d'), findsOneWidget);
    expect(repository.redeemedCodes, isEmpty);
  });

  testWidgets('건너뛰기 바탕은 화면이 아니라 버튼이 칠한다(§4-2)', (tester) async {
    await tester.pumpWidget(_app(FakeReferralRepository()));

    final ink = find.descendant(of: find.byKey(const Key('referral-skip')), matching: find.byType(InkWell));
    final material = find.ancestor(of: ink, matching: find.byType(Material)).first;

    expect(tester.getSize(material), tester.getSize(ink));
  });

  testWidgets('건너뛰기는 §13-93 예외 스타일이다(#F2F2F2 · radius.sm 바탕, #C4224B 14/600 글자)', (tester) async {
    await tester.pumpWidget(_app(FakeReferralRepository()));

    final material = tester.widget<Material>(find.byKey(const Key('referral-skip')));
    final text = tester.widget<Text>(
      find.descendant(of: find.byKey(const Key('referral-skip')), matching: find.byType(Text)),
    );

    expect(material.color, const Color(0xFFF2F2F2));
    expect(material.borderRadius, BorderRadius.circular(8));
    expect(text.style?.color, const Color(0xFFC4224B));
    expect(text.style?.fontSize, 14);
    expect(text.style?.fontWeight, FontWeight.w600);
  });

  // pen U0dkgR (2026-09-28 값표) — 앱바 없음, 배지 · 마스코트 · 문구, 확인 52 · r8, 건너뛰기 48 · 같은 폭.
  testWidgets('pen U0dkgR: 앱바 없이 배지 · 마스코트 · 헤드라인 · 설명 · 라벨 · 힌트가 있다', (tester) async {
    await tester.pumpWidget(_app(FakeReferralRepository()));

    expect(find.byType(AppBar), findsNothing);
    expect(find.text('마지막 단계'), findsOneWidget);
    expect(find.image(const AssetImage('assets/images/mascot-female.png')), findsOneWidget);
    expect(find.text('친구에게 받은 코드가 있나요?'), findsOneWidget);
    expect(find.text('코드를 입력하면 친구가 남긴 따뜻한 한마디를 프로필에 담을 수 있어요.'), findsOneWidget);
    expect(find.text('추천 코드'), findsOneWidget);
    expect(find.text('예: K7M2QX'), findsOneWidget);
    expect(find.text('코드 확인하기'), findsOneWidget);
  });

  testWidgets('pen eI62H · bTBCQ: 확인은 높이 52 · 모서리 8 주색, 건너뛰기는 높이 48 · 확인과 같은 폭', (tester) async {
    await tester.pumpWidget(_app(FakeReferralRepository()));
    await tester.enterText(find.byType(TextField), 'k7qmx2');
    await tester.pump();

    final confirm = tester.getSize(_confirm());
    final skip = tester.getSize(find.byKey(const Key('referral-skip')));
    final style = tester.widget<ElevatedButton>(_confirm()).style!;

    expect(confirm.height, 52);
    expect(skip.height, 48);
    expect(skip.width, confirm.width);
    expect(style.shape?.resolve({}), RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)));
    expect(style.backgroundColor?.resolve({}), const Color(0xFFFF385C));
  });

  for (final scale in [1.3, 2.0]) {
    testWidgets('pen 크기(360×780) 글자 $scale배에서도 넘치지 않는다', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      tester.view
        ..physicalSize = const Size(360, 780)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_app(FakeReferralRepository()));
      await tester.enterText(find.byType(TextField), 'k7qmx2');
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  }
}
