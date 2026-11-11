import 'package:flutter/animation.dart';

/// 모션 토큰 (DESIGN.md §7). 위젯은 이 상수만 읽는다.
abstract final class AppMotion {
  /// 눌림 피드백(투명도·색) 시간
  static const Duration press = Duration(milliseconds: 120);

  /// 눌림 피드백 커브
  static const Curve pressCurve = Curves.easeOut;

  /// 화면 전환, 시트 열림, 상태 변화 시간
  static const Duration standard = Duration(milliseconds: 220);

  /// 화면 전환 커브
  static const Curve standardCurve = Curves.easeOutCubic;

  /// 매칭 성사·카드 등장 시간. 하루 최대 두 번만 쓴다
  static const Duration emphasis = Duration(milliseconds: 420);

  /// 매칭 성사·카드 등장 커브
  static const Curve emphasisCurve = Curves.easeOutBack;

  /// 19 코호트 대기 마스코트가 한 번 떠올랐다 내려오는 시간(오르기 + 내리기). 되풀이한다 — pen `tUaGw` 움직임 메모
  static const Duration float = Duration(milliseconds: 1600);

  /// 떠오름 커브(오르기 · 내리기 같은 곡선)
  static const Curve floatCurve = Curves.easeInOut;
}
