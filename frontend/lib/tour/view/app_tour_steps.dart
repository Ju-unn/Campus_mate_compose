import 'package:campus_mate/core/router/app_routes.dart';
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

  /// 하트 스토어 "무료로 모으기" 제목 + 안내 + 작업 줄 3개(pen 구멍이 셋 다 감싼다)
  heartStoreFree,
}

/// 투어 한 단계(pen 섹션 24 `vfrto` 앱 투어 v2). 설정 값 묶음이라 UiState 처럼 값을 그대로 연다.
class TourStep {
  const TourStep({
    required this.location,
    required this.title,
    required this.body,
    this.targets = const [],
    this.holeRadius = 16,
    this.holePadding = EdgeInsets.zero,
    this.lineLength = 52,
    this.push = false,
    this.scrollAnchor,
    this.detail,
    this.alignTop,
  });

  /// 이 단계의 화면 경로. 지금 화면이 아니면 옮긴다 — 탭은 `go`(하단 내비와 같은 방식), [push] 면 위에 올린다.
  final String location;
  final String title;
  final String body;

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
}

Widget _precisionPoints(BuildContext context) => const TourPrecisionPoints();

/// 앱 투어 6단계 — 문구는 사용자 확정본 그대로다. 단계를 고치거나 더할 때는 이 목록만 고친다.
const List<TourStep> appTourSteps = [
  TourStep(
    location: AppRoutes.home,
    targets: [TourTargetId.homeHero],
    holeRadius: 34,
    holePadding: EdgeInsets.all(2),
    title: '여기가 캠퍼스메이트의 시작이에요',
    body: '오늘의 카드와 학교 소식을 홈에서 한눈에 봐요.',
  ),
  TourStep(
    location: AppRoutes.home,
    targets: [TourTargetId.homeProfileNudge],
    holeRadius: 26,
    holePadding: EdgeInsets.all(2),
    scrollAnchor: TourTargetId.homeHero,
    title: '프로필부터 채워 보세요',
    body: '사진, 소개, 이상형을 채우면 더 잘 맞아요.',
  ),
  TourStep(
    location: AppRoutes.community,
    targets: [TourTargetId.communityTabs],
    holePadding: EdgeInsets.fromLTRB(8, 4, 8, 6),
    title: '사람들과 이야기해요',
    body: '전체, 인기, 내 질문, 내 투표로 골라 볼 수 있어요.',
  ),
  TourStep(
    location: AppRoutes.today,
    targets: [TourTargetId.todayArrival, TourTargetId.todayHeader],
    holePadding: EdgeInsets.symmetric(vertical: 7, horizontal: 38),
    title: '매주 월요일 오전 7시에 열려요',
    body: '월요일 아침 7시에 새로운 한 명이 도착해요.',
  ),
  // 가입 직후엔 카드가 없어 진짜 정밀 분석 시트(`G30cC`)를 못 연다 — 오늘 탭 위 가운데 설명 카드에 시트의 항목 넷을 한 줄씩 보인다.
  TourStep(
    location: AppRoutes.today,
    title: '하트로 여는 카드는 더 정밀해요',
    body: '성향, 관심사, 글, 조건을 비교해 골라 드려요.',
    detail: _precisionPoints,
    lineLength: 32,
  ),
  TourStep(
    location: AppRoutes.heartStore,
    push: true,
    targets: [TourTargetId.heartStoreFree],
    holePadding: EdgeInsets.all(4),
    scrollAnchor: TourTargetId.heartStoreTop,
    // pen(campus-pen 10-16, 360×780): 무료로 모으기를 앱바 아래 12 로 올린 모습 — 구멍 x12 · y68 · 336×306, 말풍선 x24 · y426.
    alignTop: 12,
    title: '하트는 무료로도 모아요',
    body: '무료로 모으기에서 미션을 인증하면 받아요.',
  ),
];
