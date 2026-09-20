import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/mbti_pole_toggle.dart';
import 'package:campus_mate/common/widgets/onboarding_app_bar.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/profile/view/appearance_pickers.dart';
import 'package:campus_mate/profile/viewmodel/ideal_conditions_ui_state.dart';
import 'package:campus_mate/profile/viewmodel/ideal_conditions_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 이상형 조건 화면(DESIGN.md 화면 06-1, datingApp.pen `06-1 이상형 조건`).
/// 순서는 얼굴상 → 인상 → 선호 MBTI → 선호 나이 → 선호 키(§9 7, 2026-09-13 확정).
class IdealConditionsScreen extends ConsumerWidget {
  const IdealConditionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(idealConditionsViewModelProvider);
    final viewModel = ref.read(idealConditionsViewModelProvider.notifier);
    return Scaffold(
      appBar: const OnboardingAppBar(current: 0, total: 3),
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('어떤 사람이 좋아요?', style: AppTypography.headline.copyWith(color: AppColors.ink)),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '얼굴상·인상은 1~3개씩 골라 주세요.',
                    style: AppTypography.body.copyWith(color: AppColors.body),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionTitle('선호하는 얼굴상', hint: '1~3개'),
                    AnimalTypePicker(
                      selected: state.preferredAnimalTypes.toSet(),
                      onTap: viewModel.toggleAnimalType,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    const _SectionTitle('선호하는 인상', hint: '1~3개'),
                    ImpressionTypePicker(
                      selected: state.preferredImpressionTypes.toSet(),
                      onTap: viewModel.toggleImpressionType,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    const _SectionTitle('선호하는 성향 (MBTI)', hint: '선택하지 않으면 상관없어요.'),
                    MbtiPoleToggle(
                      poles: IdealConditionsUiState.mbtiPoles,
                      selected: {
                        for (final entry in state.preferredMbtiFlags.entries)
                          if (entry.value) entry.key,
                      },
                      onTap: viewModel.toggleMbtiPole,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    const _SectionTitle('선호하는 나이 범위'),
                    _RangeField(
                      summary: _ageSummary(state),
                      values: RangeValues(
                        state.preferredAgeMin.toDouble(),
                        state.preferredAgeMax.toDouble(),
                      ),
                      min: IdealConditionsUiState.ageFloor.toDouble(),
                      max: IdealConditionsUiState.ageCeiling.toDouble(),
                      divisions: IdealConditionsUiState.ageCeiling - IdealConditionsUiState.ageFloor,
                      endLabels: const ('19세', '1세 단위', '35세 이상'),
                      ignoreLabel: '나이는 상관없어요',
                      ignored: state.ageIgnored,
                      onChanged: (values) =>
                          viewModel.changeAgeRange(values.start.round(), values.end.round()),
                      onIgnoredChanged: viewModel.changeAgeIgnored,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    const _SectionTitle('선호하는 키 범위'),
                    _RangeField(
                      summary: _heightSummary(state),
                      values: RangeValues(
                        state.preferredHeightMin.toDouble(),
                        state.preferredHeightMax.toDouble(),
                      ),
                      min: IdealConditionsUiState.heightFloor.toDouble(),
                      max: IdealConditionsUiState.heightCeiling.toDouble(),
                      divisions:
                          (IdealConditionsUiState.heightCeiling - IdealConditionsUiState.heightFloor) ~/
                              IdealConditionsUiState.heightStep,
                      endLabels: const ('150cm 이하', '5cm 단위', '190cm 이상'),
                      ignoreLabel: '키는 상관없어요',
                      ignored: state.heightIgnored,
                      onChanged: (values) =>
                          viewModel.changeHeightRange(values.start.round(), values.end.round()),
                      onIgnoredChanged: viewModel.changeHeightIgnored,
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (state.errorMessage != null) ...[
                    Text(
                      state.errorMessage!,
                      style: AppTypography.caption.copyWith(color: AppColors.error),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                  ],
                  AppButton(label: '다음', onPressed: state.canSubmit ? viewModel.submit : null),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 위 끝값은 "이상", 아래 끝값은 "이하"로 읽어준다(DESIGN.md §8.5 프리셋 표기).
  String _ageSummary(IdealConditionsUiState state) {
    final max = state.preferredAgeMax == IdealConditionsUiState.ageCeiling
        ? '${state.preferredAgeMax}세 이상'
        : '${state.preferredAgeMax}세';
    return '${state.preferredAgeMin}세 ~ $max';
  }

  String _heightSummary(IdealConditionsUiState state) {
    final min = state.preferredHeightMin == IdealConditionsUiState.heightFloor
        ? '${state.preferredHeightMin}cm 이하'
        : '${state.preferredHeightMin}cm';
    final max = state.preferredHeightMax == IdealConditionsUiState.heightCeiling
        ? '${state.preferredHeightMax}cm 이상'
        : '${state.preferredHeightMax}cm';
    return '$min ~ $max';
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.hint});

  final String title;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(title, style: AppTypography.labelSmall.copyWith(color: AppColors.body)),
          if (hint != null) ...[
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(hint!, style: AppTypography.caption.copyWith(color: AppColors.muted)),
            ),
          ],
        ],
      ),
    );
  }
}

/// 나이·키 공통 range-slider(DESIGN.md §8.5). "상관없어요"를 켜면 슬라이더가 비활성된다.
class _RangeField extends StatelessWidget {
  const _RangeField({
    required this.summary,
    required this.values,
    required this.min,
    required this.max,
    required this.divisions,
    required this.endLabels,
    required this.ignoreLabel,
    required this.ignored,
    required this.onChanged,
    required this.onIgnoredChanged,
  });

  final String summary;
  final RangeValues values;
  final double min;
  final double max;
  final int divisions;

  /// 슬라이더 아래 왼끝·단위·오른끝 라벨.
  final (String, String, String) endLabels;
  final String ignoreLabel;
  final bool ignored;
  final ValueChanged<RangeValues> onChanged;
  final ValueChanged<bool> onIgnoredChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          summary,
          style: AppTypography.bodyStrong.copyWith(
            color: ignored ? AppColors.disabled : AppColors.ink,
          ),
        ),
        RangeSlider(
          values: values,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: ignored ? null : onChanged,
        ),
        Row(
          children: [
            Text(endLabels.$1, style: AppTypography.caption.copyWith(color: AppColors.muted)),
            Expanded(
              child: Text(
                endLabels.$2,
                textAlign: TextAlign.center,
                style: AppTypography.caption.copyWith(color: AppColors.muted),
              ),
            ),
            Text(endLabels.$3, style: AppTypography.caption.copyWith(color: AppColors.muted)),
          ],
        ),
        InkWell(
          onTap: () => onIgnoredChanged(!ignored),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(value: ignored, onChanged: (value) => onIgnoredChanged(value ?? false)),
              Text(ignoreLabel, style: AppTypography.bodySmall.copyWith(color: AppColors.body)),
            ],
          ),
        ),
      ],
    );
  }
}
