import 'package:campus_mate/account/model/account_repository.dart';
import 'package:campus_mate/account/view/account_screen.dart';
import 'package:campus_mate/account/view/account_suspended_screen.dart';
import 'package:campus_mate/account/view/kakao_id_settings_screen.dart';
import 'package:campus_mate/auth/model/verification_gate.dart';
import 'package:campus_mate/chat/model/chat_repository_provider.dart';
import 'package:campus_mate/chat/view/chat_room_screen.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/auth/account_status_listenable.dart';
import 'package:campus_mate/core/router/app_router.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_theme.dart';
import 'package:campus_mate/faq/model/faq_cache.dart';
import 'package:campus_mate/faq/model/faq_repository.dart';
import 'package:campus_mate/faq/view/faq_screen.dart';
import 'package:campus_mate/friend_review/model/friend_review_repository_provider.dart';
import 'package:campus_mate/home/model/home_repository_provider.dart';
import 'package:campus_mate/home/view/home_screen.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:campus_mate/matching/view/conversations_screen.dart';
import 'package:campus_mate/me/model/me_repository_provider.dart';
import 'package:campus_mate/me/model/my_profile.dart';
import 'package:campus_mate/me/view/basic_info_edit_screen.dart';
import 'package:campus_mate/me/view/card_preview_screen.dart';
import 'package:campus_mate/me/view/my_photos_screen.dart';
import 'package:campus_mate/me/view/my_profile_screen.dart';
import 'package:campus_mate/me/view/profile_edit_screen.dart';
import 'package:campus_mate/me/view/profile_manage_screen.dart';
import 'package:campus_mate/profile/model/onboarding_step.dart';
import 'package:campus_mate/profile/view/ideal_conditions_screen.dart';
import 'package:campus_mate/profile/view/tag_picker_screen.dart';
import 'package:campus_mate/profile/viewmodel/tag_picker_kind.dart';
import 'package:campus_mate/safety/model/safety_repository_provider.dart';
import 'package:campus_mate/safety/view/block_list_screen.dart';
import 'package:campus_mate/safety/view/partner_profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../account/model/fake_account_repository.dart';
import '../../chat/model/fake_chat_repository.dart';
import '../../faq/model/fake_faq.dart';
import '../../friend_review/model/fake_friend_review_repository.dart';
import '../../home/model/fake_home_repository.dart';
import '../../matching/model/fake_card_repository.dart';
import '../../me/model/fake_me_repository.dart';
import '../../safety/model/fake_safety_repository.dart';

/// 이 파일은 경로·화면 연결만 본다. 게이트별 이동 규칙은 auth_redirect_test 가 맡는다.
VerificationGate _passedGate() => VerificationGate.complete;
OnboardingStep _passedStep() => OnboardingStep.complete;

