import 'dart:math';

import 'package:campus_mate/community/model/poll.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 투표 뒤 결과 도넛(pen `raSK1` 96×96). 호는 12시에서 시계 방향으로 **선택지 A 몫**(pen `D18xFi`),
/// 가운데 % 는 **우세한 쪽**이다(DESIGN §8.11 — 대장 예외). 끝은 평평하고 두 색 사이 틈이 없다.
/// CircularProgressIndicator 는 쓰지 않는다 — 버전마다 트랙 틈 · 둥근 끝 기본값이 바뀌어 pen 과 어긋난다.
class PollDonut extends StatelessWidget {
  const PollDonut({required this.poll, super.key});

  final Poll poll;

  static const double size = 96;

  /// pen 은 두께가 아니라 안쪽 반지름 비율 0.62 로 그렸다(`wnXtI`) → 두께 = 48 × 0.38 ≈ 18.2.
  static const double stroke = size / 2 * (1 - 0.62);

  @override
  Widget build(BuildContext context) {
    final lead = max(poll.aPercent, poll.bPercent);
    return Semantics(
      label: '${poll.optionA} ${poll.aPercent}%, ${poll.optionB} ${poll.bPercent}%',
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _DonutPainter(aShare: poll.total == 0 ? 0 : poll.aCount / poll.total),
          child: Padding(
            padding: const EdgeInsets.all(stroke),
            // 글자를 키워도 고리 밖으로 나가지 않게 줄여서 맞춘다. pen `zJP3C` 20/700 #222.
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '$lead%',
                  style: AppTypography.title.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter({required this.aShare});

  final double aShare;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(PollDonut.stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = PollDonut.stroke;
    canvas.drawArc(rect, 0, 2 * pi, false, paint..color = AppColors.surfaceStrong);
    canvas.drawArc(rect, -pi / 2, 2 * pi * aShare, false, paint..color = AppColors.primary);
  }

  @override
  bool shouldRepaint(_DonutPainter oldDelegate) => oldDelegate.aShare != aShare;
}
