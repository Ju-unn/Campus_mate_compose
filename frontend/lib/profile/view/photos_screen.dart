import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/onboarding_app_bar.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/profile/viewmodel/photos_ui_state.dart';
import 'package:campus_mate/profile/viewmodel/photos_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 사진 업로드 화면(DESIGN.md 화면 04-2, datingApp.pen `F5DPI`).
/// 최소 2장·최대 4장을 고르기만 하고, 올리기는 다음 화면 04-3 에서 아바타 원본을 정한 뒤 한 번에 한다
/// (2026-09-23 사용자 결정 — 2026-09-20 C2 의 "한 화면으로 합치기"를 되돌림).
class PhotosScreen extends ConsumerStatefulWidget {
  const PhotosScreen({super.key});

  @override
  ConsumerState<PhotosScreen> createState() => _PhotosScreenState();
}

class _PhotosScreenState extends ConsumerState<PhotosScreen> {
  /// 04-3 으로 넘어가는 중. **빠르게 두 번 누르면 04-3 이 두 장 쌓인다** —
  /// 돌아올 때까지 버튼을 꺼 둔다.
  bool _isLeaving = false;

  Future<void> _goToAvatarSource() async {
    setState(() => _isLeaving = true);
    ref.read(photosViewModelProvider.notifier).prepareAvatarSource();
    await context.push<void>(AppRoutes.onboardingAvatarSource);
    if (mounted) {
      setState(() => _isLeaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(photosViewModelProvider);
    final viewModel = ref.read(photosViewModelProvider.notifier);
    return Scaffold(
      appBar: const OnboardingAppBar(current: 1, total: 6),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 사진 칸이 158 고정이라 작은 기기·큰 글씨에서는 위쪽이 넘친다.
              // 넘치는 쪽을 스크롤로 내주고 버튼은 늘 바닥에 남긴다(3b 와 같은 얼개).
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: AppSpacing.lg),
                      Text('실제 사진을 올려주세요',
                          style: AppTypography.headline.copyWith(color: AppColors.ink)),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '얼굴이 잘 보이는 사진을 2~4장 골라주세요.',
                        style: AppTypography.body.copyWith(color: AppColors.body, height: 1.6),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      _PhotoGrid(state: state, viewModel: viewModel),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        '갤러리에서 여러 장을 한 번에 고를 수 있어요. 최소 2장이 필요해요.',
                        style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
                      ),
                      if (state.errorMessage != null) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(state.errorMessage!,
                            style: AppTypography.caption.copyWith(color: AppColors.error)),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppButton(
                label: '다음',
                onPressed: state.canProceed && !_isLeaving ? _goToAvatarSource : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 2×2 네 칸이 늘 보인다. 빈칸은 모두 "사진 추가" 칸이다.
class _PhotoGrid extends StatelessWidget {
  const _PhotoGrid({required this.state, required this.viewModel});

  final PhotosUiState state;
  final PhotosViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    Widget slot(int index) => index < state.photos.length
        ? _PhotoTile(index: index, state: state, viewModel: viewModel)
        : _AddPhotoTile(onTap: viewModel.addPhoto);
    return Column(
      children: [
        for (var row = 0; row < 2; row++) ...[
          if (row > 0) const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: 158,
            child: Row(
              children: [
                Expanded(child: slot(row * 2)),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: slot(row * 2 + 1)),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.index, required this.state, required this.viewModel});

  final int index;
  final PhotosUiState state;
  final PhotosViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Stack(
        children: [
          Positioned.fill(child: Image.file(state.photos[index].file, fit: BoxFit.cover)),
          if (index == 0)
            Positioned(
              left: AppSpacing.xs,
              top: AppSpacing.xs,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
                decoration: BoxDecoration(
                  color: AppColors.surfaceInk,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text('대표', style: AppTypography.badge.copyWith(color: AppColors.onInk)),
              ),
            ),
          Positioned(
            right: 0,
            top: 0,
            child: Semantics(
              button: true,
              label: '사진 빼기',
              child: GestureDetector(
                onTap: () => viewModel.removePhoto(index),
                // 그림은 28 원 그대로 두고 **누를 수 있는 넓이만** 44 로 키운다 —
                // 바깥 여백이 곧 터치 영역이라 모서리에서도 잘 눌린다.
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(AppIcons.x, size: 14, color: AppColors.onInk),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddPhotoTile extends StatelessWidget {
  const _AddPhotoTile({required this.onTap});

  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Ink(
        decoration: BoxDecoration(
          color: AppColors.primaryWash,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(AppIcons.plus, size: 24, color: AppColors.primaryText),
            const SizedBox(height: AppSpacing.xs),
            Text('사진 추가', style: AppTypography.labelSmall.copyWith(color: AppColors.primaryText)),
          ],
        ),
      ),
    );
  }
}
