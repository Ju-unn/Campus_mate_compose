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

  // ── 뜨고 사라지는 것: 스낵바 · 토스트 · 팝업 · 바텀시트(사용자 2026-11-16) ──
  // 시간은 원문에 없어 standard 에 맞추고 사라질 때는 더 짧게 정했다(대장 결정, 확인 대상).
  // 띄우는 함수는 common/widgets 의 app_snack_bar · app_toast · app_dialog_route · app_bottom_sheet 한 곳씩이다.

  /// 나타나는 시간(= [standard])
  static const Duration appear = standard;

  /// 사라지는 시간 — 나타날 때보다 짧다
  static const Duration disappear = Duration(milliseconds: 180);

  /// 나타날 때 커브 — 사용자 「들어올땐 ease out」(스낵바 · 토스트 · 팝업). 바텀시트는 §7 "시트 열림" 대로 [standardCurve]
  static const Curve appearCurve = Curves.easeOut;

  /// 사라질 때 눈에 보이는 커브 — 사용자 「나갈때 ease in」: 천천히 떠나기 시작해 빨라진다
  static const Curve disappearCurve = Curves.easeIn;

  /// 컨트롤러를 거꾸로(1→0) 돌려 사라지게 할 때 reverseCurve 로 주는 값. CurvedAnimation 은 거꾸로 돌 때도 커브를 t 그대로
  /// 읽어 [disappearCurve] 를 그대로 주면 눈에는 easeOut 모양이 된다 — 뒤집어 준다.
  static const Curve disappearReverseCurve = FlippedCurve(disappearCurve);

  /// 팝업이 커지기 시작하는 크기 — 사용자 「살짝 커지면서」, 값은 pen 확인 팝업 값표(scale 0.96 → 1, 대장 전달 2026-11-16)
  static const double popupScaleFrom = 0.96;

  /// 체크박스 켜고 끄기 시간 — 원문에 없어 [standard] 에 맞췄다
  static const Duration checkbox = standard;

  /// 체크박스 커브 — 사용자 「체크박스 ease in out 부드럽게」
  static const Curve checkboxCurve = Curves.easeInOut;
}
