import 'package:campus_mate/account/view/account_screen.dart';
import 'package:campus_mate/account/view/account_suspended_screen.dart';
import 'package:campus_mate/account/view/kakao_id_settings_screen.dart';
import 'package:campus_mate/auth/model/university_email.dart';
import 'package:campus_mate/auth/model/verification_gate.dart';
import 'package:campus_mate/auth/view/school_info_screen.dart';
import 'package:campus_mate/auth/view/sign_up_screen.dart';
import 'package:campus_mate/auth/view/student_verification_screen.dart';
import 'package:campus_mate/auth/view/verify_code_screen.dart';
import 'package:campus_mate/billing/model/heart_task.dart';
import 'package:campus_mate/consent/view/consent_screen.dart';
import 'package:campus_mate/billing/view/heart_task_pending_screen.dart';
import 'package:campus_mate/billing/view/heart_task_submit_screen.dart';
import 'package:campus_mate/billing/view/heart_tasks_screen.dart';
import 'package:campus_mate/chat/view/chat_room_screen.dart';
import 'package:campus_mate/community/view/community_feed_screen.dart';
import 'package:campus_mate/community/view/poll_composer_screen.dart';
import 'package:campus_mate/community/view/poll_detail_screen.dart';
import 'package:campus_mate/core/auth/account_status_listenable.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/router/auth_redirect.dart';
import 'package:campus_mate/core/router/placeholder_screens.dart';
import 'package:campus_mate/faq/view/faq_screen.dart';
import 'package:campus_mate/friend_review/view/friend_review_compose_sheet.dart';
import 'package:campus_mate/friend_review/view/received_reviews_screen.dart';
import 'package:campus_mate/friend_review/view/written_reviews_screen.dart';
import 'package:campus_mate/home/view/home_screen.dart';
import 'package:campus_mate/matching/model/acceptance.dart';
import 'package:campus_mate/matching/view/card_detail_screen.dart';
import 'package:campus_mate/matching/view/conversations_screen.dart';
import 'package:campus_mate/matching/view/match_made_screen.dart';
import 'package:campus_mate/matching/view/notification_settings_screen.dart';
import 'package:campus_mate/matching/view/settings_screen.dart';
import 'package:campus_mate/matching/view/today_cards_screen.dart';
import 'package:campus_mate/me/view/basic_info_edit_screen.dart';
import 'package:campus_mate/me/view/card_preview_screen.dart';
import 'package:campus_mate/me/view/my_photos_screen.dart';
import 'package:campus_mate/me/view/my_profile_screen.dart';
import 'package:campus_mate/me/view/profile_edit_screen.dart';
import 'package:campus_mate/me/view/profile_manage_screen.dart';
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
import 'package:campus_mate/profile/view/photos_screen.dart';
import 'package:campus_mate/profile/view/survey_screen.dart';
import 'package:campus_mate/profile/view/tag_picker_screen.dart';
import 'package:campus_mate/profile/viewmodel/tag_picker_kind.dart';
import 'package:campus_mate/referral/view/referral_code_screen.dart';
import 'package:campus_mate/safety/view/block_list_screen.dart';
import 'package:campus_mate/safety/view/contact_block_list_screen.dart';
import 'package:campus_mate/safety/view/contact_picker_screen.dart';
import 'package:campus_mate/safety/view/partner_profile_screen.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// 앱의 라우터를 구성한다.
/// 이동 판단은 [AuthRedirect] 가 맡고 여기서는 경로와 화면만 연결한다.
abstract final class AppRouter {
  static GoRouter create({
    required bool Function() isAuthenticated,
    required VerificationGate Function() verificationGate,
    required OnboardingStep Function() onboardingStep,
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
      GoRoute(path: AppRoutes.splash, builder: (context, state) => const SplashScreen()),
      GoRoute(path: AppRoutes.login, builder: (context, state) => const SignUpScreen()),
      GoRoute(path: AppRoutes.verifyCode, redirect: _verifyCodeGuard, builder: _buildVerifyCode),
      GoRoute(path: AppRoutes.consent, builder: (context, state) => const ConsentScreen()),
      GoRoute(path: AppRoutes.studentVerification, builder: (context, state) => const StudentVerificationScreen()),
      GoRoute(path: AppRoutes.schoolInfo, builder: (context, state) => const SchoolInfoScreen()),
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
      GoRoute(path: AppRoutes.myProfileEdit, builder: (context, state) => const ProfileEditScreen()),
      GoRoute(
        path: AppRoutes.myIdealConditions,
        builder: (context, state) => const IdealConditionsScreen(isEditing: true),
      ),
      GoRoute(
        path: '${AppRoutes.myTags}/:kind',
        // 모르는 종류면 15c 로 돌려보낸다 — 화면이 kind 없이는 뜰 수 없다.
        redirect: (context, state) => _tagKind(state) == null ? AppRoutes.myProfileEdit : null,
        builder: (context, state) => TagPickerScreen(kind: _tagKind(state)!, isEditing: true),
      ),
      // 화면 15 개편(계획서 2026-09-28-me-profile.md A10) — 15 입구에서 push 로 연다.
      GoRoute(path: AppRoutes.myProfileManage, builder: (context, state) => const ProfileManageScreen()),
      GoRoute(path: AppRoutes.myCardPreview, builder: (context, state) => const CardPreviewScreen()),
      GoRoute(path: AppRoutes.myPhotos, builder: (context, state) => const MyPhotosScreen()),
      GoRoute(path: AppRoutes.myBasicInfo, builder: (context, state) => const BasicInfoEditScreen()),
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
      GoRoute(path: AppRoutes.blockList, builder: (context, state) => const BlockListScreen()),
      GoRoute(path: AppRoutes.contactBlocks, builder: (context, state) => const ContactBlockListScreen()),
      GoRoute(path: AppRoutes.contactPicker, builder: (context, state) => const ContactPickerScreen()),
      GoRoute(path: AppRoutes.accountSuspended, builder: (context, state) => const AccountSuspendedScreen()),
      GoRoute(path: AppRoutes.kakaoIdSettings, builder: (context, state) => const KakaoIdSettingsScreen()),
      GoRoute(
        path: '${AppRoutes.partnerProfile}/:profileId',
        builder: (context, state) => PartnerProfileScreen(profileId: state.pathParameters['profileId']!),
      ),
      GoRoute(path: AppRoutes.heartTasks, builder: (context, state) => const HeartTasksScreen()),
      GoRoute(
        path: '${AppRoutes.heartTaskSubmit}/:task',
        // 인증샷 항목이 아니면(투표 · 잘못된 값) 18a 로 돌려보낸다.
        redirect: (context, state) =>
            HeartTaskKind.tryParse(state.pathParameters['task'])?.needsProof == true ? null : AppRoutes.heartTasks,
        builder: (context, state) => HeartTaskSubmitScreen(
          kind: HeartTaskKind.tryParse(state.pathParameters['task'])!,
          rejectReason: HeartTaskRejectReason.tryParse(state.uri.queryParameters['reason']),
        ),
      ),
      GoRoute(path: AppRoutes.heartTaskPending, builder: (context, state) => const HeartTaskPendingScreen()),
      GoRoute(path: AppRoutes.friendReviews, builder: (context, state) => const ReceivedReviewsScreen()),
      GoRoute(path: AppRoutes.friendReviewsWritten, builder: (context, state) => const WrittenReviewsScreen()),
    ];
  }

