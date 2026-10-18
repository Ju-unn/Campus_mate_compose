import 'package:flutter/widgets.dart';

/// 웹 전용 움직임 토큰. 시작값은 앱 토큰(frontend/lib/core/theme/app_motion.dart) 10-18 사본(press 120ms · easeOutCubic)이고
/// 관리자 도구라 모두 200ms 이하로 둔다. 화면 전환 · 메뉴 전환은 움직이지 않는다(router 의 NoTransitionPage).
/// pen 에 없는 값이다 — 대장 보고표로 pen 에 역반영한다.
abstract final class AdminMotion {
  /// 단추 색 변화(올림 · 누름)
  static const Duration press = Duration(milliseconds: 120);

  /// 관문 카드 · 토스트가 들어올 때
  static const Duration enter = Duration(milliseconds: 200);

  /// 토스트가 나갈 때 — 들어올 때보다 짧게, 같은 길로
  static const Duration exit = Duration(milliseconds: 150);

  /// 들어올 때 곡선. 나갈 때는 이 곡선을 뒤집어(flipped) 시간상 똑같이 빠르게 시작하게 한다.
  static const Curve curve = Curves.easeOutCubic;

  /// 도는 아이콘 한 바퀴(일정한 속도 — pen 은 멈춘 그림이라 정한 값)
  static const Duration spin = Duration(milliseconds: 1000);

  /// 관문 카드가 올라오는 거리
  static const double rise = 8;

  /// 운영체제 "동작 줄이기"(브라우저 prefers-reduced-motion)가 켜졌으면 움직임을 모두 끈다(frontend/CLAUDE.md §7 과 같은 규칙).
  static bool reduced(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}
