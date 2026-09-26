import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/onboarding_app_bar.dart';
import 'package:campus_mate/common/widgets/trait_slider.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/profile/model/profile_enums.dart';
import 'package:campus_mate/profile/viewmodel/survey_ui_state.dart';
import 'package:campus_mate/profile/viewmodel/survey_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 성향 설문 문항(DESIGN.md §8.5 "성향 설문 슬라이더 문항 카피", 9축 × 1회).
/// 문구는 datingApp.pen 05-01~05-09 를 따른다(2026-09-20 사용자 결정 C1).
typedef _Axis = ({int axis, String headline, String left, String right});

/// 줄바꿈 자리도 pen 값이다(05-01~05-09, erd3 2026-09-26) — 기기 폭에 맡기면 두 줄이 어디서 끊길지
/// 매번 달라져서, 짧은 질문이 한 줄로 붙고 긴 질문만 두 줄이 된다.
const List<_Axis> _axes = [
  (axis: 1, headline: '밖에 나가서 활동하는 걸\n좋아하시나요?', left: '집이 편해요', right: '밖이 좋아요'),
  (axis: 2, headline: '낯선 사람과 빨리\n친해지는 편인가요?', left: '낯을 많이 가려요', right: '금방 친해져요'),
  (axis: 3, headline: '미리 계획을\n세우는 편인가요?', left: '즉흥적이에요', right: '계획적이에요'),
  (axis: 4, headline: '연애할 때 연락을\n자주 하는 편인가요?', left: '필요할 때만 해요', right: '자주 연락해요'),
  (axis: 5, headline: '감정 표현이\n풍부한 편인가요?', left: '담백해요', right: '표현이 풍부해요'),
  (axis: 6, headline: '술자리를\n즐기는 편인가요?', left: '거의 안 마셔요', right: '자주 즐겨요'),
  (axis: 7, headline: '운동을 꾸준히\n하는 편인가요?', left: '관심 없어요', right: '꾸준히 해요'),
  (axis: 8, headline: '마음이 확실하면 관계를\n빠르게 진전시키나요?', left: '천천히요', right: '빠르게요'),
  (axis: 9, headline: '새로운 걸 시도하는 걸\n좋아하시나요?', left: '익숙한 게 편해요', right: '새로운 걸 찾아요'),
];

/// 9축 + 종교 + 흡연 = 11화면(DESIGN.md 화면 05-01~05-11).
const int _axisCount = 9;
const int _pageCount = _axisCount + 2;
const int _religionPage = _axisCount;
const int _smokePage = _axisCount + 1;

/// 성향 설문 화면(DESIGN.md 화면 05-01~05-11).
/// 11화면을 라우트로 쪼개지 않고 `PageView` 하나로 넘긴다 — 서버가 세는 단계는 설문 전체 1개다.
class SurveyScreen extends ConsumerStatefulWidget {
  const SurveyScreen({super.key});

  @override
  ConsumerState<SurveyScreen> createState() => _SurveyScreenState();
}

