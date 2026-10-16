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

// 사진 칸 위젯 — 04-2 사진 업로드와 15-7 사진 수정이 같이 쓴다(계획서 2026-09-27-me-edit.md C9: 15-7 칸은 04-2 모양,
// 크기만 다르다). photos_screen.dart 에서 그대로 옮겼다 — 모양을 두 벌 두면 한쪽만 고쳐진다.
// 칸 크기는 부모가 준다 — 04-2 · 15-7 모두 [PhotoSlotGrid] 로 놓고 열 간격만 다르다.

/// 사진 칸 2×2 배치 — 15-7 그리드(pen `u6AR7K`: 행 사이 12, 칸 높이 158). 칸 폭은 부모 폭에서 [columnGap] 을 뺀 반이다.
/// 칸 그리기는 아래 칸 위젯이 맡고, 이 위젯은 어느 자리에 어느 칸을 놓을지만 정한다 — 04-2 · 15-7 이 같이 쓰도록 화면 값은
/// 열 간격만 받는다(04-2 는 12, 15-7 은 16).
class PhotoSlotGrid extends StatelessWidget {
  const PhotoSlotGrid({
    required this.state,
    required this.viewModel,
    required this.columnGap,
    this.markRejectedSlot = false,
    this.onOpenPhoto,
    super.key,
  });

  final PhotosUiState state;
  final PhotosViewModel viewModel;
  final double columnGap;

  /// 글자 많은 사진 거절([PhotosUiState.documentRejected]) 뒤 빠진 사진 자리(첫 빈 칸)에 오류 테두리를 둔다 — 04-2 만.
  /// 15-7 은 여러 장을 한 번에 바꿔 어느 칸인지 몰라 끈다.
  final bool markRejectedSlot;

  /// 사진 칸을 누르면 그 칸 번호로 부른다(크게 보기). null 이면 꺼짐 — 15-7 내 사진 수정만 켠다
  /// (사용자 결정 2026-10-16 "다른 사람이 내 사진 확대하는거는 싫은데 … 실제사진 교체 페이지에서 클릭시 확대가능하게").
  final ValueChanged<int>? onOpenPhoto;

  static const int _columns = 2;
  static const int _rows = 2;
  static const double _tileHeight = 158;

  @override
  Widget build(BuildContext context) {
    // 두 줄 높이만 차지한다 — 스크롤 밖에 놓여도 남는 세로를 먹지 않게.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var row = 0; row < _rows; row++) ...[
          if (row > 0) const SizedBox(height: AppSpacing.sm),
          SizedBox(height: _tileHeight, child: _row(row)),
        ],
      ],
    );
  }

  Widget _row(int row) {
    return Row(
      children: [
        for (var column = 0; column < _columns; column++) ...[
          if (column > 0) SizedBox(width: columnGap),
          Expanded(child: _slot(row * _columns + column)),
        ],
      ],
    );
  }

  /// 사진이 있으면 사진 칸, 살펴보는 중이면 들어올 자리에 기다리는 표시, 나머지는 빈 칸.
  Widget _slot(int index) {
    if (index < state.photos.length) {
      final open = onOpenPhoto;
      return DraggablePhotoTile(
        index: index,
        state: state,
        viewModel: viewModel,
        onOpen: open == null ? null : () => open(index),
      );
    }
    if (state.isCheckingPhotos && index == state.photos.length) {
      return const CheckingTile();
    }
    final rejected = markRejectedSlot && state.documentRejected && index == state.photos.length;
    return AddPhotoTile(onTap: viewModel.addPhoto, hasError: rejected);
  }
}

/// 서버가 글자 많은 사진을 거절했을 때(422 `photo_looks_like_document`) 사진 칸 바로 아래에 두는 앱 고정 문구 — 서버 임시 문구 대신.
const String photoDocumentRejectedMessage = '학생증·신분증처럼 글자가 많은 사진은 올릴 수 없어요. 얼굴이 잘 나온 일반 사진을 올려 주세요';

/// 04-2 · 15-7 사진 칸 아래 오류 한 덩어리 — 입력칸 오류 줄(`LabeledField`)과 같은 모양(circle-alert 14 · 4 · 12/normal error), 두 줄까지 내려간다.
/// 칸과의 간격 8 은 놓는 쪽이 둔다.
class PhotoDocumentNote extends StatelessWidget {
  const PhotoDocumentNote({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      // 두 줄이면 표식은 첫 줄 옆에 둔다.
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(AppIcons.circleAlert, size: 14, color: AppColors.error),
        const SizedBox(width: AppSpacing.xxs),
        Expanded(
          child: Text(photoDocumentRejectedMessage, style: AppTypography.caption.copyWith(color: AppColors.error)),
        ),
      ],
    );
  }
}

