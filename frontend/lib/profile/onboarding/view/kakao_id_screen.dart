import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/labeled_field.dart';
import 'package:campus_mate/common/widgets/notice_card.dart';
import 'package:campus_mate/common/widgets/onboarding_app_bar.dart';
import 'package:campus_mate/core/back_exit/back_exit_scope.dart';
import 'package:campus_mate/core/l10n/error_text.dart';
import 'package:campus_mate/core/l10n/l10n_context.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/profile/onboarding/view/onboarding_back.dart';
import 'package:campus_mate/profile/onboarding/viewmodel/kakao_id_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 카카오톡 아이디 화면(DESIGN.md 화면 04-1b, datingApp.pen `04-1b 카카오톡 아이디`).
/// 건너뛰기 없음(§13-100).
class KakaoIdScreen extends ConsumerWidget {
  const KakaoIdScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(kakaoIdViewModelProvider);
    final viewModel = ref.read(kakaoIdViewModelProvider.notifier);
    final back = onboardingBack(ref, isBusy: state.isSubmitting);
    final l10n = context.l10n;
    final error = state.error;
    // 시스템 뒤로도 화살표처럼 04-1 로 간다. 라우터는 이 화면을 두르지 않는다 — 두 겹이면 안내까지 뜬다.
    return BackExitScope(onBack: back, child: Scaffold(
      // pen `sN9Il` 은 04-1 과 같은 첫째 점을 켠다 — 04-1b 는 04-1 에 딸린 화면이다.
      appBar: OnboardingAppBar(current: 0, total: 6, onBack: back),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: AppSpacing.xl),
                      Text(
                        l10n.profileKakaoIdHeadline,
                        style: AppTypography.headline.copyWith(color: AppColors.ink),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        l10n.profileKakaoIdSubtitle,
                        style: AppTypography.body.copyWith(color: AppColors.body),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      LabeledField(
                        label: l10n.commonKakaoId,
                        placeholder: l10n.profileKakaoIdPlaceholder,
                        initialValue: state.kakaoIdInput,
                        onChanged: viewModel.changeKakaoId,
                        helper: l10n.profileKakaoIdHelper,
                        errorText: error == null ? null : context.errorText(error),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      NoticeCard(
                        isEmphasis: true,
                        title: l10n.profileKakaoIdNoticeTitle,
                        body: l10n.profileKakaoIdNoticeBody,
                        footer: l10n.profileKakaoIdNoticeFooter,
                        child: const KakaoSettingExample(),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppButton(label: l10n.commonNext, onPressed: state.canSubmit ? viewModel.submit : null),
            ],
          ),
        ),
      ),
    ));
  }
}

/// 카카오톡 설정 화면이 어떻게 생겼는지 보여주는 그림(pen `sN9Il` 의 `W2tFQt`)이다 —
/// 우리 화면이 아니라 남의 앱 화면을 옮겨 그린 것이라 눌러도 아무 일이 없다.
class KakaoSettingExample extends StatelessWidget {
  const KakaoSettingExample({super.key});

  @override
  Widget build(BuildContext context) {
    // 조각을 하나씩 읽어 봐야 소용이 없는 그림이라 통째로 한 문장으로 읽힌다.
    return Semantics(
      label: context.l10n.profileKakaoSettingExampleSemantics,
      image: true,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.profileKakaoSettingExampleCaption,
            // 토큰 badge(10/600)에서 굵기만 pen 값으로 낮춘다.
            style: AppTypography.badge.copyWith(color: AppColors.disabled, fontWeight: FontWeight.w500),
          ),
          // 캡션과 패널 사이는 카드 gap 과 같은 12 다(pen 실측).
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.kakaoPanel,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    context.l10n.profileKakaoSettingExampleToggle,
                    style: AppTypography.labelSmall.copyWith(color: AppColors.onInk),
                  ),
                ),
                const KakaoToggleImage(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 켜져 있는 카카오톡 토글 그림. 트랙 44×24 · 손잡이 20 (pen `W2tFQt`).
class KakaoToggleImage extends StatelessWidget {
  const KakaoToggleImage({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 24,
      padding: const EdgeInsets.all(2),
      alignment: Alignment.centerRight,
      decoration: BoxDecoration(
        color: AppColors.kakaoContainer,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Container(
        width: 20,
        height: 20,
        alignment: Alignment.center,
        decoration: const BoxDecoration(color: AppColors.canvas, shape: BoxShape.circle),
        child: const Icon(AppIcons.check, size: 12, color: AppColors.kakaoCheckMark),
      ),
    );
  }
}
