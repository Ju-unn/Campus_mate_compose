import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/labeled_field.dart';
import 'package:campus_mate/common/widgets/mbti_pole_toggle.dart';
import 'package:campus_mate/common/widgets/onboarding_app_bar.dart';
import 'package:campus_mate/common/widgets/select_chip.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/profile/basic/viewmodel/basic_info_ui_state.dart';
import 'package:campus_mate/profile/basic/viewmodel/basic_info_view_model.dart';
import 'package:campus_mate/profile/basic/viewmodel/phone_verify_ui_state.dart';
import 'package:campus_mate/profile/basic/view/phone_verify_field.dart';
import 'package:campus_mate/core/l10n/error_text.dart';
import 'package:campus_mate/core/l10n/l10n_context.dart';
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

/// 키는 맨 앞 0 도 받지 않는다(2026-11-02 앱 1.0.1) — "017" 처럼 3자리가 되는데 범위 밖인 값을 만들지 않는다.
/// 글자를 지우지 않고 통째로 보고 거절한다(이전 값 유지) — 가운데에 0 을 끼운 "107" 은 맨 앞이 아니라 그대로 받는다.
final heightInputFormatters = <TextInputFormatter>[
  FilteringTextInputFormatter.digitsOnly,
  TextInputFormatter.withFunction((oldValue, newValue) => newValue.text.startsWith('0') ? oldValue : newValue),
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
                    // 보내는 동안 입력칸 · 칩을 잠근다 — 보낸 값과 화면 값이 어긋나지 않게.
                    child: IgnorePointer(
                      ignoring: state.isSubmitting,
                      child: _Form(state: state, viewModel: viewModel),
                    ),
                  ),
                ),
                // 오류는 **스크롤 밖**, 누른 버튼 바로 위다 — 스크롤 맨 아래에 두면 "다음"을 눌러도
                // 화면에 안 보인다(서버 409 닉네임 중복도 여기로 온다).
                if (state.error != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(context.errorText(state.error!), style: AppTypography.caption.copyWith(color: AppColors.error)),
                ],
                const SizedBox(height: AppSpacing.md),
                // 보내는 중(pen 04-1 Button · Loading 추가 예정)에는 글자 자리에 도는 표시 · 누름 막음. 잡혀 있던 입력칸은
                // 먼저 놓는다 — 잠금(IgnorePointer)은 이미 열린 키보드의 입력까지는 못 막는다.
                AppButton(
                  label: context.l10n.commonNext,
                  isLoading: state.isSubmitting,
                  onPressed: state.canSubmit
                      ? () {
                          FocusScope.of(context).unfocus();
                          unawaited(viewModel.submit());
                        }
                      : null,
                ),
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.xl),
        Text(
          context.l10n.profileBasicInfoHeadline,
          style: AppTypography.headline.copyWith(color: AppColors.ink),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          context.l10n.profileBasicInfoSubtitle,
          style: AppTypography.body.copyWith(color: AppColors.body),
        ),
        const SizedBox(height: AppSpacing.xl),
        // 보내는 동안 입력칸을 흐리게 둔다(pen 04-1 저장 중 `g0K1T2` 투명도 0.5) — 누름 막음은 화면의 IgnorePointer 가 한다.
        Opacity(opacity: state.isSubmitting ? 0.5 : 1, child: _inputs(context)),
      ],
    );
  }

  /// 칸 아래 빨간 한 줄. 종류는 상태가 고르고 글자는 문구 파일(ARB)에서 읽는다.
  static String? _errorText(BuildContext context, Failure? failure) => failure == null ? null : context.errorText(failure);

  /// 입력칸 · 성별 · MBTI — 보내는 동안 같이 흐려진다.
  Widget _inputs(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LabeledField(
          // "· 필수" 는 3b 실명 · 3c 학과 · 학번과 같은 표기다. 선택 항목인 내 MBTI 에는 붙이지 않는다.
          label: l10n.profileBasicInfoNicknameLabel,
          initialValue: state.nicknameInput,
          onChanged: viewModel.changeNickname,
          helper: l10n.profileBasicInfoNicknameHelper,
          errorText: _errorText(context, state.nicknameError),
          successText: state.nicknameCheck == NicknameCheck.available ? l10n.profileNicknameAvailable : null,
          pendingText: state.nicknameCheck == NicknameCheck.checking ? l10n.profileNicknameChecking : null,
          inputFormatters: nicknameInputFormatters,
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: LabeledField(
                label: l10n.profileBasicInfoBirthYearLabel,
                placeholder: l10n.profileBasicInfoBirthYearPlaceholder,
                initialValue: state.birthYearInput,
                onChanged: viewModel.changeBirthYear,
                helper: l10n.profileBasicInfoBirthYearHelper,
                errorText: _errorText(context, state.birthYearError),
                keyboardType: TextInputType.number,
                inputFormatters: birthYearInputFormatters,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: LabeledField(
                label: l10n.profileBasicInfoHeightLabel,
                placeholder: l10n.profileBasicInfoHeightPlaceholder,
                initialValue: state.heightInput,
                onChanged: viewModel.changeHeight,
                errorText: _errorText(context, state.heightError),
                keyboardType: TextInputType.number,
                inputFormatters: heightInputFormatters,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        // 휴대폰 문자 인증(pen 2c): 번호 줄(+ 상태 줄) → 보낸 뒤에만 8 → 인증번호 줄. 번호 도움말은 뺐다(사용자 결정 11-11).
        PhoneVerifyField(state: state, viewModel: viewModel),
        if (state.phoneVerify.step == PhoneVerifyStep.codeSent) ...[
          const SizedBox(height: AppSpacing.xs),
          OtpEntryRow(state: state, viewModel: viewModel),
        ],
        // 도움말 없는 덩어리 → 다음 라벨 24: 이 화면에서 도움말 없는 키 칸 상자 바닥 → 「전화번호 · 필수」 가 출생연도 도움말 줄 16.8 +
        // 줄 사이 8 = 24.8 이다. 그 간격을 토큰으로 맞춘다(대장 지시 11-11, pen 은 나중에 맞춘다).
        const SizedBox(height: AppSpacing.lg),
        Text(l10n.profileBasicInfoGenderLabel, style: AppTypography.labelSmall.copyWith(color: AppColors.body)),
        const SizedBox(height: AppSpacing.xs),
        _GenderRow(state: state, viewModel: viewModel),
        const SizedBox(height: 20),
        Text(l10n.profileBasicInfoMbtiLabel, style: AppTypography.labelSmall.copyWith(color: AppColors.body)),
        const SizedBox(height: AppSpacing.xs),
        MbtiPoleToggle(
          selected: state.mbtiPoles,
          onTap: viewModel.toggleMbtiPole,
          unknownLabel: l10n.profileBasicInfoMbtiUnknown,
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
          label: context.l10n.profileBasicInfoGenderMale,
          width: 76,
          radius: AppRadius.pill,
          isSelected: state.gender == 'male',
          onTap: () => viewModel.changeGender('male'),
        ),
        const SizedBox(width: AppSpacing.sm),
        SelectChip(
          label: context.l10n.profileBasicInfoGenderFemale,
          width: 76,
          radius: AppRadius.pill,
          isSelected: state.gender == 'female',
          onTap: () => viewModel.changeGender('female'),
        ),
      ],
    );
  }
}
