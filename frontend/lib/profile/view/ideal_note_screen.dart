import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/labeled_field.dart';
import 'package:campus_mate/common/widgets/onboarding_app_bar.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/profile/viewmodel/ideal_note_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// "이런 사람이 좋아요" 자유 글 화면(DESIGN.md 화면 06-2a, datingApp.pen `06-2a 자유 입력`).
/// 2026-09-19 매칭 공식 결정으로 되살아난 화면이다 — AI 는 쓰지 않고 문장 임베딩에만 쓴다.
class IdealNoteScreen extends ConsumerWidget {
  const IdealNoteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(idealNoteViewModelProvider);
    final viewModel = ref.read(idealNoteViewModelProvider.notifier);
    return Scaffold(
      appBar: const OnboardingAppBar(current: 1, total: 3),
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
                        // 서버가 돌려준 오류가 먼저다. 그런 오류가 없을 때만 길이 안내를 보여준다.
                        errorText: state.errorMessage ?? state.lengthMessage,
                        maxLines: 6,
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
