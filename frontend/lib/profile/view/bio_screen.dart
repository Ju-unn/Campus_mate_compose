import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/labeled_field.dart';
import 'package:campus_mate/common/widgets/onboarding_app_bar.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/profile/viewmodel/bio_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 자기소개 화면(DESIGN.md 화면 06-3, datingApp.pen `06-3 자기소개`).
/// 06-2b 가 받아 온 초안이 placeholder 가 아니라 실제 입력값으로 들어와 있다(§13-71).
/// "다시 만들기" 버튼은 없다(2026-09-13 사용자 결정, §13-79).
class BioScreen extends ConsumerStatefulWidget {
  const BioScreen({super.key});

  @override
  ConsumerState<BioScreen> createState() => _BioScreenState();
}

class _BioScreenState extends ConsumerState<BioScreen> {
  late final TextEditingController _controller =
      TextEditingController(text: ref.read(bioViewModelProvider).bio);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(bioViewModelProvider);
    final viewModel = ref.read(bioViewModelProvider.notifier);
    return Scaffold(
      appBar: const OnboardingAppBar(current: 2, total: 3),
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
                        '이렇게 소개해볼까요?',
                        style: AppTypography.headline.copyWith(color: AppColors.ink),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '설문을 바탕으로 초안을 썼어요. 마음에 안 들면 자유롭게 고쳐주세요.',
                        style: AppTypography.body.copyWith(color: AppColors.body),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      LabeledField(
                        label: '자기소개',
                        placeholder: '나를 한두 문장으로 소개해주세요',
                        controller: _controller,
                        onChanged: viewModel.changeBio,
                        errorText: state.errorMessage,
                        maxLines: 8,
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
