import 'package:campus_mate/home/model/home_people.dart';
import 'package:campus_mate/home/view/auto_marquee.dart';
import 'package:campus_mate/home/view/mosaic_tile.dart';
import 'package:flutter/material.dart';

/// 칸 사이 간격(pen `P2sFxR` gap).
const double _gap = 10;

/// 인원이 모자랄 때 사람 칸 대신 놓는 기본 그림 칸 수(pen `HhKIR` Home Mosaic Rail · 인원 부족).
const int _defaultTiles = 2;

/// mosaic-rail(pen `P2sFxR`). 사람 칸 뒤에 빈 칸 하나를 붙인 한 벌을 끝없이 되풀이하며 오른쪽으로 흐른다.
/// 사람 칸은 서버가 준 만큼만 둔다(채우려고 같은 그림을 한 벌에 되풀이하지 않는다). 없으면(인원 부족 · 못 받음 · 받는 중) 레일을 숨기지 않고
/// 기본 그림 칸 2 + 빈 칸으로 대신한다(pen `HhKIR`).
/// 흐름 · 누르면 멈춤 · 동작 줄이기에서 손으로 밀기 · 화면 읽기 한 벌은 [AutoMarquee](참여 대학 칩 줄과 같이 쓴다, 10-15)가 맡는다.
/// pause 아이콘은 없다(사용자 결정 2026-09-26). 높이는 칸 중 가장 높은 것을 따른다 — 배율 1.0 에서 140, 글자를 키우면 빈 칸 글자만큼 늘어난다.
/// ponytail: 한 벌을 화면 폭만큼 복사해 Row 로 한 번에 그린다. 사람이 수십 명이 되면 높이를 배율로 계산해 ListView 로 바꾼다.
class MosaicRail extends StatelessWidget {
  const MosaicRail({required this.people, super.key});

  final HomePeople people;

  @override
  Widget build(BuildContext context) {
    final tiles = people.isEmpty
        ? List<Widget>.filled(_defaultTiles, const MosaicDefaultTile())
        : people.map<Widget>((image) => MosaicPersonTile(image: image));
    return AutoMarquee(
      // 한 벌 폭은 칸 폭이 글자 배율과 상관없어 미리 안다.
      cycleWidth: (tiles.length + 1) * (mosaicTileWidth + _gap),
      cycle: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final tile in [...tiles, const MosaicEmptyTile()]) ...[tile, const SizedBox(width: _gap)],
        ],
      ),
    );
  }
}