/// 나 탭 편집 화면이 읽는 내 프로필(지어낸 값).
const _meProfile = MyProfile(
  nickname: '여우',
  age: 23,
  university: '가나대학교',
  major: null,
  heightCm: null,
  mbti: null,
  avatarUrl: null,
  preferredAgeMin: 22,
  preferredAgeMax: 27,
  preferredHeightMin: null,
  preferredHeightMax: null,
  bio: '안녕하세요',
);

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

  testWidgets('"나" 탭(/me)으로 가면 화면 15 내 프로필이 보인다', (tester) async {
    final router = AppRouter.create(
      isAuthenticated: () => true,
      verificationGate: _passedGate,
      onboardingStep: _passedStep,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cardRepositoryProvider.overrideWithValue(FakeCardRepository()),
          chatRepositoryProvider.overrideWithValue(FakeChatRepository()),
          meRepositoryProvider.overrideWithValue(FakeMeRepository(const FailureResult(NetworkFailure()))),
        ],
        child: MaterialApp.router(routerConfig: router, theme: AppTheme.light()),
      ),
    );
    router.go(AppRoutes.myProfile);
    await tester.pumpAndSettle();

    expect(find.byType(MyProfileScreen), findsOneWidget);
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

  group('조각 6 경로', () {
    Future<GoRouter> pumpRouter(
      WidgetTester tester, {
      bool passedRoom = false,
      AccountStatus Function()? accountStatus,
    }) async {
      final router = AppRouter.create(
        isAuthenticated: () => true,
        verificationGate: _passedGate,
        onboardingStep: _passedStep,
        accountStatus: accountStatus ?? () => AccountStatus.active,
      );
      addTearDown(router.dispose);
      // 방이 열린 채 테스트가 끝나면 방의 dispose(읽음 → 목록 새로 읽기)가 컨테이너보다 늦게 돈다 —
      // 컨테이너는 위젯 트리를 걷어 낸 뒤에 닫는다.
      final container = ProviderContainer(
        overrides: [
          cardRepositoryProvider.overrideWithValue(FakeCardRepository()),
          homeRepositoryProvider.overrideWithValue(FakeHomeRepository(const FailureResult(NetworkFailure()))),
          chatRepositoryProvider.overrideWithValue(
              FakeChatRepository()..room = Success(roomFixture(passed: passedRoom, kakaoId: 'fox_rain'))),
          messageStreamProvider.overrideWithValue(FakeMessageStream()),
          safetyRepositoryProvider.overrideWithValue(FakeSafetyRepository()),
          // 16e 가 열리면 계정 정보를, 16e-1 이 열리면 저장된 아이디를 읽는다.
          accountRepositoryProvider.overrideWithValue(FakeAccountRepository()),
          friendReviewRepositoryProvider.overrideWithValue(FakeFriendReviewRepository()),
          // 21 이 열리면 FAQ 를 읽는다.
          faqRepositoryProvider.overrideWithValue(FakeFaqRepository(const Success(faqFixture))),
          faqCacheProvider.overrideWithValue(FakeFaqCache()),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router, theme: AppTheme.light()),
        ),
      );
      return router;
    }

    testWidgets('/settings/blocks 는 16f 차단 목록이다', (tester) async {
      final router = await pumpRouter(tester);

      router.go(AppRoutes.blockList);
      await tester.pumpAndSettle();

      expect(find.byType(BlockListScreen), findsOneWidget);
    });

    testWidgets('/settings/account 는 16e 계정이다', (tester) async {
      final router = await pumpRouter(tester);

      router.go(AppRoutes.account);
      await tester.pumpAndSettle();

      expect(find.byType(AccountScreen), findsOneWidget);
    });

    testWidgets('/settings/account/kakao-id 는 16e-1 카카오톡 아이디 변경이다', (tester) async {
      final router = await pumpRouter(tester);

      router.go(AppRoutes.kakaoIdSettings);
      await tester.pumpAndSettle();

      expect(find.byType(KakaoIdSettingsScreen), findsOneWidget);
    });

    testWidgets('/settings/faq 는 21 자주 묻는 질문이다', (tester) async {
      final router = await pumpRouter(tester);

      router.go(AppRoutes.faq);
      await tester.pumpAndSettle();

      expect(find.byType(FaqScreen), findsOneWidget);
    });

    testWidgets('/friend-reviews 는 20c 받은 리뷰다', (tester) async {
      final router = await pumpRouter(tester);

      router.go(AppRoutes.friendReviews);
      await tester.pumpAndSettle();

      expect(find.text('받은 리뷰'), findsOneWidget);
    });

    testWidgets('/friend-reviews/written 은 20e 내가 쓴 리뷰다', (tester) async {
      final router = await pumpRouter(tester);

      router.go(AppRoutes.friendReviewsWritten);
      await tester.pumpAndSettle();

      expect(find.text('내가 쓴 리뷰'), findsOneWidget);
    });

    // 추천 가입 푸시(`friend_review_write`)가 가는 곳 — 홈이 밑에 깔리고 그 위에 20b 시트(대장 Q1).
    testWidgets('/home/friend-reviews/write/p2 는 09b 홈 위에 20b 시트를 띄우고, 닫으면 홈이다', (tester) async {
      final router = await pumpRouter(tester);

      router.go('${AppRoutes.friendReviewWrite}/p2');
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('어떤 장점이 있나요?'), findsOneWidget);

      // 기본 화면(800×600)에서는 664 시트가 화면을 다 덮어 딤이 없다 — 시스템 뒤로가기로 닫는다.
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('어떤 장점이 있나요?'), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(router.state.matchedLocation, AppRoutes.home);
    });

    testWidgets('/profiles/:profileId 는 그 사람의 14c 상대 프로필이다', (tester) async {
      final router = await pumpRouter(tester);

      router.go('${AppRoutes.partnerProfile}/p2');
      await tester.pumpAndSettle();

      expect(tester.widget<PartnerProfileScreen>(find.byType(PartnerProfileScreen)).profileId, 'p2');
    });

    // 경로가 없을 때는 14b 버튼이 go_router 오류 화면으로 떨어졌다.
    testWidgets('채팅방 14b "상대 프로필 보기" 를 누르면 14c 가 열리고, 뒤로가면 방으로 돌아온다', (tester) async {
      final router = await pumpRouter(tester, passedRoom: true);
      router.go('${AppRoutes.chatRoom}/m1');
      await tester.pumpAndSettle();

      await tester.tap(find.text('상대 프로필 보기'));
      await tester.pumpAndSettle();

      expect(find.byType(PartnerProfileScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(ChatRoomScreen), findsOneWidget);
    });

    testWidgets('정지된 계정은 어느 화면으로 가도 정지 안내(pen e7QaDh)가 보인다', (tester) async {
      var status = AccountStatus.active;
      final router = await pumpRouter(tester, accountStatus: () => status);
      router.go(AppRoutes.blockList);
      await tester.pumpAndSettle();
      expect(find.byType(BlockListScreen), findsOneWidget);

      status = AccountStatus.suspended;
      router.refresh();
      await tester.pumpAndSettle();

      expect(find.byType(AccountSuspendedScreen), findsOneWidget);
    });
  });

  // 나 탭 편집(계획서 A2) — 완료한 사람이 가면 돌려보내지지 않고 그 화면이 편집 모드로 뜬다.
  group('나 탭 편집 경로', () {
    Future<GoRouter> pumpRouter(WidgetTester tester) async {
      final router = AppRouter.create(
        isAuthenticated: () => true,
        verificationGate: _passedGate,
        onboardingStep: _passedStep,
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            // 첫 화면(홈)이 하단 내비 뱃지와 요약을 읽는다.
            cardRepositoryProvider.overrideWithValue(FakeCardRepository()),
            chatRepositoryProvider.overrideWithValue(FakeChatRepository()),
            homeRepositoryProvider.overrideWithValue(FakeHomeRepository(const FailureResult(NetworkFailure()))),
            meRepositoryProvider.overrideWithValue(FakeMeRepository(const Success(_meProfile))),
          ],
          child: MaterialApp.router(routerConfig: router, theme: AppTheme.light()),
        ),
      );
      return router;
    }

    testWidgets('/me/edit 는 15c 자기소개·태그 수정이다', (tester) async {
      final router = await pumpRouter(tester);

      router.go(AppRoutes.myProfileEdit);
      await tester.pumpAndSettle();

      expect(find.byType(ProfileEditScreen), findsOneWidget);
    });

    // 화면 15 개편(계획서 2026-09-28-me-profile.md A10) — 15 의 입구 "프로필 편집"(`sC8BR`)이 여는 화면.
    testWidgets('/me/manage 는 15-5 프로필 편집이다', (tester) async {
      final router = await pumpRouter(tester);

      router.go(AppRoutes.myProfileManage);
      await tester.pumpAndSettle();

      expect(find.byType(ProfileManageScreen), findsOneWidget);
    });

    // 15 의 입구 "남이 보는 내 프로필 카드"(`k3r5C`)가 여는 화면.
    testWidgets('/me/preview 는 15-4 남이 보는 내 프로필이다', (tester) async {
      final router = await pumpRouter(tester);

      router.go(AppRoutes.myCardPreview);
      await tester.pumpAndSettle();

      expect(find.byType(CardPreviewScreen), findsOneWidget);
    });

    // 15-5 "실제 사진 교체"(`E7Cv2`)가 여는 화면(계획서 2026-09-28-me-profile.md A15).
    testWidgets('/me/photos 는 15e 사진 수정이다', (tester) async {
      final router = await pumpRouter(tester);

      router.go(AppRoutes.myPhotos);
      await tester.pumpAndSettle();

      expect(find.byType(MyPhotosScreen), findsOneWidget);
    });

    // 15-5 "수정 ›"(`A8LX2`)이 여는 화면(계획서 2026-09-28-me-profile.md A16).
    testWidgets('/me/basic-info 는 15d 기본 정보 수정이다', (tester) async {
      final router = await pumpRouter(tester);

      router.go(AppRoutes.myBasicInfo);
      await tester.pumpAndSettle();

      expect(find.byType(BasicInfoEditScreen), findsOneWidget);
    });

    testWidgets('/me/ideal-conditions 는 06-1 편집 모드다', (tester) async {
      final router = await pumpRouter(tester);

      router.go(AppRoutes.myIdealConditions);
      await tester.pumpAndSettle();

      expect(tester.widget<IdealConditionsScreen>(find.byType(IdealConditionsScreen)).isEditing, isTrue);
    });

    for (final kind in TagPickerKind.values) {
      testWidgets('/me/edit/tags/${kind.endpoint} 는 ${kind.name} 태그 편집 모드다', (tester) async {
        final router = await pumpRouter(tester);

        router.go('${AppRoutes.myTags}/${kind.endpoint}');
        await tester.pumpAndSettle();

        final screen = tester.widget<TagPickerScreen>(find.byType(TagPickerScreen));
        expect((screen.kind, screen.isEditing), (kind, true));
      });
    }

    testWidgets('없는 태그 종류(/me/edit/tags/없는값)는 15c 로 보낸다', (tester) async {
      final router = await pumpRouter(tester);

      router.go('${AppRoutes.myTags}/없는값');
      await tester.pumpAndSettle();

      expect(find.byType(ProfileEditScreen), findsOneWidget);
      expect(find.byType(TagPickerScreen), findsNothing);
    });
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

  test('06-3 뒤 앱에서만 잇는 20 · 20d 경로도 라우터에 등록돼 있다', () {
    final router = AppRouter.create(
      isAuthenticated: () => true,
      verificationGate: _passedGate,
      onboardingStep: _passedStep,
    );
    final registered = router.configuration.routes.whereType<GoRoute>().map((route) => route.path);

    expect(registered, containsAll(<String>[AppRoutes.onboardingReferral, AppRoutes.onboardingAcquisition]));
  });
}
