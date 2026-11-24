import 'dart:typed_data';

import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:flutter/material.dart';

/// 사람 칸 · 기본 그림 칸 폭(pen `O5FCD9` · `HYaRA`). 글자를 키워도 늘지 않아 레일이 한 벌 폭을 계산한다.
const double mosaicTileWidth = 112;
const double _height = 140;

/// mosaic-rail 사람 칸(pen `O5FCD9` Home Rail Tile · Blur Avatar). 서버가 실제 가입자 아바타를 줄이기만 한 그림(224×280,
/// 블러 없음 — 사용자 10-17)을 칸에 덮어 그린다 — 앱도 흐리지 않는다. 이름 · 학교 · 배지 · 누름이 없는 장식이라 화면 읽기에서 뺀다.
class MosaicPersonTile extends StatelessWidget {
  const MosaicPersonTile({required this.image, super.key});

  final Uint8List image;

  @override
  Widget build(BuildContext context) {
    // 그림 크기를 칸(112×140)으로 박아 둔다 — 그림 비율로 제 높이를 주장하면 레일 높이가 흔들린다.
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
        // 그림을 못 풀면 토끼 칸으로 둔다 — 레일에 구멍을 내지 않고, 없는 사람 그림도 넣지 않는다(사용자 11-13).
        errorBuilder: (context, error, stackTrace) => const MosaicMascotTile(),
      ),
    );
  }
}

/// 기본 상태(사람 칸 없음)와 사람 그림을 못 푼 칸의 마스코트 칸(pen 10-16 campus-pen 확정) — primary-wash 바탕 가운데 기다리는 토끼(`mascot-male-waiting`) 88.
/// 사용자 결정 11-13: 없는 사람 그림을 내보내지 않는다 — 기본 상태 레일은 이 칸만 되풀이한다. 장식이라 화면 읽기에서 뺀다.
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
        'assets/images/mascot-male-waiting.webp',
        width: _mascotSize,
        height: _mascotSize,
        fit: BoxFit.contain,
        excludeFromSemantics: true,
      ),
    );
  }
}
