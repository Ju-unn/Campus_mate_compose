import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/labeled_field.dart';
import 'package:campus_mate/common/widgets/onboarding_app_bar.dart';
import 'package:campus_mate/common/widgets/select_chip.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/profile/model/profile_enums.dart';
import 'package:campus_mate/profile/viewmodel/acquisition_ui_state.dart';
import 'package:campus_mate/profile/viewmodel/acquisition_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// 화면 문구 — pen uPNnZ(2026-09-28 값표).
const _headline = 'CampusMate를 어떻게 알게 되셨나요?'; // pen CmStT
const _subtitle = '하나만 골라주세요.\n더 많은 학교에 알리는 데 참고할게요.'; // pen BX9US
const _startLabel = '시작하기'; // pen k4ym5O
const _skipLabel = '건너뛰기'; // pen k8Mb37
const _otherLabel = '어디서 알게 되셨나요?'; // pen s8u4Y (힌트 · 글자 수 표시 없음)

// 토큰에 없는 pen 값.
const _skipPadding = EdgeInsets.symmetric(horizontal: 12); // pen k8Mb37 76×48 padding [0,12]
const _skipHeight = 48.0; // pen k8Mb37
const _chipHeight = 36.0; // pen lVe24 · 마스터 WzXvK
const _chipPadding = EdgeInsets.symmetric(horizontal: 12); // pen WzXvK padding [8,12]

/// 유입경로 화면(DESIGN.md 화면 20d). 저장하거나 건너뛰면 가입 마지막 화면 06-4 지인 차단으로 간다(결정 8 ①).
/// 서버 온보딩 단계가 아니라 앱에서만 잇는다(2026-09-28 대장 D2).
class AcquisitionScreen extends ConsumerWidget {
  const AcquisitionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(acquisitionViewModelProvider.select((s) => s.completed), (previous, completed) {
      if (completed) {
        context.go(AppRoutes.onboardingContactBlock);
      }
    });
    final state = ref.watch(acquisitionViewModelProvider);
    final viewModel = ref.read(acquisitionViewModelProvider.notifier);
    return Scaffold(
      // pen qcQvZ: 뒤로(LoyFK) · 가운데 빈 자리(O7JBZ — 진행 점 없음) · 건너뛰기(k8Mb37, 바탕 없는 일반 button-text).
      // 뒤로는 앞 화면 20 으로 간다 — go 로 들어와 쌓인 화면이 없어 onBack 을 준다.
      appBar: OnboardingAppBar(
        current: 0,
        total: 0,
        onBack: () => context.go(AppRoutes.onboardingReferral),
        action: TextButton(
          onPressed: () => context.go(AppRoutes.onboardingContactBlock),
          style: TextButton.styleFrom(padding: _skipPadding, minimumSize: const Size(0, _skipHeight)),
          child: Text(_skipLabel, style: AppTypography.labelSmall.copyWith(color: AppColors.primaryText)),
        ),
      ),
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
                      Text(_headline, style: AppTypography.headline.copyWith(color: AppColors.ink)),
                      const SizedBox(height: AppSpacing.xs),
                      Text(_subtitle, style: AppTypography.body.copyWith(color: AppColors.body)),
                      const SizedBox(height: AppSpacing.xl),
                      _ChannelChips(selected: state.channel, onSelect: viewModel.select),
                      if (state.isOther) ...[
                        const SizedBox(height: AppSpacing.md), // pen 칩 끝 y272 → 입력 y288
                        LabeledField(
                          label: _otherLabel,
                          initialValue: state.note,
                          onChanged: viewModel.changeNote,
                          inputFormatters: [LengthLimitingTextInputFormatter(acquisitionNoteMaxLength)],
                        ),
                      ],
                      // 저장 실패 문구 — pen uPNnZ 에 없는 상태라 가안(칩 · 입력칸 아래 빨간 한 줄). 결정 필요로 보고.
                      if (state.errorMessage != null) ...[
                        const SizedBox(height: AppSpacing.md),
                        Text(state.errorMessage!, style: AppTypography.caption.copyWith(color: AppColors.error)),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppButton(label: _startLabel, onPressed: state.canSubmit ? viewModel.submit : null),
            ],
          ),
        ),
      ),
    );
  }
}

/// 단일 선택 `tag-chip` 5개(pen lVe24, 마스터 WzXvK — 높이 36 · 좌우 12 · 모서리 8 · 가로세로 간격 8).
/// pen 은 칩 폭을 89 · 89 · 80 · 76 · 50 으로 적었지만 글자 폭 + 좌우 12 라서 폭을 고정하지 않는다 —
/// 글자를 키우면 칩이 따라 넓어지고 `Wrap` 이 줄을 바꾼다(360 폭에서 pen 과 같이 3 · 2 로 나뉜다).
class _ChannelChips extends StatelessWidget {
  const _ChannelChips({required this.selected, required this.onSelect});

  final AcquisitionChannel? selected;
  final ValueChanged<AcquisitionChannel> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        for (final channel in AcquisitionChannel.values)
          SelectChip(
            label: channel.label,
            height: _chipHeight,
            padding: _chipPadding,
            isSelected: channel == selected,
            onTap: () => onSelect(channel),
          ),
      ],
    );
  }
}
