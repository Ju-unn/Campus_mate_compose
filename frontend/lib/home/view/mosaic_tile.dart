import 'dart:typed_data';

import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 사람 칸 · 기본 그림 칸 · 빈 칸 폭(pen `O5FCD9` · `HYaRA` · `FqMYC`). 글자를 키워도 늘지 않아 레일이 한 벌 폭을 계산한다.
const double mosaicTileWidth = 112;
const double _height = 140;

/// mosaic-rail 사람 칸(pen `O5FCD9` Home Rail Tile · Blur Avatar). 서버가 실제 가입자 아바타를 **이미 흐리게** 줄여 준 그림을
/// 그대로 그린다 — 앱에서 다시 흐리지 않는다. 이름 · 학교 · 배지 · 누름이 없는 장식이라 화면 읽기에서 뺀다.
class MosaicPersonTile extends StatelessWidget {
  const MosaicPersonTile({required this.image, super.key});

  final Uint8List image;

  @override
  Widget build(BuildContext context) {
    // 그림 크기를 칸(112×140)으로 박아 둔다 — 그림 비율로 제 높이를 주장하면 레일 높이가 흔들린다. 높이 140 은 최소다(빈 칸 글자를 키우면 같이 늘어난다).
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Image.memory(
        image,
        width: mosaicTileWidth,
        height: _height,
        fit: BoxFit.cover,
        // 레일이 다시 그려져도(같은 그림) 빈칸으로 깜빡이지 않는다.
        gaplessPlayback: true,
        excludeFromSemantics: true,
        // 그림을 못 풀면 기본 그림 칸 모양으로 둔다 — 레일에 구멍을 내지 않는다.
        errorBuilder: (context, error, stackTrace) => const MosaicDefaultTile(),
      ),
    );
  }
}

/// 사람 칸 자리의 기본 그림(pen `HYaRA` Home Rail Tile · 기본 그림) — 인원이 모자라(서버 빈 목록) · 못 받았거나 · 받는 중일 때.
/// primary-wash 바탕 가운데 3D 사용자 아이콘(`U17hk`) 56 만 둔다. 실제 가입자가 아니라 사람 그림(선명한 일러스트)을 넣지 않는다 — 가짜 사람으로 보이지 않게.
class MosaicDefaultTile extends StatelessWidget {
  const MosaicDefaultTile({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: mosaicTileWidth,
      constraints: const BoxConstraints(minHeight: _height),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: AppColors.primaryWash, borderRadius: BorderRadius.circular(AppRadius.md)),
      child: const Icon3d(AppIcon3d.users, size: 56),
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
