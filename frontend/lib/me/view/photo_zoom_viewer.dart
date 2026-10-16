import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_motion.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

// 15-7 사진 수정에서 사진 칸을 누르면 여는 전체 화면 확대 뷰어(pen `ZExxs` "내 사진 수정 · 사진 확대 (초안)").
// 사용자 결정 2026-10-16 — 내 사진 수정에서만 연다. 저장 · 공유 버튼은 두지 않는다(그림은 이미 받은 메모리 캐시만 쓴다).

/// 바탕 `ITtLC` — ink 알파 .9(#222222E6). 토큰에 없는 값이라 이 파일 상수로 둔다(DESIGN §12, `core/theme` 는 공유 파일).
final Color _backdrop = AppColors.ink.withAlpha(0xE6);

/// 안내 `g3uTN` 글자색 — 흰색 80%(#FFFFFFCC).
final Color _guideColor = AppColors.onInk.withAlpha(0xCC);

/// 확대 범위 1 ~ 4배 — pen 에 값이 없어 대장 지시 값(2026-10-16).
const double _minScale = 1;
const double _maxScale = 4;

/// 안내 글과 화면 바닥(안전 영역 위) 사이 — pen 값표에 숫자가 없어 정한 값(대장 확인 대상).
const double _guideBottomGap = AppSpacing.xl;

/// [image] 를 전체 화면으로 연다. [index] 는 칸 번호(0부터) — 화면 읽기가 "사진 N 크게 보기" 로 읽는다.
/// 열고 닫기는 투명도만 `{motion.standard}` 동안 바뀌고, 동작 줄이기면 바로 열리고 닫힌다.
Future<void> showPhotoZoomViewer(BuildContext context, {required ImageProvider image, required int index}) {
  final curve = AppMotion.standardCurve;
  return showGeneralDialog<void>(
    context: context,
    barrierColor: _backdrop,
    transitionDuration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : AppMotion.standard,
    pageBuilder: (context, _, _) => PhotoZoomViewer(image: image, index: index),
    transitionBuilder: (context, animation, _, child) =>
        FadeTransition(opacity: CurvedAnimation(parent: animation, curve: curve), child: child),
  );
}

/// 뷰어 화면. 바탕은 뒤의 막(barrier)이 칠하고, 이 위젯은 사진 · 닫기 · 안내만 놓는다.
/// 닫기 = 닫기 버튼 · 사진 밖 바탕 탭 · 시스템 뒤로가기(다이얼로그 경로라 그냥 닫힌다).
class PhotoZoomViewer extends StatefulWidget {
  const PhotoZoomViewer({required this.image, required this.index, super.key});

  /// 올려 둔 사진은 서명 주소(`NetworkImage`), 이번에 고른 사진은 파일(`FileImage`) — 칸이 쓰는 그대로.
  final ImageProvider image;
  final int index;

  @override
  State<PhotoZoomViewer> createState() => _PhotoZoomViewerState();
}

class _PhotoZoomViewerState extends State<PhotoZoomViewer> {
  final TransformationController _transform = TransformationController();

  /// 안내는 확대가 처음 1배를 넘으면 거두고 다시 띄우지 않는다 — 1배 근처를 오가며 켜졌다 꺼졌다 깜빡이지 않게.
  bool _guideShown = true;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _onZoom(ScaleUpdateDetails _) {
    if (!_guideShown || _transform.value.getMaxScaleOnAxis() <= _minScale) return;
    setState(() => _guideShown = false);
  }

  void _close() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    // 경로 이름 — 열리면 화면 읽기가 몇 번째 사진인지 먼저 읽는다.
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: '사진 ${widget.index + 1} 크게 보기',
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            Positioned.fill(child: _zoomArea(MediaQuery.sizeOf(context).width)),
            Positioned(left: 0, right: 0, bottom: 0, child: _guide(context)),
            Positioned(top: MediaQuery.paddingOf(context).top, right: AppSpacing.xs, child: _closeButton()),
          ],
        ),
      ),
    );
  }

  /// 사진 `FgziF` — 화면 폭 가득 contain, 세로 가운데. 폭만 주면 사진 비율대로 높이가 정해져 사진 상자 = 보이는 사진이고,
  /// 그 밖은 바탕이라 누르면 닫힌다.
  Widget _zoomArea(double width) {
    return GestureDetector(
      onTap: _close,
      excludeFromSemantics: true,
      child: InteractiveViewer(
        transformationController: _transform,
        minScale: _minScale,
        maxScale: _maxScale,
        onInteractionUpdate: _onZoom,
        child: Center(
          // 사진 위 탭은 여기서 받아 버린다 — 바탕만 닫는다(두 손가락 확대는 InteractiveViewer 가 가져간다).
          child: GestureDetector(
            onTap: () {},
            excludeFromSemantics: true,
            child: Image(image: widget.image, width: width, fit: BoxFit.contain, excludeFromSemantics: true),
          ),
        ),
      ),
    );
  }

  /// 안내 `g3uTN` — 12/normal 흰색 80% 가운데 정렬, 하단. 큰 글씨면 줄을 바꾼다(높이 고정 없음).
  /// 누름은 통과시켜 글자 위를 눌러도 바탕 탭 · 확대가 된다.
  Widget _guide(BuildContext context) {
    return IgnorePointer(
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, _guideBottomGap),
          child: AnimatedOpacity(
            opacity: _guideShown ? 1 : 0,
            duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : AppMotion.standard,
            curve: AppMotion.standardCurve,
            child: Text(
              '두 손가락으로 크게 볼 수 있어요',
              textAlign: TextAlign.center,
              style: AppTypography.caption.copyWith(color: _guideColor),
            ),
          ),
        ),
      ),
    );
  }

  /// 닫기 — 오른쪽 위 48×48 누름 칸(pen x304 · y44 = 상태 표시줄 바로 아래), lucide x 24 흰색.
  Widget _closeButton() {
    return IconButton(
      onPressed: _close,
      tooltip: '닫기',
      icon: const Icon(AppIcons.x, size: 24, color: AppColors.onInk),
    );
  }
}
