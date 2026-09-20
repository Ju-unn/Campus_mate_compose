import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/profile/view/appearance_pickers.dart';
import 'package:campus_mate/profile/viewmodel/appearance_type_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 외모 타입 화면(DESIGN.md 화면 04-4). 얼굴상·인상을 하나씩 고르면 다음으로 넘어간다.
class AppearanceTypeScreen extends ConsumerWidget {
  const AppearanceTypeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appearanceTypeViewModelProvider);
    final viewModel = ref.read(appearanceTypeViewModelProvider.notifier);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 56,
        backgroundColor: AppColors.canvas,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        title: Text('외모 타입', style: AppTypography.navTitle.copyWith(color: AppColors.ink)),
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
                      Text(
                        '본인과 가장 닮은 동물상을 골라주세요.',
                        style: AppTypography.headline.copyWith(color: AppColors.ink),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      AnimalTypePicker(
                        selected: {?state.animalType},
                        onTap: viewModel.changeAnimalType,
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      Text(
                        '어떤 인상이라는 말을 자주 듣나요?',
                        style: AppTypography.headline.copyWith(color: AppColors.ink),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      ImpressionTypePicker(
                        selected: {?state.impressionType},
                        onTap: viewModel.changeImpressionType,
                      ),
                    ],
                  ),
                ),
              ),
              if (state.errorMessage != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  state.errorMessage!,
                  style: AppTypography.caption.copyWith(color: AppColors.error),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              AppButton(label: '다음', onPressed: state.canSubmit ? viewModel.submit : null),
            ],
          ),
        ),
      ),
    );
  }
}
