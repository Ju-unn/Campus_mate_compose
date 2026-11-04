import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/mbti_pole_toggle.dart';
import 'package:campus_mate/common/widgets/onboarding_app_bar.dart';
import 'package:campus_mate/core/back_exit/back_exit_scope.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/me/view/edit_app_bar.dart';
import 'package:campus_mate/me/viewmodel/ideal_conditions_edit_view_model.dart';
import 'package:campus_mate/profile/view/appearance_pickers.dart';
import 'package:campus_mate/profile/view/choice_pickers.dart';
import 'package:campus_mate/profile/view/onboarding_back.dart';
import 'package:campus_mate/profile/viewmodel/ideal_conditions_ui_state.dart';
import 'package:campus_mate/profile/viewmodel/ideal_conditions_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 이상형 조건 화면(DESIGN.md 화면 06-1, datingApp.pen `06-1 이상형 조건`).
/// 순서는 얼굴상 → 인상 → 선호 MBTI → 선호 나이 → 선호 키(§9 7, 2026-09-13 확정) → 흡연하는 사람(앱 1.0.2, pen `dFTqN`).
class IdealConditionsScreen extends ConsumerWidget {
  const IdealConditionsScreen({this.isEditing = false, super.key});

  /// 나 탭 편집 모드(계획서 A5 · D5) — 15-5 프로필 편집의 "이상형 조건 수정" 한 줄(pen `sR3If`)이 연다. 서버 값으로
  /// 채우고, 편집 앱바 "이상형 조건 수정" 과 "저장" 을 쓰고, 저장이 끝나면 15-5 로 돌아간다. 본문은 온보딩과 같다.
  final bool isEditing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final NotifierProvider<IdealConditionsViewModel, IdealConditionsUiState> provider =
        isEditing ? idealConditionsEditViewModelProvider : idealConditionsViewModelProvider;
    final state = ref.watch(provider);
    final viewModel = ref.read(provider.notifier);
    if (isEditing) {
      ref.listen(provider, (previous, next) {
        if (next.completed && !(previous?.completed ?? false)) context.pop();
      });
    }
    // 온보딩 모드만 설문(흡연 문항)으로 돌아간다. 시스템 뒤로도 같다 — 라우터는 이 화면을 두르지 않는다(두 겹이면 안내까지 뜬다).
    // 편집 모드는 push 라 편집 앱바가 평소대로 닫는다.
    final back = isEditing ? null : onboardingBack(ref, isBusy: state.isSubmitting);
    final scaffold = Scaffold(
      appBar: isEditing
          ? const EditAppBar(title: '이상형 조건 수정')
          : OnboardingAppBar(current: 0, total: 3, onBack: back),
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
                    const _SectionTitle('선호하는 얼굴상', hint: '1~3개', titleColor: AppColors.ink),
                    AnimalTypePicker(
                      selected: state.preferredAnimalTypes.toSet(),
                      onTap: viewModel.toggleAnimalType,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    const _SectionTitle('선호하는 인상', hint: '1~3개', titleColor: AppColors.ink),
                    ImpressionTypePicker(
                      selected: state.preferredImpressionTypes.toSet(),
                      onTap: viewModel.toggleImpressionType,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    const _SectionTitle('선호하는 성향 (MBTI)'),
                    MbtiPoleToggle(
                      poles: IdealConditionsUiState.mbtiPoles,
                      selected: {
                        for (final entry in state.preferredMbtiFlags.entries)
                          if (entry.value) entry.key,
                      },
                      onTap: viewModel.toggleMbtiPole,
                    ),
                    // pen 06-1 `QrUdQ` 안내 `MED5L` — 제목 옆이 아니라 칩 묶음 아래 8, 12/normal muted, 한 줄 자동 폭(앱 1.0.1).
                    // 서버는 축마다 따로 봐서 두 극을 다 골라도 그 축은 상관없다.
                    const SizedBox(height: AppSpacing.xs),
                    Text('고르지 않거나 둘 다 고르면 상관없어요.', style: AppTypography.caption.copyWith(color: AppColors.muted)),
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
                    const SizedBox(height: AppSpacing.xl),
                    _SmokingSection(
                      acceptsSmoker: state.acceptsSmoker,
                      onSelected: viewModel.changeAcceptsSmoker,
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: AppSpacing.bottomCta,
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
                  // 편집 모드만 "저장" 과 저장 중 스피너(D8)를 쓴다 — 온보딩 모양은 그대로 둔다.
                  AppButton(
                    label: isEditing ? '저장' : '다음',
                    onPressed: state.canSubmit ? viewModel.submit : null,
                    isLoading: isEditing && state.isSubmitting,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return isEditing ? scaffold : BackExitScope(onBack: back, child: scaffold);
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

/// 섹션 머리줄 — pen `u3Dfkd` · `wOFH0` 등. 가로 한 줄, 양 끝 정렬(space_between), 세로 가운데. 왼쪽이 제목(14/600),
/// 있으면 오른쪽 끝이 안내(12/normal muted). 머리줄과 고르기 칸 사이는 8 이다.
/// 제목 색은 pen 이 섹션마다 다르다 — 얼굴상 · 인상 `AByJi` · `BaCk1` 은 #222222([AppColors.ink]),
/// MBTI `IhhKP` · 나이 `B6MW6` · 키 `T8UoRL` · 흡연 `vCjus` 는 #3F3F3F([AppColors.body], 기본값).
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.hint, this.titleColor = AppColors.body});

  final String title;
  final String? hint;
  final Color titleColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: AppTypography.labelSmall.copyWith(color: titleColor)),
          if (hint != null) Text(hint!, style: AppTypography.caption.copyWith(color: AppColors.muted)),
        ],
      ),
    );
  }
}

/// 흡연하는 사람 섹션(앱 1.0.2, pen Smoking Section `dFTqN`) — 제목 `vCjus` · 두 칸 `Mg9O3` · 설명 `wd83D`, 섹션 안 gap 8.
/// 흡연자에게도 보인다(사용자 결정). 싫어요를 고르면 서버가 흡연하지 않는 분을 먼저 보여 준다.
class _SmokingSection extends StatelessWidget {
  const _SmokingSection({required this.acceptsSmoker, required this.onSelected});

  final bool? acceptsSmoker;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('흡연하는 사람'),
        AcceptsSmokerPicker(acceptsSmoker: acceptsSmoker, onSelected: onSelected),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '싫어요를 고르면 흡연하지 않는 분을 먼저 보여 드려요.',
          style: AppTypography.caption.copyWith(color: AppColors.muted),
        ),
      ],
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
        // 줄이 자기 Material 을 들고 있어야 눌림 효과가 Scaffold 에 그려지지 않는다 — 없으면
        // 스크롤해도 테두리만 제자리에 떠 있다(2026-09-27 실기기, select_chip.dart 와 같은 자리).
        Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: () => onIgnoredChanged(!ignored),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Checkbox(value: ignored, onChanged: (value) => onIgnoredChanged(value ?? false)),
                Text(ignoreLabel, style: AppTypography.bodySmall.copyWith(color: AppColors.body)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
