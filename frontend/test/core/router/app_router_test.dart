import 'package:campus_mate/auth/model/verification_gate.dart';
import 'package:campus_mate/chat/model/chat_repository_provider.dart';
import 'package:campus_mate/chat/view/chat_room_screen.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/router/app_router.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_theme.dart';
import 'package:campus_mate/home/model/home_repository_provider.dart';
import 'package:campus_mate/home/view/home_screen.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:campus_mate/matching/view/conversations_screen.dart';
import 'package:campus_mate/profile/model/onboarding_step.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../chat/model/fake_chat_repository.dart';
import '../../home/model/fake_home_repository.dart';
import '../../matching/model/fake_card_repository.dart';

/// 이 파일은 경로·화면 연결만 본다. 게이트별 이동 규칙은 auth_redirect_test 가 맡는다.
VerificationGate _passedGate() => VerificationGate.complete;
OnboardingStep _passedStep() => OnboardingStep.complete;

const _onboardingPaths = <String>[
  AppRoutes.onboardingBasicInfo,
  AppRoutes.onboardingKakaoId,
  AppRoutes.onboardingPhotos,
  AppRoutes.onboardingAvatar,
  AppRoutes.onboardingAppearanceType,
  AppRoutes.onboardingInterests,
  AppRoutes.onboardingMyTraits,
  AppRoutes.onboardingSurvey,
  AppRoutes.onboardingIdealConditions,
  AppRoutes.onboardingIdealTraits,
  AppRoutes.onboardingIdealNote,
  AppRoutes.onboardingBio,
];

void main() {
  testWidgets('스플래시를 붙잡는 동안에는 스플래시가 보인다', (tester) async {
    var isHeld = true;
    final router = AppRouter.create(
      isAuthenticated: () => false,
      verificationGate: _passedGate,
      onboardingStep: _passedStep,
      isSplashHeld: () => isHeld,
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(routerConfig: router, theme: AppTheme.light()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('CampusMate'), findsOneWidget);

    // 시간이 다 되면(SplashHold 가 알림) 원래 이동 규칙으로 돌아간다.
    isHeld = false;
    router.refresh();
    await tester.pumpAndSettle();

    expect(find.text('대학 이메일로 시작해요'), findsOneWidget);
  });

  testWidgets('로그인하지 않으면 로그인 화면이 보인다', (tester) async {
    final router = AppRouter.create(
      isAuthenticated: () => false,
      verificationGate: _passedGate,
      onboardingStep: _passedStep,
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(routerConfig: router, theme: AppTheme.light()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('대학 이메일로 시작해요'), findsOneWidget);
  });

  // 홈은 09b 메인이다. 오늘의 카드는 하단 내비 "오늘" 탭(`/today`)에 있다.
  testWidgets('로그인하면 09b 메인 화면이 보인다', (tester) async {
    final router = AppRouter.create(
      isAuthenticated: () => true,
      verificationGate: _passedGate,
      onboardingStep: _passedStep,
    );

    await tester.pumpWidget(
      ProviderScope(
        // 하단 내비 뱃지가 수락 대기·안 읽은 메시지를 읽는다(§8.8).
        overrides: [
          cardRepositoryProvider.overrideWithValue(FakeCardRepository()),
          chatRepositoryProvider.overrideWithValue(FakeChatRepository()),
          homeRepositoryProvider.overrideWithValue(FakeHomeRepository(const FailureResult(NetworkFailure()))),
        ],
        child: MaterialApp.router(routerConfig: router, theme: AppTheme.light()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('extra 없이 인증코드 화면에 진입하면 로그인 화면으로 보낸다', (tester) async {
    final router = AppRouter.create(
      isAuthenticated: () => false,
      verificationGate: _passedGate,
      onboardingStep: _passedStep,
    );
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router, theme: AppTheme.light())),
    );
    router.go(AppRoutes.verifyCode);
    await tester.pumpAndSettle();

    expect(find.text('대학 이메일로 시작해요'), findsOneWidget);
  });

  // 푸시·매칭 성사는 `go` 로 방을 여는데 그때 스택에는 방 한 장뿐이다.
  // 뒤로가기가 그 한 장을 pop 하면 빈 화면이 남는다 — 목록으로 내려보내야 한다.
  testWidgets('푸시로 연 채팅방에서 뒤로가기를 누르면 대화 목록이 보인다', (tester) async {
    final router = AppRouter.create(
      isAuthenticated: () => true,
      verificationGate: _passedGate,
      onboardingStep: _passedStep,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cardRepositoryProvider.overrideWithValue(FakeCardRepository()),
          chatRepositoryProvider
              .overrideWithValue(FakeChatRepository()..room = Success(roomFixture())),
          messageStreamProvider.overrideWithValue(FakeMessageStream()),
        ],
        child: MaterialApp.router(routerConfig: router, theme: AppTheme.light()),
      ),
    );
    router.go('${AppRoutes.chatRoom}/m1');
    await tester.pumpAndSettle();
    expect(find.byType(ChatRoomScreen), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.byType(ConversationsScreen), findsOneWidget);
  });

  // 백로그 23: 앱바 화살표만 고쳐 두면 안드로이드 시스템 뒤로가기에서 앱이 그냥 닫힌다.
  testWidgets('푸시로 연 채팅방에서 시스템 뒤로가기를 해도 대화 목록이 보인다', (tester) async {
    final router = AppRouter.create(
      isAuthenticated: () => true,
      verificationGate: _passedGate,
      onboardingStep: _passedStep,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cardRepositoryProvider.overrideWithValue(FakeCardRepository()),
          chatRepositoryProvider
              .overrideWithValue(FakeChatRepository()..room = Success(roomFixture())),
          messageStreamProvider.overrideWithValue(FakeMessageStream()),
        ],
        child: MaterialApp.router(routerConfig: router, theme: AppTheme.light()),
      ),
    );
    router.go('${AppRoutes.chatRoom}/m1');
    await tester.pumpAndSettle();

    // false 면 안드로이드가 뒤로가기를 "앱 종료" 로 처리한다.
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();

    expect(find.byType(ConversationsScreen), findsOneWidget);
  });

  test('온보딩 경로 12개가 전부 라우터에 등록돼 있다', () {
    final router = AppRouter.create(
      isAuthenticated: () => true,
      verificationGate: _passedGate,
      onboardingStep: _passedStep,
    );
    final registered = router.configuration.routes.whereType<GoRoute>().map((route) => route.path);

    // 하나라도 빠지면 AuthRedirect 가 보낸 곳에 화면이 없어 앱이 오류 페이지로 떨어진다.
    expect(registered, containsAll(_onboardingPaths));
  });
}
