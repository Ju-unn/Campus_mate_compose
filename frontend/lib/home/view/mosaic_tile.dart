import 'dart:typed_data';

import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 사람 칸 · 기본 그림 칸 · 빈 칸 폭(pen `O5FCD9` · `HYaRA` · `FqMYC`). 글자를 키워도 늘지 않아 레일이 한 벌 폭을 계산한다.
const double mosaicTileWidth = 112;
const double _height = 140;

/// 기본 상태 예시 — 사진이 아니라 아바타 변환 일러스트(사용자 10-16 "Node ID: jReRU 실사진이 아니라 아바타 변환이야").
/// 04-2 `photo_example.dart` 의 아바타 일러스트 예시와 같은 그림이다(실존 인물 아님). 한 벌에 이 순서로 둔다 — 단발머리 여학생 → 안경 쓴 남학생.
const List<String> mosaicExampleAvatars = [
  'assets/images/example-illust-b-v1.webp',
  'assets/images/example-illust-a-v1.webp',
];

/// 예시 그림을 칸보다 사방으로 더 크게 그리는 거리(음수) — 112×140 칸이면 pen 그림 136×170. 칸 틀이 가장자리를 잘라 낸다.
const Offset _exampleBleed = Offset((mosaicTileWidth - 136) / 2, (_height - 170) / 2);

/// mosaic-rail 사람 칸(pen `O5FCD9` Home Rail Tile · Blur Avatar). 서버가 실제 가입자 아바타를 줄이기만 한 그림(224×280,
/// 블러 없음 — 사용자 10-17)을 칸에 덮어 그린다 — 앱도 흐리지 않는다. 이름 · 학교 · 배지 · 누름이 없는 장식이라 화면 읽기에서 뺀다.
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
        // 그림을 못 풀면 예시 칸으로 둔다 — 레일에 구멍을 내지 않는다.
        errorBuilder: (context, error, stackTrace) => const MosaicDefaultTile(),
      ),
    );
  }
}

/// 사람 칸 자리의 기본 상태 칸(pen 10-16 campus-pen 확정) — 인원이 모자라(서버 빈 목록) · 못 받았거나 · 받는 중일 때.
/// 아바타 변환 예시 그림([mosaicExampleAvatars])을 112×140 · 모서리 14 로 잘라 흐리지 않고 둔다(사용자 10-16 "블러 처리 빼줘").
/// 실제 가입자가 아니다 — 장식이라 화면 읽기에서 뺀다.
class MosaicDefaultTile extends StatelessWidget {
  const MosaicDefaultTile({this.asset = 'assets/images/example-illust-b-v1.webp', super.key});

  /// 그릴 예시 그림(에셋 경로).
  final String asset;

  @override
  Widget build(BuildContext context) {
    // 칸 틀(폭 112 · 높이 140 이상)은 빈 상자가 정하고, 그림은 사방으로 더 크게(pen 136×170) 깔아 가장자리를 틀 밖으로 보낸다.
    // 레일은 IntrinsicHeight 로 칸 높이를 재므로 그림 크기가 높이에 끼어들지 않게 Positioned 로 둔다.
    return SizedBox(
      width: mosaicTileWidth,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Stack(
          children: [
            const SizedBox(width: mosaicTileWidth, height: _height),
            Positioned(
              left: _exampleBleed.dx,
              right: _exampleBleed.dx,
              top: _exampleBleed.dy,
              bottom: _exampleBleed.dy,
              child: Image.asset(asset, fit: BoxFit.cover, excludeFromSemantics: true),
            ),
          ],
        ),
      ),
    );
  }
}

/// 기본 상태 한 벌 끝의 마스코트 칸(pen 10-16 campus-pen 확정) — primary-wash 바탕 가운데 기다리는 토끼(`mascot-male-waiting`) 88.
/// 사람 칸이 있을 때 끝에 붙는 [MosaicEmptyTile] 자리를 기본 상태에서는 이 칸이 맡는다. 장식이라 화면 읽기에서 뺀다.
class MosaicMascotTile extends StatelessWidget {
  const MosaicMascotTile({super.key});

  static const double _mascotSize = 88;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: mosaicTileWidth,
      constraints: const BoxConstraints(minHeight: _height),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: AppColors.primaryWash, borderRadius: BorderRadius.circular(AppRadius.md)),
      child: Image.asset(
        'assets/images/mascot-male-waiting.png',
        width: _mascotSize,
        height: _mascotSize,
        fit: BoxFit.contain,
        excludeFromSemantics: true,
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
