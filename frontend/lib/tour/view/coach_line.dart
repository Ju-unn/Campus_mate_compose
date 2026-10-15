import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:flutter/widgets.dart';

/// 선 두께(pen `c4jwKG` · `h1gWg` CoachLine — 선 1.5 · 점 10 흰색).
const double _stroke = 1.5;
const double _dot = CoachLine.dotDiameter;

/// 구멍과 말풍선을 잇는 가는 선(pen `h1gWg` 점 위 / `c4jwKG` 점 아래). 점은 구멍 쪽 끝에 있고,
/// 선은 점에서 말풍선 쪽으로 [progress](0~1)만큼 그려진다 — 대상에서 말풍선으로 뻗어 나가 보이게.
class CoachLine extends StatelessWidget {
  const CoachLine({required this.length, required this.dotAtTop, this.progress = 1, super.key});

  /// 점 지름(pen 10). 호스트가 선을 대상 가운데에 맞출 때도 쓴다.
  static const double dotDiameter = 10;

  /// [length] 는 점까지 넣은 길이다(pen 52 = 점 10 + 보이는 선 42).

  final double length;

  /// 말풍선이 구멍 아래면 점이 위(`h1gWg`), 위면 점이 아래(`c4jwKG`).
  final bool dotAtTop;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size(_dot, length), painter: _CoachLinePainter(dotAtTop, progress));
  }
}

class _CoachLinePainter extends CustomPainter {
  _CoachLinePainter(this.dotAtTop, this.progress);

  final bool dotAtTop;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2;
    final dotY = dotAtTop ? _dot / 2 : size.height - _dot / 2;
    final endY = dotAtTop ? size.height : 0.0;
    final paint = Paint()..color = AppColors.canvas;
    canvas.drawLine(
      Offset(x, dotY),
      Offset(x, dotY + (endY - dotY) * progress),
      Paint()
        ..color = AppColors.canvas
        ..strokeWidth = _stroke,
    );
    canvas.drawCircle(Offset(x, dotY), _dot / 2, paint);
  }

  @override
  bool shouldRepaint(_CoachLinePainter oldDelegate) =>
      oldDelegate.dotAtTop != dotAtTop || oldDelegate.progress != progress;
}
