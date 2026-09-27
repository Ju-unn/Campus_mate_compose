import 'dart:math';

import 'package:campus_mate/community/model/poll.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 찬성 O 버튼 · 도넛 A 몫 파랑(pen `VhiAe`, DESIGN §8.11). 토큰표 밖 값이다.
/// 결과도 버튼 색을 따른다 — A 파랑 · B 분홍(사용자 결정, 09-27).
const Color pollAgreeBlue = Color(0xFF2D96DE);

/// 투표 뒤 결과 도넛(pen `raSK1` 96×96). 12시에서 시계 방향으로 **A 몫 파랑**, 이어서 **B 몫 분홍**,
/// 가운데 % 는 **우세한 쪽**이다(DESIGN §8.11 — 대장 예외). 끝은 평평하고 두 색 사이 틈이 없다.
/// 아무도 안 눌렀으면 회색 고리만 남는다.
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
          painter: _DonutPainter(aCount: poll.aCount, bCount: poll.bCount),
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
  const _DonutPainter({required this.aCount, required this.bCount});

  final int aCount;
  final int bCount;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(PollDonut.stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = PollDonut.stroke;
    canvas.drawArc(rect, 0, 2 * pi, false, paint..color = AppColors.surfaceStrong);
    final total = aCount + bCount;
    if (total == 0) return;
    final aSweep = 2 * pi * aCount / total;
    canvas.drawArc(rect, -pi / 2, aSweep, false, paint..color = pollAgreeBlue);
    canvas.drawArc(rect, -pi / 2 + aSweep, 2 * pi - aSweep, false, paint..color = AppColors.primary);
  }

  @override
  bool shouldRepaint(_DonutPainter oldDelegate) => oldDelegate.aCount != aCount || oldDelegate.bCount != bCount;
}
