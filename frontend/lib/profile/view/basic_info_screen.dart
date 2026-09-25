import 'package:campus_mate/common/phone_number_formatter.dart';
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
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 한글·영문만 받는다(DESIGN §8.5 `nickname-field`). **자모(ㄱ-ㅎ·ㅏ-ㅣ)까지 허용해야 한다** —
/// 한글 입력기는 조합 중에 자모를 먼저 넣기 때문에 막으면 기기에서 한글 자체를 칠 수 없다.
/// 자모만 남은 값은 보내기 전 [BasicInfoUiState.nicknamePattern] 이 거른다.
/// 글자 수는 여기서 자르지 않는다 — 조합 중인 글자를 잘라 내면 입력기가 꼬인다.
final nicknameInputFormatters = [
  FilteringTextInputFormatter.allow(RegExp(r'[가-힣a-zA-Zㄱ-ㅎㅏ-ㅣ]')),
];

/// 출생연도·키는 숫자만 받고 자릿수에서 끊는다(2026-09-26 사용자 요청).
final birthYearInputFormatters = [
  FilteringTextInputFormatter.digitsOnly,
  LengthLimitingTextInputFormatter(4),
];
final heightInputFormatters = [
  FilteringTextInputFormatter.digitsOnly,
  LengthLimitingTextInputFormatter(3),
];

/// 기본 정보 화면(DESIGN.md 화면 04-1, datingApp.pen `04-1 기본 정보`).
class BasicInfoScreen extends ConsumerWidget {
  const BasicInfoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(basicInfoViewModelProvider);
    final viewModel = ref.read(basicInfoViewModelProvider.notifier);
    return Scaffold(
      appBar: const OnboardingAppBar(current: 0, total: 6),
      // 입력칸 밖 빈 곳을 누르면 키보드를 내린다 — 아래쪽 칸을 채우면 키보드가 "다음" 버튼을 덮는다.
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    // 스크롤을 끌기만 해도 내려간다.
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    child: _Form(state: state, viewModel: viewModel),
                  ),
                ),
                // 오류는 **스크롤 밖**, 누른 버튼 바로 위다 — 스크롤 맨 아래에 두면 "다음"을 눌러도
                // 화면에 안 보인다(서버 409 닉네임 중복도 여기로 온다).
                if (state.errorMessage != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(state.errorMessage!, style: AppTypography.caption.copyWith(color: AppColors.error)),
                ],
                const SizedBox(height: AppSpacing.md),
                AppButton(label: '다음', onPressed: state.canSubmit ? viewModel.submit : null),
              ],
            ),
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

  /// 11자리를 다 채우면 키보드를 내린다 — 마지막 입력칸이라 더 칠 것이 없다.
  void _changePhoneNumber(BuildContext context, String value) {
    viewModel.changePhoneNumber(value);
    if (value.replaceAll(RegExp(r'\D'), '').length == PhoneNumberFormatter.maxDigits) {
      FocusScope.of(context).unfocus();
    }
  }

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
          successText: state.nicknameSuccess,
          pendingText: state.nicknameChecking,
          inputFormatters: nicknameInputFormatters,
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
                helper: '숫자 4자리',
                keyboardType: TextInputType.number,
                inputFormatters: birthYearInputFormatters,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: LabeledField(
                label: '키 (cm)',
                placeholder: '예: 170',
                initialValue: state.heightInput,
                onChanged: viewModel.changeHeight,
                errorText: state.heightError,
                keyboardType: TextInputType.number,
                inputFormatters: heightInputFormatters,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        LabeledField(
          label: '전화번호',
          placeholder: '010-0000-0000',
          initialValue: state.phoneNumberInput,
          onChanged: (value) => _changePhoneNumber(context, value),
          keyboardType: TextInputType.phone,
          inputFormatters: const [PhoneNumberFormatter()],
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
