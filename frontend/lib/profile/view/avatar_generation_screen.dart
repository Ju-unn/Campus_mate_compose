import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/onboarding_app_bar.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/profile/viewmodel/avatar_generation_ui_state.dart';
import 'package:campus_mate/profile/viewmodel/avatar_generation_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 아바타 생성 화면(DESIGN.md 화면 04-3). 진입 즉시 생성을 시작하고, 실패하면 다시 시도,
/// 5회 연속 실패(fallback)면 보상 하트 안내 다이얼로그를 띄운다(project_slice2_decisions_2026-09-19).
class AvatarGenerationScreen extends ConsumerStatefulWidget {
  const AvatarGenerationScreen({super.key});

  @override
  ConsumerState<AvatarGenerationScreen> createState() => _AvatarGenerationScreenState();
}

class _AvatarGenerationScreenState extends ConsumerState<AvatarGenerationScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(avatarGenerationViewModelProvider.notifier).generate());
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(avatarGenerationViewModelProvider, (previous, next) {
      if (next.showCompensationDialog && previous?.showCompensationDialog != true) {
        _showCompensationDialog(next.compensationHearts);
      }
    });
    final state = ref.watch(avatarGenerationViewModelProvider);
    final viewModel = ref.read(avatarGenerationViewModelProvider.notifier);
    return Scaffold(
      // 사진 단계에 딸린 자동 처리라 진행 점은 사진(3번째)에 머문다.
      appBar: const OnboardingAppBar(current: 2, total: 6),
      body: SafeArea(
        child: Center(child: _content(state, viewModel)),
      ),
    );
  }

  Widget _content(AvatarGenerationUiState state, AvatarGenerationViewModel viewModel) {
    if (state.isGenerating) {
      return const _GeneratingIndicator();
    }
    if (state.canRetry) {
      return _RetryPrompt(onRetry: viewModel.generate);
    }
    return const SizedBox.shrink();
  }

  void _showCompensationDialog(int hearts) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text('서버 오류로 하트 $hearts개 드렸어요, 설정 > 아바타 재생성 에서 다시 만들 수 있어요'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('확인')),
        ],
      ),
    );
  }
}

class _GeneratingIndicator extends StatelessWidget {
  const _GeneratingIndicator();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: AppSpacing.md),
        Text('아바타를 만들고 있어요', style: AppTypography.body.copyWith(color: AppColors.body)),
      ],
    );
  }
}

class _RetryPrompt extends StatelessWidget {
  const _RetryPrompt({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('아바타 생성에 실패했어요', style: AppTypography.body.copyWith(color: AppColors.body)),
        const SizedBox(height: AppSpacing.md),
        AppButton(label: '다시 시도', onPressed: onRetry),
      ],
    );
  }
}
