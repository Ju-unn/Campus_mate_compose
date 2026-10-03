import 'package:flutter/material.dart';

/// 타이포그래피 토큰 (DESIGN.md §3.2). 위젯은 이 상수만 읽는다.
abstract final class AppTypography {
  static const String _family = 'Pretendard';
  static const List<String> _fallback = <String>[
    'Apple SD Gothic Neo',
    'Noto Sans KR',
    'sans-serif',
  ];

  /// 다음 카드까지 남은 시간 — 시스템에서 가장 큰 한 곳
  static const TextStyle countdown = TextStyle(
    fontFamily: _family,
    fontFamilyFallback: _fallback,
    fontSize: 48,
    fontWeight: FontWeight.w700,
    height: 1.10,
    letterSpacing: -0.03 * 48,
    // 1초마다 숫자가 바뀌어도 자릿수 폭이 흔들리지 않게 (DESIGN §3.1)
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
  );

  /// 온보딩 단계 헤드라인, 매칭 성사 화면
  static const TextStyle display = TextStyle(
    fontFamily: _family,
    fontFamilyFallback: _fallback,
    fontSize: 32,
    fontWeight: FontWeight.w700,
    height: 1.30,
    letterSpacing: -0.03 * 32,
  );

  /// 화면 제목
  static const TextStyle headline = TextStyle(
    fontFamily: _family,
    fontFamilyFallback: _fallback,
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 1.35,
    letterSpacing: -0.02 * 24,
  );

  /// 앱바 제목, 채팅방 헤더 상대 이름 (2026-09-14 §13-99 해결)
  static const TextStyle navTitle = TextStyle(
    fontFamily: _family,
    fontFamilyFallback: _fallback,
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 1.50,
    letterSpacing: -0.02 * 20,
  );

  /// 카드의 이름·나이, 섹션 헤드
  static const TextStyle title = TextStyle(
    fontFamily: _family,
    fontFamilyFallback: _fallback,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.40,
    letterSpacing: -0.02 * 20,
  );

  /// 리스트 행 제목, 설문 문항
  static const TextStyle subtitle = TextStyle(
    fontFamily: _family,
    fontFamilyFallback: _fallback,
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.45,
    letterSpacing: -0.01 * 17,
  );

  /// 자기소개 본문, 채팅 메시지, 설명 문단
  static const TextStyle body = TextStyle(
    fontFamily: _family,
    fontFamilyFallback: _fallback,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.60,
    letterSpacing: -0.01 * 16,
  );

  /// 본문 내 강조
  static const TextStyle bodyStrong = TextStyle(
    fontFamily: _family,
    fontFamilyFallback: _fallback,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.60,
    letterSpacing: -0.01 * 16,
  );

  /// 메타 정보(학과·키·MBTI), 채팅 미리보기
  static const TextStyle bodySmall = TextStyle(
    fontFamily: _family,
    fontFamilyFallback: _fallback,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.55,
  );

  /// 전체 폭 버튼 라벨 — Rausch 위 대비 확보를 위해 굵고 크게 (DESIGN §2.1)
  static const TextStyle label = TextStyle(
    fontFamily: _family,
    fontFamilyFallback: _fallback,
    fontSize: 18,
    fontWeight: FontWeight.w700,
    height: 1.20,
    letterSpacing: -0.01 * 18,
  );

  /// 뒤로가 있는 보조 앱바 제목 (pen AppBar · Sub `KH1hX` 제목 `YSMvI` 18/700 · 1.5, 2026-10-01 개편).
  /// 탭 머리 제목은 [navTitle] 20 그대로다
  static const TextStyle subNavTitle = TextStyle(
    fontFamily: _family,
    fontFamilyFallback: _fallback,
    fontSize: 18,
    fontWeight: FontWeight.w700,
    height: 1.50,
  );

  /// 채움 버튼 라벨 (pen Button `HE8FZ` 라벨 `ifX9K` 16/700, 2026-10-01 개편). 줄높이 · 자간은 pen 에 없어 [label] 과 같은 비율로 둔다
  /// — 자간을 비우면 버튼 안에서 Material 기본(+0.1)이 끼어들어 글자 폭을 재는 화면(17 빈 상태 버튼)과 어긋난다.
  static const TextStyle button = TextStyle(
    fontFamily: _family,
    fontFamilyFallback: _fallback,
    fontSize: 16,
    fontWeight: FontWeight.w700,
    height: 1.20,
    letterSpacing: -0.01 * 16,
  );

  /// 리스트 안의 작은 버튼, 칩 버튼
  static const TextStyle labelSmall = TextStyle(
    fontFamily: _family,
    fontFamilyFallback: _fallback,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.20,
  );

  /// 보조 설명, 타임스탬프, 약관
  static const TextStyle caption = TextStyle(
    fontFamily: _family,
    fontFamilyFallback: _fallback,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.40,
  );

  /// 인증 뱃지, 카운트 뱃지 — 하한값. 항상 옆 텍스트가 의미를 보완한다
  static const TextStyle badge = TextStyle(
    fontFamily: _family,
    fontFamilyFallback: _fallback,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    height: 1.30,
    letterSpacing: 0.02 * 11,
  );

  /// 전체 목록 — 폰트 일괄 검증 등에 쓴다
  static const List<TextStyle> values = <TextStyle>[
    countdown,
    display,
    headline,
    navTitle,
    subNavTitle,
    title,
    subtitle,
    body,
    bodyStrong,
    bodySmall,
    label,
    button,
    labelSmall,
    caption,
    badge,
  ];
}
