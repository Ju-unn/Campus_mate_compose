import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:campus_mate/matching/view/daily_card_summary.dart';
import 'package:campus_mate/tour/view/tour_precision_points.dart';
import 'package:flutter/widgets.dart';

/// 투어가 가리킬 수 있는 화면 요소. 화면은 그 요소를 `TourTarget(id: …)` 로 감싸기만 한다.
enum TourTargetId {
  /// 홈 hero-today 카드
  homeHero,

  /// 홈 프로필 완성도 카드(100% 면 없다 — 그 단계는 건너뛴다)
  homeProfileNudge,

  /// 커뮤니티 탭 4개 줄
  communityTabs,

  /// 오늘 탭 다음 카드 도착 시각 안내(카드 대기 화면)
  todayArrival,

  /// 오늘 탭 앱바 제목 — 도착 시각 안내가 없는 상태의 대신 자리(상단 영역)
  todayHeader,

  /// 하트 스토어 맨 위 그림 — 늘 그려져 있어 목록을 스크롤할 손잡이로 쓴다
  heartStoreTop,

  /// 하트 스토어 "무료로 모으기" 제목 + 작업 줄 3개(pen 구멍이 둘 다 감싼다 — 제목 아래 안내는 10-16 에 지웠다)
  heartStoreFree,
}

/// 투어 단계 하나의 문구 묶음(제목 · 설명). 단계 설정([TourStep])은 글자를 직접 들지 않고 이 식별자만 들며, 글자는 문구 파일(ARB)에서 읽는다.
/// 문구는 사용자 확정본 그대로다.
enum TourCopy {
  start,
  profile,
  community,
  arrival,
  precision,
  heartFree;

  String title(AppLocalizations l10n) => switch (this) {
        TourCopy.start => l10n.tourStartTitle,
        TourCopy.profile => l10n.tourProfileTitle,
        TourCopy.community => l10n.tourCommunityTitle,
        TourCopy.arrival => l10n.tourArrivalTitle,
        TourCopy.precision => l10n.tourPrecisionTitle,
        TourCopy.heartFree => l10n.tourHeartFreeTitle,
      };

  String body(AppLocalizations l10n) => switch (this) {
        TourCopy.start => l10n.tourStartBody,
        TourCopy.profile => l10n.tourProfileBody,
        TourCopy.community => l10n.tourCommunityBody,
        TourCopy.arrival => l10n.tourArrivalBody,
        TourCopy.precision => l10n.tourPrecisionBody,
        TourCopy.heartFree => l10n.tourHeartFreeBody,
      };
}

/// 투어 한 단계(pen 섹션 24 `vfrto` 앱 투어 v2). 설정 값 묶음이라 UiState 처럼 값을 그대로 연다.
class TourStep {
  const TourStep({
    required this.location,
    required this.copy,
    this.targets = const [],
    this.holeRadius = 16,
    this.holePadding = EdgeInsets.zero,
    this.lineLength = 52,
    this.push = false,
    this.scrollAnchor,
    this.detail,
    this.alignTop,
    this.titleAt,
  });

  /// 이 단계의 화면 경로. 지금 화면이 아니면 옮긴다 — 탭은 `go`(하단 내비와 같은 방식), [push] 면 위에 올린다.
  final String location;

  /// 제목 · 설명 글자의 식별자(글자는 [TourCopy.title] · [TourCopy.body]).
  final TourCopy copy;

  /// 가리킬 요소 후보. 앞의 것이 먼저이고, 앞의 것이 안 보이면 뒤의 것을 쓴다. 비어 있으면 구멍 없이 가운데 설명 카드다.
  final List<TourTargetId> targets;

  /// 구멍 모서리(pen 값표).
  final double holeRadius;

  /// 요소 상자에서 구멍까지 띄우는 거리(pen 값, campus-pen 확인) — 카드 사방 2(반경 +2) · 탭 줄 좌우 8 위 4 아래 6 ·
  /// 글자 영역 위아래 7 좌우 38 · 섹션 묶음 사방 4.
  final EdgeInsets holePadding;

  /// 구멍과 말풍선 사이 = 선 길이(pen — 점 10 을 넣어 52, 5단계는 32). 5단계는 구멍이 없어 선을 그리지 않는다.
  final double lineLength;
  final bool push;

  /// 요소가 긴 목록 끝이라 아직 안 만들어졌을 수 있으면, 같은 목록 안에 늘 있는 요소. 호스트가 그 목록을 끝으로 민다.
  final TourTargetId? scrollAnchor;

  /// 설명 아래에 붙일 내용(5단계 정밀 분석 항목).
  final WidgetBuilder? detail;

