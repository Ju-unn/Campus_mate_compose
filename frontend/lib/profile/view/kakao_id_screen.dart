import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/labeled_field.dart';
import 'package:campus_mate/common/widgets/notice_card.dart';
import 'package:campus_mate/common/widgets/onboarding_app_bar.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/profile/viewmodel/kakao_id_view_model.dart';
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
    return Scaffold(
      appBar: const OnboardingAppBar(current: 1, total: 6),
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
                        '카카오톡 아이디를 알려주세요',
                        style: AppTypography.headline.copyWith(color: AppColors.ink),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '서로 수락하고 신뢰 확인을 마친 상대에게만 공개돼요.',
                        style: AppTypography.body.copyWith(color: AppColors.body),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      LabeledField(
                        label: '카카오톡 아이디',
                        placeholder: '예: campusmate_22',
                        initialValue: state.kakaoIdInput,
                        onChanged: viewModel.changeKakaoId,
                        helper: '설정 > 계정에서 언제든 바꿀 수 있어요',
                        errorText: state.errorMessage,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      const NoticeCard(
                        isEmphasis: true,
                        title: '꼭 확인해 주세요',
                        body: '카카오톡에서 \'아이디로 친구 추가 허용\'을 켜주셔야 상대가 내 아이디를 검색할 수 있어요. '
                            '꺼져 있으면 신뢰 확인을 마쳐도 연락이 닿지 않아요.',
                        footer: '카카오톡 > 설정 > 프로필 관리에서 켤 수 있어요',
                        child: _AllowSearchRow(),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppButton(label: '다음', onPressed: state.canSubmit ? viewModel.submit : null),
            ],
          ),
        ),
      ),
    );
  }
}

/// 카카오톡 설정 화면이 어떻게 생겼는지 보여주는 그림이다 — 여기서 켜고 끌 수는 없다.
class _AllowSearchRow extends StatelessWidget {
  const _AllowSearchRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            '아이디로 친구 추가 허용',
            style: AppTypography.bodySmall.copyWith(color: AppColors.ink),
          ),
        ),
        Container(
          width: 48,
          height: 28,
          padding: const EdgeInsets.all(AppSpacing.xxs),
          alignment: Alignment.centerRight,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Container(
            width: 20,
            height: 20,
            decoration: const BoxDecoration(color: AppColors.canvas, shape: BoxShape.circle),
          ),
        ),
      ],
    );
  }
}
