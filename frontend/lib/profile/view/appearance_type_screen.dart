import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/onboarding_app_bar.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/profile/view/appearance_pickers.dart';
import 'package:campus_mate/profile/viewmodel/appearance_type_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 외모 타입 화면(DESIGN.md 화면 04-4, datingApp.pen `04-4 얼굴상`).
/// 얼굴상·인상을 하나씩 고르면 다음으로 넘어간다.
class AppearanceTypeScreen extends ConsumerWidget {
  const AppearanceTypeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appearanceTypeViewModelProvider);
    final viewModel = ref.read(appearanceTypeViewModelProvider.notifier);
    return Scaffold(
      appBar: const OnboardingAppBar(current: 3, total: 6),
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
                  Text('어떤 얼굴상인가요?', style: AppTypography.headline.copyWith(color: AppColors.ink)),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '동물상 하나, 인상 하나를 골라주세요. 매칭에 참고돼요.',
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
                    _SectionLabel('동물상'),
                    AnimalTypePicker(
                      selected: {?state.animalType},
                      onTap: viewModel.changeAnimalType,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _SectionLabel('인상'),
                    ImpressionTypePicker(
                      selected: {?state.impressionType},
                      onTap: viewModel.changeImpressionType,
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
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(label, style: AppTypography.labelSmall.copyWith(color: AppColors.body)),
    );
  }
}
