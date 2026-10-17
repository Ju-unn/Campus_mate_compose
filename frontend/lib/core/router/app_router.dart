import 'package:campus_mate/account/view/account_screen.dart';
import 'package:campus_mate/account/view/account_suspended_screen.dart';
import 'package:campus_mate/account/view/kakao_id_settings_screen.dart';
import 'package:campus_mate/auth/model/university_email.dart';
import 'package:campus_mate/auth/model/verification_gate.dart';
import 'package:campus_mate/auth/view/school_info_screen.dart';
import 'package:campus_mate/auth/view/sign_up_screen.dart';
import 'package:campus_mate/auth/view/start_view.dart';
import 'package:campus_mate/auth/view/student_verification_screen.dart';
import 'package:campus_mate/auth/view/verify_code_screen.dart';
import 'package:campus_mate/billing/model/heart_task.dart';
import 'package:campus_mate/consent/view/consent_screen.dart';
import 'package:campus_mate/billing/view/heart_task_pending_screen.dart';
import 'package:campus_mate/billing/view/heart_task_submit_screen.dart';
import 'package:campus_mate/billing/view/heart_store_screen.dart';
import 'package:campus_mate/billing/view/heart_tasks_screen.dart';
import 'package:campus_mate/chat/view/chat_room_screen.dart';
import 'package:campus_mate/community/view/community_feed_screen.dart';
import 'package:campus_mate/community/view/poll_composer_screen.dart';
import 'package:campus_mate/community/view/poll_detail_screen.dart';
import 'package:campus_mate/core/auth/account_status_listenable.dart';
import 'package:campus_mate/core/back_exit/back_exit_scope.dart';
import 'package:campus_mate/core/offline/offline_screen.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/router/auth_redirect.dart';
import 'package:campus_mate/faq/view/faq_screen.dart';
import 'package:campus_mate/friend_review/view/friend_code_screen.dart';
import 'package:campus_mate/friend_review/view/friend_review_compose_sheet.dart';
import 'package:campus_mate/friend_review/view/received_reviews_screen.dart';
import 'package:campus_mate/friend_review/view/written_reviews_screen.dart';
import 'package:campus_mate/home/view/event_coming_screen.dart';
import 'package:campus_mate/home/view/home_screen.dart';
import 'package:campus_mate/matching/model/acceptance.dart';
import 'package:campus_mate/matching/view/acceptance_detail_screen.dart';
import 'package:campus_mate/matching/view/card_detail_screen.dart';
import 'package:campus_mate/matching/view/conversations_screen.dart';
import 'package:campus_mate/matching/view/match_made_screen.dart';
import 'package:campus_mate/matching/view/notification_settings_screen.dart';
import 'package:campus_mate/matching/view/settings_screen.dart';
import 'package:campus_mate/matching/view/today_cards_screen.dart';
import 'package:campus_mate/me/view/basic_info_edit_screen.dart';
import 'package:campus_mate/me/view/avatar_regen_pick_screen.dart';
import 'package:campus_mate/me/view/card_preview_screen.dart';
import 'package:campus_mate/me/view/my_photos_screen.dart';
import 'package:campus_mate/me/view/my_profile_screen.dart';
import 'package:campus_mate/me/view/profile_edit_screen.dart';
import 'package:campus_mate/me/view/profile_manage_screen.dart';
import 'package:campus_mate/notifications/view/notifications_screen.dart';
import 'package:campus_mate/profile/model/onboarding_step.dart';
import 'package:campus_mate/profile/view/acquisition_screen.dart';
import 'package:campus_mate/profile/view/appearance_type_screen.dart';
import 'package:campus_mate/profile/view/avatar_generation_screen.dart';
import 'package:campus_mate/profile/view/avatar_source_screen.dart';
import 'package:campus_mate/profile/view/basic_info_screen.dart';
import 'package:campus_mate/profile/view/bio_draft_loading_screen.dart';
import 'package:campus_mate/profile/view/ideal_conditions_screen.dart';
import 'package:campus_mate/profile/view/ideal_note_screen.dart';
import 'package:campus_mate/profile/view/kakao_id_screen.dart';
import 'package:campus_mate/profile/view/onboarding_contact_block_screen.dart';
import 'package:campus_mate/profile/view/photos_screen.dart';
import 'package:campus_mate/profile/view/survey_screen.dart';
import 'package:campus_mate/profile/view/tag_picker_screen.dart';
import 'package:campus_mate/profile/viewmodel/tag_picker_kind.dart';
import 'package:campus_mate/referral/view/referral_code_screen.dart';
import 'package:campus_mate/safety/view/block_list_screen.dart';
import 'package:campus_mate/safety/view/contact_block_list_screen.dart';
import 'package:campus_mate/safety/view/contact_picker_screen.dart';
import 'package:campus_mate/safety/view/partner_profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// 앱의 라우터를 구성한다.
/// 이동 판단은 [AuthRedirect] 가 맡고 여기서는 경로와 화면만 연결한다.
abstract final class AppRouter {
  static GoRouter create({
    required bool Function() isAuthenticated,
    required VerificationGate Function() verificationGate,
    // null 이면 아직 조회 중이라 스플래시에 둔다([AuthRedirect]).
    required OnboardingStep? Function() onboardingStep,
    bool Function() isSplashHeld = _splashNotHeld,
    AccountStatus Function() accountStatus = _active,
    Listenable? refreshListenable,
  }) {
    return GoRouter(
      initialLocation: AppRoutes.splash,
      refreshListenable: refreshListenable,
      redirect: (context, state) {
        // 스플래시를 붙잡아 두는 동안에는 이동 판단을 미룬다 (임시 — [SplashHold] 주석 참고).
        if (isSplashHeld() && state.matchedLocation == AppRoutes.splash) {
          return null;
        }
        return AuthRedirect(isAuthenticated(), verificationGate(), onboardingStep(), accountStatus: accountStatus())
            .resolve(state.matchedLocation);
      },
      routes: _routes(),
    );
  }

