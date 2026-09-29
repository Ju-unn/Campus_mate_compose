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

// 사진 칸 위젯 — 04-2 사진 업로드와 15e 사진 수정이 같이 쓴다(계획서 2026-09-27-me-edit.md C9: 15e 칸은 04-2 모양,
// 크기만 다르다). photos_screen.dart 에서 그대로 옮겼다 — 모양을 두 벌 두면 한쪽만 고쳐진다.
// 칸 크기는 부모가 준다(04-2 는 Expanded + 높이 158, 15e 는 160×200 · 66×88).

/// 길게 눌러 끌면 두 칸이 자리를 바꾼다(15e 와 같은 방식, 2026-09-24 사용자 결정).
/// 빈 "사진 추가" 칸은 받는 쪽이 아니다 — 사진을 빈 자리로 밀면 순서에 구멍이 생긴다.
class DraggablePhotoTile extends StatelessWidget {
  const DraggablePhotoTile({required this.index, required this.state, required this.viewModel, super.key});

  final int index;
  final PhotosUiState state;
  final PhotosViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final tile = _PhotoTile(index: index, state: state, viewModel: viewModel);
    // 끄는 것은 자리가 아니라 사진이다 — 끄는 중에 다른 칸이 지워져 번호가 밀려도
    // 처음 집은 사진이 그대로 옮겨지도록 사진 열쇠(새 사진은 파일 경로, 올려 둔 사진은 행 id)를 들고 다닌다.
    final photoPath = state.photos[index].key;
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
              viewModel.swapPhotos(state.photos.indexWhere((p) => p.key == details.data), index),
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
          Positioned.fill(child: Image(image: state.photos[index].image, fit: BoxFit.cover)),
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
class CheckingTile extends StatelessWidget {
  const CheckingTile({super.key});

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

class AddPhotoTile extends StatelessWidget {
  const AddPhotoTile({required this.onTap, super.key});

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