  /// 값이 있으면 대상을 찾은 뒤 목록을 밀어 **구멍 위쪽을 보이는 영역 맨 위(앱바 바로 아래)에서 이만큼 아래**에 둔다(목록 끝이라
  /// 더 못 밀면 그 목록의 `TourScrollRoom` 이 잠깐 빈자리를 낸다). 이때 구멍이 아래 말풍선 · 선 자리까지 먹으면 구멍 아래쪽을
  /// 잘라 말풍선이 보이는 영역(하단 바 위) 안에 다 들어오게 한다. null 이면 대상을 가운데로 민다(화면 밖일 때만).
  final double? alignTop;

  /// 다음 카드 지급 시각을 알 때 [TourCopy.title] 대신 쓸 제목을 만든다. 없으면 제목은 늘 [TourCopy.title] 이다.
  final String Function(AppLocalizations l10n, DateTime nextIssueAt)? titleAt;

  /// 말풍선에 쓸 제목. [titleAt] 이 있고 [nextIssueAt] 을 알면 그것으로 만들고, 아니면 [TourCopy.title] 이다.
  String titleFor(AppLocalizations l10n, DateTime? nextIssueAt) {
    final at = nextIssueAt;
    final build = titleAt;
    if (at == null || build == null) {
      return copy.title(l10n);
    }
    return build(l10n, at);
  }
}

Widget _precisionPoints(BuildContext context) => const TourPrecisionPoints();

/// 4단계 제목 — 서버가 준 다음 지급 시각의 서울 요일 · 시각이다. 지급 주기는 학교 인원에 따라 주 1회 ~ 매일이라 요일을 못 박지 않는다.
/// 오늘 탭 대기 화면 부제(`waitingSubtitle`)와 같은 [seoulClock] · [weekdayName] · [hourLabel](요일 · 시각 글자도 같은 ARB 키)을 쓴다.
String _arrivalTitle(AppLocalizations l10n, DateTime nextIssueAt) {
  final issue = seoulClock(nextIssueAt);
  return l10n.tourArrivalTitleAt(weekday: weekdayName(l10n, issue), hour: hourLabel(l10n, issue));
}

/// 앱 투어 6단계 — 문구는 사용자 확정본 그대로다. 단계를 고치거나 더할 때는 이 목록만 고친다.
const List<TourStep> appTourSteps = [
  TourStep(
    location: AppRoutes.home,
    targets: [TourTargetId.homeHero],
    holeRadius: 34,
    holePadding: EdgeInsets.all(2),
    copy: TourCopy.start,
  ),
  TourStep(
    location: AppRoutes.home,
    targets: [TourTargetId.homeProfileNudge],
    holeRadius: 26,
    holePadding: EdgeInsets.all(2),
    scrollAnchor: TourTargetId.homeHero,
    copy: TourCopy.profile,
  ),
  TourStep(
    location: AppRoutes.community,
    targets: [TourTargetId.communityTabs],
    holePadding: EdgeInsets.fromLTRB(AppSpacing.xs, AppSpacing.xxs, AppSpacing.xs, 6),
    copy: TourCopy.community,
  ),
  TourStep(
    location: AppRoutes.today,
    targets: [TourTargetId.todayArrival, TourTargetId.todayHeader],
    holePadding: EdgeInsets.symmetric(vertical: 7, horizontal: 38),
    // 제목은 서버 다음 지급 시각을 알 때 [_arrivalTitle] 이 만든다 — [TourCopy.arrival] 의 글은 시각을 아직 모르거나 못 받았을 때의 기본이다.
    copy: TourCopy.arrival,
    titleAt: _arrivalTitle,
  ),
  // 가입 직후엔 카드가 없어 진짜 정밀 분석 시트(`G30cC`)를 못 연다 — 오늘 탭 위 가운데 설명 카드에 시트의 항목 넷을 한 줄씩 보인다.
  TourStep(
    location: AppRoutes.today,
    copy: TourCopy.precision,
    detail: _precisionPoints,
    lineLength: 32,
  ),
  TourStep(
    location: AppRoutes.heartStore,
    push: true,
    targets: [TourTargetId.heartStoreFree],
    holePadding: EdgeInsets.all(AppSpacing.xxs),
    scrollAnchor: TourTargetId.heartStoreTop,
    // pen(campus-pen 10-16, 360×780): 무료로 모으기를 앱바 아래 12 로 올린 모습 — 구멍 x12 · y68 · 336×306, 말풍선 x24 · y426.
    alignTop: 12,
    copy: TourCopy.heartFree,
  ),
];