  /// 스플래시를 붙잡지 않는 기본값. 테스트는 기다릴 이유가 없다.
  static bool _splashNotHeld() => false;

  /// 계정 상태를 넘기지 않으면 정상 계정으로 본다 — 기존 테스트가 그대로 돈다.
  static AccountStatus _active() => AccountStatus.active;

  /// 3b·3c 는 [AuthRedirect] 가 미인증·게이트 미충족을 이미 막아 화면 가드를 두지 않는다.
  static List<RouteBase> _routes() {
    return <RouteBase>[
      _PlatformRoute(path: AppRoutes.splash, builder: (context, state) => const StartView()),
      _PlatformRoute(path: AppRoutes.offline, builder: (context, state) => const OfflineScreen()),
      _ExitGuardedRoute(path: AppRoutes.login, builder: (context, state) => const SignUpScreen()),
      // 03 은 화면 안에 돌아갈 곳(02)이 있어 화면이 스스로 [BackExitScope] 를 두른다(여기서 또 두르면 두 겹이 된다).
      _PlatformRoute(path: AppRoutes.verifyCode, redirect: _verifyCodeGuard, builder: _buildVerifyCode),
      // 약관은 관문이라 뒤로가기를 막아 둔 채 둔다(화면의 PopScope, 나갈 길은 로그아웃뿐 — 대장 결정 pen ②).
      _PlatformRoute(path: AppRoutes.consent, builder: (context, state) => const ConsentScreen()),
      _ExitGuardedRoute(path: AppRoutes.studentVerification, builder: (context, state) => const StudentVerificationScreen()),
      _ExitGuardedRoute(path: AppRoutes.schoolInfo, builder: (context, state) => const SchoolInfoScreen()),
      ..._onboardingRoutes(),
      ..._slice4Routes(),
      ..._slice6Routes(),
      ..._meRoutes(),
    ];
  }

  /// 나 탭 편집(계획서 2026-09-27-me-edit.md A2) — 15c, 그리고 온보딩 06-1 · 태그 3종을 편집 모드로 다시 띄운다.
  /// 화면 15 · 15c 에서 push 로 연다.
  static List<RouteBase> _meRoutes() {
    return <RouteBase>[
      _PlatformRoute(path: AppRoutes.myProfileEdit, builder: (context, state) => const ProfileEditScreen()),
      _PlatformRoute(
        path: AppRoutes.myIdealConditions,
        builder: (context, state) => const IdealConditionsScreen(isEditing: true),
      ),
      _PlatformRoute(
        path: '${AppRoutes.myTags}/:kind',
        // 모르는 종류면 15c 로 돌려보낸다 — 화면이 kind 없이는 뜰 수 없다.
        redirect: (context, state) => _tagKind(state) == null ? AppRoutes.myProfileEdit : null,
        builder: (context, state) => TagPickerScreen(kind: _tagKind(state)!, isEditing: true),
      ),
      // 화면 15 개편(계획서 2026-09-28-me-profile.md A10) — 15 입구에서 push 로 연다.
      _PlatformRoute(path: AppRoutes.myProfileManage, builder: (context, state) => const ProfileManageScreen()),
      _PlatformRoute(path: AppRoutes.myCardPreview, builder: (context, state) => const CardPreviewScreen()),
      _PlatformRoute(path: AppRoutes.myAvatarRegen, builder: (context, state) => const AvatarRegenPickScreen()),
      _PlatformRoute(path: AppRoutes.myPhotos, builder: (context, state) => const MyPhotosScreen()),
      _PlatformRoute(path: AppRoutes.myBasicInfo, builder: (context, state) => const BasicInfoEditScreen()),
    ];
  }