class _SurveyScreenState extends ConsumerState<SurveyScreen> {
  final PageController _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    assert(_axes.length == _axisCount, '축 문항 수와 페이지 번호 계산이 어긋났다');
    final state = ref.watch(surveyViewModelProvider);
    final viewModel = ref.read(surveyViewModelProvider.notifier);
    return Scaffold(
      appBar: OnboardingAppBar(
        current: _page,
        total: _pageCount,
        isBar: true,
        onBack: _page == 0 ? null : _goBack,
      ),
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Padding(
                // 디자인 파일이 질문을 앱바에서 116 아래에 둔다.
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 116, AppSpacing.lg, 0),
                child: PageView(
                  controller: _controller,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (page) => setState(() => _page = page),
                  children: [
                    for (final axis in _axes)
                      _TraitSliderPage(
                        axis: axis,
                        value: state.answers[axis.axis],
                        onChanged: (value) => viewModel.answer(axis.axis, value),
                      ),
                    _ReligionPage(selected: state.religion, onSelected: viewModel.changeReligion),
                    _SmokePage(isSmoker: state.isSmoker, onSelected: viewModel.changeIsSmoker),
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
                  AppButton(label: '다음', onPressed: _canAdvance(state) ? _advance : null),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 값을 고르기 전까지 "다음"은 비활성이다(DESIGN.md §8.5 — 기본 선택값 없음).
  bool _canAdvance(SurveyUiState state) {
    if (state.isSubmitting) {
      return false;
    }
    return switch (_page) {
      _religionPage => state.religion != null,
      _smokePage => state.canSubmit,
      final page => state.answers.containsKey(_axes[page].axis),
    };
  }

  void _advance() {
    if (_page == _smokePage) {
      ref.read(surveyViewModelProvider.notifier).submit();
      return;
    }
    _controller.nextPage(duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
  }

  void _goBack() {
    _controller.previousPage(duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
  }
}

class _TraitSliderPage extends StatelessWidget {
  const _TraitSliderPage({required this.axis, required this.value, required this.onChanged});

  final _Axis axis;
  final double? value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(axis.headline, style: AppTypography.headline.copyWith(color: AppColors.ink)),
        const SizedBox(height: AppSpacing.xxl),
        // 5단계 -1/-0.5/0/0.5/1 (설계 문서 §6.2). 숫자는 노출하지 않는다.
        TraitSlider(
          value: value,
          onChanged: onChanged,
          leftLabel: axis.left,
          rightLabel: axis.right,
        ),
      ],
    );
  }
}

class _ReligionPage extends StatelessWidget {
  const _ReligionPage({required this.selected, required this.onSelected});

  final Religion? selected;
  final ValueChanged<Religion> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('종교가 있으신가요?', style: AppTypography.headline.copyWith(color: AppColors.ink)),
        const SizedBox(height: AppSpacing.xl),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: AppSpacing.sm,
          crossAxisSpacing: AppSpacing.sm,
          mainAxisExtent: 56,
          children: [
            for (final religion in Religion.values)
              _ChoiceCell(
                label: religion.label,
                isSelected: selected == religion,
                onTap: () => onSelected(religion),
              ),
          ],
        ),
      ],
    );
  }
}

class _SmokePage extends StatelessWidget {
  const _SmokePage({required this.isSmoker, required this.onSelected});

  final bool? isSmoker;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('담배를 피우시나요?', style: AppTypography.headline.copyWith(color: AppColors.ink)),
        const SizedBox(height: AppSpacing.xl),
        SizedBox(
          height: 56,
          child: Row(
            children: [
              Expanded(
                child: _ChoiceCell(
                  label: '한다',
                  isSelected: isSmoker == true,
                  onTap: () => onSelected(true),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _ChoiceCell(
                  label: '안 한다',
                  isSelected: isSmoker == false,
                  onTap: () => onSelected(false),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 종교·흡연 공통 "칸 선택"(DESIGN.md §8.5 religion-select·smoke-toggle).
/// 비선택 채움은 표면 회색이다(pen `Rmfti`·`Y1TDq2` 2026-09-26 수정) —
/// 종전 `primaryDisabled`(#E5E5E5)는 **비활성 채움** 토큰이라, 고를 수 있는 칸이 꺼진 버튼처럼 보였다.
class _ChoiceCell extends StatelessWidget {
  const _ChoiceCell({required this.label, required this.isSelected, required this.onTap});

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 칸이 자기 Material 을 들고 있어야 채움이 Scaffold 에 칠해지지 않는다(select_chip.dart 와 같다).
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Ink(
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primaryWash : AppColors.surfaceSoft,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: isSelected ? AppColors.primary : Colors.transparent),
          ),
          child: Center(
            child: Text(label, style: AppTypography.label.copyWith(color: AppColors.ink)),
          ),
        ),
      ),
    );
  }
}
