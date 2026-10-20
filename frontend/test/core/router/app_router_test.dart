import 'dart:async';

import 'package:campus_mate/account/model/account_repository.dart';
import 'package:campus_mate/common/widgets/labeled_field.dart';
import 'package:campus_mate/common/widgets/onboarding_app_bar.dart';
import 'package:campus_mate/common/widgets/select_chip.dart';
import 'package:campus_mate/profile/model/profile_enums.dart';
import 'package:campus_mate/profile/view/appearance_pickers.dart';
import 'package:campus_mate/profile/view/appearance_type_screen.dart';
import 'package:campus_mate/core/router/onboarding_step_listenable_provider.dart';
import 'package:campus_mate/profile/model/basic_info_repository_provider.dart';
import 'package:campus_mate/profile/model/kakao_id_repository_provider.dart';
import 'package:campus_mate/profile/model/avatar_generation_outcome.dart';
import 'package:campus_mate/profile/model/avatar_repository_provider.dart';
import 'package:campus_mate/profile/model/onboarding_repository_provider.dart';
import 'package:campus_mate/profile/view/kakao_id_screen.dart';
import 'package:campus_mate/profile/view/photos_screen.dart';
import 'package:campus_mate/profile/viewmodel/basic_info_view_model.dart';
import 'package:campus_mate/account/view/account_screen.dart';
import 'package:campus_mate/account/view/account_suspended_screen.dart';
import 'package:campus_mate/account/view/kakao_id_settings_screen.dart';
import 'package:campus_mate/auth/model/school_email_repository_provider.dart';
import 'package:campus_mate/auth/model/school_name_provider.dart';
import 'package:campus_mate/auth/model/social_login_repository_provider.dart';
import 'package:campus_mate/auth/model/university_email.dart';
import 'package:campus_mate/auth/model/verification_gate.dart';
import 'package:campus_mate/auth/view/sign_up_screen.dart';
import 'package:campus_mate/auth/view/start_view.dart';
import 'package:campus_mate/auth/view/verify_code_screen.dart';
import 'package:campus_mate/billing/view/heart_store_screen.dart';
import 'package:campus_mate/chat/model/chat_repository_provider.dart';
import 'package:campus_mate/chat/view/chat_room_screen.dart';
import 'package:campus_mate/community/model/community_repository_provider.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/university_logos.dart';
import 'package:campus_mate/core/analytics/screen_view_observer.dart';
import 'package:campus_mate/core/auth/account_status_listenable.dart';
import 'package:campus_mate/core/back_exit/back_exit_scope.dart';
import 'package:campus_mate/core/back_exit/back_exit_view_model.dart';
import 'package:campus_mate/core/router/app_router.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/router/onboarding_step_listenable.dart';
import 'package:campus_mate/core/supabase/auth_session_listenable_provider.dart';
import 'package:campus_mate/core/theme/app_theme.dart';
import 'package:campus_mate/faq/model/faq_cache.dart';
import 'package:campus_mate/faq/model/faq_repository.dart';
import 'package:campus_mate/faq/view/faq_screen.dart';
import 'package:campus_mate/home/view/event_coming_screen.dart';
import 'package:campus_mate/friend_review/view/friend_code_screen.dart';
import 'package:campus_mate/friend_review/model/friend_review_repository_provider.dart';
import 'package:campus_mate/home/model/home_repository_provider.dart';
import 'package:campus_mate/home/view/home_screen.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:campus_mate/matching/view/acceptance_detail_screen.dart';
import 'package:campus_mate/matching/view/conversations_screen.dart';
import 'package:campus_mate/me/model/me_repository_provider.dart';
import 'package:campus_mate/me/model/my_profile.dart';
import 'package:campus_mate/me/view/avatar_regen_pick_screen.dart';
import 'package:campus_mate/me/view/basic_info_edit_screen.dart';
import 'package:campus_mate/me/view/card_preview_screen.dart';
import 'package:campus_mate/me/view/my_photos_screen.dart';
import 'package:campus_mate/me/view/my_profile_screen.dart';
import 'package:campus_mate/me/view/profile_edit_screen.dart';
import 'package:campus_mate/me/view/profile_manage_screen.dart';
import 'package:campus_mate/profile/model/onboarding_repository.dart';
import 'package:campus_mate/profile/model/onboarding_step.dart';
import 'package:campus_mate/profile/view/acquisition_screen.dart';
import 'package:campus_mate/profile/view/basic_info_screen.dart';
import 'package:campus_mate/profile/model/bio_repository_provider.dart';
import 'package:campus_mate/profile/model/ideal_note_repository_provider.dart';
import 'package:campus_mate/profile/model/survey_repository_provider.dart';
import 'package:campus_mate/profile/view/bio_screen.dart';
import 'package:campus_mate/profile/view/ideal_conditions_screen.dart';
import 'package:campus_mate/profile/view/ideal_note_screen.dart';
import 'package:campus_mate/profile/view/survey_screen.dart';
import 'package:campus_mate/profile/view/tag_picker_screen.dart';
import 'package:campus_mate/profile/viewmodel/tag_picker_kind.dart';
import 'package:campus_mate/referral/view/referral_code_screen.dart';
import 'package:campus_mate/safety/model/safety_repository_provider.dart';
import 'package:campus_mate/safety/view/block_list_screen.dart';
import 'package:campus_mate/safety/view/partner_profile_screen.dart';
import 'package:campus_mate/notifications/model/notifications_repository_provider.dart';
import 'package:campus_mate/notifications/view/notifications_screen.dart';
import 'package:flutter/cupertino.dart' show CupertinoRouteTransitionMixin;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../account/model/fake_account_repository.dart';
import '../../auth/model/fake_school_email_repository.dart';
import '../../auth/model/fake_social_login_repository.dart';
import '../../chat/model/fake_chat_repository.dart';
import '../../community/model/fake_community_repository.dart';
import '../../faq/model/fake_faq.dart';
import '../../friend_review/model/fake_friend_review_repository.dart';
import '../../home/model/fake_home_repository.dart';
import '../../matching/model/fake_card_repository.dart';
import '../../me/model/fake_me_repository.dart';
import '../../profile/model/fake_avatar_repository.dart';
import '../../profile/model/fake_basic_info_repository.dart';
import '../../profile/model/fake_kakao_id_repository.dart';
import '../../profile/model/fake_bio_repository.dart';
import '../../profile/model/fake_ideal_note_repository.dart';
import '../../profile/model/fake_onboarding_repository.dart';
import '../../profile/model/fake_survey_repository.dart';
import '../analytics/fake_analytics_service.dart';
import '../../safety/model/fake_safety_repository.dart';
import '../supabase/fake_auth_session.dart';
import '../../notifications/model/fake_notifications_repository.dart';

