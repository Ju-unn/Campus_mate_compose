import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/profile/view/appearance_pickers.dart';
import 'package:campus_mate/profile/viewmodel/ideal_conditions_ui_state.dart';
import 'package:campus_mate/profile/viewmodel/ideal_conditions_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 이상형 조건 화면(DESIGN.md 화면 06-1).
/// 순서는 얼굴상 → 인상 → 선호 MBTI → 선호 나이 → 선호 키(§9 7, 2026-09-13 확정).
class IdealConditionsScreen extends ConsumerWidget {
  const IdealConditionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(idealConditionsViewModelProvider);
    final viewModel = ref.read(idealConditionsViewModelProvider.notifier);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 56,
        backgroundColor: AppColors.canvas,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        title: Text('어떤 분을 만나고 싶나요?', style: AppTypography.navTitle.copyWith(color: AppColors.ink)),
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
                      const _SectionTitle('어떤 얼굴상이 좋으세요?', hint: '최대 3개, 안 고르면 상관없어요'),
                      AnimalTypePicker(
                        selected: state.preferredAnimalTypes.toSet(),
                        onTap: viewModel.toggleAnimalType,
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      const _SectionTitle('어떤 인상이 좋으세요?', hint: '최대 3개, 안 고르면 상관없어요'),
                      ImpressionTypePicker(
                        selected: state.preferredImpressionTypes.toSet(),
                        onTap: viewModel.toggleImpressionType,
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      const _SectionTitle('선호하는 MBTI가 있나요?', hint: '해당하는 글자만 켜주세요'),
                      _MbtiToggles(
                        flags: state.preferredMbtiFlags,
                        onToggle: viewModel.toggleMbtiPole,
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
                        divisions: (IdealConditionsUiState.heightCeiling -
                                IdealConditionsUiState.heightFloor) ~/
                            IdealConditionsUiState.heightStep,
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
              if (state.errorMessage != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(state.errorMessage!, style: AppTypography.caption.copyWith(color: AppColors.error)),
              ],
              const SizedBox(height: AppSpacing.md),
              AppButton(label: '다음', onPressed: state.canSubmit ? viewModel.submit : null),
            ],
          ),
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
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTypography.title.copyWith(color: AppColors.ink)),
          if (hint != null)
            Text(hint!, style: AppTypography.caption.copyWith(color: AppColors.muted)),
        ],
      ),
    );
  }
}

/// 선호 MBTI 8극 pill 토글(DESIGN.md §8.5 `mbti-toggle`). 체크 아이콘 없이 색만으로 표시한다.
class _MbtiToggles extends StatelessWidget {
  const _MbtiToggles({required this.flags, required this.onToggle});

  final Map<String, bool> flags;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        for (final pole in IdealConditionsUiState.mbtiPoles)
          _MbtiPill(pole: pole, isOn: flags[pole] ?? false, onTap: () => onToggle(pole)),
      ],
    );
  }
}

class _MbtiPill extends StatelessWidget {
  const _MbtiPill({required this.pole, required this.isOn, required this.onTap});

  final String pole;
  final bool isOn;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Ink(
        decoration: BoxDecoration(
          color: isOn ? AppColors.primaryWash : AppColors.surfaceSoft,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: isOn ? AppColors.primary : Colors.transparent),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          child: Text(pole, style: AppTypography.label.copyWith(color: AppColors.ink)),
        ),
      ),
    );
  }
}

/// 나이·키 공통 `range-slider`(DESIGN.md §8.5). "상관없어요"를 켜면 슬라이더가 비활성된다.
class _RangeField extends StatelessWidget {
  const _RangeField({
    required this.summary,
    required this.values,
    required this.min,
    required this.max,
    required this.divisions,
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
