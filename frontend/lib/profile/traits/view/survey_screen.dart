import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/onboarding_app_bar.dart';
import 'package:campus_mate/common/widgets/trait_slider.dart';
import 'package:campus_mate/core/back_exit/back_exit_scope.dart';
import 'package:campus_mate/core/l10n/error_text.dart';
import 'package:campus_mate/core/l10n/l10n_context.dart';
import 'package:campus_mate/core/router/onboarding_step_listenable_provider.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:campus_mate/profile/onboarding/model/data/profile_enums.dart';
import 'package:campus_mate/profile/onboarding/view/onboarding_back.dart';
import 'package:campus_mate/profile/traits/view/choice_pickers.dart';
import 'package:campus_mate/profile/traits/viewmodel/survey_ui_state.dart';
import 'package:campus_mate/profile/traits/viewmodel/survey_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 성향 설문 문항(DESIGN.md §8.5 "성향 설문 슬라이더 문항 카피", 9축 × 1회).
/// 문구는 datingApp.pen 05-01~05-09 를 따른다(2026-09-20 사용자 결정 C1).
typedef _Axis = ({int axis, String headline, String left, String right});

/// 줄바꿈 자리도 pen 값이다(05-01~05-09, erd3 2026-09-26) — 기기 폭에 맡기면 두 줄이 어디서 끊길지
/// 매번 달라져서, 짧은 질문이 한 줄로 붙고 긴 질문만 두 줄이 된다. 글자는 문구 파일에 있고, 서버로는 축 번호와 값만 간다.
List<_Axis> _axes(AppLocalizations l10n) => [
      (axis: 1, headline: l10n.profileSurveyAxis1Question, left: l10n.profileSurveyAxis1Left, right: l10n.profileSurveyAxis1Right),
      (axis: 2, headline: l10n.profileSurveyAxis2Question, left: l10n.profileSurveyAxis2Left, right: l10n.profileSurveyAxis2Right),
      (axis: 3, headline: l10n.profileSurveyAxis3Question, left: l10n.profileSurveyAxis3Left, right: l10n.profileSurveyAxis3Right),
      (axis: 4, headline: l10n.profileSurveyAxis4Question, left: l10n.profileSurveyAxis4Left, right: l10n.profileSurveyAxis4Right),
      (axis: 5, headline: l10n.profileSurveyAxis5Question, left: l10n.profileSurveyAxis5Left, right: l10n.profileSurveyAxis5Right),
      (axis: 6, headline: l10n.profileSurveyAxis6Question, left: l10n.profileSurveyAxis6Left, right: l10n.profileSurveyAxis6Right),
      (axis: 7, headline: l10n.profileSurveyAxis7Question, left: l10n.profileSurveyAxis7Left, right: l10n.profileSurveyAxis7Right),
      (axis: 8, headline: l10n.profileSurveyAxis8Question, left: l10n.profileSurveyAxis8Left, right: l10n.profileSurveyAxis8Right),
      (axis: 9, headline: l10n.profileSurveyAxis9Question, left: l10n.profileSurveyAxis9Left, right: l10n.profileSurveyAxis9Right),
    ];

/// 9축 + 종교 + 흡연 = 11화면(DESIGN.md 화면 05-01~05-11).
/// 축 개수는 뷰모델이 들고 있는 하나만 본다 — 화면에서 또 세면 둘이 어긋난 걸 아무도 못 본다.
const int _pageCount = SurveyUiState.axisCount + 2;
const int _religionPage = SurveyUiState.axisCount;
const int _smokePage = SurveyUiState.axisCount + 1;

/// 성향 설문 화면(DESIGN.md 화면 05-01~05-11).
/// 11화면을 라우트로 쪼개지 않고 `PageView` 하나로 넘긴다 — 서버가 세는 단계는 설문 전체 1개다.
class SurveyScreen extends ConsumerStatefulWidget {
  const SurveyScreen({super.key});

  @override
  ConsumerState<SurveyScreen> createState() => _SurveyScreenState();
}

class _SurveyScreenState extends ConsumerState<SurveyScreen> {
  late int _page = _openingPage();
  late final PageController _controller = PageController(initialPage: _page);

  /// 06-1 에서 돌아왔고 11문항이 다 골라져 있으면 마지막(흡연) 문항에서 연다 — "다음" 한 번이면 다시 저장된다.
  /// 고칠 문항은 앱바 뒤로로 한 문항씩 찾아간다. 처음 설문이거나 빈 답이 있으면 첫 문항이다.
  int _openingPage() {
    final revisiting = ref.read(onboardingStepListenableProvider).isRevisiting;
    return revisiting && ref.read(surveyViewModelProvider).isFilled ? _smokePage : 0;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    assert(_axes(context.l10n).length == SurveyUiState.axisCount, '축 문항 수와 페이지 번호 계산이 어긋났다');
    final state = ref.watch(surveyViewModelProvider);
    final viewModel = ref.read(surveyViewModelProvider.notifier);
    // 첫 문항은 앞 단계(04-6)로, 나머지는 이전 문항으로 간다. 저장 중에는 눌러도 아무 일이 없다
    // (화살표는 숨기지 않는다 — 숨기면 깜빡인다).
    final goBack = _page == 0
        ? onboardingBack(ref, isBusy: state.isSubmitting)
        : (state.isSubmitting ? () {} : _goBack);
    // 안드로이드 시스템 뒤로가기는 앱바 화살표와 같다. 라우터는 이 화면을 두르지 않는다 — 두 겹이면 같은 뒤로가기에 안내까지 뜬다.
    return BackExitScope(
      onBack: goBack,
      child: _scaffold(state, viewModel, goBack),
    );
  }

  Widget _scaffold(SurveyUiState state, SurveyViewModel viewModel, VoidCallback? goBack) {
    return Scaffold(
      appBar: OnboardingAppBar(
        current: _page,
        total: _pageCount,
        isBar: true,
        onBack: goBack,
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
                    for (final axis in _axes(context.l10n))
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
              padding: AppSpacing.bottomCta,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (state.error != null) ...[
                    Text(
                      context.errorText(state.error!),
                      style: AppTypography.caption.copyWith(color: AppColors.error),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                  ],
                  AppButton(label: context.l10n.commonNext, onPressed: _canAdvance(state) ? _advance : null),
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
      final page => state.answers.containsKey(_axes(context.l10n)[page].axis),
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
        Text(context.l10n.profileSurveyReligionQuestion, style: AppTypography.headline.copyWith(color: AppColors.ink)),
        const SizedBox(height: AppSpacing.xl),
        ReligionPicker(selected: selected, onSelected: onSelected),
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
        Text(context.l10n.profileSurveySmokeQuestion, style: AppTypography.headline.copyWith(color: AppColors.ink)),
        const SizedBox(height: AppSpacing.xl),
        SmokePicker(isSmoker: isSmoker, onSelected: onSelected),
      ],
    );
  }
}
