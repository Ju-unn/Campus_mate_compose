import 'dart:async';

import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/common/widgets/onboarding_app_bar.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/profile/view/photo_tiles.dart';
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

  /// 지금 떠 있는 안내. 겹쳐 뜨지 않게 한 번에 하나만 들고 있는다(pen `EvcRf`).
  String? _toast;
  Timer? _toastTimer;

  /// pen 에 표시 시간이 없고 앱에 정해 둔 값도 없어 3초로 둔다.
  static const Duration _toastDuration = Duration(seconds: 3);

  void _showToast(String message) {
    _toastTimer?.cancel();
    setState(() => _toast = message);
    _toastTimer = Timer(_toastDuration, () {
      if (mounted) {
        setState(() => _toast = null);
      }
    });
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    super.dispose();
  }

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
    // 안내는 칸 아래 글이 아니라 버튼 위 토스트로 나간다(pen `EvcRf`).
    ref.listen(photosViewModelProvider, (previous, next) {
      if (next.errorMessage != null) {
        _showToast(next.errorMessage!);
      }
    });
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
                      // pen `hco2A` 실측 6. 간격 토큰 xxs(4)·xs(8) 사이 값이라 토큰으로 갈음하지 않는다.
                      const SizedBox(height: 6),
                      Text(
                        '사진을 길게 눌러 끌면 순서를 바꿀 수 있어요. 첫 칸이 대표 사진이에요.',
                        style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              if (_toast != null) ...[
                Center(
                  child: AppToast(
                    leading: const Icon(AppIcons.alertTriangle, size: 16, color: AppColors.onInk),
                    label: _toast!,
                  ),
                ),
                // 버튼과 간격 12(pen 실측).
                const SizedBox(height: AppSpacing.sm),
              ],
              AppButton(
                label: '다음',
                // 살펴보는 중에 넘어가면 늦게 끝난 검사가 04-3 이 올리는 목록에 끼거나,
                // 이미 올라간 화면 위에 '…빠졌어요' 토스트가 얹힌다.
                onPressed: state.canProceed && !state.isCheckingPhotos && !_isLeaving
                    ? _goToAvatarSource
                    : null,
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
    Widget slot(int index) {
      if (index < state.photos.length) {
        return DraggablePhotoTile(index: index, state: state, viewModel: viewModel);
      }
      // 살펴보는 중인 사진은 아직 칸에 없다 — 들어올 자리에서 기다리는 표시를 보여준다.
      if (state.isCheckingPhotos && index == state.photos.length) {
        return const CheckingTile();
      }
      return AddPhotoTile(onTap: viewModel.addPhoto);
    }
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
