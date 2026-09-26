import 'dart:async';

import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/common/widgets/onboarding_app_bar.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_elevation.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/profile/viewmodel/photos_ui_state.dart';
import 'package:campus_mate/profile/viewmodel/photos_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
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
        return _DraggablePhotoTile(index: index, state: state, viewModel: viewModel);
      }
      // 살펴보는 중인 사진은 아직 칸에 없다 — 들어올 자리에서 기다리는 표시를 보여준다.
      if (state.isCheckingPhotos && index == state.photos.length) {
        return const _CheckingTile();
      }
      return _AddPhotoTile(onTap: viewModel.addPhoto);
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

/// 길게 눌러 끌면 두 칸이 자리를 바꾼다(15e 와 같은 방식, 2026-09-24 사용자 결정).
/// 빈 "사진 추가" 칸은 받는 쪽이 아니다 — 사진을 빈 자리로 밀면 순서에 구멍이 생긴다.
class _DraggablePhotoTile extends StatelessWidget {
  const _DraggablePhotoTile({required this.index, required this.state, required this.viewModel});

  final int index;
  final PhotosUiState state;
  final PhotosViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final tile = _PhotoTile(index: index, state: state, viewModel: viewModel);
    // 끄는 것은 자리가 아니라 사진이다 — 끄는 중에 다른 칸이 지워져 번호가 밀려도
    // 처음 집은 사진이 그대로 옮겨지도록 파일 경로를 들고 다닌다.
    final photoPath = state.photos[index].file.path;
    return Semantics(
      label: index == 0 ? '사진 1, 대표' : '사진 ${index + 1}',
      // 끌지 못하는 사람도 대표를 바꿀 수 있어야 한다 — 토크백 메뉴에 액션으로 둔다.
      // 첫 칸은 이미 대표라 액션이 없다(빈 맵을 주면 빈 메뉴가 생긴다).
      customSemanticsActions: index == 0
          ? null
          : {const CustomSemanticsAction(label: '대표로 지정'): () => viewModel.swapPhotos(index, 0)},
      child: LayoutBuilder(
        builder: (context, constraints) => DragTarget<String>(
          onWillAcceptWithDetails: (details) => details.data != photoPath,
          onAcceptWithDetails: (details) =>
              viewModel.swapPhotos(state.photos.indexWhere((p) => p.file.path == details.data), index),
          builder: (context, candidates, _) => LongPressDraggable<String>(
            data: photoPath,
            // 길게 누른 순간 한 번만 울린다 — 끄는 내내 울리면 시끄럽다.
            onDragStarted: HapticFeedback.selectionClick,
            feedback: _LiftedTile(size: constraints.biggest, child: tile),
            childWhenDragging: Opacity(opacity: 0.4, child: tile),
            child: candidates.isEmpty ? tile : _DropOutline(child: tile),
          ),
        ),
      ),
    );
  }
}

/// 끄는 동안 손가락을 따라다니는 그림. pen 에 없는 모습이라 토큰 안에서 최소한으로 —
/// 조금 크게(1.05) + 카드 그림자만으로 "들렸다"를 알린다.
class _LiftedTile extends StatelessWidget {
  const _LiftedTile({required this.size, required this.child});

  final Size size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Transform.scale(
        scale: 1.05,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.md),
              boxShadow: AppElevation.card,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// 놓으면 여기로 온다는 표시. 테두리만 얹어 다른 칸이 밀리지 않게 한다.
class _DropOutline extends StatelessWidget {
  const _DropOutline({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: child),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.primary, width: 2),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
          ),
        ),
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
                // 칸 라벨이 이미 "사진 1, 대표" 라고 읽어 준다 — 여기서 또 읽으면 두 번 들린다.
                child: ExcludeSemantics(
                  child: Text('대표', style: AppTypography.badge.copyWith(color: AppColors.onInk)),
                ),
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

/// 얼굴이 보이는지 살펴보는 동안의 빈 칸. 모양은 "사진 추가" 칸과 같고 표시만 돈다.
class _CheckingTile extends StatelessWidget {
  const _CheckingTile();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '사진을 살펴보는 중',
      child: DecoratedBox(
        // pen `EvcRf` Skeleton — 칸과 같은 모서리(14)를 회색으로 덮고 가운데만 돈다.
        decoration: BoxDecoration(
          color: AppColors.hairlineSoft,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.muted),
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
    // 칸이 자기 Material 을 들고 있어야 분홍 바탕이 Scaffold 에 칠해지지 않는다
    // (select_chip.dart 와 같은 자리 — 목록을 당겼다 놓으면 글자만 움직였다).
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
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
              Text(
                '사진 추가',
                style: AppTypography.labelSmall.copyWith(color: AppColors.primaryText),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
