import 'package:flutter/material.dart';

/// 색상 토큰 (DESIGN.md §2). 위젯은 Color 리터럴을 직접 쓰지 않고 이 상수만 읽는다.
abstract final class AppColors {
  /// 모든 CTA 채움, 하트, 활성 탭 — 채움 전용. 텍스트에는 [primaryText] 를 쓴다
  static const Color primary = Color(0xFFFF385C);

  /// [primary] 눌림 상태
  static const Color primaryPressed = Color(0xFFE00B41);

  /// 흰 배경 위 핑크 텍스트·링크 전용
  static const Color primaryText = Color(0xFFC4224B);

  /// 아주 옅은 핑크 표면 — 수락 대기 행, 선택된 칩
  static const Color primaryWash = Color(0xFFFFF0F2);

  /// 비활성 채움 (2026-09-15 사용자 결정)
  static const Color primaryDisabled = Color(0xFFE5E5E5);

  /// [primary] 채움 위의 텍스트·아이콘
  static const Color onPrimary = Color(0xFFFFFFFF);

  /// 모든 화면의 바닥. 순백
  static const Color canvas = Color(0xFFFFFFFF);

  /// 입력 필드 채움, 상대 말풍선, 태그 칩
  static const Color surfaceSoft = Color(0xFFF7F7F7);

  /// 원형 아이콘 버튼 바탕
  static const Color surfaceStrong = Color(0xFFF2F2F2);

  /// 잉크 표면 — 학생 인증 뱃지, 사진 위 오버레이 칩
  static const Color surfaceInk = Color(0xFF222222);

  /// 모달 뒤 딤, 모자이크 배너 위 덮개
  static final Color scrim = Colors.black.withValues(alpha: 0.5);

  /// 제목, 이름, 강조 본문
  static const Color ink = Color(0xFF222222);

  /// 긴 본문
  static const Color body = Color(0xFF3F3F3F);

  /// 보조 설명, 메타 정보, 캡션
  static const Color muted = Color(0xFF6A6A6A);

  /// 비활성 텍스트 전용 (대비 요건 면제 대상)
  static const Color disabled = Color(0xFF929292);

  /// 잉크 표면 위 텍스트
  static const Color onInk = Color(0xFFFFFFFF);

  /// 잉크 표면 위 보조 텍스트 — 화면 11 "내일 만날 사람들" 띠의 둘째 줄
  /// (2026-09-23 pen `i4VFS` 대조에서 신설. DESIGN.md §2 표에 줄 추가 필요)
  static const Color onInkMuted = Color(0xFFE6E6E6);

  /// 기본 1px 구분선
  static const Color hairline = Color(0xFFDDDDDD);

  /// 더 옅은 구분선 — 긴 스크롤 본문
  static const Color hairlineSoft = Color(0xFFEBEBEB);

  /// 컨트롤 경계선 — 입력 필드, 아웃라인 버튼
  static const Color outline = Color(0xFF767676);

  /// 인증 실패, 입력 오류, 신고 확인
  static const Color error = Color(0xFFC13515);

  /// 아주 옅은 에러 표면 — 반려 사유 배너 바탕 (2026-09-19 신설, 화면 3b).
  /// [primaryWash] 와 같은 성격의 워시 토큰. 위에 올리는 텍스트는 [error] 로 둔다
  static const Color errorWash = Color(0xFFFAEFEC);

  /// 매칭 성사, 학생 인증 완료
  static const Color success = Color(0xFF25795A);

  // ── 소셜 로그인 버튼(시작 화면). 앱 토큰이 아니라 각 사 브랜드 규칙 값이다(대장 지시문 07 규칙표).
  //    눌림 · 로딩 · 비활성에서도 바꾸지 않는다.

  /// 카카오 로그인 버튼 바탕(카카오 로그인 디자인 가이드)
  static const Color kakaoContainer = Color(0xFFFEE500);

  /// 카카오 말풍선 심볼. 공식 SVG 의 #191919 가 아니라 가이드 본문 값(규칙표 §1)
  static const Color kakaoSymbol = Color(0xFF000000);

  /// 카카오 레이블 — 검정 불투명도 85%
  static final Color kakaoLabel = const Color(0xFF000000).withValues(alpha: 0.85);

  /// 구글 버튼 바탕(Google 브랜드 가이드, 밝은 테마)
  static const Color googleContainer = Color(0xFFFFFFFF);

  /// 구글 버튼 안쪽 1px 획
  static const Color googleStroke = Color(0xFF747775);

  /// 구글 레이블
  static const Color googleLabel = Color(0xFF1F1F1F);
}