/// 이 파일은 경로·화면 연결만 본다. 게이트별 이동 규칙은 auth_redirect_test 가 맡는다.
VerificationGate _passedGate() => VerificationGate.complete;
OnboardingStep _passedStep() => OnboardingStep.complete;

/// 경로 id 칸에 넣는 값(지어낸 UUID). 라우터는 UUID 모양이 아닌 id 를 그 목록 · 홈으로 돌려보낸다.
const _matchId = '11111111-1111-4111-8111-111111111111';
const _profileId = '22222222-2222-4222-8222-222222222222';
const _cardId = '33333333-3333-4333-8333-333333333333';

/// 서버 next-step 이 늦게 오는 상황. [answer] 를 부를 때까지 답을 미룬다.
class _SlowOnboardingRepository implements OnboardingRepository {
  final _answer = Completer<Result<OnboardingStep>>();

  void answer(OnboardingStep step) => _answer.complete(Success(step));

  @override
  Future<Result<OnboardingStep>> fetchNextStep() => _answer.future;
}

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

/// 로그아웃 상태의 시작 화면이 읽는 세션 · 소셜 로그인 저장소를 가짜로 건다(실제 Supabase 없음).
Widget _guestScope(Widget child) {
  return ProviderScope(
    overrides: [
      authSessionListenableProvider.overrideWithValue(FakeAuthSession().listenable),
      socialLoginRepositoryProvider.overrideWithValue(FakeSocialLoginRepository()),
    ],
    child: child,
  );
}

