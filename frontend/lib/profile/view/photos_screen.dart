import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/profile/viewmodel/photos_ui_state.dart';
import 'package:campus_mate/profile/viewmodel/photos_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 사진 업로드 화면(DESIGN.md 화면 04-2). 최소 2장·최대 4장, 그중 1장을 아바타 원본으로 고른다.
class PhotosScreen extends ConsumerWidget {
  const PhotosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(photosViewModelProvider);
    final viewModel = ref.read(photosViewModelProvider.notifier);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 56,
        backgroundColor: AppColors.canvas,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        title: Text('사진 등록', style: AppTypography.navTitle.copyWith(color: AppColors.ink)),
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '사진을 2~4장 올려주세요. 그중 하나를 아바타 원본으로 골라주세요.',
                style: AppTypography.body.copyWith(color: AppColors.body),
              ),
              const SizedBox(height: AppSpacing.md),
              Expanded(child: _PhotoGrid(state: state, viewModel: viewModel)),
              if (state.errorMessage != null) ...[
                Text(state.errorMessage!, style: AppTypography.caption.copyWith(color: AppColors.error)),
                const SizedBox(height: AppSpacing.xs),
              ],
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
    return Stack(
      children: [
        Positioned.fill(child: Image.file(photo.file, fit: BoxFit.cover)),
        Positioned(
          left: 4,
          top: 4,
          child: ChoiceChip(
            label: const Text('아바타 원본'),
            selected: photo.isAvatarSource,
            onSelected: (_) => viewModel.setAvatarSource(index),
          ),
        ),
        Positioned(
          right: 4,
          top: 4,
          child: IconButton(
            onPressed: () => viewModel.removePhoto(index),
            icon: const Icon(Icons.close, color: AppColors.onPrimary),
          ),
        ),
      ],
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
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceSoft,
          border: Border.all(color: AppColors.outline),
        ),
        child: const Icon(Icons.add_a_photo, color: AppColors.muted),
      ),
    );
  }
}
