import 'package:campus_mate/common/widgets/app_button.dart';
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
typedef _Axis = ({int axis, String headline, String left, String right});

const List<_Axis> _axes = [
  (axis: 1, headline: '쉬는 날, 밖으로 나가야 힘이 나나요?', left: '집콕', right: '밖으로'),
  (axis: 2, headline: '처음 만난 사람과 금방 친해지나요?', left: '낯가림', right: '금방 친해짐'),
  (axis: 3, headline: '약속·일정을 미리 계획하는 편인가요?', left: '즉흥적', right: '계획적'),
  (axis: 4, headline: '연인과 연락은 자주 하고 싶나요?', left: '필요할 때만', right: '자주'),
  (axis: 5, headline: '좋고 싫음을 겉으로 잘 드러내나요?', left: '담백한 편', right: '표현이 풍부'),
  (axis: 6, headline: '술자리를 자주 즐기나요?', left: '거의 안 마셔요', right: '자주 즐겨요'),
  (axis: 7, headline: '평소 운동을 꾸준히 하나요?', left: '거의 안 해요', right: '꾸준히 해요'),
  (axis: 8, headline: '호감이 생기면 빠르게 다가가는 편인가요?', left: '천천히 알아가요', right: '확신하면 빠르게'),
  (axis: 9, headline: '익숙한 것과 새로운 것, 어느 쪽이 편한가요?', left: '익숙한 게 좋아요', right: '새로운 게 좋아요'),
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
      appBar: AppBar(
        toolbarHeight: 56,
        backgroundColor: AppColors.canvas,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: _page == 0 ? null : BackButton(color: AppColors.ink, onPressed: _goBack),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LinearProgressIndicator(
                value: (_page + 1) / _pageCount,
                minHeight: 5,
                backgroundColor: AppColors.hairlineSoft,
                color: AppColors.primary,
              ),
              const SizedBox(height: AppSpacing.xl),
              Expanded(
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
              if (state.errorMessage != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(state.errorMessage!, style: AppTypography.caption.copyWith(color: AppColors.error)),
              ],
              const SizedBox(height: AppSpacing.md),
              AppButton(label: '다음', onPressed: _canAdvance(state) ? _advance : null),
            ],
          ),
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
        Slider(value: value ?? 0, min: -1, max: 1, divisions: 4, onChanged: onChanged),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(axis.left, style: AppTypography.caption.copyWith(color: AppColors.muted)),
            Text(axis.right, style: AppTypography.caption.copyWith(color: AppColors.muted)),
          ],
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
          mainAxisSpacing: AppSpacing.xs,
          crossAxisSpacing: AppSpacing.xs,
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
              const SizedBox(width: AppSpacing.xs),
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

/// 종교·흡연 공통 "칸 선택"(DESIGN.md §8.5 `religion-select`·`smoke-toggle`).
/// 비선택 채움이 `{colors.primary-disabled}` 인 점만 얼굴상 칸과 다르다(2026-09-15 사용자 결정).
class _ChoiceCell extends StatelessWidget {
  const _ChoiceCell({required this.label, required this.isSelected, required this.onTap});

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Ink(
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryWash : AppColors.primaryDisabled,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: isSelected ? AppColors.primary : Colors.transparent),
        ),
        child: Center(
          child: Text(label, style: AppTypography.label.copyWith(color: AppColors.ink)),
        ),
      ),
    );
  }
}
