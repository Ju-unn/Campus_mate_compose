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

/// 아바타 사진 고르기(DESIGN.md 화면 04-3, datingApp.pen `dWNkb`).
/// 04-2 에서 고른 사진 중 한 장을 아바타 원본으로 정하고, 이때 사진 전부를 올린다.
/// 올리기가 끝나면 서버 단계가 `avatar` 로 넘어가 라우터가 생성 화면으로 보낸다.
class AvatarSourceScreen extends ConsumerWidget {
  const AvatarSourceScreen({super.key});

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
              // 사진 칸이 158 고정이라 작은 기기·큰 글씨에서는 위쪽이 넘친다.
              // 넘치는 쪽을 스크롤로 내주고 버튼은 늘 바닥에 남긴다(3b 와 같은 얼개).
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: AppSpacing.lg),
                      Text('아바타로 만들 사진을 골라주세요',
                          style: AppTypography.headline.copyWith(color: AppColors.ink)),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '고른 사진 한 장이 아바타로 변환돼요.',
                        style: AppTypography.body.copyWith(color: AppColors.body, height: 1.6),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      _SourceGrid(
                        state: state,
                        onSelect: state.isSubmitting ? null : viewModel.setAvatarSource,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      const NoticeCard(
                        icon: AppIcons.lock,
                        title: '상호 수락 전에는 아바타만 보여요',
                        body: '올린 실제 사진은 서로 수락하고 신뢰 확인을 마친 뒤에 공개돼요.',
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
              if (state.isSubmitting) ...[
                const Center(child: _ConvertingToast()),
                const SizedBox(height: AppSpacing.sm),
              ],
              AppButton(label: '이 사진으로 아바타 만들기', onPressed: state.canSubmit ? viewModel.submit : null),
            ],
          ),
        ),
      ),
    );
  }
}

/// 올린 사진만 두 칸씩 보인다. 고른 칸은 빨간 테두리와 "아바타로 선택" 배지.
class _SourceGrid extends StatelessWidget {
  const _SourceGrid({required this.state, required this.onSelect});

  final PhotosUiState state;
  final void Function(int index)? onSelect;

  @override
  Widget build(BuildContext context) {
    final photos = state.photos;
    return Column(
      children: [
        for (var row = 0; row * 2 < photos.length; row++) ...[
          if (row > 0) const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: 158,
            child: Row(
              children: [
                for (var col = 0; col < 2; col++) ...[
                  if (col > 0) const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: row * 2 + col < photos.length
                        ? _SourceTile(
                            photo: photos[row * 2 + col],
                            onTap: onSelect == null ? null : () => onSelect!(row * 2 + col),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({required this.photo, required this.onTap});

  final SelectedPhoto photo;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isSelected = photo.isAvatarSource;
    return Semantics(
      button: true,
      selected: isSelected,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          clipBehavior: Clip.antiAlias,
          foregroundDecoration: isSelected
              ? BoxDecoration(
                  border: Border.all(color: AppColors.primary, width: 3),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                )
              : null,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppRadius.md)),
          child: Stack(
            children: [
              Positioned.fill(child: Image.file(photo.file, fit: BoxFit.cover)),
              if (isSelected)
                Positioned(
                  left: AppSpacing.xs,
                  top: AppSpacing.xs,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(AppIcons.check, size: 12, color: AppColors.onPrimary),
                        const SizedBox(width: AppSpacing.xxs),
                        Text('아바타로 선택', style: AppTypography.badge.copyWith(color: AppColors.onPrimary)),
                      ],
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

/// 올리는 동안 버튼 위에 뜨는 토스트(pen `I8UOWm`).
class _ConvertingToast extends StatelessWidget {
  const _ConvertingToast();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceInk,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onInk),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text('아바타로 변환 중이에요', style: AppTypography.labelSmall.copyWith(color: AppColors.onInk)),
        ],
      ),
    );
  }
}
