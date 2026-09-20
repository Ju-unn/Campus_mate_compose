import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/labeled_field.dart';
import 'package:campus_mate/common/widgets/mbti_pole_toggle.dart';
import 'package:campus_mate/common/widgets/onboarding_app_bar.dart';
import 'package:campus_mate/common/widgets/select_chip.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/profile/viewmodel/basic_info_ui_state.dart';
import 'package:campus_mate/profile/viewmodel/basic_info_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 기본 정보 화면(DESIGN.md 화면 04-1, datingApp.pen `04-1 기본 정보`).
class BasicInfoScreen extends ConsumerWidget {
  const BasicInfoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(basicInfoViewModelProvider);
    final viewModel = ref.read(basicInfoViewModelProvider.notifier);
    return Scaffold(
      appBar: const OnboardingAppBar(current: 0, total: 6),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: SingleChildScrollView(child: _Form(state: state, viewModel: viewModel))),
              const SizedBox(height: AppSpacing.md),
              AppButton(label: '다음', onPressed: state.canSubmit ? viewModel.submit : null),
            ],
          ),
        ),
      ),
    );
  }
}

class _Form extends StatelessWidget {
  const _Form({required this.state, required this.viewModel});

  final BasicInfoUiState state;
  final BasicInfoViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.xl),
        Text(
          '닉네임과 기본 정보를\n알려주세요',
          style: AppTypography.headline.copyWith(color: AppColors.ink),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '정확한 정보일수록 더 잘 맞는 상대를 만나요.',
          style: AppTypography.body.copyWith(color: AppColors.body),
        ),
        const SizedBox(height: AppSpacing.xl),
        LabeledField(
          label: '닉네임',
          initialValue: state.nicknameInput,
          onChanged: viewModel.changeNickname,
          helper: '2~5자, 한글 또는 영문',
          errorText: state.nicknameError,
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: LabeledField(
                label: '출생연도',
                placeholder: '예: 2003',
                initialValue: state.birthYearInput,
                onChanged: viewModel.changeBirthYear,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: LabeledField(
                label: '키 (cm)',
                placeholder: '예: 170',
                initialValue: state.heightInput,
                onChanged: viewModel.changeHeight,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        LabeledField(
          label: '전화번호',
          placeholder: '010-0000-0000',
          initialValue: state.phoneNumberInput,
          onChanged: viewModel.changePhoneNumber,
          helper: '다른 사람이 나를 지인으로 등록했을 때만 사용돼요',
        ),
        const SizedBox(height: AppSpacing.sm),
        Text('성별', style: AppTypography.labelSmall.copyWith(color: AppColors.body)),
        const SizedBox(height: AppSpacing.xs),
        _GenderRow(state: state, viewModel: viewModel),
        const SizedBox(height: 20),
        Text('내 MBTI', style: AppTypography.labelSmall.copyWith(color: AppColors.body)),
        const SizedBox(height: AppSpacing.xs),
        MbtiPoleToggle(
          selected: state.mbtiPoles,
          onTap: viewModel.toggleMbtiPole,
          unknownLabel: '모름',
          isUnknownSelected: state.isMbtiUnknown,
          onUnknownTap: viewModel.toggleMbtiUnknown,
        ),
        if (state.errorMessage != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(state.errorMessage!, style: AppTypography.caption.copyWith(color: AppColors.error)),
        ],
      ],
    );
  }
}

class _GenderRow extends StatelessWidget {
  const _GenderRow({required this.state, required this.viewModel});

  final BasicInfoUiState state;
  final BasicInfoViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SelectChip(
          label: '남성',
          width: 76,
          radius: AppRadius.pill,
          isSelected: state.gender == 'male',
          onTap: () => viewModel.changeGender('male'),
        ),
        const SizedBox(width: AppSpacing.sm),
        SelectChip(
          label: '여성',
          width: 76,
          radius: AppRadius.pill,
          isSelected: state.gender == 'female',
          onTap: () => viewModel.changeGender('female'),
        ),
      ],
    );
  }
}