  /// 조각 4 — 오늘의 카드와 그 주변. `home` 은 09b 메인이고 서버 `/home/summary` 로 채운다 — 사람들 칸·리뷰 칸만 목값이다(`homeRepositoryProvider`).
  static List<RouteBase> _slice4Routes() {
    return <RouteBase>[
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const HomeScreen(),
        routes: [
          // 20b — AppRoutes.friendReviewWrite/:profileId. 홈이 밑에 깔리고 그 위에 시트가 뜬다(추천 가입 푸시).
          GoRoute(
            path: 'friend-reviews/write/:profileId',
            pageBuilder: (context, state) =>
                FriendReviewComposePage(key: state.pageKey, revieweeId: state.pathParameters['profileId']!),
          ),
        ],
      ),
      GoRoute(path: AppRoutes.today, builder: (context, state) => const TodayCardsScreen()),
      GoRoute(
        path: '${AppRoutes.cardDetail}/:cardId',
        builder: (context, state) => CardDetailScreen(cardId: state.pathParameters['cardId']!),
      ),
      GoRoute(
        path: AppRoutes.conversations,
        builder: (context, state) => const ConversationsScreen(),
      ),
      GoRoute(
        path: AppRoutes.matchMade,
        builder: (context, state) {
          final args = state.extra as MatchMadeArgs?;
          return MatchMadeScreen(nickname: args?.nickname ?? '상대', matchId: args?.matchId);
        },
      ),
      GoRoute(
        path: '${AppRoutes.chatRoom}/:matchId',
        builder: (context, state) => ChatRoomScreen(matchId: state.pathParameters['matchId']!),
      ),
      GoRoute(path: AppRoutes.settings, builder: (context, state) => const SettingsScreen()),
      GoRoute(
        path: AppRoutes.notificationSettings,
        builder: (context, state) => const NotificationSettingsScreen(),
      ),
      GoRoute(path: AppRoutes.account, builder: (context, state) => const AccountScreen()),
      GoRoute(path: AppRoutes.faq, builder: (context, state) => const FaqScreen()),
      GoRoute(
        path: AppRoutes.community,
        builder: (context, state) => const CommunityFeedScreen(),
      ),
      GoRoute(path: AppRoutes.communityNew, builder: (context, state) => const PollComposerScreen()),
      GoRoute(
        path: '${AppRoutes.communityPoll}/:pollId',
        builder: (context, state) => PollDetailScreen(pollId: state.pathParameters['pollId']!),
      ),
      GoRoute(
        path: AppRoutes.myProfile,
        builder: (context, state) => const MyProfileScreen(),
      ),
    ];
  }

  /// 조각 2 온보딩 04-1~06-3. 순서는 [AppRoutes] 상수 순서이자 서버 `next-step` 응답 순서다.
  /// 06-2b(초안 생성)는 06-3 과 같은 `bio` 단계라 라우트를 따로 두지 않는다
  /// ([BioDraftLoadingScreen] 이 끝나면 스스로 06-3 으로 바뀐다).
  static List<RouteBase> _onboardingRoutes() {
    return <RouteBase>[
      GoRoute(path: AppRoutes.onboardingBasicInfo, builder: (context, state) => const BasicInfoScreen()),
      GoRoute(path: AppRoutes.onboardingKakaoId, builder: (context, state) => const KakaoIdScreen()),
      GoRoute(path: AppRoutes.onboardingPhotos, builder: (context, state) => const PhotosScreen()),
      GoRoute(path: AppRoutes.onboardingAvatarSource, builder: (context, state) => const AvatarSourceScreen()),
      GoRoute(path: AppRoutes.onboardingAvatar, builder: (context, state) => const AvatarGenerationScreen()),
      GoRoute(
        path: AppRoutes.onboardingAppearanceType,
        builder: (context, state) => const AppearanceTypeScreen(),
      ),
      GoRoute(
        path: AppRoutes.onboardingInterests,
        builder: (context, state) => const TagPickerScreen(kind: TagPickerKind.interests),
      ),
      GoRoute(
        path: AppRoutes.onboardingMyTraits,
        builder: (context, state) => const TagPickerScreen(kind: TagPickerKind.myTraits),
      ),
      GoRoute(path: AppRoutes.onboardingSurvey, builder: (context, state) => const SurveyScreen()),
      GoRoute(
        path: AppRoutes.onboardingIdealConditions,
        builder: (context, state) => const IdealConditionsScreen(),
      ),
      GoRoute(
        path: AppRoutes.onboardingIdealTraits,
        builder: (context, state) => const TagPickerScreen(kind: TagPickerKind.idealTraits),
      ),
      GoRoute(path: AppRoutes.onboardingIdealNote, builder: (context, state) => const IdealNoteScreen()),
      GoRoute(path: AppRoutes.onboardingBio, builder: (context, state) => const BioDraftLoadingScreen()),
      GoRoute(path: AppRoutes.onboardingReferral, builder: (context, state) => const ReferralCodeScreen()),
      GoRoute(path: AppRoutes.onboardingAcquisition, builder: (context, state) => const AcquisitionScreen()),
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
