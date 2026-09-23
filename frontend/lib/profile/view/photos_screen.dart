import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/notice_card.dart';
import 'package:campus_mate/common/widgets/onboarding_app_bar.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/profile/viewmodel/photos_ui_state.dart';
import 'package:campus_mate/profile/viewmodel/photos_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 사진 업로드 화면(DESIGN.md 화면 04-2, datingApp.pen `04-2 사진 업로드`).
/// 최소 2장·최대 4장을 올리고 그중 한 장을 아바타 원본으로 고른다 —
/// 아바타 원본 고르기는 디자인 파일의 04-3 에 있지만, 서버가 업로드할 때 함께 받으므로
/// 여기서 같이 고른다(2026-09-20 사용자 결정 C2).
class PhotosScreen extends ConsumerWidget {
  const PhotosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(photosViewModelProvider);
    final viewModel = ref.read(photosViewModelProvider.notifier);
    return Scaffold(
      appBar: const OnboardingAppBar(current: 2, total: 6),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpacing.lg),
              Text('실제 사진을 올려주세요', style: AppTypography.headline.copyWith(color: AppColors.ink)),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '얼굴이 잘 보이는 사진을 2~4장 골라주세요.',
                style: AppTypography.body.copyWith(color: AppColors.body),
              ),
              const SizedBox(height: AppSpacing.xl),
              Expanded(child: _PhotoGrid(state: state, viewModel: viewModel)),
              const SizedBox(height: AppSpacing.md),
              Text(
                '갤러리에서 여러 장을 한 번에 고를 수 있어요. 최소 2장이 필요해요.',
                style: AppTypography.caption.copyWith(color: AppColors.muted),
              ),
              const SizedBox(height: AppSpacing.sm),
              const NoticeCard(
                title: '상호 수락 전에는 아바타만 보여요',
                body: '올린 실제 사진은 서로 수락하고 신뢰 확인을 마친 뒤에 공개돼요.',
                icon: AppIcons.eye,
              ),
              if (state.errorMessage != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(state.errorMessage!, style: AppTypography.caption.copyWith(color: AppColors.error)),
              ],
              const SizedBox(height: AppSpacing.sm),
              AppButton(label: '다음', onPressed: state.canSubmit ? viewModel.submit : null),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoGrid extends StatelessWidget {
  const _PhotoGrid({required this.state, required this.viewModel});

  final PhotosUiState state;
  final PhotosViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: AppSpacing.sm,
      crossAxisSpacing: AppSpacing.sm,
      children: [
        for (var i = 0; i < state.photos.length; i++) _PhotoTile(index: i, state: state, viewModel: viewModel),
        if (state.photos.length < 4) _AddPhotoTile(onTap: viewModel.addPhoto),
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
    final photo = state.photos[index];
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Stack(
        children: [
          Positioned.fill(child: Image.file(photo.file, fit: BoxFit.cover)),
          Positioned(
            left: AppSpacing.xs,
            top: AppSpacing.xs,
            child: _AvatarBadge(
              isSelected: photo.isAvatarSource,
              onTap: () => viewModel.setAvatarSource(index),
            ),
          ),
          Positioned(
            right: AppSpacing.xxs,
            top: AppSpacing.xxs,
            child: IconButton(
              onPressed: () => viewModel.removePhoto(index),
              icon: const Icon(AppIcons.x, color: AppColors.onPrimary),
              tooltip: '사진 빼기',
            ),
          ),
        ],
      ),
    );
  }
}

/// 아바타로 쓸 한 장을 표시하는 뱃지(datingApp.pen 04-3 `아바타로 선택`).
class _AvatarBadge extends StatelessWidget {
  const _AvatarBadge({required this.isSelected, required this.onTap});

  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Ink 는 가장 가까운 Material 에 칠해진다. 이게 없으면 Scaffold 에 칠해져 사진 뒤에 깔리고
    // 흰 글씨만 떠 보여, 누를 수 있는 버튼인지·골랐는지 알 수 없었다(2026-09-23 실기기 테스트).
    return Material(
      type: MaterialType.transparency,
      child: _inkWell(),
    );
  }

  Widget _inkWell() {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Ink(
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.surfaceInk,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            '아바타로 선택',
            style: AppTypography.badge.copyWith(color: AppColors.onPrimary),
          ),
        ),
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
          color: AppColors.surfaceSoft,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(AppIcons.imagePlus, color: AppColors.primaryText),
            const SizedBox(height: AppSpacing.xs),
            Text('사진 추가', style: AppTypography.labelSmall.copyWith(color: AppColors.primaryText)),
          ],
        ),
      ),
    );
  }
}
