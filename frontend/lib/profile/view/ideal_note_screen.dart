import 'package:campus_mate/chat/view/chat_input_bar.dart';
import 'package:campus_mate/common/line_break_limit_formatter.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/labeled_field.dart';
import 'package:campus_mate/common/widgets/onboarding_app_bar.dart';
import 'package:campus_mate/core/back_exit/back_exit_scope.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/profile/model/ideal_note_repository.dart';
import 'package:campus_mate/profile/view/onboarding_back.dart';
import 'package:campus_mate/profile/view/writing_example.dart';
import 'package:campus_mate/profile/viewmodel/ideal_note_ui_state.dart';
import 'package:campus_mate/profile/viewmodel/ideal_note_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 6줄 · 300자. 줄 상한이 먼저다. 카운터 · 상한 안내는 없다(pen `dIONW` · `vMxds` · `fGKgO` 에 없다).
final _noteInputFormatters = [
  lineBreakLimitFormatter(idealNoteMaxLines),
  codePointLimitFormatter(idealNoteMaxLength),
];

/// "이런 사람이 좋아요" 자유 글 화면(DESIGN.md 화면 06-2a, datingApp.pen `06-2a 자유 입력`).
/// 2026-09-19 매칭 공식 결정으로 되살아난 화면이다 — AI 는 쓰지 않고 문장 임베딩에만 쓴다.
class IdealNoteScreen extends ConsumerWidget {
  const IdealNoteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(idealNoteViewModelProvider);
    final viewModel = ref.read(idealNoteViewModelProvider.notifier);
    // 06-2 로 돌아간다. 시스템 뒤로도 같다 — 라우터는 이 화면을 두르지 않는다(두 겹이면 안내까지 뜬다).
    final back = onboardingBack(ref, isBusy: state.isSubmitting);
    return BackExitScope(onBack: back, child: _scaffold(state, viewModel, back));
  }

  Widget _scaffold(IdealNoteUiState state, IdealNoteViewModel viewModel, VoidCallback? back) {
    return Scaffold(
      appBar: OnboardingAppBar(current: 1, total: 3, onBack: back),
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
                      Text(
                        '이런 사람이 좋아요를\n자유롭게 적어주세요',
                        style: AppTypography.headline.copyWith(color: AppColors.ink),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '10자 이상 자유롭게 적어주세요',
                        style: AppTypography.body.copyWith(color: AppColors.body),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      LabeledField(
                        label: '이런 사람이 좋아요',
                        placeholder: '말이 잘 통하는 사람이 좋아요',
                        initialValue: state.note,
                        onChanged: viewModel.changeNote,
                        // 오류(짧은 채로 "다음" 또는 서버 오류)가 있으면 같은 자리의 회색 안내 대신 오류가 나온다.
                        errorText: state.errorMessage,
                        guideText: state.lengthMessage,
                        inputFormatters: _noteInputFormatters,
                        maxLines: idealNoteMaxLines,
                      ),
                      // 작성 예시(사용자 요청 10-15, 대장 전달 값 — 입력칸 아래 32). 키보드가 올라오면 Scaffold 가 본문을 줄이고
                      // 이 스크롤이 쓰는 칸을 키보드 위로 올린다 — 예시는 그 아래로 밀린다.
                      const SizedBox(height: AppSpacing.xl),
                      const WritingExample(
                        sentences: [
                          '말이 잘 통하고 주말에 같이 산책하거나 맛집 가는 걸 좋아하는 사람이면 좋겠어요',
                          '연락을 자주 하고 약속을 잘 지키는 사람이 좋아요',
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppButton(label: '다음', onPressed: state.canSubmit ? viewModel.submit : null),
            ],
          ),
        ),
      ),
    );
  }
}