  static TagPickerKind? _tagKind(GoRouterState state) {
    final endpoint = state.pathParameters['kind'];
    return TagPickerKind.values.where((kind) => kind.endpoint == endpoint).firstOrNull;
  }

  /// 조각 6 — 16f 차단 목록(설정 아래), 14c 상대 프로필(채팅방 14b "상대 프로필 보기"),
  /// 정지 안내, 16e-1 카카오톡 아이디 변경(16e 계정 · 14f "변경").
  static List<RouteBase> _slice6Routes() {
    return <RouteBase>[
      _PlatformRoute(path: AppRoutes.blockList, builder: (context, state) => const BlockListScreen()),
      _PlatformRoute(path: AppRoutes.contactBlocks, builder: (context, state) => const ContactBlockListScreen()),
      _PlatformRoute(path: AppRoutes.contactPicker, builder: (context, state) => const ContactPickerScreen()),
      _PlatformRoute(path: AppRoutes.accountSuspended, builder: (context, state) => const AccountSuspendedScreen()),
      _PlatformRoute(path: AppRoutes.kakaoIdSettings, builder: (context, state) => const KakaoIdSettingsScreen()),
      _PlatformRoute(
        path: '${AppRoutes.partnerProfile}/:profileId',
        builder: (context, state) => PartnerProfileScreen(profileId: state.pathParameters['profileId']!),
      ),
      _PlatformRoute(path: AppRoutes.heartStore, builder: (context, state) => const HeartStoreScreen()),
      _PlatformRoute(path: AppRoutes.heartTasks, builder: (context, state) => const HeartTasksScreen()),
      _PlatformRoute(
        path: '${AppRoutes.heartTaskSubmit}/:task',
        // 인증샷 항목이 아니면(투표 · 잘못된 값) 18a 로 돌려보낸다.
        redirect: (context, state) =>
            HeartTaskKind.tryParse(state.pathParameters['task'])?.needsProof == true ? null : AppRoutes.heartTasks,
        builder: (context, state) => HeartTaskSubmitScreen(
          kind: HeartTaskKind.tryParse(state.pathParameters['task'])!,
          rejectReason: HeartTaskRejectReason.tryParse(state.uri.queryParameters['reason']),
        ),
      ),
      _PlatformRoute(path: AppRoutes.heartTaskPending, builder: (context, state) => const HeartTaskPendingScreen()),
      _PlatformRoute(path: AppRoutes.friendReviews, builder: (context, state) => const ReceivedReviewsScreen()),
      _PlatformRoute(path: AppRoutes.friendReviewsWritten, builder: (context, state) => const WrittenReviewsScreen()),
      _PlatformRoute(path: AppRoutes.friendReviewCode, builder: (context, state) => const FriendCodeScreen()),
    ];
  }

