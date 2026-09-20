import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/profile/viewmodel/basic_info_ui_state.dart';
import 'package:campus_mate/profile/viewmodel/basic_info_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 기본 정보 화면(DESIGN.md 화면 04-1). 조각1b SchoolInfoScreen 과 같은 골격을 따른다.
class BasicInfoScreen extends ConsumerWidget {
  const BasicInfoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(basicInfoViewModelProvider);
    final viewModel = ref.read(basicInfoViewModelProvider.notifier);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 56,
        backgroundColor: AppColors.canvas,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        title: Text('기본 정보', style: AppTypography.navTitle.copyWith(color: AppColors.ink)),
      ),
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
        _field('닉네임 · 필수', '2~5자, 한글 또는 영문', state.nicknameInput, viewModel.changeNickname),
        if (state.nicknameError != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xxs),
            child: Text(state.nicknameError!, style: AppTypography.caption.copyWith(color: AppColors.error)),
          ),
        const SizedBox(height: AppSpacing.md),
        _field('출생 연도 · 필수', '예: 2002', state.birthYearInput, viewModel.changeBirthYear),
        const SizedBox(height: AppSpacing.md),
        _field('키(cm) · 필수', '예: 175', state.heightInput, viewModel.changeHeight),
        const SizedBox(height: AppSpacing.md),
        _field('전화번호 · 필수', '숫자만 입력', state.phoneNumberInput, viewModel.changePhoneNumber),
        const SizedBox(height: AppSpacing.md),
        _genderPicker(),
        if (state.errorMessage != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(state.errorMessage!, style: AppTypography.caption.copyWith(color: AppColors.error)),
        ],
      ],
    );
  }

  Widget _genderPicker() {
    return Wrap(
      spacing: AppSpacing.xs,
      children: [
        ChoiceChip(
          label: const Text('남성'),
          selected: state.gender == 'male',
          onSelected: (_) => viewModel.changeGender('male'),
        ),
        ChoiceChip(
          label: const Text('여성'),
          selected: state.gender == 'female',
          onSelected: (_) => viewModel.changeGender('female'),
        ),
      ],
    );
  }

  Widget _field(String label, String placeholder, String value, ValueChanged<String> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.labelSmall.copyWith(color: AppColors.body)),
        const SizedBox(height: AppSpacing.xs),
        TextFormField(
          initialValue: value,
          onChanged: onChanged,
          decoration: InputDecoration(hintText: placeholder),
        ),
      ],
    );
  }
}
