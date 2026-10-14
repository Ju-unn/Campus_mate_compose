import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 사람 칸·빈 칸 폭(pen `b9Rask` · `FqMYC`). 글자를 키워도 늘지 않아 레일이 한 벌 폭을 계산한다.
const double mosaicTileWidth = 112;
const double _height = 140;

/// mosaic-rail 사람 칸(pen `b9Rask` · `Ch4h6`). Z54et 에 마스터가 없다. 실제 사람 사진은 넣지 않는다.
class MosaicPersonTile extends StatelessWidget {
  const MosaicPersonTile({required this.image, super.key});

  final String image;

  @override
  Widget build(BuildContext context) {
    // 그림을 decoration 으로 깐다 — Image 위젯은 그림 비율로 제 높이를 주장해 rail 높이를 흔든다.
    return Container(
      width: mosaicTileWidth,
      constraints: const BoxConstraints(minHeight: _height),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
        image: DecorationImage(image: AssetImage(image), fit: BoxFit.cover),
      ),
    );
  }
}

/// mosaic-rail 끝의 빈 칸(pen `FqMYC`, 2026-10-14 — 마스코트 · 바탕 없이 hairline 1px 안쪽 선 + 가운데 문구 12).
/// pen 은 실선으로 그려 두고 "코드에서는 점선" 이라고 정했다(대장 지시) — 점 4 · 틈 4 는 pen 에 없는 값이라 정한 값이다.
class MosaicEmptyTile extends StatelessWidget {
  const MosaicEmptyTile({super.key});

  @override
  Widget build(BuildContext context) {
    // pen 높이 140 은 최소 높이다 — 글자를 키우면 늘어난다(DESIGN §11.2).
    return CustomPaint(
      foregroundPainter: const _DashedBorderPainter(),
      child: Container(
        width: mosaicTileWidth,
        constraints: const BoxConstraints(minHeight: _height),
        padding: const EdgeInsets.all(AppSpacing.xs),
        alignment: Alignment.center,
        // pen `ldj8D` 는 칸 폭(96)을 채우고 가운데 정렬이다. 렌더 16(lineHeight 속성 없음) — caption 토큰은 16.8 이라 맞춘다.
        child: SizedBox(
          width: double.infinity,
          child: Text(
            '아직 비어 있어요',
            textAlign: TextAlign.center,
            style: AppTypography.caption.copyWith(height: 16 / 12, color: AppColors.muted),
          ),
        ),
      ),
    );
  }
}

/// 둥근 모서리(14) 1px 점선. pen 처럼 선을 칸 안쪽에 그린다(strokeAlignment inner — 반 픽셀 들여 긋는다).
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter();

  static const double _dash = 4;
  static const double _gap = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.hairline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final outline = Path()
      ..addRRect(RRect.fromRectAndRadius((Offset.zero & size).deflate(0.5), const Radius.circular(AppRadius.md - 0.5)));
    for (final metric in outline.computeMetrics()) {
      for (var at = 0.0; at < metric.length; at += _dash + _gap) {
        canvas.drawPath(metric.extractPath(at, at + _dash), paint);
      }
    }
  }

  /// 바탕이 비어 있어도 칸 전체가 눌린다 — 레일은 칸이 눌려야 멈춘다([MosaicRail] 의 Listener 는 자식이 맞아야 받는다).
  @override
  bool hitTest(Offset position) => true;

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) => false;
}
