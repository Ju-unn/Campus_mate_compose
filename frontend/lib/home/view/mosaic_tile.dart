import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
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

/// mosaic-rail 끝의 빈 칸(pen `FqMYC`). Z54et 에 마스터가 없다.
class MosaicEmptyTile extends StatelessWidget {
  const MosaicEmptyTile({super.key});

  @override
  Widget build(BuildContext context) {
    // pen 높이 140 은 최소 높이다 — 글자를 키우면 늘어난다(DESIGN §11.2).
    return Container(
      width: mosaicTileWidth,
      constraints: const BoxConstraints(minHeight: _height),
      padding: const EdgeInsets.only(top: 26, bottom: 6),
      decoration: BoxDecoration(
        color: AppColors.primaryWash,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      // pen 은 그림을 x20, 글자를 x14 에 따로 놓는다 — 가운데 정렬이 아니다.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 20),
            child: Image.asset('assets/images/mascot-female.png', width: 72, height: 72),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Text('아직 비어 있어요', style: AppTypography.caption.copyWith(fontSize: 11, color: AppColors.muted)),
          ),
        ],
      ),
    );
  }
}
