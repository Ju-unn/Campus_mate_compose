import 'package:flutter/painting.dart';

/// 웹 전용 색 토큰. 시작값은 앱 토큰(frontend/lib/core/theme/app_colors.dart) 10-18 사본이었고, 같은 날 pen 웹 변수
/// `web-*`(영역 WOjcG · 컴포넌트 보드 UUkLx, 대장 전달 값표 — 노드 id 미확인)로 맞췄다. 앱 토큰과 따로 바뀐다 —
/// 앱 쪽을 import 하지 않는다.
abstract final class AdminColors {
  /// web-primary — 주 단추 채움 · 로고 글자
  static const Color primary = Color(0xFFFF385C);

  /// web-primary-pressed
  static const Color primaryPressed = Color(0xFFE00B41);

  /// web-primary-text — 흰 바탕 위 분홍 글자(글자 단추 · 선택된 메뉴)
  static const Color primaryText = Color(0xFFC4224B);

  /// web-primary-wash — 선택된 메뉴 바탕
  static const Color primaryWash = Color(0xFFFFF0F2);

  /// web-on-primary
  static const Color onPrimary = Color(0xFFFFFFFF);

  /// web-ink — 제목 · 강조
  static const Color ink = Color(0xFF222222);

  /// web-body — 본문 · 메뉴 글자
  static const Color body = Color(0xFF3F3F3F);

  /// web-muted — 보조 설명 · 메뉴 아이콘
  static const Color muted = Color(0xFF6A6A6A);

  /// web-disabled
  static const Color disabled = Color(0xFF929292);

  /// web-canvas — 내용 바탕
  static const Color canvas = Color(0xFFF7F7F7);

  /// web-surface — 카드 · SideNav · TopBar
  static const Color surface = Color(0xFFFFFFFF);

  /// web-surface-strong — 비밀 키 상자
  static const Color surfaceStrong = Color(0xFFF2F2F2);

  /// web-board
  static const Color board = Color(0xFFEBEBEB);

  /// web-outline — 카드 테두리
  static const Color outline = Color(0xFFDDDDDD);

  /// web-outline-strong — 입력칸 · 보조 단추 테두리(A0 · A1 PNG 측정 #767676)
  static const Color outlineStrong = Color(0xFF767676);

  /// web-hairline — SideNav · TopBar 구분선
  static const Color hairline = Color(0xFFEBEBEB);

  /// web-danger — 위험 단추 · 오류 글자
  static const Color danger = Color(0xFFC13515);

  /// web-danger-wash
  static const Color dangerWash = Color(0xFFFDECE8);

  /// web-success — "2단계 인증됨" 배지 글자 · 점
  static const Color success = Color(0xFF25795A);

  /// web-success-wash — "2단계 인증됨" 배지 바탕
  static const Color successWash = Color(0xFFE6F4EE);

  /// web-warning
  static const Color warning = Color(0xFF8A5A00);

  /// web-warning-wash
  static const Color warningWash = Color(0xFFFFF4D6);

  /// web-scrim (#00000080)
  static const Color scrim = Color(0x80000000);
}
