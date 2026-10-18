import 'package:flutter/painting.dart';

/// 웹 전용 글자 토큰. 크기는 pen 웹 값표(xs 12 / sm 14 / md 16 / lg 20 / xl 28 / stat 32, 대장 전달 — 노드 id 미확인),
/// 글꼴 · 대체 글꼴은 앱 토큰(frontend/lib/core/theme/app_typography.dart) 10-18 사본이다. 앱 토큰과 따로 바뀐다.
///
/// 줄 높이는 pen 에 속성이 없어 렌더된 글자 상자로 맞췄다(campus-pen 재조회 10-18, A0 CRAiQ 의 블록 y 40 · 102 · 153 · 219):
/// sm 14 → 21, lg 20 → 27, xl 28 → 38. SideNav 로고만 PNG 측정 30(side_nav.dart).
abstract final class AdminTypography {
  static const String family = 'Pretendard';
  static const List<String> _fallback = <String>['Apple SD Gothic Neo', 'Noto Sans KR', 'sans-serif'];

  /// 오류 줄 · 배지 · 보조 글자
  static const TextStyle xs = TextStyle(
    fontFamily: family,
    fontFamilyFallback: _fallback,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  /// 배지 글자
  static const TextStyle xsStrong = TextStyle(
    fontFamily: family,
    fontFamilyFallback: _fallback,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: 1.5,
  );

  /// 설명 문단 · 관리자 메일
  static const TextStyle sm = TextStyle(
    fontFamily: family,
    fontFamilyFallback: _fallback,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  /// 단추 · 메뉴 글자
  static const TextStyle smStrong = TextStyle(
    fontFamily: family,
    fontFamilyFallback: _fallback,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.5,
  );

  static const TextStyle md = TextStyle(
    fontFamily: family,
    fontFamilyFallback: _fallback,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  /// 카드 제목 · TopBar 제목 · 비밀 키 · 코드 숫자
  static const TextStyle lg = TextStyle(
    fontFamily: family,
    fontFamilyFallback: _fallback,
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 27 / 20,
  );

  /// A0 로고 글자
  static const TextStyle xl = TextStyle(
    fontFamily: family,
    fontFamilyFallback: _fallback,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    height: 38 / 28,
  );

  /// 홈 통계 숫자(다음 조각)
  static const TextStyle stat = TextStyle(
    fontFamily: family,
    fontFamilyFallback: _fallback,
    fontSize: 32,
    fontWeight: FontWeight.w700,
    height: 1.2,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
  );
}
