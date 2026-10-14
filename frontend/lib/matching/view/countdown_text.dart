import 'package:campus_mate/chat/view/chat_time.dart';
import 'package:flutter/material.dart';

/// 다음 카드까지 남은 시간 `hh:mm:ss`(오늘 탭 11 · 홈 hero 확인 완료 pen `FMjgB`). 1초 타이머는 [CountdownBuilder] 가 맡고
/// 지나면 00:00:00 에 멈춘다. 1초마다 다시 그리는 칸을 [RepaintBoundary] 로 끊어 옆 그림(흐린 띠 · 마스코트)까지 다시 그리지 않는다.
/// 숫자 폭이 흔들리지 않게 tabularFigures 를 늘 붙인다(DESIGN §3.1).
class CountdownText extends StatelessWidget {
  const CountdownText({required this.target, required this.style, this.onDone, super.key});

  final DateTime target;
  final TextStyle style;

  /// 0 이 되면 [target] 하나에 한 번 부른다([CountdownBuilder.onDone]) — 다음 카드를 다시 읽는 신호다.
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    final figures = style.fontFeatures ?? const <FontFeature>[];
    final tabular = figures.contains(const FontFeature.tabularFigures())
        ? style
        : style.copyWith(fontFeatures: [...figures, const FontFeature.tabularFigures()]);
    return RepaintBoundary(
      child: CountdownBuilder(
        deadlineAt: target,
        onDone: onDone,
        builder: (context, remaining) => Text(countdownLabel(remaining), style: tabular),
      ),
    );
  }
}
