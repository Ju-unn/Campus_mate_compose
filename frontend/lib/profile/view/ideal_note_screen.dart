import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/profile/viewmodel/ideal_note_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// "이런 사람이 좋아요" 화면(DESIGN.md 화면 06-2a, 2026-09-19 신설).
/// 매칭 점수의 절반을 차지하는 자유 글이지만 AI 는 쓰지 않는다 — 쓴 문장을 그대로 임베딩한다.
class IdealNoteScreen extends ConsumerWidget {
  const IdealNoteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(idealNoteViewModelProvider);
    final viewModel = ref.read(idealNoteViewModelProvider.notifier);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 56,
        backgroundColor: AppColors.canvas,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            onPressed: state.isSubmitting ? null : viewModel.skip,
            child: Text('건너뛰기', style: AppTypography.labelSmall.copyWith(color: AppColors.primaryText)),
          ),
        ],
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
                      Text('이런 사람이 좋아요', style: AppTypography.headline.copyWith(color: AppColors.ink)),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '어떤 사람과 잘 맞을지 자유롭게 적어주세요. 적은 만큼 더 잘 맞는 사람을 찾아드려요.',
                        style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      TextFormField(
                        initialValue: state.note,
                        onChanged: viewModel.changeNote,
                        maxLines: 6,
                        decoration: const InputDecoration(
                          hintText: '예) 취미 얘기를 오래 할 수 있는 사람이면 좋겠어요',
                        ),
                      ),
                      if (state.errorMessage != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Text(state.errorMessage!, style: AppTypography.caption.copyWith(color: AppColors.error)),
                      ],
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
