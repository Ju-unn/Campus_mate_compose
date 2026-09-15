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
}
