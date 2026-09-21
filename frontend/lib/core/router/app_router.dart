import 'package:campus_mate/auth/model/university_email.dart';
import 'package:campus_mate/auth/model/verification_gate.dart';
import 'package:campus_mate/auth/view/school_info_screen.dart';
import 'package:campus_mate/auth/view/sign_up_screen.dart';
import 'package:campus_mate/auth/view/student_verification_screen.dart';
import 'package:campus_mate/auth/view/verify_code_screen.dart';
import 'package:campus_mate/common/widgets/app_bottom_nav.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/router/auth_redirect.dart';
import 'package:campus_mate/core/router/placeholder_screens.dart';
import 'package:campus_mate/matching/view/card_detail_screen.dart';
import 'package:campus_mate/matching/view/conversations_screen.dart';
import 'package:campus_mate/matching/view/match_made_screen.dart';
import 'package:campus_mate/matching/view/today_cards_screen.dart';
import 'package:campus_mate/profile/model/onboarding_step.dart';
import 'package:campus_mate/profile/view/appearance_type_screen.dart';
import 'package:campus_mate/profile/view/avatar_generation_screen.dart';
import 'package:campus_mate/profile/view/basic_info_screen.dart';
import 'package:campus_mate/profile/view/bio_draft_loading_screen.dart';
import 'package:campus_mate/profile/view/ideal_conditions_screen.dart';
import 'package:campus_mate/profile/view/ideal_note_screen.dart';
import 'package:campus_mate/profile/view/kakao_id_screen.dart';
import 'package:campus_mate/profile/view/photos_screen.dart';
import 'package:campus_mate/profile/view/survey_screen.dart';
import 'package:campus_mate/profile/view/tag_picker_screen.dart';
import 'package:campus_mate/profile/viewmodel/tag_picker_kind.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// 앱의 라우터를 구성한다.
/// 이동 판단은 [AuthRedirect] 가 맡고 여기서는 경로와 화면만 연결한다.
abstract final class AppRouter {
  static GoRouter create({
    required bool Function() isAuthenticated,
    required VerificationGate Function() verificationGate,
    required OnboardingStep Function() onboardingStep,
    Listenable? refreshListenable,
  }) {
    return GoRouter(
      initialLocation: AppRoutes.splash,
      refreshListenable: refreshListenable,
      redirect: (context, state) {
        return AuthRedirect(isAuthenticated(), verificationGate(), onboardingStep())
            .resolve(state.matchedLocation);
      },
      routes: _routes(),
    );
  }

  /// 3b·3c 는 [AuthRedirect] 가 미인증·게이트 미충족을 이미 막아 화면 가드를 두지 않는다.
  static List<RouteBase> _routes() {
    return <RouteBase>[
      GoRoute(path: AppRoutes.splash, builder: (context, state) => const SplashScreen()),
      GoRoute(path: AppRoutes.login, builder: (context, state) => const SignUpScreen()),
      GoRoute(path: AppRoutes.verifyCode, redirect: _verifyCodeGuard, builder: _buildVerifyCode),
      GoRoute(path: AppRoutes.studentVerification, builder: (context, state) => const StudentVerificationScreen()),
      GoRoute(path: AppRoutes.schoolInfo, builder: (context, state) => const SchoolInfoScreen()),
      ..._onboardingRoutes(),
      ..._slice4Routes(),
    ];
  }

  /// 조각 4 — 오늘의 카드와 그 주변. 09b 메인은 아직 없어 `home` 도 자리 화면이다(Part A 가정 1).
  static List<RouteBase> _slice4Routes() {
    return <RouteBase>[
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const ComingSoonScreen(tab: AppTab.main),
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
        builder: (context, state) => MatchMadeScreen(nickname: state.extra as String? ?? '상대'),
      ),
      GoRoute(
        path: AppRoutes.community,
        builder: (context, state) => const ComingSoonScreen(tab: AppTab.community),
      ),
      GoRoute(
        path: AppRoutes.myProfile,
        builder: (context, state) => const ComingSoonScreen(tab: AppTab.me),
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
