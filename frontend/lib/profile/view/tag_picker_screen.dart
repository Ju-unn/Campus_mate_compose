import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/onboarding_app_bar.dart';
import 'package:campus_mate/common/widgets/select_chip.dart';
import 'package:campus_mate/common/widgets/select_count_bar.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/profile/viewmodel/tag_picker_kind.dart';
import 'package:campus_mate/profile/viewmodel/tag_picker_ui_state.dart';
import 'package:campus_mate/profile/viewmodel/tag_picker_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 관심사(04-5)·나의 특징(04-6)·이상형 특징(06-2) 공용 화면.
class TagPickerScreen extends ConsumerWidget {
  const TagPickerScreen({required this.kind, super.key});

  final TagPickerKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(tagPickerViewModelProvider(kind));
    final viewModel = ref.read(tagPickerViewModelProvider(kind).notifier);
    return Scaffold(
      appBar: OnboardingAppBar(current: kind.dotIndex, total: kind.dotTotal),
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
                  Text(kind.headline, style: AppTypography.headline.copyWith(color: AppColors.ink)),
                  const SizedBox(height: AppSpacing.xs),
                  Text(kind.subtext, style: AppTypography.body.copyWith(color: AppColors.body)),
                ],
              ),
            ),
            Expanded(child: _TagSection(kind: kind, state: state, onToggle: viewModel.toggle)),
            _Footer(state: state, onSubmit: viewModel.submit),
          ],
        ),
      ),
    );
  }
}

class _TagSection extends StatelessWidget {
  const _TagSection({required this.kind, required this.state, required this.onToggle});

  final TagPickerKind kind;
  final TagPickerUiState state;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(kind.tagLabel, style: AppTypography.labelSmall.copyWith(color: AppColors.body)),
          const SizedBox(height: AppSpacing.xs),
          // pen 은 그리드가 아니다 — 칩이 글자 폭만큼 넓어지고 한 줄에 들어가는 만큼 놓인다
          // (erd3 실측 2026-09-26: 04-5 는 한 줄에 4·3·2개가 섞인다). 그게 `Wrap` 의 동작이다.
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final tag in kind.pool)
                SelectChip(
                  label: tag,
                  // 태그 칩은 pen 마스터 `WzXvK` 값이다 — 높이 36(여백 8×2 + 줄 20), 좌우 12.
                  // `SelectChip` 기본값 35 는 04-1 Chip 값이라 그대로 둔다.
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  isSelected: state.selected.contains(tag),
                  onTap: () => onToggle(tag),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.state, required this.onSubmit});

  final TagPickerUiState state;
  final Future<void> Function() onSubmit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SelectCountBar(selected: state.selected.length, max: 5, min: 3),
          if (state.errorMessage != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(state.errorMessage!, style: AppTypography.caption.copyWith(color: AppColors.error)),
          ],
          const SizedBox(height: AppSpacing.sm),
          AppButton(label: '다음', onPressed: state.canSubmit ? onSubmit : null),
        ],
      ),
    );
  }
}
