import 'package:campus_mate/common/widgets/onboarding_app_bar.dart';
import 'package:campus_mate/common/widgets/step_marker.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/profile/view/bio_screen.dart';
import 'package:campus_mate/profile/viewmodel/bio_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 자기소개 초안 생성 화면(DESIGN.md 화면 06-2b, datingApp.pen `06-2b 초안 생성`).
/// 초안이 오면 곧바로 06-3 을 그린다 — 라우트를 따로 두지 않는다(§13-70).
class BioDraftLoadingScreen extends ConsumerStatefulWidget {
  const BioDraftLoadingScreen({super.key});

  @override
  ConsumerState<BioDraftLoadingScreen> createState() => _BioDraftLoadingScreenState();
}

class _BioDraftLoadingScreenState extends ConsumerState<BioDraftLoadingScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(bioViewModelProvider.notifier).loadDraft());
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(bioViewModelProvider).draftLoaded) {
      return const BioScreen();
    }
    final viewModel = ref.read(bioViewModelProvider.notifier);
    return Scaffold(
      appBar: const OnboardingAppBar(current: 2, total: 3),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpacing.xl),
              Text('설문을 읽고 있어요', style: AppTypography.headline.copyWith(color: AppColors.ink)),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '답해주신 내용으로 자기소개 초안을 써드릴게요.',
                style: AppTypography.body.copyWith(color: AppColors.body),
              ),
              const SizedBox(height: AppSpacing.xxl),
              const StepMarker(label: '성향 답변 11개 확인', status: StepMarkerStatus.done),
              const SizedBox(height: AppSpacing.sm),
              const StepMarker(label: '관심사·특징 정리 중', status: StepMarkerStatus.active),
              const SizedBox(height: AppSpacing.sm),
              const StepMarker(label: '문장으로 다듬기', status: StepMarkerStatus.wait),
              const Spacer(),
              Center(
                child: TextButton(
                  onPressed: viewModel.skipDraft,
                  child: Text(
                    '직접 쓸게요',
                    style: AppTypography.labelSmall.copyWith(color: AppColors.primaryText),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