/// 길게 눌러 끌면 두 칸이 자리를 바꾼다(15-7 과 같은 방식, 2026-09-24 사용자 결정).
/// 빈 "사진 추가" 칸은 받는 쪽이 아니다 — 사진을 빈 자리로 밀면 순서에 구멍이 생긴다.
class DraggablePhotoTile extends StatelessWidget {
  const DraggablePhotoTile({required this.index, required this.state, required this.viewModel, this.onOpen, super.key});

  final int index;
  final PhotosUiState state;
  final PhotosViewModel viewModel;

  /// 칸 본체를 누르면 부른다(크게 보기, [PhotoSlotGrid.onOpenPhoto]). null 이면 칸 탭은 아무 일도 없다.
  /// x(사진 빼기)는 더 안쪽 누름이라 먼저 받고, 길게 눌러 끌기가 시작되면 이 탭은 취소된다.
  final VoidCallback? onOpen;

  /// 화면 읽기가 칸 탭 동작을 읽는 말 — "두 번 탭하여 사진 크게 보기".
  static const String _openHint = '사진 크게 보기';

  @override
  Widget build(BuildContext context) {
    final tile = _PhotoTile(index: index, state: state, viewModel: viewModel);
    // 끄는 것은 자리가 아니라 사진이다 — 끄는 중에 다른 칸이 지워져 번호가 밀려도
    // 처음 집은 사진이 그대로 옮겨지도록 사진 열쇠(새 사진은 파일 경로, 올려 둔 사진은 행 id)를 들고 다닌다.
    final photoPath = state.photos[index].key;
    return Semantics(
      label: index == 0 ? '사진 1, 대표' : '사진 ${index + 1}',
      onTap: onOpen,
      onTapHint: onOpen == null ? null : _openHint,
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
            // 낭독 탭 동작은 위 Semantics 가 단다 — 여기서 또 달면 같은 칸에 두 번 붙는다.
            child: GestureDetector(
              onTap: onOpen,
              excludeFromSemantics: true,
              child: candidates.isEmpty ? tile : _DropOutline(child: tile),
            ),
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
              // 칸과 다른 낭독 칸으로 떼어 둔다 — 합쳐지면 칸을 두 번 탭할 때 사진이 빠졌다(칸 탭 = 크게 보기와도 부딪힌다).
              container: true,
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

/// 빈 "사진 추가" 칸. 글자가 칸에 안 들어가면(15-7 보조 칸 66×88 에 큰 글씨) 더하기 아이콘만 두고, 낭독 이름은
/// "사진 추가" 그대로 아이콘에 단다(대장 결정 (가), 2026-09-29 — 잘림 · 넘침은 안 된다, DESIGN §11.2).
class AddPhotoTile extends StatelessWidget {
  const AddPhotoTile({required this.onTap, this.hasError = false, super.key});

  final Future<void> Function() onTap;

  /// 방금 거절된 사진 자리 — error 2 안쪽 테두리.
  final bool hasError;

  static const String _label = '사진 추가';
  static const double _iconSize = 24;
  static final TextStyle _labelStyle = AppTypography.labelSmall.copyWith(color: AppColors.primaryText);

  /// 아이콘 + 간격 + 글자가 칸 높이 안에 드는지 실제 글꼴 · 배율로 잰다(배율 숫자를 박지 않는다 — 글꼴이 바뀌어도 맞게).
  static bool _labelFits(BuildContext context, BoxConstraints constraints) {
    final painter = TextPainter(
      text: TextSpan(text: _label, style: DefaultTextStyle.of(context).style.merge(_labelStyle)),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: constraints.maxWidth);
    final height = _iconSize + AppSpacing.xs + painter.height;
    painter.dispose();
    return height <= constraints.maxHeight;
  }

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
            border: hasError ? Border.all(color: AppColors.error, width: 2) : null,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final labelFits = _labelFits(context, constraints);
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    AppIcons.plus,
                    size: _iconSize,
                    color: AppColors.primaryText,
                    semanticLabel: labelFits ? null : _label,
                  ),
                  if (labelFits) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(_label, style: _labelStyle),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