void main() {
  testWidgets('스플래시를 붙잡는 동안에는 스플래시가 보인다', (tester) async {
    var isHeld = true;
    final router = AppRouter.create(
      isAuthenticated: () => false,
      verificationGate: _passedGate,
      onboardingStep: _passedStep,
      isSplashHeld: () => isHeld,
    );

    await tester.pumpWidget(_guestScope(MaterialApp.router(routerConfig: router, theme: AppTheme.light())));
    await tester.pumpAndSettle();

    expect(find.text('CampusMate'), findsOneWidget);

    // 시간이 다 되면(SplashHold 가 알림) 원래 이동 규칙으로 돌아간다 — 로그아웃 상태는 시작 화면에 그대로 머문다
    // (예전에는 02 학교 메일 입력 화면으로 갔다, 대장 지시문 07).
    isHeld = false;
    router.refresh();
    await tester.pumpAndSettle();

    expect(find.byType(StartView), findsOneWidget);
    expect(find.text('대학 이메일로 시작해요'), findsNothing);
  });

  testWidgets('로그인하지 않으면 소셜 로그인 버튼이 있는 시작 화면이 보인다', (tester) async {
    final router = AppRouter.create(
      isAuthenticated: () => false,
      verificationGate: _passedGate,
      onboardingStep: _passedStep,
    );

    await tester.pumpWidget(_guestScope(MaterialApp.router(routerConfig: router, theme: AppTheme.light())));
    await tester.pumpAndSettle();

    expect(find.byType(StartView), findsOneWidget);
    expect(find.text('카카오 로그인').hitTestable(), findsOneWidget);
    expect(find.text('Google 계정으로 로그인').hitTestable(), findsOneWidget);
  });

  // main.dart 는 관문과 온보딩 단계를 동시에 묻는다. 관문이 먼저 오면 예전에는 온보딩을 마친 사람에게
  // 04-1 이 몇 초 보였다가 홈으로 갔다 — 단계를 알기 전에는 스플래시에 머물러야 한다.
  testWidgets('관문이 먼저 통과돼도 온보딩 단계를 알기 전에는 04-1 을 띄우지 않고, 알면 홈으로 간다', (tester) async {
    final steps = _SlowOnboardingRepository();
    final stepCache = OnboardingStepListenable(steps);
    addTearDown(stepCache.dispose);
    final router = AppRouter.create(
      isAuthenticated: () => true,
      verificationGate: _passedGate,
      onboardingStep: () => stepCache.value,
      refreshListenable: stepCache,
    );
    addTearDown(router.dispose);
    final visited = <String>[];
    router.routerDelegate.addListener(() => visited.add(router.state.matchedLocation));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionListenableProvider.overrideWithValue(FakeAuthSession(signedIn: true).listenable),
          socialLoginRepositoryProvider.overrideWithValue(FakeSocialLoginRepository()),
          cardRepositoryProvider.overrideWithValue(FakeCardRepository()),
          chatRepositoryProvider.overrideWithValue(FakeChatRepository()),
          homeRepositoryProvider.overrideWithValue(FakeHomeRepository(const FailureResult(NetworkFailure()))),
          notificationsRepositoryProvider.overrideWithValue(FakeNotificationsRepository()),
        ],
        child: MaterialApp.router(routerConfig: router, theme: AppTheme.light()),
      ),
    );
    unawaited(stepCache.refresh());
    await tester.pumpAndSettle();

    expect(find.byType(StartView), findsOneWidget);
    expect(find.byType(BasicInfoScreen), findsNothing);

    steps.answer(OnboardingStep.complete);
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(visited, isNot(contains(AppRoutes.onboardingBasicInfo)));
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
          notificationsRepositoryProvider.overrideWithValue(FakeNotificationsRepository()),
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
          notificationsRepositoryProvider.overrideWithValue(FakeNotificationsRepository()),
        ],
        child: MaterialApp.router(routerConfig: router, theme: AppTheme.light()),
      ),
    );
    router.go(AppRoutes.myProfile);
    await tester.pumpAndSettle();

    expect(find.byType(MyProfileScreen), findsOneWidget);
  });

  // 예전에는 "extra 없이 인증코드 화면에 진입하면 로그인 화면으로" 를 봤다. 이제 로그아웃 상태는 인증코드 화면에
  // 닿기 전에 AuthRedirect 가 시작 화면으로 돌려보낸다(옛 경로는 지시문 08 까지 남아 있다).
  testWidgets('로그아웃 상태로 옛 인증코드 · 로그인 화면에 가도 시작 화면으로 보낸다', (tester) async {
    final router = AppRouter.create(
      isAuthenticated: () => false,
      verificationGate: _passedGate,
      onboardingStep: _passedStep,
    );
    await tester.pumpWidget(_guestScope(MaterialApp.router(routerConfig: router, theme: AppTheme.light())));

    for (final path in [AppRoutes.verifyCode, AppRoutes.login]) {
      router.go(path);
      await tester.pumpAndSettle();

      expect(find.byType(StartView), findsOneWidget, reason: path);
      expect(find.text('대학 이메일로 시작해요'), findsNothing, reason: path);
    }
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
          notificationsRepositoryProvider.overrideWithValue(FakeNotificationsRepository()),
        ],
        child: MaterialApp.router(routerConfig: router, theme: AppTheme.light()),
      ),
    );
    router.go('${AppRoutes.chatRoom}/$_matchId');
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
          notificationsRepositoryProvider.overrideWithValue(FakeNotificationsRepository()),
        ],
        child: MaterialApp.router(routerConfig: router, theme: AppTheme.light()),
      ),
    );
    router.go('${AppRoutes.chatRoom}/$_matchId');
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
          // 10b 가 열리면 카드를 읽는다 — 화면이 뜨는지만 보므로 실패로 둔다.
          cardRepositoryProvider.overrideWithValue(FakeCardRepository()..card = const FailureResult(NetworkFailure())),
          homeRepositoryProvider.overrideWithValue(FakeHomeRepository(const FailureResult(NetworkFailure()))),
          notificationsRepositoryProvider.overrideWithValue(FakeNotificationsRepository()),
          // id 를 고쳐 쓴 주소가 열리는지 보는 시험이 커뮤니티 탭으로 돌아간다.
          communityRepositoryProvider.overrideWithValue(FakeCommunityRepository()),
          chatRepositoryProvider.overrideWithValue(FakeChatRepository()
            ..room = Success(roomFixture(passed: passedRoom, kakaoId: 'fox_rain', partnerProfileId: _profileId))),
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

    testWidgets('/me/avatar-regen 은 15b-4 아바타 다시 만들기 · 사진 고르기다', (tester) async {
      final router = await pumpRouter(tester);

      router.go(AppRoutes.myAvatarRegen);
      await tester.pumpAndSettle();

      expect(find.byType(AvatarRegenPickScreen), findsOneWidget);
    });

    testWidgets('/hearts/store 는 18 하트 스토어다', (tester) async {
      final router = await pumpRouter(tester);

      router.go(AppRoutes.heartStore);
      await tester.pumpAndSettle();

      expect(find.byType(HeartStoreScreen), findsOneWidget);
    });

    testWidgets('/events 는 9b-1 이벤트(출시 예정)다', (tester) async {
      final router = await pumpRouter(tester);

      router.go(AppRoutes.events);
      await tester.pumpAndSettle();

      expect(find.byType(EventComingScreen), findsOneWidget);
    });

    testWidgets('/notifications 는 09c 홈 종 알림함이다', (tester) async {
      final router = await pumpRouter(tester);

      router.go(AppRoutes.notifications);
      await tester.pumpAndSettle();

      expect(find.byType(NotificationsScreen), findsOneWidget);
      expect(find.text('아직 받은 알림이 없어요'), findsOneWidget);
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

    testWidgets('/friend-reviews/code 는 20f 친구 코드로 리뷰 쓰기다', (tester) async {
      final router = await pumpRouter(tester);

      router.go(AppRoutes.friendReviewCode);
      await tester.pumpAndSettle();

      expect(find.byType(FriendCodeScreen), findsOneWidget);
    });

    // 추천 가입 푸시(`friend_review_write`)가 가는 곳 — 홈이 밑에 깔리고 그 위에 20b 시트(대장 Q1).
    testWidgets('/home/friend-reviews/write/:profileId 는 09b 홈 위에 20b 시트를 띄우고, 닫으면 홈이다', (tester) async {
      final router = await pumpRouter(tester);

      router.go('${AppRoutes.friendReviewWrite}/$_profileId');
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

    testWidgets('/acceptances/:cardId 는 그 받은 신청의 프로필 보기(pen `o4QqYR`)다', (tester) async {
      final router = await pumpRouter(tester);

      router.go('${AppRoutes.acceptanceDetail}/$_cardId');
      await tester.pumpAndSettle();

      expect(tester.widget<AcceptanceDetailScreen>(find.byType(AcceptanceDetailScreen)).cardId, _cardId);
    });

    testWidgets('/profiles/:profileId 는 그 사람의 14c 상대 프로필이다', (tester) async {
      final router = await pumpRouter(tester);

      router.go('${AppRoutes.partnerProfile}/$_profileId');
      await tester.pumpAndSettle();

      expect(tester.widget<PartnerProfileScreen>(find.byType(PartnerProfileScreen)).profileId, _profileId);
    });

    // 2026-10-18 보안 검사: 경로 id 는 전부 DB uuid 다(matches · daily_cards · profiles · polls). 모양이 아니면 화면을 열지 않고
    // 그 목록 · 홈으로 돌려보낸다 — 푸시 `match_id` · 바깥에서 만든 주소의 엉뚱한 값이 화면을 거쳐 서버 경로에 실리지 않는다.
    for (final (path, fallback) in <(String, String)>[
      ('${AppRoutes.chatRoom}/m1', AppRoutes.conversations),
      ('${AppRoutes.cardDetail}/card-1', AppRoutes.today),
      ('${AppRoutes.acceptanceDetail}/card-7', AppRoutes.conversations),
      ('${AppRoutes.partnerProfile}/p2', AppRoutes.home),
      ('${AppRoutes.partnerProfile}/${_profileId}x', AppRoutes.home),
      ('${AppRoutes.communityPoll}/p1', AppRoutes.community),
      ('${AppRoutes.friendReviewWrite}/p2', AppRoutes.home),
    ]) {
      testWidgets('UUID 가 아닌 id 의 $path 는 $fallback 로 보낸다', (tester) async {
        final router = await pumpRouter(tester);

        router.go(path);
        await tester.pumpAndSettle();

        expect(router.state.matchedLocation, fallback);
      });
    }

    for (final path in [
      '${AppRoutes.cardDetail}/$_cardId',
      '${AppRoutes.communityPoll}/${_cardId.toUpperCase()}',
    ]) {
      testWidgets('UUID id 의 $path 는 그대로 연다', (tester) async {
        final router = await pumpRouter(tester);

        router.go(path);
        await tester.pumpAndSettle();

        expect(router.state.matchedLocation, path);
      });
    }

    // 경로가 없을 때는 14b 버튼이 go_router 오류 화면으로 떨어졌다.
    testWidgets('채팅방 14b "상대 프로필 보기" 를 누르면 14c 가 열리고, 뒤로가면 방으로 돌아온다', (tester) async {
      final router = await pumpRouter(tester, passedRoom: true);
      router.go('${AppRoutes.chatRoom}/$_matchId');
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

  // 화면 추적(Firebase Analytics screen_view) — 화면 이름은 페이지 이름에 실린 경로 패턴이다.
  testWidgets('화면 추적기는 경로 패턴 이름만 받는다 — 채팅방 id 가 이름에 섞이지 않는다', (tester) async {
    final analytics = FakeAnalyticsService();
    final router = AppRouter.create(
      isAuthenticated: () => true,
      verificationGate: _passedGate,
      onboardingStep: _passedStep,
      observers: [ScreenViewObserver(analytics)],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cardRepositoryProvider.overrideWithValue(FakeCardRepository()),
          chatRepositoryProvider.overrideWithValue(FakeChatRepository()..room = Success(roomFixture())),
          messageStreamProvider.overrideWithValue(FakeMessageStream()),
          homeRepositoryProvider.overrideWithValue(FakeHomeRepository(const FailureResult(NetworkFailure()))),
          notificationsRepositoryProvider.overrideWithValue(FakeNotificationsRepository()),
        ],
        child: MaterialApp.router(routerConfig: router, theme: AppTheme.light()),
      ),
    );
    await tester.pumpAndSettle();
    router.go('${AppRoutes.chatRoom}/$_matchId');
    await tester.pumpAndSettle();

    expect(analytics.calls, contains('screen:${AppRoutes.home}'));
    expect(analytics.calls, contains('screen:${AppRoutes.chatRoom}/:matchId'));
    expect(analytics.calls.where((call) => call.contains(_matchId)), isEmpty);
    // 채팅방이 dispose 에서 목록을 다시 읽는다 — provider 가 아직 살아 있을 때 채팅방을 떠난다.
    router.go(AppRoutes.conversations);
    await tester.pumpAndSettle();
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
            notificationsRepositoryProvider.overrideWithValue(FakeNotificationsRepository()),
            meRepositoryProvider.overrideWithValue(FakeMeRepository(const Success(_meProfile))),
            // 15-4 가 카드 안 지인 리뷰로 내가 받은 리뷰를 읽는다.
            friendReviewRepositoryProvider.overrideWithValue(FakeFriendReviewRepository()),
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
    testWidgets('/me/photos 는 15-7 사진 수정이다', (tester) async {
      final router = await pumpRouter(tester);

      router.go(AppRoutes.myPhotos);
      await tester.pumpAndSettle();

      expect(find.byType(MyPhotosScreen), findsOneWidget);
    });

    // 15-5 "수정 ›"(`A8LX2`)이 여는 화면(계획서 2026-09-28-me-profile.md A16).
    testWidgets('/me/basic-info 는 15-6 기본 정보 수정이다', (tester) async {
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

  test('06-3 뒤 앱에서만 잇는 20 · 20d · 06-4 경로도 라우터에 등록돼 있다', () {
    final router = AppRouter.create(
      isAuthenticated: () => true,
      verificationGate: _passedGate,
      onboardingStep: _passedStep,
    );
    final registered = router.configuration.routes.whereType<GoRoute>().map((route) => route.path);

    expect(
      registered,
      containsAll(<String>[
        AppRoutes.onboardingReferral,
        AppRoutes.onboardingAcquisition,
        AppRoutes.onboardingContactBlock,
        AppRoutes.onboardingContactPicker,
      ]),
    );
  });

  // 안드로이드에서 하단 내비 탭(최상위 화면)의 시스템 뒤로가기는 앱이 닫히려는 순간뿐이다 — 거기서만 한 번 더 확인한다.
  group('최상위 탭의 뒤로가기 확인', () {
    late int exitCalls;
    late FakeSchoolEmailRepository schoolEmail;

    Future<GoRouter> pumpMember(
      WidgetTester tester, {
      OnboardingStep step = OnboardingStep.complete,
      VerificationGate gate = VerificationGate.complete,
    }) async {
      exitCalls = 0;
      schoolEmail = FakeSchoolEmailRepository();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'SystemNavigator.pop') exitCalls++;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      final router = AppRouter.create(
        isAuthenticated: () => true,
        verificationGate: () => gate,
        onboardingStep: () => step,
      );
      addTearDown(router.dispose);
      final container = ProviderContainer(
        overrides: [
          // 03 뒤로가기가 임시 연결을 비운다.
          schoolEmailRepositoryProvider.overrideWithValue(schoolEmail),
          // 온보딩 화면 뷰모델이 "다시 보는 중" 인지 단계 캐시에 묻는다(라우터 단계는 위 고정값).
          onboardingRepositoryProvider.overrideWithValue(FakeOnboardingRepository()),
          // 3c 관문 화면이 읽는 학교명 · 로고(지어낸 값, 로고 없음).
          schoolNameProvider.overrideWithValue(const AsyncData('가나대학교')),
          universityLogosProvider.overrideWith((ref) => const <String, String>{}),
          cardRepositoryProvider.overrideWithValue(FakeCardRepository()),
          chatRepositoryProvider.overrideWithValue(FakeChatRepository()),
          communityRepositoryProvider.overrideWithValue(FakeCommunityRepository()),
          homeRepositoryProvider.overrideWithValue(FakeHomeRepository(const FailureResult(NetworkFailure()))),
          meRepositoryProvider.overrideWithValue(FakeMeRepository(const FailureResult(NetworkFailure()))),
          // 아바타 확인 화면(06-3 뒤)은 완성으로 둔다 — 만드는 중이면 도는 표시 때문에 화면이 멈추지 않는다.
          avatarRepositoryProvider.overrideWithValue(
            FakeAvatarRepository()..nextResult = const Success(AvatarReady('https://example.com/avatar.png')),
          ),
          notificationsRepositoryProvider.overrideWithValue(FakeNotificationsRepository()),
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
      await tester.pumpAndSettle();
      return router;
    }

    const tabs = <(String, String)>[
      (AppRoutes.home, '메인'),
      (AppRoutes.today, '오늘'),
      (AppRoutes.community, '커뮤니티'),
      (AppRoutes.conversations, '대화'),
      (AppRoutes.myProfile, '나'),
    ];
    for (final (path, name) in tabs) {
      testWidgets('$name 탭: 첫 뒤로가기는 안내만, 한 번 더 누르면 앱을 닫는다', (tester) async {
        final router = await pumpMember(tester);
        router.go(path);
        await tester.pumpAndSettle();

        await tester.binding.handlePopRoute();
        await tester.pump();

        expect(find.text(backExitMessage), findsOneWidget);
        expect(exitCalls, 0);

        await tester.binding.handlePopRoute();
        await tester.pump();

        expect(exitCalls, 1);
      });
    }

    testWidgets('탭 위에 열린 화면에서는 한 단계만 뒤로 가고 안내는 뜨지 않는다', (tester) async {
      final router = await pumpMember(tester);
      unawaited(router.push(AppRoutes.faq));
      await tester.pumpAndSettle();
      expect(find.byType(FaqScreen), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text(backExitMessage), findsNothing);
      expect(exitCalls, 0);
    });

    testWidgets('다른 화면 위에 push 로 올라온 탭에서는 안내 없이 그 화면으로 돌아간다', (tester) async {
      final router = await pumpMember(tester);
      unawaited(router.push(AppRoutes.faq));
      await tester.pumpAndSettle();
      unawaited(router.push(AppRoutes.today));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(FaqScreen), findsOneWidget);
      expect(find.text(backExitMessage), findsNothing);
      expect(exitCalls, 0);
    });

    // 10-15 사용자 지적: 온보딩 · 관문도 go 로만 들어와 맨 아래 한 장이라 시스템 뒤로가기가 곧바로 앱을 닫았다.
    // 탭과 같이 한 번 더 확인한다(종전 "온보딩 도중의 뒤로가기는 건드리지 않는다" 를 뒤집었다). 약관(02-c)은 종전대로 막아 둔다.
    Future<void> expectHintThenExit(WidgetTester tester) async {
      expect(find.byType(BackExitScope), findsOneWidget, reason: '두 겹이면 같은 뒤로가기에 둘 다 불린다');
      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(find.text(backExitMessage), findsOneWidget);
      expect(exitCalls, 0);

      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(exitCalls, 1);
    }

    // 04-1 · 04-4 는 뒤로가 없다(사용자 결정 ⑦ · ①).
    // 04-1b 와 설문 첫 문항은 이제 앞 단계로 간다 — 아래 '온보딩 뒤로가기' 묶음이 본다(종전엔 이 줄에 kakaoId · survey 가 있었다).
    // 아바타 확인(리빌 · 05-12)은 가입 맨 끝이라 뒤로가 없다(10-17, 결정 G4 추천안) — 시스템 뒤로는 종료 안내다.
    for (final step in [
      OnboardingStep.basicInfo,
      OnboardingStep.appearanceType,
      OnboardingStep.avatar,
    ]) {
      testWidgets('온보딩(${step.name})에서도 첫 뒤로가기는 안내만, 한 번 더 누르면 앱을 닫는다', (tester) async {
        await pumpMember(tester, step: step);
        expect(find.byTooltip(onboardingBackLabel), findsNothing, reason: '뒤로 갈 앞 화면이 없다');

        await expectHintThenExit(tester);
      });
    }

    group('온보딩 뒤로가기(조각 0~4)', () {
      late FakeOnboardingRepository onboarding;
      late FakeSurveyRepository survey;
      late FakeBioRepository bio;
      late OnboardingStepListenable steps;

      /// 화면들이 부르는 것과 같은 단계 캐시를 라우터에 건다(main.dart 와 같은 연결).
      Future<GoRouter> pumpOnboarding(WidgetTester tester, OnboardingStep server, {Completer<void>? holdDraft}) async {
        exitCalls = 0;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'SystemNavigator.pop') exitCalls++;
          return null;
        });
        addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
        onboarding = FakeOnboardingRepository()..nextResult = Success(server);
        survey = FakeSurveyRepository();
        bio = FakeBioRepository()..holdDraft = holdDraft;
        final container = ProviderContainer(
          overrides: [
            onboardingRepositoryProvider.overrideWithValue(onboarding),
            surveyRepositoryProvider.overrideWithValue(survey),
            bioRepositoryProvider.overrideWithValue(bio),
            idealNoteRepositoryProvider.overrideWithValue(FakeIdealNoteRepository()),
            // 06-3 저장 뒤 아바타 확인 화면 — 완성으로 둔다(만드는 중이면 도는 표시 때문에 화면이 멈추지 않는다).
            avatarRepositoryProvider.overrideWithValue(
              FakeAvatarRepository()..nextResult = const Success(AvatarReady('https://example.com/avatar.png')),
            ),
            meRepositoryProvider.overrideWithValue(FakeMeRepository(const Success(savedOnboardingProfile))),
            accountRepositoryProvider.overrideWithValue(FakeAccountRepository()),
            basicInfoRepositoryProvider.overrideWithValue(FakeBasicInfoRepository()),
            basicInfoNowProvider.overrideWithValue(() => DateTime(2026, 6, 1)),
            kakaoIdRepositoryProvider.overrideWithValue(FakeKakaoIdRepository()),
          ],
        );
        addTearDown(container.dispose);
        steps = container.read(onboardingStepListenableProvider);
        await steps.refresh();
        final router = AppRouter.create(
          isAuthenticated: () => true,
          verificationGate: () => VerificationGate.complete,
          onboardingStep: () => steps.value,
          refreshListenable: steps,
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp.router(routerConfig: router, theme: AppTheme.light()),
          ),
        );
        await tester.pumpAndSettle();
        return router;
      }

      Finder backArrow() => find.byTooltip(onboardingBackLabel);

      testWidgets('04-1b 의 시스템 뒤로는 04-1 로 가고 종료 안내는 뜨지 않는다', (tester) async {
        await pumpOnboarding(tester, OnboardingStep.kakaoId);
        expect(find.byType(KakaoIdScreen), findsOneWidget);
        expect(find.byType(BackExitScope), findsOneWidget, reason: '두 겹이면 같은 뒤로가기에 둘 다 불린다');

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(find.byType(BasicInfoScreen), findsOneWidget);
        expect(find.text(backExitMessage), findsNothing);
        expect(exitCalls, 0);
      });

      testWidgets('04-2 의 시스템 뒤로는 04-1b 로 가고 종료 안내는 뜨지 않는다', (tester) async {
        await pumpOnboarding(tester, OnboardingStep.photos);
        expect(find.byType(BackExitScope), findsOneWidget, reason: '두 겹이면 같은 뒤로가기에 둘 다 불린다');

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(find.byType(KakaoIdScreen), findsOneWidget);
        expect(find.text(backExitMessage), findsNothing);
      });

      testWidgets('04-1b 앱바 뒤로 → 04-1 이 서버 값으로 채워지고, 전화번호를 넣어 다시 저장하면 04-1b 로 돌아온다', (tester) async {
        await pumpOnboarding(tester, OnboardingStep.kakaoId);

        await tester.tap(backArrow());
        await tester.pumpAndSettle();

        expect(find.byType(BasicInfoScreen), findsOneWidget);
        expect(backArrow(), findsNothing, reason: '04-1 앞은 관문이라 화살표가 없다(사용자 결정 ⑦)');
        expect(find.text('여우비'), findsOneWidget);
        expect(find.text('2002'), findsOneWidget);
        expect(find.text('172'), findsOneWidget);

        final phone = find.descendant(
          of: find.widgetWithText(LabeledField, '전화번호 · 필수'),
          matching: find.byType(TextField),
        );
        await tester.ensureVisible(phone);
        await tester.enterText(phone, '01001352468');
        await tester.pump(const Duration(milliseconds: 350));
        await tester.tap(find.text('다음'));
        await tester.pumpAndSettle();

        expect(find.byType(KakaoIdScreen), findsOneWidget);
        expect(steps.isRevisiting, isFalse);
      });

      // 앞으로 건너뛰기 금지: 다시 보는 중에는 서버 단계(가장 멀리 간 곳)로도 바로 갈 수 없다.
      testWidgets('다시 보는 중에는 주소로 앞 화면에 가려 해도 다시 보는 화면에 묶인다', (tester) async {
        final router = await pumpOnboarding(tester, OnboardingStep.photos);
        steps
          ..goBack()
          ..goBack();
        await tester.pumpAndSettle();
        expect(find.byType(BasicInfoScreen), findsOneWidget);

        for (final ahead in [AppRoutes.onboardingKakaoId, AppRoutes.onboardingPhotos, AppRoutes.onboardingInterests]) {
          router.go(ahead);
          await tester.pumpAndSettle();

          expect(find.byType(BasicInfoScreen), findsOneWidget, reason: ahead);
        }
      });

      // 사진 경계(사용자 결정 ①): 04-5 에서 돌아온 04-4 에는 화살표가 없고 시스템 뒤로는 종료 안내다.
      testWidgets('04-5 시스템 뒤로 → 04-4: 얼굴상 · 인상이 채워져 있고, 화살표 없이 시스템 뒤로는 안내다', (tester) async {
        await pumpOnboarding(tester, OnboardingStep.interests);
        expect(find.byType(BackExitScope), findsOneWidget, reason: '두 겹이면 같은 뒤로가기에 둘 다 불린다');

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(find.byType(AppearanceTypeScreen), findsOneWidget);
        expect(find.text(backExitMessage), findsNothing);
        expect(backArrow(), findsNothing);
        expect(steps.isRevisiting, isTrue);
        expect(tester.widget<AnimalTypePicker>(find.byType(AnimalTypePicker)).selected, {AnimalType.fox});
        expect(tester.widget<ImpressionTypePicker>(find.byType(ImpressionTypePicker)).selected, {ImpressionType.innocent});

        await tester.binding.handlePopRoute();
        await tester.pump();
        expect(find.text(backExitMessage), findsOneWidget);
        expect(find.byType(AppearanceTypeScreen), findsOneWidget);
      });

      testWidgets('06-2 시스템 뒤로 → 06-1 은 이상형 조건이 채워져 있다', (tester) async {
        await pumpOnboarding(tester, OnboardingStep.idealTraits);
        expect(find.byType(BackExitScope), findsOneWidget, reason: '두 겹이면 같은 뒤로가기에 둘 다 불린다');

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(find.byType(IdealConditionsScreen), findsOneWidget);
        expect(find.text(backExitMessage), findsNothing);
        expect(find.text('24세 ~ 30세'), findsOneWidget);
      });

      // 06-1 화살표를 미룬 이유(조각 0~2 편차 2)가 풀렸는지: 서버 답으로 채워 흡연 문항에서 열고, "다음" 한 번은 같은 답을 보낸다.
      testWidgets('06-1 시스템 뒤로 → 설문 흡연 문항에서 열리고, "다음" 한 번이면 같은 답을 다시 저장하고 06-1 로 돌아온다', (tester) async {
        await pumpOnboarding(tester, OnboardingStep.idealConditions);
        expect(find.byType(BackExitScope), findsOneWidget, reason: '두 겹이면 같은 뒤로가기에 둘 다 불린다');
        expect(backArrow(), findsOneWidget);

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(find.byType(SurveyScreen), findsOneWidget);
        expect(find.text('담배를 피우시나요?'), findsOneWidget);
        expect(find.text(backExitMessage), findsNothing);
        expect(exitCalls, 0);

        await tester.tap(find.text('다음'));
        await tester.pumpAndSettle();

        expect(survey.submittedAnswers, savedOnboardingProfile.surveyAnswers);
        expect(find.byType(IdealConditionsScreen), findsOneWidget);
        expect(steps.isRevisiting, isFalse);
      });

      // 계획서 조각 3(269-270줄): 설문 첫 문항의 앱바 · 시스템 뒤로 → 04-6, 종료 안내 없음.
      testWidgets('설문 첫 문항의 시스템 뒤로 → 04-6, 저장해 둔 특징 칩이 켜져 있고 안내는 뜨지 않는다', (tester) async {
        await pumpOnboarding(tester, OnboardingStep.survey);
        expect(find.text('밖에 나가서 활동하는 걸\n좋아하시나요?'), findsOneWidget);
        expect(find.byType(BackExitScope), findsOneWidget, reason: '두 겹이면 같은 뒤로가기에 둘 다 불린다');

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(tester.widget<TagPickerScreen>(find.byType(TagPickerScreen)).kind, TagPickerKind.myTraits);
        expect(find.text(backExitMessage), findsNothing);
        expect(exitCalls, 0);
        final picked = tester.widgetList<SelectChip>(find.byType(SelectChip)).where((chip) => chip.isSelected);
        expect([for (final chip in picked) chip.label], unorderedEquals(savedOnboardingProfile.myTraits));
      });

      testWidgets('설문 첫 문항의 앱바 뒤로를 읽는 중에 두 번 눌러도 04-6 까지 한 단계만 간다', (tester) async {
        await pumpOnboarding(tester, OnboardingStep.survey);

        await tester.tap(backArrow());
        await tester.tap(backArrow());
        await tester.pumpAndSettle();

        expect(steps.value, OnboardingStep.myTraits);
        expect(tester.widget<TagPickerScreen>(find.byType(TagPickerScreen)).kind, TagPickerKind.myTraits);
      });

      testWidgets('06-1 앱바 뒤로를 읽는 중에 두 번 눌러도 설문까지 한 단계만 간다', (tester) async {
        await pumpOnboarding(tester, OnboardingStep.idealConditions);

        await tester.tap(backArrow());
        await tester.tap(backArrow());
        await tester.pumpAndSettle();

        expect(steps.value, OnboardingStep.survey);
        expect(find.byType(SurveyScreen), findsOneWidget);
      });

      String fieldText(WidgetTester tester) => tester.widget<TextField>(find.byType(TextField)).controller!.text;

      testWidgets('06-2a 시스템 뒤로 → 06-2 는 이상형 특징 칩이 켜져 있다', (tester) async {
        await pumpOnboarding(tester, OnboardingStep.idealNote);
        expect(find.byType(BackExitScope), findsOneWidget, reason: '두 겹이면 같은 뒤로가기에 둘 다 불린다');

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(tester.widget<TagPickerScreen>(find.byType(TagPickerScreen)).kind, TagPickerKind.idealTraits);
        expect(find.text(backExitMessage), findsNothing);
        expect(exitCalls, 0);
        final picked = tester.widgetList<SelectChip>(find.byType(SelectChip)).where((chip) => chip.isSelected);
        expect([for (final chip in picked) chip.label], unorderedEquals(savedOnboardingProfile.idealTraits));
      });

      testWidgets('06-2b(초안 만드는 중) 앱바 뒤로 → 06-2a 는 저장해 둔 이상형 글이 채워져 있다', (tester) async {
        await pumpOnboarding(tester, OnboardingStep.bio, holdDraft: Completer<void>());
        expect(find.text('설문을 읽고 있어요'), findsOneWidget);
        expect(find.byType(BackExitScope), findsOneWidget, reason: '두 겹이면 같은 뒤로가기에 둘 다 불린다');

        await tester.tap(backArrow());
        await tester.pumpAndSettle();

        expect(find.byType(IdealNoteScreen), findsOneWidget);
        expect(fieldText(tester), savedOnboardingProfile.idealNote);
        bio.holdDraft!.complete();
        await tester.pumpAndSettle();
      });

      testWidgets('06-3 시스템 뒤로 → 06-2a, 다시 저장하면 06-3 으로 돌아오고 쓰던 글이 그대로다', (tester) async {
        await pumpOnboarding(tester, OnboardingStep.bio);
        expect(find.byType(BioScreen), findsOneWidget);
        expect(find.byType(BackExitScope), findsOneWidget, reason: '두 겹이면 같은 뒤로가기에 둘 다 불린다');
        await tester.enterText(find.byType(TextField), '고쳐 쓰던 자기소개예요');
        await tester.pump();

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(find.byType(IdealNoteScreen), findsOneWidget);
        expect(find.text(backExitMessage), findsNothing);
        expect(fieldText(tester), savedOnboardingProfile.idealNote);

        await tester.tap(find.text('다음'));
        await tester.pumpAndSettle();

        expect(find.byType(BioScreen), findsOneWidget);
        expect(fieldText(tester), '고쳐 쓰던 자기소개예요');
        expect(bio.draftCount, 1, reason: '초안은 한 번만 만든다(결정 ⑨)');
        expect(steps.isRevisiting, isFalse);
      });

      // 06-3 저장 순간 가입이 끝날 수 있다(위험 8). 아바타 화면으로 옮기기 전 틈에 뒤로를 누르면 가입을 마친 채 06-2a 에 묶인다.
      // 서버 단계 조회를 bio 로 붙잡아 그 틈을 늘린다.
      testWidgets('06-3 저장이 끝난 뒤에는 뒤로를 눌러도 06-2a 로 가지 않는다', (tester) async {
        await pumpOnboarding(tester, OnboardingStep.bio);
        onboarding.holdFetch = Completer<void>();

        await tester.tap(find.text('다음'));
        await tester.pump();
        expect(bio.submittedBio, isNotNull);
        await tester.binding.handlePopRoute();
        await tester.pump();
        onboarding.nextResult = const Success(OnboardingStep.complete);
        onboarding.holdFetch!.complete();
        await tester.pumpAndSettle();

        expect(find.byType(IdealNoteScreen), findsNothing);
        expect(steps.isRevisiting, isFalse);
      });

      testWidgets('04-6 시스템 뒤로 → 04-5 는 저장해 둔 관심사 칩이 켜져 있다', (tester) async {
        await pumpOnboarding(tester, OnboardingStep.myTraits);
        expect(find.byType(BackExitScope), findsOneWidget, reason: '두 겹이면 같은 뒤로가기에 둘 다 불린다');

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        final screen = tester.widget<TagPickerScreen>(find.byType(TagPickerScreen));
        expect(screen.kind, TagPickerKind.interests);
        final picked = tester.widgetList<SelectChip>(find.byType(SelectChip)).where((chip) => chip.isSelected);
        expect([for (final chip in picked) chip.label], unorderedEquals(['카페가기', '전시회관람', '등산']));
      });

      // 04-2 가 스스로 BackExitScope 를 둘러도 위에 push 로 올라온 04-3 이 먼저 닫힌다 — 04-1b 로 튀지 않는다.
      testWidgets('04-2 위에 올라온 04-3 의 시스템 뒤로는 04-2 로 한 장만 돌아간다', (tester) async {
        final router = await pumpOnboarding(tester, OnboardingStep.photos);
        unawaited(router.push(AppRoutes.onboardingAvatarSource));
        await tester.pumpAndSettle();

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(find.byType(PhotosScreen), findsOneWidget);
        expect(steps.value, OnboardingStep.photos);
        expect(steps.isRevisiting, isFalse);
      });

      testWidgets('토큰 갱신처럼 단계를 다시 물어도 다시 보는 화면에 그대로 있다', (tester) async {
        await pumpOnboarding(tester, OnboardingStep.photos);
        steps.goBack();
        await tester.pumpAndSettle();

        await steps.refresh();
        await tester.pumpAndSettle();

        expect(find.byType(KakaoIdScreen), findsOneWidget);
      });
    });

    testWidgets('20 추천 코드에서도 첫 뒤로가기는 안내만, 한 번 더 누르면 앱을 닫는다', (tester) async {
      final router = await pumpMember(tester);
      router.go(AppRoutes.onboardingReferral);
      await tester.pumpAndSettle();
      expect(find.byType(ReferralCodeScreen), findsOneWidget);
      // 06-3 저장 순간 가입이 끝난다 — 20 → 06-3 뒤로는 없다(사용자 결정 ⑥).
      expect(find.byTooltip(onboardingBackLabel), findsNothing);

      await expectHintThenExit(tester);
    });

    testWidgets('3c 관문에서도 첫 뒤로가기는 안내만, 한 번 더 누르면 앱을 닫는다', (tester) async {
      await pumpMember(tester, gate: VerificationGate.needsSchoolInfo);

      await expectHintThenExit(tester);
    });

    testWidgets('설문 둘째 문항의 시스템 뒤로가기는 첫 문항으로 가고 안내는 뜨지 않는다', (tester) async {
      await pumpMember(tester, step: OnboardingStep.survey);
      await tester.tap(find.text('다음'));
      await tester.pumpAndSettle();
      expect(find.text('낯선 사람과 빨리\n친해지는 편인가요?'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('밖에 나가서 활동하는 걸\n좋아하시나요?'), findsOneWidget);
      expect(find.text(backExitMessage), findsNothing);
      expect(exitCalls, 0);
    });

    testWidgets('20d 의 시스템 뒤로가기는 앱바 화살표처럼 20 으로 간다', (tester) async {
      final router = await pumpMember(tester);
      router.go(AppRoutes.onboardingAcquisition);
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(ReferralCodeScreen), findsOneWidget);
      expect(find.text(backExitMessage), findsNothing);
      expect(exitCalls, 0);
    });

    testWidgets('06-4 의 시스템 뒤로가기는 앱바 화살표처럼 20d 로 간다', (tester) async {
      final router = await pumpMember(tester);
      router.go(AppRoutes.onboardingContactBlock);
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(AcquisitionScreen), findsOneWidget);
      expect(find.text(backExitMessage), findsNothing);
      expect(exitCalls, 0);
    });

    // 사용자 10-16 — 03 은 앱바 뒤로가 생겼다. 화면이 스스로 BackExitScope(onBack) 를 둘러 라우터 쪽 한 겹을 뺐다.
    testWidgets('03 인증코드의 시스템 뒤로가기는 앱바 화살표처럼 임시 연결을 비우고 02 로 간다 · 안내 없음 · 한 겹', (tester) async {
      final router = await pumpMember(tester, gate: VerificationGate.needsSchoolEmail);
      router.go(AppRoutes.verifyCode, extra: UniversityEmail.tryParse('hong@snu.ac.kr'));
      // 03 은 만료 타이머가 1초마다 다시 그려 pumpAndSettle 이 끝나지 않는다 — 전환 시간만큼 민다.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(VerifyCodeScreen), findsOneWidget);
      expect(find.byType(BackExitScope), findsOneWidget, reason: '두 겹이면 같은 뒤로가기에 둘 다 불린다');

      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(schoolEmail.calls, ['discard']);
      expect(find.byType(SignUpScreen), findsOneWidget);
      expect(find.byType(VerifyCodeScreen), findsNothing);
      expect(find.text(backExitMessage), findsNothing);
      expect(exitCalls, 0);
    });

    testWidgets('메일(extra) 없이 03 으로 가면 02 로 돌려보낸다(_verifyCodeGuard)', (tester) async {
      final router = await pumpMember(tester, gate: VerificationGate.needsSchoolEmail);
      router.go(AppRoutes.verifyCode);
      await tester.pumpAndSettle();

      expect(find.byType(SignUpScreen), findsOneWidget);
      expect(find.byType(VerifyCodeScreen), findsNothing);
    });
  });

  // go_router 18 은 `package:material_ui` 의 MaterialApp 을 찾아 전환을 고르는데 앱은 flutter 의 MaterialApp 을 써서
  // 못 찾는다 — 그대로 두면 모든 화면이 NoTransitionPage(0ms)라 iOS 밀어서 뒤로가기도 없다.
  group('화면 전환', () {
    Future<GoRouter> pumpHome(WidgetTester tester) async {
      final router = AppRouter.create(
        isAuthenticated: () => true,
        verificationGate: _passedGate,
        onboardingStep: _passedStep,
      );
      addTearDown(router.dispose);
      final container = ProviderContainer(
        overrides: [
          cardRepositoryProvider.overrideWithValue(FakeCardRepository()),
          chatRepositoryProvider.overrideWithValue(FakeChatRepository()),
          communityRepositoryProvider.overrideWithValue(FakeCommunityRepository()),
          homeRepositoryProvider.overrideWithValue(FakeHomeRepository(const FailureResult(NetworkFailure()))),
          meRepositoryProvider.overrideWithValue(FakeMeRepository(const FailureResult(NetworkFailure()))),
          notificationsRepositoryProvider.overrideWithValue(FakeNotificationsRepository()),
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
      await tester.pumpAndSettle();
      return router;
    }

    ModalRoute<Object?> routeOf(WidgetTester tester, Finder finder) => ModalRoute.of(tester.element(finder))!;

    Iterable<GoRoute> goRoutes(List<RouteBase> routes) sync* {
      for (final route in routes) {
        if (route is GoRoute) yield route;
        yield* goRoutes(route.routes);
      }
    }

    test('모든 경로가 페이지를 직접 만든다 — builder 만 두면 go_router 가 0ms 페이지로 떨어뜨린다', () {
      final router = AppRouter.create(
        isAuthenticated: () => true,
        verificationGate: _passedGate,
        onboardingStep: _passedStep,
      );
      addTearDown(router.dispose);

      final bare = goRoutes(router.configuration.routes).where((route) => route.pageBuilder == null);

      expect(bare.map((route) => route.path), isEmpty);
    });

    testWidgets('탭이 아닌 화면은 안드로이드 기본 전환(450ms · 예측 뒤로가기)으로 열린다', (tester) async {
      final router = await pumpHome(tester);

      unawaited(router.push(AppRoutes.faq));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final route = routeOf(tester, find.byType(FaqScreen));
      expect(route, isA<MaterialRouteTransitionMixin<Object?>>());
      expect(route.transitionDuration, const Duration(milliseconds: FadeForwardsPageTransitionsBuilder.kTransitionMilliseconds));
      expect(route.animation!.status, AnimationStatus.forward, reason: '100ms 에는 아직 들어오는 중이다');

      await tester.pumpAndSettle();
      expect(route.animation!.status, AnimationStatus.completed);
      expect(route.popGestureEnabled, isTrue, reason: '예측 뒤로가기 · 밀어서 뒤로가기가 이 값을 본다');
    });

    const tabs = <(String, String)>[
      (AppRoutes.home, '메인'),
      (AppRoutes.today, '오늘'),
      (AppRoutes.community, '커뮤니티'),
      (AppRoutes.conversations, '대화'),
      (AppRoutes.myProfile, '나'),
    ];
    for (final (path, name) in tabs) {
      testWidgets('$name 탭은 전환 없이 바로 바뀐다(NoTransitionPage)', (tester) async {
        final router = await pumpHome(tester);

        router.go(path);
        await tester.pumpAndSettle();

        expect(routeOf(tester, find.byType(BackExitScope)).settings, isA<NoTransitionPage<Object?>>());
      });
    }

    testWidgets(
      'iOS 에서는 탭이 아닌 화면이 500ms 로 밀려 들어오고, 왼쪽 가장자리를 밀면 뒤로 간다',
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
      (tester) async {
        final router = await pumpHome(tester);
        unawaited(router.push(AppRoutes.faq));
        await tester.pumpAndSettle();

        final route = routeOf(tester, find.byType(FaqScreen));
        expect(route.transitionDuration, CupertinoRouteTransitionMixin.kTransitionDuration);
        expect(route.popGestureEnabled, isTrue);

        await tester.dragFrom(const Offset(5, 300), const Offset(500, 0));
        await tester.pumpAndSettle();

        expect(find.byType(FaqScreen), findsNothing);
        expect(find.byType(HomeScreen), findsOneWidget);
      },
    );

    // Flutter 는 동작 줄이기면 전환 시간을 0 이 아니라 5% 로 줄인다(AnimationController · AnimationBehavior.normal).
    testWidgets('동작 줄이기를 켜면 전환이 한두 프레임 안에 끝난다', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final router = await pumpHome(tester);

      unawaited(router.push(AppRoutes.faq));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));

      final faq = find.byType(FaqScreen);
      expect(MediaQuery.disableAnimationsOf(tester.element(faq)), isTrue);
      expect(routeOf(tester, faq).animation!.status, AnimationStatus.completed);
      await tester.pumpAndSettle();
    });
  });
}