  /// 조각 4 — 오늘의 카드와 그 주변. 하단 내비 탭 5개(`home` · `today` · `community` · `conversations` · `myProfile`)는
  /// 셸 없이 각자 최상위 경로라, 안드로이드 뒤로가기 확인([BackExitScope])을 탭마다 한 겹씩 두른다.
  /// `home` 은 09b 메인이고 서버 `/home/summary` · `/home/people`(레일 사람 칸)로 채운다 — 리뷰 칸만 출시 전 고정값이다(`homeRepositoryProvider`).
  static List<RouteBase> _slice4Routes() {
    return <RouteBase>[
      _TabRoute(
        path: AppRoutes.home,
        builder: (context, state) => const BackExitScope(child: HomeScreen()),
        routes: [
          // 20b — AppRoutes.friendReviewWrite/:profileId. 홈이 밑에 깔리고 그 위에 시트가 뜬다(추천 가입 푸시).
          GoRoute(
            path: 'friend-reviews/write/:profileId',
            pageBuilder: (context, state) =>
                FriendReviewComposePage(key: state.pageKey, revieweeId: state.pathParameters['profileId']!),
          ),
        ],
      ),
      _PlatformRoute(path: AppRoutes.notifications, builder: (context, state) => const NotificationsScreen()),
      _PlatformRoute(path: AppRoutes.events, builder: (context, state) => const EventComingScreen()),
      _TabRoute(path: AppRoutes.today, builder: (context, state) => const BackExitScope(child: TodayCardsScreen())),
      _PlatformRoute(
        path: '${AppRoutes.cardDetail}/:cardId',
        builder: (context, state) => CardDetailScreen(cardId: state.pathParameters['cardId']!),
      ),
      _TabRoute(
        path: AppRoutes.conversations,
        builder: (context, state) => const BackExitScope(child: ConversationsScreen()),
      ),
      // 받은 신청 · 프로필 보기(pen `o4QqYR`) — 대화 탭 받은 신청 행의 "프로필 보기" 가 push 로 연다.
      _PlatformRoute(
        path: '${AppRoutes.acceptanceDetail}/:cardId',
        builder: (context, state) => AcceptanceDetailScreen(cardId: state.pathParameters['cardId']!),
      ),
      _PlatformRoute(
        path: AppRoutes.matchMade,
        builder: (context, state) {
          final args = state.extra as MatchMadeArgs?;
          return MatchMadeScreen(nickname: args?.nickname ?? '상대', matchId: args?.matchId);
        },
      ),
      _PlatformRoute(
        path: '${AppRoutes.chatRoom}/:matchId',
        builder: (context, state) => ChatRoomScreen(matchId: state.pathParameters['matchId']!),
      ),
      _PlatformRoute(path: AppRoutes.settings, builder: (context, state) => const SettingsScreen()),
      _PlatformRoute(
        path: AppRoutes.notificationSettings,
        builder: (context, state) => const NotificationSettingsScreen(),
      ),
      _PlatformRoute(path: AppRoutes.account, builder: (context, state) => const AccountScreen()),
      _PlatformRoute(path: AppRoutes.faq, builder: (context, state) => const FaqScreen()),
      _TabRoute(
        path: AppRoutes.community,
        builder: (context, state) => const BackExitScope(child: CommunityFeedScreen()),
      ),
      _PlatformRoute(path: AppRoutes.communityNew, builder: (context, state) => const PollComposerScreen()),
      _PlatformRoute(
        path: '${AppRoutes.communityPoll}/:pollId',
        builder: (context, state) => PollDetailScreen(pollId: state.pathParameters['pollId']!),
      ),
      _TabRoute(
        path: AppRoutes.myProfile,
        builder: (context, state) => const BackExitScope(child: MyProfileScreen()),
      ),
    ];
  }

  /// 조각 2 온보딩 04-1~06-3. 순서는 [AppRoutes] 상수 순서이자 서버 `next-step` 응답 순서다.
  /// 06-2b(초안 생성)는 06-3 과 같은 `bio` 단계라 라우트를 따로 두지 않는다
  /// ([BioDraftLoadingScreen] 이 끝나면 스스로 06-3 으로 바뀐다).
  /// 설문 · 20d · 06-4 와 온보딩 뒤로가기가 있는 화면(04-1b · 04-2 · 04-5 · 04-6 · 06-1 · 06-2 · 06-2a · 06-2b · 06-3)은
  /// 화면 안에 돌아갈 곳이 있어 화면이 스스로 [BackExitScope] 를 두른다(여기서 또 두르면 두 겹이 된다).
  /// 뒤로가 없는 04-1(앞이 관문) · 04-4(사진 경계) · 05-12(가입 맨 끝 아바타 확인) · 20(06-3 저장 순간 가입 끝)은 여기서 종료 확인을 두른다.
  /// 04-3 · 8d 는 push 로 올라와 시스템 뒤로가기가 평소대로 한 단계 돌아간다.
  static List<RouteBase> _onboardingRoutes() {
    return <RouteBase>[
      _ExitGuardedRoute(path: AppRoutes.onboardingBasicInfo, builder: (context, state) => const BasicInfoScreen()),
      _PlatformRoute(path: AppRoutes.onboardingKakaoId, builder: (context, state) => const KakaoIdScreen()),
      _PlatformRoute(path: AppRoutes.onboardingPhotos, builder: (context, state) => const PhotosScreen()),
      _PlatformRoute(path: AppRoutes.onboardingAvatarSource, builder: (context, state) => const AvatarSourceScreen()),
      _ExitGuardedRoute(path: AppRoutes.onboardingAvatar, builder: (context, state) => const AvatarGenerationScreen()),
      _ExitGuardedRoute(
        path: AppRoutes.onboardingAppearanceType,
        builder: (context, state) => const AppearanceTypeScreen(),
      ),
      _PlatformRoute(
        path: AppRoutes.onboardingInterests,
        builder: (context, state) => const TagPickerScreen(kind: TagPickerKind.interests),
      ),
      _PlatformRoute(
        path: AppRoutes.onboardingMyTraits,
        builder: (context, state) => const TagPickerScreen(kind: TagPickerKind.myTraits),
      ),
      _PlatformRoute(path: AppRoutes.onboardingSurvey, builder: (context, state) => const SurveyScreen()),
      _PlatformRoute(
        path: AppRoutes.onboardingIdealConditions,
        builder: (context, state) => const IdealConditionsScreen(),
      ),
      _PlatformRoute(
        path: AppRoutes.onboardingIdealTraits,
        builder: (context, state) => const TagPickerScreen(kind: TagPickerKind.idealTraits),
      ),
      _PlatformRoute(path: AppRoutes.onboardingIdealNote, builder: (context, state) => const IdealNoteScreen()),
      _PlatformRoute(path: AppRoutes.onboardingBio, builder: (context, state) => const BioDraftLoadingScreen()),
      _ExitGuardedRoute(path: AppRoutes.onboardingReferral, builder: (context, state) => const ReferralCodeScreen()),
      _PlatformRoute(path: AppRoutes.onboardingAcquisition, builder: (context, state) => const AcquisitionScreen()),
      _PlatformRoute(path: AppRoutes.onboardingContactBlock, builder: (context, state) => const OnboardingContactBlockScreen()),
      _PlatformRoute(path: AppRoutes.onboardingContactPicker, builder: (context, state) => const ContactPickerScreen()),
    ];
  }

