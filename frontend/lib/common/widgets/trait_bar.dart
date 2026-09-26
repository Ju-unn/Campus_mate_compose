import 'dart:math' as math;

import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 표시 전용 성향 바(DESIGN.md §8.1 10b — 입력용 `TraitSlider` 와 별개다).
/// 라벨 60 · 간격 8 · 바 150 은 시안 실측값이다(2026-09-13 라운드2 에서
/// 라벨 64 → 60 으로 줄여 우측 라벨이 잘리던 버그를 고쳤다 — 되돌리지 않는다).
/// 배율 1.0 에서 60/150 이고, 글자가 커지면(§11.2) 라벨이 넓어지는 만큼 바가 줄어든다(백로그 31).
///
/// 2026-09-23: 실기기 대조에서 pen `TORAs` 와 어긋나 트랙을 2 선 + 점 12 에서
/// **6 굵기 트랙 + 16×6 표시**로 바꿨다. 표시가 트랙 안에 머물러 양 끝에서 잘리지 않는다.
class TraitBar extends StatelessWidget {
  const TraitBar({
    required this.leftLabel,
    required this.rightLabel,
    required this.value,
    super.key,
  });

  final String leftLabel;
  final String rightLabel;

  /// -1.0 ~ 1.0
  final double value;

  @override
  Widget build(BuildContext context) {
    final ratio = ((value + 1) / 2).clamp(0.0, 1.0);
    return Row(
      children: [
        _Label(leftLabel),
        const SizedBox(width: AppSpacing.xs),
        // 150 은 최대값이다 — 라벨이 넓어지면 남은 폭만큼만 쓴다.
        Flexible(
          child: SizedBox(
            width: 150,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceStrong,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                Align(
                  alignment: Alignment(ratio * 2 - 1, 0),
                  child: Container(
                    width: 16,
                    height: 6,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        // 오른쪽 라벨도 왼쪽 정렬이다(pen `TORAs`) — 줄마다 글자 시작점이 맞는다.
        _Label(rightLabel),
      ],
    );
  }
}

/// 폭 60(pen)을 최소로 두되, 가장 긴 **낱말**이 60 을 넘으면 그만큼 넓어진다.
/// `minWidth` 만 걸면 "금방 친해짐" 처럼 띄어쓰기가 있는 라벨이 배율 1.0 에서도 한 줄로 펴져
/// 바가 150 보다 줄어든다. 엔진의 `minIntrinsicWidth` 는 한글을 음절마다 끊을 수 있다고 보고
/// 한 음절 폭을 돌려줘서("금방/친해/짐") 쓸 수 없다 — 띄어쓰기로 나눈 낱말마다 폭을 재서 가장 긴 것을 쓴다.
class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    var style = DefaultTextStyle.of(context).style.merge(
      AppTypography.caption.copyWith(color: AppColors.muted),
    );
    // `Text` 가 그릴 때와 같은 스타일로 잰다(굵은 글꼴 설정도 `Text` 와 같은 방식으로 얹는다).
    if (MediaQuery.boldTextOf(context)) {
      style = style.merge(const TextStyle(fontWeight: FontWeight.bold));
    }
    var longestWord = 0.0;
    for (final word in text.split(' ')) {
      final painter = TextPainter(
        text: TextSpan(text: word, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      longestWord = math.max(longestWord, painter.width);
      painter.dispose();
    }
    // 올림 — 소수점 아래가 잘려 마지막 글자가 다음 줄로 밀리지 않게 한다.
    final width = math.max(60.0, longestWord).ceilToDouble();
    return SizedBox(
      width: width,
      child: Text(text, style: style),
    );
  }
}
