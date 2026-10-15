import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:flutter/widgets.dart';

/// 덮개 색 — pen `tFIey` Dim 검정 알파 B3(70%). 토큰 [AppColors.scrim] 은 50% 라 다르다(토큰표 밖 리터럴).
const Color _dim = Color(0xB3000000);

/// 테두리 두께(pen `tFIey` Ring primary 2px).
const double _ring = 2;

/// 앱 투어 덮개(pen `tFIey` CoachOverlay). 화면 전체를 어둡게 칠하고 [hole] 만 비운다(evenodd), 구멍 바로 바깥에 primary 2 테두리.
/// [hole] 이 없거나 크기가 0 이면 덮개만 칠한다(5단계 가운데 카드). 장식이라 스크린리더에 읽히지 않는다.
class CoachOverlay extends StatelessWidget {
  const CoachOverlay({required this.hole, required this.radius, super.key});

  final Rect? hole;
  final double radius;

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _CoachOverlayPainter(hole, radius), size: Size.infinite);
}

class _CoachOverlayPainter extends CustomPainter {
  _CoachOverlayPainter(this.hole, this.radius);

  final Rect? hole;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size);
    final cut = hole;
    if (cut == null || cut.width < 1 || cut.height < 1) {
      canvas.drawPath(dim, Paint()..color = _dim);
      return;
    }
    canvas.drawPath(dim..addRRect(RRect.fromRectAndRadius(cut, Radius.circular(radius))), Paint()..color = _dim);
    // 선 가운데가 구멍 가장자리 1 바깥 — 테두리가 대상 위로 올라오지 않는다.
    canvas.drawRRect(
      RRect.fromRectAndRadius(cut.inflate(_ring / 2), Radius.circular(radius + _ring / 2)),
      Paint()
        ..color = AppColors.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = _ring,
    );
  }

  @override
  bool shouldRepaint(_CoachOverlayPainter oldDelegate) => oldDelegate.hole != hole || oldDelegate.radius != radius;
}