  /// 이메일 없이 이 경로에 들어오면 로그인부터 다시 시작한다.
  static String? _verifyCodeGuard(BuildContext context, GoRouterState state) {
    return state.extra is UniversityEmail ? null : AppRoutes.login;
  }

  static Widget _buildVerifyCode(BuildContext context, GoRouterState state) {
    return VerifyCodeScreen(email: state.extra as UniversityEmail);
  }
}

/// 탭이 아닌 화면 — 플랫폼 기본 전환으로 뜬다(안드로이드 450ms · 예측 뒤로가기, iOS 500ms · 왼쪽 가장자리 밀어서 뒤로가기).
/// go_router 18 은 `package:material_ui` 의 MaterialApp 을 조상에서 찾아 페이지를 고르는데 앱은 flutter 의 MaterialApp 을
/// 써서 못 찾는다 — `builder` 만 주면 전환 0ms 인 NoTransitionPage 로 떨어지니 페이지를 여기서 직접 만든다.
/// 전환 모양 · 시간은 테마의 PageTransitionsTheme(Flutter 기본값)이 플랫폼별로 고른다.
/// ponytail: builder 는 페이지 바깥 context 로 불린다(go_router 의 builder 는 페이지 안쪽) — 지금 builder 는 모두
/// state 만 읽는다. context 로 ModalRoute 등을 읽어야 하면 `Builder` 로 감싼다.
class _PlatformRoute extends GoRoute {
  _PlatformRoute({required super.path, required GoRouterWidgetBuilder builder, super.redirect})
      : super(pageBuilder: (context, state) => MaterialPage<void>(key: state.pageKey, child: builder(context, state)));
}

/// 온보딩 · 관문 화면 — go 로만 들어와 맨 아래 한 장이라 안드로이드 시스템 뒤로가기가 곧바로 앱을 닫는다.
/// 탭과 같이 [BackExitScope] 로 한 번 더 확인한다(2026-10-15 사용자 지적). 전환은 [_PlatformRoute] 그대로다.
class _ExitGuardedRoute extends _PlatformRoute {
  _ExitGuardedRoute({required super.path, required GoRouterWidgetBuilder builder})
      : super(builder: (context, state) => BackExitScope(child: builder(context, state)));
}

/// 하단 내비 탭 5개 — 탭끼리는 미끄러지지 않고 바로 바뀐다(10-14 대장 지시). go_router 가 판별을 고쳐도 그대로다.
class _TabRoute extends GoRoute {
  _TabRoute({required super.path, required GoRouterWidgetBuilder builder, super.routes})
      : super(pageBuilder: (context, state) => NoTransitionPage<void>(key: state.pageKey, child: builder(context, state)));
}
